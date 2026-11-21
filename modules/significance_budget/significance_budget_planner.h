/**************************************************************************/
/*  significance_budget_planner.h                                          */
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

/**
 * Reusable, bounded, deterministic top-K significance ranking.
 * Higher priority (0..3) wins, then nearer distance, then original index.
 * Pure calculations: the caller decides what VFX/UI/audio/AI work to skip.
 * No scene-tree references, clock, mutable state or RNG.
 */
class SignificanceBudgetPlanner : public RefCounted {
	GDCLASS(SignificanceBudgetPlanner, RefCounted);

protected:
	static void _bind_methods();

public:
	// Precomputed nearest-viewer distances. Validated, ordered, bounded indices.
	PackedInt32Array select_top(const PackedFloat64Array &p_distances,
			const PackedByteArray &p_priorities, int p_budget) const;

	// Convenience for multi-viewer worlds. Only candidates within inclusive
	// p_max_distance of at least one viewer are eligible.
	PackedInt32Array select_world(const PackedVector3Array &p_positions,
			const PackedVector3Array &p_viewers, const PackedByteArray &p_priorities,
			int p_budget, double p_max_distance = 1000.0) const;
};
