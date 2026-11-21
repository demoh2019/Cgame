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

#include "animation_node_motion_matching.h"
#include "cgame_aim_modifier_3d.h"
#include "cgame_facial_animation.h"
#include "cgame_lip_sync.h"
#include "cgame_locomotion_tools.h"
#include "cgame_mocap_cleanup.h"
#include "cgame_motion_matching_database.h"
#include "cgame_retargeter.h"
#include "cgame_rig_ik.h"
#include "constraint_graph_modifier_3d.h"
#include "foot_lock_modifier_3d.h"
#include "full_body_ik_modifier_3d.h"

#include "core/object/class_db.h"

void initialize_cgame_animation_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(CgameMotionMatchingDatabase);
	GDREGISTER_CLASS(AnimationNodeMotionMatching);
	GDREGISTER_CLASS(FootLockModifier3D);
	GDREGISTER_CLASS(FullBodyIKModifier3D);
	GDREGISTER_CLASS(CgameAimModifier3D);
	GDREGISTER_CLASS(ConstraintGraphModifier3D);
	GDREGISTER_CLASS(CgameRetargeter);
	GDREGISTER_CLASS(CgameMocapCleanup);
	GDREGISTER_CLASS(CgameLipSync);
	GDREGISTER_CLASS(CgameFacialAnimation);
	GDREGISTER_CLASS(CgameRigIK);
	GDREGISTER_CLASS(CgameLocomotionTools);
}

void uninitialize_cgame_animation_module(ModuleInitializationLevel p_level) {
	// Nothing to do here.
}
