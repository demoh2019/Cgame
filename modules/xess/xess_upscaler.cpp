/**************************************************************************/
/*  xess_upscaler.cpp                                                   */
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

#include "xess_upscaler.h"

#include "core/config/project_settings.h"
#include "core/string/print_string.h"
#include "drivers/vulkan/godot_vulkan.h"
#include "servers/rendering/rendering_device.h"

// Intel XeSS public headers, resolved from the user supplied SDK (`xess_sdk_path`).
#include <xess/xess.h>
#include <xess/xess_vk.h>

using RD = RenderingDevice;
using RDC = RenderingDeviceCommons;

struct XeSSUpscaler::Context : public RendererRD::VendorUpscalerContext {
	xess_context_handle_t handle = nullptr;
	Size2i internal_size;
	Size2i target_size;
	bool ready = false;

	~Context() {
		if (handle) {
			xessDestroyContext(handle);
			handle = nullptr;
		}
	}
};

struct XeSSUpscaler::CallbackArgs {
	xess_context_handle_t handle = nullptr;
	xess_vk_execute_params_t params = {};
};

static xess_quality_settings_t _quality_for_scale(float p_scale) {
	if (p_scale >= 0.99f) {
		return XESS_QUALITY_SETTING_AA;
	} else if (p_scale >= 0.70f) {
		return XESS_QUALITY_SETTING_ULTRA_QUALITY; // 1.3x, ~0.77
	} else if (p_scale >= 0.62f) {
		return XESS_QUALITY_SETTING_QUALITY; // 1.5x, ~0.667
	} else if (p_scale >= 0.54f) {
		return XESS_QUALITY_SETTING_BALANCED; // 1.7x, ~0.59
	} else if (p_scale >= 0.42f) {
		return XESS_QUALITY_SETTING_PERFORMANCE; // 2.0x, 0.5
	}
	return XESS_QUALITY_SETTING_ULTRA_PERFORMANCE; // 3.0x, ~0.333
}

static xess_vk_image_view_info _make_view(RD *p_rd, RID p_texture, const Size2i &p_size) {
	xess_vk_image_view_info info = {};
	info.image = (VkImage)p_rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_IMAGE, p_texture);
	info.imageView = (VkImageView)p_rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_IMAGE_VIEW, p_texture);
	info.format = (VkFormat)p_rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_IMAGE_NATIVE_TEXTURE_FORMAT, p_texture);
	info.width = uint32_t(p_size.x);
	info.height = uint32_t(p_size.y);
	info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	info.subresourceRange.baseMipLevel = 0;
	info.subresourceRange.levelCount = 1;
	info.subresourceRange.baseArrayLayer = 0;
	info.subresourceRange.layerCount = 1;
	return info;
}

void XeSSUpscaler::_check_support() {
	if (checked) {
		return;
	}
	checked = true; // Only try once.

	RD *rd = RD::get_singleton();
	if (rd == nullptr || rd->get_device_api_name() != "Vulkan") {
		return;
	}

	xess_context_handle_t probe = nullptr;
	xess_result_t res = xessVKCreateContext(
			(VkInstance)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_INSTANCE),
			(VkPhysicalDevice)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_PHYSICAL_DEVICE),
			(VkDevice)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_DEVICE),
			&probe);
	if (res != XESS_RESULT_SUCCESS) {
		print_verbose(vformat("XeSS: xessVKCreateContext failed (%d). Is libxess next to the executable?", int(res)));
		return;
	}
	supported = true;
	xessDestroyContext(probe);
}

bool XeSSUpscaler::is_supported() const {
	// Lazy: the RenderingDevice does not exist yet when modules register.
	const_cast<XeSSUpscaler *>(this)->_check_support();
	return supported;
}

void XeSSUpscaler::get_scale_limits(float &r_min, float &r_max) const {
	r_min = 0.33f;
	r_max = 1.0f;
}

