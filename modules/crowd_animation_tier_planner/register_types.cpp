#include "register_types.h"

#include "core/object/class_db.h"
#include "crowd_animation_tier_planner.h"

void initialize_crowd_animation_tier_planner_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(CrowdAnimationTierPlanner);
}

void uninitialize_crowd_animation_tier_planner_module(ModuleInitializationLevel p_level) {
}
