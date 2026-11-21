/**************************************************************************/
/*  register_types.cpp                                                      */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "register_types.h"

#include "cull_distance_profile_3d.h"
#include "core/object/class_db.h"

#ifdef TESTS_ENABLED
#include "tests/test_cull_distance_profile_3d.h"
#endif

void initialize_cull_distance_policy_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(CullDistanceProfile3D);
}

void uninitialize_cull_distance_policy_module(ModuleInitializationLevel p_level) {
}
