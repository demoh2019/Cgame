/**************************************************************************/
/*  register_types.cpp                                                     */
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "register_types.h"

#include "smart_object_slot_reservations.h"

#include "core/object/class_db.h"

#ifdef TESTS_ENABLED
#include "tests/test_smart_object_slot_reservations.h"
#endif

void initialize_smart_object_slots_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(SmartObjectSlotReservations);
}

void uninitialize_smart_object_slots_module(ModuleInitializationLevel p_level) {
}
