/**************************************************************************/
/*  register_types.cpp                                                  */
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

#include "register_types.h"

#include "xess_upscaler.h"

#include "core/config/project_settings.h"

static XeSSUpscaler *xess_upscaler = nullptr;

void initialize_xess_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SERVERS) {
		return;
	}
	// Motion vector scale applied before XeSS sees them. Godot's velocity buffer is in UV units; the right
	// factor/sign must be confirmed on hardware, so it is exposed for tuning.
	GLOBAL_DEF("rendering/scaling_3d/xess/velocity_scale", Vector2(2.0, 2.0));
	xess_upscaler = memnew(XeSSUpscaler);
	RendererRD::VendorUpscalerRegistry::register_upscaler(RSE::VIEWPORT_SCALING_3D_MODE_XESS, xess_upscaler);
}

void uninitialize_xess_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SERVERS) {
		return;
	}
	RendererRD::VendorUpscalerRegistry::unregister_upscaler(RSE::VIEWPORT_SCALING_3D_MODE_XESS);
	if (xess_upscaler) {
		memdelete(xess_upscaler);
		xess_upscaler = nullptr;
	}
}
