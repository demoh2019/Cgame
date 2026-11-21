/**************************************************************************/
/*  vendor_upscaler.h                                                   */
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

#pragma once

#include "core/math/projection.h"
#include "core/math/transform_3d.h"
#include "core/math/vector2.h"
#include "core/math/vector2i.h"
#include "core/templates/rid.h"
#include "servers/rendering/rendering_server_enums.h"

namespace RendererRD {

// Backend-agnostic hook for optional, vendor supplied temporal upscalers (NVIDIA DLSS, Intel XeSS).
//
// The engine itself ships NO vendor SDK code. Optional modules (`modules/dlss`, `modules/xess`) are only
// compiled when the user supplies the vendor SDK path to SCons; they register an implementation of this
// interface here. When nothing is registered for a scaling mode, the viewport falls back to FSR 2.

class VendorUpscalerContext {
public:
	virtual ~VendorUpscalerContext() {}
};

class VendorUpscaler {
public:
	struct Parameters {
		RID color; // Jittered, pre-tonemap internal color.
		RID depth;
		RID velocity; // UV-space motion vectors (same convention as the MetalFX path).
		RID exposure; // Optional, may be invalid.
		RID output; // Upscaled target.
		uint32_t view = 0; // Multiview index.
		Size2i internal_size;
		Size2i target_size;
		Vector2 jitter; // Jitter in pixels, ±0.5 range (same as the MetalFX path, y not flipped).
		float sharpness = 0.0f; // 0..1
		float z_near = 0.0f;
		float z_far = 0.0f;
		float fovy = 0.0f;
		float delta_time = 0.0f; // Seconds.
		bool reset_accumulation = false;
		Projection cam_projection;
		Projection prev_cam_projection;
		Transform3D cam_transform;
		Transform3D prev_cam_transform;
	};

	virtual ~VendorUpscaler() {}

	virtual String get_name() const = 0;
	// True when the runtime (driver, GPU, SDK DLLs) can actually run this upscaler on the current device.
	virtual bool is_supported() const = 0;
	// Valid range of `scaling_3d_scale` (render scale), e.g. 0.33 .. 1.0.
	virtual void get_scale_limits(float &r_min, float &r_max) const {
		r_min = 0.33f;
		r_max = 1.0f;
	}
	virtual VendorUpscalerContext *create_context(const Size2i &p_internal_size, const Size2i &p_target_size) = 0;
	// Records the upscale into the current frame (typically through RenderingDevice::driver_callback_add).
	virtual void upscale(VendorUpscalerContext *p_context, const Parameters &p_params) = 0;
};

class VendorUpscalerRegistry {
public:
	static void register_upscaler(RSE::ViewportScaling3DMode p_mode, VendorUpscaler *p_upscaler);
	static void unregister_upscaler(RSE::ViewportScaling3DMode p_mode);
	static VendorUpscaler *get(RSE::ViewportScaling3DMode p_mode);
	static bool is_available(RSE::ViewportScaling3DMode p_mode);
	static bool is_vendor_mode(RSE::ViewportScaling3DMode p_mode);
};

} // namespace RendererRD
