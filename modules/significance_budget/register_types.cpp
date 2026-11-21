/**************************************************************************/
/*  register_types.cpp                                                     */
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "register_types.h"

#include "significance_budget_planner.h"

#include "core/object/class_db.h"

#ifdef TESTS_ENABLED
#include "tests/test_significance_budget_planner.h"
#endif

void initialize_significance_budget_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(SignificanceBudgetPlanner);
}

void uninitialize_significance_budget_module(ModuleInitializationLevel p_level) {
}
