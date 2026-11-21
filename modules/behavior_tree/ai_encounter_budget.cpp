/**************************************************************************/
/*  ai_encounter_budget.cpp                                              */
/**************************************************************************/

#include "ai_encounter_budget.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

bool AIEncounterBudget::configure_limits(int p_global_limit, int p_soft_density, int p_dense_density,
		int p_local_hard_limit, int p_base_squad, int p_max_squad, int p_max_zone_bonus) {
	ERR_FAIL_COND_V_MSG(p_global_limit < 1 || p_global_limit > 8192 ||
			p_soft_density < 1 || p_soft_density >= p_dense_density ||
			p_dense_density >= p_local_hard_limit || p_local_hard_limit > p_global_limit ||
			p_base_squad < 1 || p_max_squad < p_base_squad || p_max_squad > 64 ||
			p_max_zone_bonus < 0 || p_max_zone_bonus > 10,
			false, "Encounter limits must be bounded, and density thresholds strictly increasing.");
	global_limit = p_global_limit;
	soft_density = p_soft_density;
	dense_density = p_dense_density;
	local_hard_limit = p_local_hard_limit;
	base_squad = p_base_squad;
	max_squad = p_max_squad;
	max_zone_bonus = p_max_zone_bonus;
	return true;
}

int AIEncounterBudget::get_spawn_budget(int p_total, int p_nearby, double p_health_ratio, int p_zone) const {
	if (p_total < 0 || p_nearby < 0 || !Math::is_finite(p_health_ratio)) {
		return 0;
	}
	const int headroom = global_limit - p_total;
	if (headroom <= 0 || p_nearby >= local_hard_limit) {
		return 0;
	}
	const int zone_bonus = CLAMP(p_zone, 0, max_zone_bonus);
	int budget = MIN(max_squad, base_squad + zone_bonus);
	if (p_nearby >= dense_density) {
		budget = MIN(budget, 2);
	} else if (p_nearby >= soft_density) {
		budget = MIN(budget, 4);
	}
	const double health = CLAMP(p_health_ratio, 0.0, 1.0);
	if (health <= 0.30) {
		budget = MIN(budget, 2);
	} else if (health <= 0.55) {
		budget = MIN(budget, 4);
	}
	return CLAMP(budget, 0, headroom);
}

double AIEncounterBudget::get_respite_seconds(double p_base_delay, int p_nearby, double p_health_ratio) const {
	if (!Math::is_finite(p_base_delay) || p_base_delay < 0.0 || !Math::is_finite(p_health_ratio)) {
		return 0.0;
	}
	double bonus = 0.0;
	if (p_nearby >= dense_density) {
		bonus += 45.0;
	} else if (p_nearby >= soft_density) {
		bonus += 20.0;
	}
	if (p_health_ratio <= 0.30) {
		bonus += 30.0;
	} else if (p_health_ratio <= 0.55) {
		bonus += 15.0;
	}
	return CLAMP(p_base_delay + bonus, p_base_delay, p_base_delay + 75.0);
}

void AIEncounterBudget::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure_limits", "global_limit", "soft_density", "dense_density",
			"local_hard_limit", "base_squad", "max_squad", "max_zone_bonus"), &AIEncounterBudget::configure_limits);
	ClassDB::bind_method(D_METHOD("get_spawn_budget", "total_infected", "nearby", "health_ratio", "zone"),
			&AIEncounterBudget::get_spawn_budget);
	ClassDB::bind_method(D_METHOD("get_respite_seconds", "base_delay", "nearby", "health_ratio"),
			&AIEncounterBudget::get_respite_seconds);
	ClassDB::bind_method(D_METHOD("get_global_limit"), &AIEncounterBudget::get_global_limit);
	ClassDB::bind_method(D_METHOD("get_local_hard_limit"), &AIEncounterBudget::get_local_hard_limit);
	ClassDB::bind_method(D_METHOD("get_soft_density"), &AIEncounterBudget::get_soft_density);
	ClassDB::bind_method(D_METHOD("get_dense_density"), &AIEncounterBudget::get_dense_density);
}
