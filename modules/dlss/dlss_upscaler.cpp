/**************************************************************************/
/*  dlss_upscaler.cpp                                                   */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "dlss_upscaler.h"

#include "core/config/project_settings.h"
#include "core/string/print_string.h"
#include "drivers/vulkan/godot_vulkan.h"
#include "servers/rendering/rendering_device.h"

// NVIDIA Streamline public headers, resolved from the user supplied SDK (`dlss_sdk_path`).
#include <sl.h>
#include <sl_consts.h>
#include <sl_dlss.h>
#include <sl_helpers_vk.h>

using RD = RenderingDevice;
using RDC = RenderingDeviceCommons;

struct DLSSUpscaler::CallbackArgs {
	uint32_t viewport_id = 0;
	uint32_t frame_index = 0;
	bool new_frame = false;

	VkImage color = VK_NULL_HANDLE;
	VkImage depth = VK_NULL_HANDLE;
	VkImage velocity = VK_NULL_HANDLE;
	VkImage exposure = VK_NULL_HANDLE;
	VkImage output = VK_NULL_HANDLE;
	VkFormat color_format = VK_FORMAT_UNDEFINED;
	VkFormat depth_format = VK_FORMAT_UNDEFINED;
	VkFormat velocity_format = VK_FORMAT_UNDEFINED;
	VkFormat exposure_format = VK_FORMAT_UNDEFINED;
	VkFormat output_format = VK_FORMAT_UNDEFINED;

	Size2i internal_size;
	Size2i target_size;
	float sharpness = 0.0f;
	bool reset = false;
	bool set_options = false;
	float scale = 1.0f;

	// Camera.
	Vector2 jitter;
	float z_near = 0.0f;
	float z_far = 0.0f;
	float fovy = 0.0f;
	float aspect = 1.0f;
	Projection view_to_clip;
	Projection prev_view_to_clip;
	Transform3D cam_transform;
	Transform3D prev_cam_transform;
};

static void _fill_matrix(sl::float4x4 &r_dst, const Projection &p_src) {
	// Godot's Projection is column major with column vectors; Streamline expects row-major matrices used with
	// row vectors, which is the transpose. Copying column i into row i performs that transposition.
	for (int i = 0; i < 4; i++) {
		r_dst.row[i] = sl::float4(float(p_src.columns[i].x), float(p_src.columns[i].y), float(p_src.columns[i].z), float(p_src.columns[i].w));
	}
}

static sl::DLSSMode _mode_for_scale(float p_scale) {
	if (p_scale >= 0.99f) {
		return sl::DLSSMode::eDLAA;
	} else if (p_scale >= 0.62f) {
		return sl::DLSSMode::eMaxQuality; // ~0.667
	} else if (p_scale >= 0.54f) {
		return sl::DLSSMode::eBalanced; // ~0.58
	} else if (p_scale >= 0.42f) {
		return sl::DLSSMode::eMaxPerformance; // 0.5
	}
	return sl::DLSSMode::eUltraPerformance; // ~0.333
}

DLSSUpscaler::Context::~Context() {
	if (options_set) {
		// Releases DLSS resources (NGX feature handles, history buffers) for this viewport.
		slFreeResources(sl::kFeatureDLSS, sl::ViewportHandle(viewport_id));
	}
}

DLSSUpscaler::DLSSUpscaler() {
}

DLSSUpscaler::~DLSSUpscaler() {
	if (initialized) {
		slShutdown();
	}
}

