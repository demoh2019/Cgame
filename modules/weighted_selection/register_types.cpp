/**************************************************************************/
/*  register_types.cpp                                                     */
/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "register_types.h"

#include "weighted_choice_table.h"

#include "core/object/class_db.h"

#ifdef TESTS_ENABLED
#include "tests/test_weighted_choice_table.h"
#endif

void initialize_weighted_selection_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(WeightedChoiceTable);
}

void uninitialize_weighted_selection_module(ModuleInitializationLevel p_level) {
}
