#include "register_types.h"

#include "core/object/class_db.h"
#include "crowd_animation_tier_planner.h"
#include "crowd_animation_budget_governor.h"

void initialize_crowd_animation_tier_planner_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(CrowdAnimationTierPlanner);
	GDREGISTER_CLASS(CrowdAnimationBudgetGovernor);
}

void uninitialize_crowd_animation_tier_planner_module(ModuleInitializationLevel p_level) {
}