void DLSSUpscaler::_initialize() {
	if (initialized) {
		return;
	}
	initialized = true; // Only try once.

	RD *rd = RD::get_singleton();
	if (rd == nullptr || rd->get_device_api_name() != "Vulkan") {
		return;
	}

	sl::Feature features[] = { sl::kFeatureDLSS };
	sl::Preferences pref{};
	pref.showConsole = false;
	pref.logLevel = sl::LogLevel::eOff;
	pref.featuresToLoad = features;
	pref.numFeaturesToLoad = 1;
	pref.renderAPI = sl::RenderAPI::eVulkan;
	// Godot loads Vulkan itself (volk), so Streamline cannot proxy the Vulkan loader: use manual hooking.
	pref.flags = sl::PreferenceFlags::eDisableCLStateTracking | sl::PreferenceFlags::eUseManualHooking;
	// NVIDIA requires a registered application id for shipping builds; 0 works for development.
	pref.applicationId = uint32_t(int(GLOBAL_GET("rendering/scaling_3d/dlss/application_id")));

	sl::Result res = slInit(pref, sl::kSDKVersion);
	if (res != sl::Result::eOk) {
		print_verbose(vformat("DLSS: slInit failed (%d). Is the Streamline runtime next to the executable?", int(res)));
		return;
	}

	if (!_ensure_vulkan_info()) {
		slShutdown();
		return;
	}

	sl::AdapterInfo adapter{};
	adapter.vkPhysicalDevice = (VkPhysicalDevice)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_PHYSICAL_DEVICE);
	res = slIsFeatureSupported(sl::kFeatureDLSS, adapter);
	supported = res == sl::Result::eOk;
	if (!supported) {
		print_verbose(vformat("DLSS: not supported on this adapter (sl::Result %d).", int(res)));
	}
}

bool DLSSUpscaler::_ensure_vulkan_info() {
	if (vulkan_info_set) {
		return true;
	}
	RD *rd = RD::get_singleton();
	sl::VulkanInfo info{};
	info.device = (VkDevice)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_DEVICE);
	info.instance = (VkInstance)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_INSTANCE);
	info.physicalDevice = (VkPhysicalDevice)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_PHYSICAL_DEVICE);
	// Godot submits everything on one graphics+compute queue.
	info.graphicsQueueFamily = uint32_t(rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_QUEUE_FAMILY_INDEX));
	info.graphicsQueueIndex = 0;
	info.computeQueueFamily = info.graphicsQueueFamily;
	info.computeQueueIndex = 0;
	if (slSetVulkanInfo(info) != sl::Result::eOk) {
		print_verbose("DLSS: slSetVulkanInfo failed.");
		return false;
	}
	vulkan_info_set = true;
	return true;
}

bool DLSSUpscaler::is_supported() const {
	// Lazy initialization: the RenderingDevice does not exist yet when modules register.
	const_cast<DLSSUpscaler *>(this)->_initialize();
	return supported;
}

void DLSSUpscaler::get_scale_limits(float &r_min, float &r_max) const {
	r_min = 0.33f;
	r_max = 1.0f;
}

RendererRD::VendorUpscalerContext *DLSSUpscaler::create_context(const Size2i &p_internal_size, const Size2i &p_target_size) {
	Context *ctx = memnew(Context);
	static uint32_t next_viewport_id = 1;
	ctx->viewport_id = next_viewport_id++;
	ctx->internal_size = p_internal_size;
	ctx->target_size = p_target_size;
	return ctx;
}

