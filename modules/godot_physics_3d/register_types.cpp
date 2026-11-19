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

#include "godot_physics_server_3d.h"

#include "core/config/project_settings.h"
#include "core/object/callable_mp.h"
#include "servers/physics_3d/physics_server_3d.h"
#include "servers/physics_3d/physics_server_3d_manager.h"
#include "servers/physics_3d/physics_server_3d_wrap_mt.h"

static PhysicsServer3D *_createGodotPhysics3DCallback() {
#ifdef THREADS_ENABLED
	bool using_threads = GLOBAL_GET("physics/3d/run_on_separate_thread");
#else
	bool using_threads = false;
#endif

	PhysicsServer3D *physics_server_3d = memnew(GodotPhysicsServer3D(using_threads));

	return memnew(PhysicsServer3DWrapMT(physics_server_3d, using_threads));
}

void initialize_godot_physics_3d_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SERVERS) {
		return;
	}
	// Optional advanced soft-body dynamics. Existing projects continue to
	// use the legacy Bullet-derived link solver until explicitly enabled.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/soft_body/xpbd_distance_constraints"), false);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/soft_body/xpbd_distance_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.00001);
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/soft_body/xpbd_volume_preservation"), false);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/soft_body/xpbd_volume_compliance", PROPERTY_HINT_RANGE, "0,0.001,0.000001,or_greater"), 0.000001);

	PhysicsServer3DManager::get_singleton()->register_server(PhysicsServer3DManager::GODOT_PHYSICS_3D_NAME, callable_mp_static(_createGodotPhysics3DCallback));
	PhysicsServer3DManager::get_singleton()->set_default_server(PhysicsServer3DManager::GODOT_PHYSICS_3D_NAME);
}

void uninitialize_godot_physics_3d_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SERVERS) {
		return;
	}
}
