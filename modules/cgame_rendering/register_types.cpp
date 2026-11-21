/**************************************************************************/
/*  register_types.cpp                                                    */
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

#include "cgame_area_lights.h"
#include "cgame_foveated_shading.h"
#include "cgame_frame_pacing.h"
#include "cgame_gpu_resource_report.h"
#include "cgame_hdr_output.h"
#include "cgame_impostor_baker.h"
#include "cgame_instance_culling.h"
#include "cgame_rt_effect.h"
#include "cgame_shader_warmup.h"
#include "cgame_vram_budget.h"
#include "impostor_field_3d.h"

#include "core/object/class_db.h"

void initialize_cgame_rendering_module(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		GDREGISTER_CLASS(CgameImpostorBaker);
		GDREGISTER_CLASS(ImpostorField3D);
		GDREGISTER_CLASS(CgameShaderWarmup);
		GDREGISTER_CLASS(CgameFoveatedShading);
		GDREGISTER_CLASS(CgameFramePacing);
		GDREGISTER_CLASS(CgameHDROutput);
		GDREGISTER_CLASS(CgameAreaLights);
		GDREGISTER_CLASS(CgameVRAMBudget);
		GDREGISTER_CLASS(CgameGPUResourceReport);
		GDREGISTER_CLASS(CgameRTEffect);
		GDREGISTER_CLASS(CgameInstanceCulling);
	}
}

void uninitialize_cgame_rendering_module(ModuleInitializationLevel p_level) {
}
