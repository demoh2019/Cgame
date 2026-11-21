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

#include "ai_action_cooldowns.h"
#include "ai_execution_profiler.h"
#include "ai_behavior_trace.h"
#include "ai_proximity_grid_2d.h"
#include "ai_hearing_sensor_2d.h"
#include "ai_stimulus_history_2d.h"
#include "ai_simulation_lod_2d.h"
#include "ai_update_scheduler.h"
#include "ai_threat_table_2d.h"
#include "ai_visual_sensor_2d.h"
#include "behavior_tree.h"

#include "core/object/class_db.h"

#ifdef TESTS_ENABLED
#include "tests/test_ai_visual_sensor_2d.h"
#include "tests/test_ai_hearing_sensor_2d.h"
#include "tests/test_ai_stimulus_history_2d.h"
#include "tests/test_reactive_behavior_tree.h"
#include "tests/test_timed_behavior_tree.h"
#include "tests/test_blackboard_compare.h"
#include "tests/test_ai_execution_profiler.h"
#include "tests/test_ai_behavior_trace.h"
#include "tests/test_ai_simulation_lod_2d.h"
#include "tests/test_ai_update_scheduler.h"
#include "tests/test_ai_proximity_grid_2d.h"
#include "tests/test_ai_threat_table_2d.h"
#endif

void initialize_behavior_tree_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	GDREGISTER_VIRTUAL_CLASS(BehaviorTreeTask);
	GDREGISTER_VIRTUAL_CLASS(BehaviorTreeComposite);
	GDREGISTER_CLASS(BehaviorTreeSequence);
	GDREGISTER_CLASS(BehaviorTreeSelector);
	GDREGISTER_CLASS(BehaviorTreeReactiveSequence);
	GDREGISTER_CLASS(BehaviorTreeReactiveSelector);
	GDREGISTER_CLASS(BehaviorTreeInverter);
	GDREGISTER_VIRTUAL_CLASS(BehaviorTreeDecorator);
	GDREGISTER_CLASS(BehaviorTreeTimeout);
	GDREGISTER_CLASS(BehaviorTreeCooldown);
	GDREGISTER_CLASS(BehaviorTreeBlackboardCheck);
	GDREGISTER_CLASS(BehaviorTreeBlackboardCompare);
	GDREGISTER_CLASS(BehaviorTreeBlackboardSet);
	GDREGISTER_CLASS(BehaviorTreeWait);
	GDREGISTER_CLASS(BehaviorTreeRunner);
	GDREGISTER_CLASS(AIVisualSensor2D);
	GDREGISTER_CLASS(AIHearingSensor2D);
	GDREGISTER_CLASS(AIStimulusHistory2D);
	GDREGISTER_CLASS(AIExecutionProfiler);
	GDREGISTER_CLASS(AIBehaviorTrace);
	GDREGISTER_CLASS(AIActionCooldowns);
	GDREGISTER_CLASS(AISimulationLOD2D);
	GDREGISTER_CLASS(AIUpdateScheduler);
	GDREGISTER_CLASS(AIProximityGrid2D);
	GDREGISTER_CLASS(AIThreatTable2D);
}

void uninitialize_behavior_tree_module(ModuleInitializationLevel) {
	// No global state to release.
}