void DLSSUpscaler::upscale(RendererRD::VendorUpscalerContext *p_context, const Parameters &p_params) {
	Context *ctx = static_cast<Context *>(p_context);
	ERR_FAIL_NULL(ctx);
	ERR_FAIL_COND(!supported);

	RD *rd = RD::get_singleton();

	CallbackArgs *args = memnew(CallbackArgs);
	args->viewport_id = ctx->viewport_id + p_params.view * 1000;
	args->new_frame = p_params.view == 0;
	if (args->new_frame) {
		frame_index++;
	}
	args->frame_index = frame_index;
	args->color = (VkImage)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_IMAGE, p_params.color);
	args->depth = (VkImage)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_IMAGE, p_params.depth);
	args->velocity = (VkImage)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_IMAGE, p_params.velocity);
	args->output = (VkImage)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_IMAGE, p_params.output);
	args->color_format = (VkFormat)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_IMAGE_NATIVE_TEXTURE_FORMAT, p_params.color);
	args->depth_format = (VkFormat)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_IMAGE_NATIVE_TEXTURE_FORMAT, p_params.depth);
	args->velocity_format = (VkFormat)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_IMAGE_NATIVE_TEXTURE_FORMAT, p_params.velocity);
	args->output_format = (VkFormat)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_IMAGE_NATIVE_TEXTURE_FORMAT, p_params.output);
	if (p_params.exposure.is_valid()) {
		args->exposure = (VkImage)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_IMAGE, p_params.exposure);
		args->exposure_format = (VkFormat)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_IMAGE_NATIVE_TEXTURE_FORMAT, p_params.exposure);
	}
	args->internal_size = p_params.internal_size;
	args->target_size = p_params.target_size;
	args->sharpness = p_params.sharpness;
	args->reset = p_params.reset_accumulation;
	args->set_options = !ctx->options_set;
	args->scale = float(p_params.internal_size.x) / float(MAX(p_params.target_size.x, 1));
	ctx->options_set = true;

	args->jitter = p_params.jitter;
	args->z_near = p_params.z_near;
	args->z_far = p_params.z_far;
	args->fovy = p_params.fovy;
	args->aspect = float(p_params.internal_size.x) / float(MAX(p_params.internal_size.y, 1));
	// Same depth correction as the FSR2 path (flip Y, reverse Z) so Streamline receives D3D-style reversed-Z clip space.
	Projection correction;
	correction.set_depth_correction(true, true, false);
	args->view_to_clip = correction * p_params.cam_projection;
	args->prev_view_to_clip = correction * p_params.prev_cam_projection;
	args->cam_transform = p_params.cam_transform;
	args->prev_cam_transform = p_params.prev_cam_transform;

	// Resources must be in the right layout when Streamline records its commands: let the render graph transition them.
	RD::CallbackResource res[5];
	uint32_t res_count = 0;
	res[res_count++] = { .rid = p_params.color, .usage = RD::CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE };
	res[res_count++] = { .rid = p_params.depth, .usage = RD::CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE };
	res[res_count++] = { .rid = p_params.velocity, .usage = RD::CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE };
	if (p_params.exposure.is_valid()) {
		res[res_count++] = { .rid = p_params.exposure, .usage = RD::CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE };
	}
	res[res_count++] = { .rid = p_params.output, .usage = RD::CALLBACK_RESOURCE_USAGE_STORAGE_IMAGE_READ_WRITE };

	rd->driver_callback_add((RDD::DriverCallback)DLSSUpscaler::callback, args, VectorView<RD::CallbackResource>(res, res_count));
}

