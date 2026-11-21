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

#include "cgame_asset_conflicts.h"
#include "cgame_gpu_matrix_db.h"
#include "cgame_gpu_settings_db.h"
#include "cgame_latency_probe.h"
#include "cgame_perf_stats.h"
#include "cgame_platform_services.h"
#include "cgame_safe_area.h"
#include "cgame_scene_crdt.h"
#include "cgame_thermal_governor.h"

#include "core/object/class_db.h"

void initialize_cgame_platform_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_ABSTRACT_CLASS(CgamePlatformBackend);
	GDREGISTER_CLASS(CgameDesktopPlatformBackend);
	GDREGISTER_CLASS(CgameMockPlatformBackend);
	GDREGISTER_CLASS(CgamePlatformServices);
	GDREGISTER_CLASS(CgameSceneCRDT);
	GDREGISTER_CLASS(CgameAssetConflicts);
	GDREGISTER_CLASS(CgameGPUSettingsDB);
	GDREGISTER_CLASS(CgameThermalGovernor);
	GDREGISTER_CLASS(CgameLatencyProbe);
	GDREGISTER_CLASS(CgameGPUMatrixDB);
	GDREGISTER_CLASS(CgamePerfStats);
	GDREGISTER_CLASS(CgameSafeArea);

	CgamePlatformServices::create_singleton();
}

void uninitialize_cgame_platform_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	CgamePlatformServices::free_singleton();
}
