#include "register_types.h"

#include "frame_update_budget.h"
#include "core/object/class_db.h"

void initialize_frame_update_budget_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(FrameUpdateBudget);
}

void uninitialize_frame_update_budget_module(ModuleInitializationLevel p_level) {
}