void DLSSUpscaler::callback(RenderingDeviceDriver *p_driver, RenderingDeviceDriver::CommandBufferID p_command_buffer, CallbackArgs *p_args) {
	// The Vulkan driver's command buffer id points at a struct whose first member is the VkCommandBuffer.
	VkCommandBuffer cmd = *reinterpret_cast<VkCommandBuffer *>(p_command_buffer.id);

	sl::ViewportHandle viewport(p_args->viewport_id);

	sl::FrameToken *frame = nullptr;
	slGetNewFrameToken(frame, &p_args->frame_index);

	if (p_args->set_options) {
		sl::DLSSOptions options{};
		options.mode = _mode_for_scale(p_args->scale);
		options.outputWidth = uint32_t(p_args->target_size.x);
		options.outputHeight = uint32_t(p_args->target_size.y);
		options.sharpness = p_args->sharpness;
		options.colorBuffersHDR = sl::Boolean::eTrue;
		options.useAutoExposure = p_args->exposure == VK_NULL_HANDLE ? sl::Boolean::eTrue : sl::Boolean::eFalse;
		slDLSSSetOptions(viewport, options);
	}

	// Constants.
	sl::Constants constants{};
	_fill_matrix(constants.cameraViewToClip, p_args->view_to_clip);
	_fill_matrix(constants.clipToCameraView, p_args->view_to_clip.inverse());
	Projection prev_clip_from_clip = p_args->prev_view_to_clip * Projection(p_args->prev_cam_transform.affine_inverse() * p_args->cam_transform) * p_args->view_to_clip.inverse();
	_fill_matrix(constants.clipToPrevClip, prev_clip_from_clip);
	_fill_matrix(constants.prevClipToClip, prev_clip_from_clip.inverse());
	constants.jitterOffset = { p_args->jitter.x, p_args->jitter.y };
	// Godot motion vectors are in UV units (0..1), which Streamline treats as the normalized default scale.
	constants.mvecScale = { 1.0f, 1.0f };
	constants.cameraPinholeOffset = { 0.0f, 0.0f };
	const Vector3 pos = p_args->cam_transform.origin;
	const Basis &b = p_args->cam_transform.basis;
	constants.cameraPosition = { float(pos.x), float(pos.y), float(pos.z) };
	constants.cameraUp = { float(b.get_column(1).x), float(b.get_column(1).y), float(b.get_column(1).z) };
	constants.cameraRight = { float(b.get_column(0).x), float(b.get_column(0).y), float(b.get_column(0).z) };
	constants.cameraFwd = { float(-b.get_column(2).x), float(-b.get_column(2).y), float(-b.get_column(2).z) }; // Godot looks down -Z.
	constants.cameraNear = p_args->z_near;
	constants.cameraFar = p_args->z_far;
	constants.cameraFOV = p_args->fovy; // Vertical FOV in radians.
	constants.cameraAspectRatio = p_args->aspect;
	constants.depthInverted = sl::Boolean::eTrue;
	constants.cameraMotionIncluded = sl::Boolean::eTrue;
	constants.motionVectors3D = sl::Boolean::eFalse;
	constants.motionVectorsJittered = sl::Boolean::eFalse;
	constants.orthographicProjection = sl::Boolean::eFalse;
	constants.reset = p_args->reset ? sl::Boolean::eTrue : sl::Boolean::eFalse;
	slSetConstants(constants, *frame, viewport);

	// Resource tags.
	auto make_resource = [](VkImage p_image, VkFormat p_format, const Size2i &p_size, VkImageLayout p_layout) {
		sl::Resource r{};
		r.type = sl::ResourceType::eTex2d;
		r.native = (void *)p_image;
		r.state = uint32_t(p_layout);
		r.width = uint32_t(p_size.x);
		r.height = uint32_t(p_size.y);
		r.nativeFormat = uint32_t(p_format);
		r.mipLevels = 1;
		r.arrayLayers = 1;
		return r;
	};

	sl::Resource color = make_resource(p_args->color, p_args->color_format, p_args->internal_size, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
	sl::Resource depth = make_resource(p_args->depth, p_args->depth_format, p_args->internal_size, VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL);
	sl::Resource velocity = make_resource(p_args->velocity, p_args->velocity_format, p_args->internal_size, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
	sl::Resource output = make_resource(p_args->output, p_args->output_format, p_args->target_size, VK_IMAGE_LAYOUT_GENERAL);
	sl::Resource exposure = make_resource(p_args->exposure, p_args->exposure_format, Size2i(1, 1), VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

	sl::Extent in_extent{ 0, 0, uint32_t(p_args->internal_size.x), uint32_t(p_args->internal_size.y) };
	sl::Extent out_extent{ 0, 0, uint32_t(p_args->target_size.x), uint32_t(p_args->target_size.y) };

	sl::ResourceTag tags[5];
	uint32_t tag_count = 0;
	tags[tag_count++] = sl::ResourceTag{ &color, sl::kBufferTypeScalingInputColor, sl::ResourceLifecycle::eValidUntilPresent, &in_extent };
	tags[tag_count++] = sl::ResourceTag{ &depth, sl::kBufferTypeDepth, sl::ResourceLifecycle::eValidUntilPresent, &in_extent };
	tags[tag_count++] = sl::ResourceTag{ &velocity, sl::kBufferTypeMotionVectors, sl::ResourceLifecycle::eValidUntilPresent, &in_extent };
	tags[tag_count++] = sl::ResourceTag{ &output, sl::kBufferTypeScalingOutputColor, sl::ResourceLifecycle::eValidUntilPresent, &out_extent };
	if (p_args->exposure != VK_NULL_HANDLE) {
		tags[tag_count++] = sl::ResourceTag{ &exposure, sl::kBufferTypeExposure, sl::ResourceLifecycle::eValidUntilPresent, nullptr };
	}
	slSetTagForFrame(*frame, viewport, tags, tag_count, (sl::CommandBuffer *)cmd);

	const sl::BaseStructure *inputs[] = { &viewport };
	slEvaluateFeature(sl::kFeatureDLSS, *frame, inputs, 1, (sl::CommandBuffer *)cmd);

	memdelete(p_args);
}
