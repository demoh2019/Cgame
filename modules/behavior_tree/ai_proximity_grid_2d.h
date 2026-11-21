/**************************************************************************/
/*  ai_proximity_grid_2d.h                                                 */
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
/* persons to whom the Software is furnished to do so, subject to the      */
/* following conditions:                                                  */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/array.h"
#include "core/variant/variant.h"

// Stateless, deterministic broadphase query for authoritative 2D crowd AI.
// No actors, scene nodes, raycasts, or gameplay decisions are accessed.
// The cell edge must be >= radius, so a query checks at most 3x3 cells.
class AIProximityGrid2D : public RefCounted {
	GDCLASS(AIProximityGrid2D, RefCounted);

private:
	Array _query_impl(const PackedVector2Array &p_positions,
			const PackedInt32Array &p_source_indices, double p_radius,
			double p_cell_size, int p_max_neighbors) const;

protected:
	static void _bind_methods();

public:
	// Result: Array of PackedInt32Array, one per source, containing indices
	// into positions (excluding itself), ascending by input index.
	// All inputs are checked before indexing; invalid requests yield [].
	Array query_radius_batch(const PackedVector2Array &p_positions,
			const PackedInt32Array &p_source_indices,
			double p_radius, double p_cell_size) const;

	// Limited nearest neighbors, ties by input index. Returns chosen indices
	// ascending by input index (not distance) to retain game event order.
	// p_max_neighbors must be 1..64. Invalid queries return [].
	Array query_nearest_batch(const PackedVector2Array &p_positions,
			const PackedInt32Array &p_source_indices,
			double p_radius, double p_cell_size, int p_max_neighbors) const;

	// Read-only crowd separation steering, using the nearest bounded neighbors
	// from the same 3x3-cell broadphase. One finite vector of length <= 1
	// per source, in input order. Coincident points diverge deterministically
	// by input index. Invalid inputs return an empty packed array.
	// This cannot change physics, gameplay targets or actor positions itself.
	PackedVector2Array query_separation_batch(const PackedVector2Array &p_positions,
			const PackedInt32Array &p_source_indices,
			double p_radius, double p_cell_size, int p_max_neighbors) const;

	// Bounded cross-set broadphase: each source position is queried against
	// a different set of target positions. Results contain target indices
	// in ascending input order (e.g. authoritative trap iteration order).
	// Uses 3x3 hashed target cells; exact gameplay collision is still owned by
	// the caller. Rejects invalid inputs / excessive candidate pairs atomically.
	// p_sources <= 4096, p_targets <= 8192, total hits <= 32768.
	Array query_cross_radius_batch(const PackedVector2Array &p_sources,
			const PackedVector2Array &p_targets, double p_radius, double p_cell_size) const;

	// Mass-style variable-radius cross-cohort broadphase for independent AI
	// sensing/leash radii. Result: one packed array of original target indices
	// per source, in ascending index order (including duplicate positions).
	// Zero-radius matches are exact. Invalid/oversized requests fail atomically.
	// Bounds: <=4096 sources, <=8192 targets, <=32768 matching pairs.
	Array query_cross_variable_radius_batch(const PackedVector2Array &p_sources,
			const PackedFloat32Array &p_radii, const PackedVector2Array &p_targets) const;

	// EQS-style nearest candidate across two independent spatial cohorts.
	// One original target index per source, -1 when none lies within radius.
	// Equal-distance ties prefer smaller persistent target ID and then index.
	// All inputs are validated atomically; no scene or gameplay mutations.
	PackedInt32Array query_cross_nearest_batch(const PackedVector2Array &p_sources,
			const PackedVector2Array &p_targets, const PackedInt64Array &p_target_ids,
			double p_radius, double p_cell_size) const;

	// Batched 3D vertical-cylinder presence query, projected into an XZ hash.
	// Returns bounded counts per source (not actor identities): useful for
	// alarms and crowd significance without exposing game targets to clients.
	// A zero target cohort gives one zero per valid source. Malformed inputs
	// yield an empty array; max 4096 sources, 8192 targets, 64 hits/source.
	PackedInt32Array query_cylinder_counts_batch(const PackedVector3Array &p_centers,
			const PackedVector3Array &p_targets, double p_radius,
			double p_max_height, int p_max_count) const;

	// Short-horizon Mass-style steering prediction, using desired velocities
	// and the existing bounded nearest-neighbor broadphase on projected sites.
	// Only read-only directions are returned, never positions or gameplay hits.
	// Time horizon 0..2 seconds; all velocities must be finite and <= 50m/s.
	// Coincident future trajectories sidestep based on relative velocity.
	PackedVector2Array query_predictive_separation_batch(const PackedVector2Array &p_positions,
			const PackedVector2Array &p_velocities, const PackedInt32Array &p_source_indices,
			double p_radius, double p_cell_size, int p_max_neighbors, double p_horizon) const;
};
