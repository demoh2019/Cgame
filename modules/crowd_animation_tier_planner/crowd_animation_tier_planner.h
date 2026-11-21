/**************************************************************************/
/*  crowd_animation_tier_planner.h                                        */
/*  This file is part of the Godot Engine (MIT License).                   */
/**************************************************************************/

#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

/**
 * Pure data-driven crowd pose LOD selection. No AnimationPlayer, Node,
 * SceneTree or rendering calls: gameplay owns all pose changes.
 */
class CrowdAnimationTierPlanner : public RefCounted {
	GDCLASS(CrowdAnimationTierPlanner, RefCounted);

protected:
	static void _bind_methods();

public:
	// Distance thresholds match Albion After's existing crowd tiers.
	// flags[i] != 0 requests a combat-critical full-rate pose (without IK).
	PackedInt32Array plan_tiers(const PackedFloat64Array &p_distances,
			const PackedByteArray &p_priority_flags, int p_full_budget, int p_priority_budget) const;

	// Optional per-frame visibility culling for costly procedural IK.
	// Non-visible actors never claim full-rate or priority slots and receive
	// at least tier 2 (30 Hz). All-visible calls match plan_tiers exactly.
	// The caller determines visibility; this class never touches the scene.
	PackedInt32Array plan_visible_tiers(const PackedFloat64Array &p_distances,
			const PackedByteArray &p_priority_flags, const PackedByteArray &p_visible_flags,
			int p_full_budget, int p_priority_budget) const;

	// Optional temporal retention for visible, near (<22m) IK users.
	// p_retained_full_flags is a per-actor hint from the preceding frame:
	// retained actors compete using max(0, distance - hysteresis), but only
	// while still visible/eligible. Priority combat slots use real distance.
	// No scene state, clock or actor references are kept by the planner.
	PackedInt32Array plan_visible_tiers_stable(const PackedFloat64Array &p_distances,
			const PackedByteArray &p_priority_flags, const PackedByteArray &p_visible_flags,
			const PackedByteArray &p_retained_full_flags, int p_full_budget,
			int p_priority_budget, double p_hysteresis = 1.5) const;
};
