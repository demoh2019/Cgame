/**************************************************************************/
/* register_types.cpp - Dynamic Resolution Panic module                    */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "register_types.h"

#include "dynamic_resolution_panic_policy.h"
#include "core/object/class_db.h"

#ifdef TESTS_ENABLED
#include "tests/test_dynamic_resolution_panic_policy.h"
#endif

void initialize_dynamic_resolution_panic_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(DynamicResolutionPanicPolicy);
}

void uninitialize_dynamic_resolution_panic_module(ModuleInitializationLevel p_level) {
}