RendererRD::VendorUpscalerContext *XeSSUpscaler::create_context(const Size2i &p_internal_size, const Size2i &p_target_size) {
	RD *rd = RD::get_singleton();
	Context *ctx = memnew(Context);
	ctx->internal_size = p_internal_size;
	ctx->target_size = p_target_size;

	xess_result_t res = xessVKCreateContext(
			(VkInstance)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_INSTANCE),
			(VkPhysicalDevice)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_PHYSICAL_DEVICE),
			(VkDevice)rd->get_driver_resource(RDC::DRIVER_RESOURCE_VULKAN_DEVICE),
			&ctx->handle);
	ERR_FAIL_COND_V_MSG(res != XESS_RESULT_SUCCESS, ctx, vformat("XeSS: xessVKCreateContext failed (%d).", int(res)));

	// Godot renders reverse-Z, uses the engine exposure buffer if there is one, and provides low-resolution
	// (internal size) motion vectors. Auto exposure is enabled so a missing exposure texture is not an error.
	xess_vk_init_params_t init = {};
	init.outputResolution = { uint32_t(p_target_size.x), uint32_t(p_target_size.y) };
	init.qualitySetting = _quality_for_scale(float(p_internal_size.x) / float(MAX(p_target_size.x, 1)));
	init.initFlags = XESS_INIT_FLAG_INVERTED_DEPTH | XESS_INIT_FLAG_ENABLE_AUTOEXPOSURE;
	res = xessVKInit(ctx->handle, &init);
	ERR_FAIL_COND_V_MSG(res != XESS_RESULT_SUCCESS, ctx, vformat("XeSS: xessVKInit failed (%d).", int(res)));

	Vector2 vel_scale = GLOBAL_GET("rendering/scaling_3d/xess/velocity_scale");
	xessSetVelocityScale(ctx->handle, vel_scale.x, vel_scale.y);

	ctx->ready = true;
	return ctx;
}

void XeSSUpscaler::upscale(RendererRD::VendorUpscalerContext *p_context, const Parameters &p_params) {
	Context *ctx = static_cast<Context *>(p_context);
	ERR_FAIL_NULL(ctx);
	if (!ctx->ready) {
		return;
	}

	RD *rd = RD::get_singleton();
	CallbackArgs *args = memnew(CallbackArgs);
	args->handle = ctx->handle;

	xess_vk_execute_params_t &ep = args->params;
	ep.colorTexture = _make_view(rd, p_params.color, p_params.internal_size);
	ep.velocityTexture = _make_view(rd, p_params.velocity, p_params.internal_size);
	ep.depthTexture = _make_view(rd, p_params.depth, p_params.internal_size);
	ep.depthTexture.subresourceRange.aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT;
	ep.outputTexture = _make_view(rd, p_params.output, p_params.target_size);
	// No exposure texture: XeSS runs with auto exposure (see init flags). Godot's luminance buffer is not
	// guaranteed to be in the format XeSS expects.
	ep.jitterOffsetX = p_params.jitter.x;
	ep.jitterOffsetY = p_params.jitter.y;
	ep.exposureScale = 1.0f;
	ep.resetHistory = p_params.reset_accumulation ? 1 : 0;
	ep.inputWidth = uint32_t(p_params.internal_size.x);
	ep.inputHeight = uint32_t(p_params.internal_size.y);

	RD::CallbackResource res[4] = {
		{ .rid = p_params.color, .usage = RD::CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE },
		{ .rid = p_params.depth, .usage = RD::CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE },
		{ .rid = p_params.velocity, .usage = RD::CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE },
		{ .rid = p_params.output, .usage = RD::CALLBACK_RESOURCE_USAGE_STORAGE_IMAGE_READ_WRITE },
	};
	rd->driver_callback_add((RDD::DriverCallback)XeSSUpscaler::callback, args, VectorView<RD::CallbackResource>(res, 4));
}

void XeSSUpscaler::callback(RenderingDeviceDriver *p_driver, RenderingDeviceDriver::CommandBufferID p_command_buffer, CallbackArgs *p_args) {
	// The Vulkan driver's command buffer id points at a struct whose first member is the VkCommandBuffer.
	VkCommandBuffer cmd = *reinterpret_cast<VkCommandBuffer *>(p_command_buffer.id);
	xess_result_t res = xessVKExecute(p_args->handle, cmd, &p_args->params);
	if (res != XESS_RESULT_SUCCESS) {
		WARN_PRINT_ONCE(vformat("XeSS: xessVKExecute failed (%d).", int(res)));
	}
	memdelete(p_args);
}
