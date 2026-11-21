/**************************************************************************/
/*  ai_encounter_budget.h                                                */
/*  Native data-only encounter pressure policy for server-authoritative AI. */
/**************************************************************************/

#pragma once

#include "core/object/ref_counted.h"

// A deterministic reusable pacing policy for enemy waves and reinforcements.
// No world, player, SceneTree, RNG, network state or timers are stored here.
class AIEncounterBudget : public RefCounted {
	GDCLASS(AIEncounterBudget, RefCounted);

	int global_limit = 150;
	int soft_density = 8;
	int dense_density = 12;
	int local_hard_limit = 20;
	int base_squad = 7;
	int max_squad = 10;
	int max_zone_bonus = 3;

protected:
	static void _bind_methods();

public:
	// Configuration is applied atomically. All fields have bounded ranges,
	// monotonically increasing density limits and a bounded squad size.
	bool configure_limits(int p_global_limit, int p_soft_density, int p_dense_density,
			int p_local_hard_limit, int p_base_squad, int p_max_squad, int p_max_zone_bonus);

	// Non-positive/invalid population and nonfinite health data fail closed.
	// Zero budget signals no permitted new spawns; no reservation is performed.
	int get_spawn_budget(int p_total, int p_nearby, double p_health_ratio, int p_zone) const;

	// Adjust an already-authored base delay upward by bounded pressure relief.
	// The caller retains responsibility for authoritative scheduling.
	double get_respite_seconds(double p_base_delay, int p_nearby, double p_health_ratio) const;

	int get_global_limit() const { return global_limit; }
	int get_local_hard_limit() const { return local_hard_limit; }
	int get_soft_density() const { return soft_density; }
	int get_dense_density() const { return dense_density; }
};
