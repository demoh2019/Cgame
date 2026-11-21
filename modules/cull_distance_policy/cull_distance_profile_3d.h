/**************************************************************************/
/*  cull_distance_profile_3d.h                                              */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "core/math/aabb.h"
#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Pure object-size-based cull distance resolution. No scene mutation.
// Pair order is arbitrary; ties choose the shortest positive range.
// Return -1 on invalid input, 0 when both authored and profile permit infinite range.
class CullDistanceProfile3D : public RefCounted {
	GDCLASS(CullDistanceProfile3D, RefCounted);

private:
	// Stored once per preset; callers can resolve many AABBs without
	// creating and revalidating two packed arrays for each visual instance.
	PackedFloat32Array configured_sizes;
	PackedFloat32Array configured_ranges;

	static bool _valid_pairs(const PackedFloat32Array &p_sizes, const PackedFloat32Array &p_ranges);
	static bool _valid_bounds(const AABB &p_bounds, double p_authored_distance);
	static double _resolve_validated(const AABB &p_bounds,
			const PackedFloat32Array &p_sizes, const PackedFloat32Array &p_ranges,
			double p_authored_distance);

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_PAIRS = 128;
	static constexpr double MAX_VALUE = 1000000.0;
	static constexpr double MAX_COORDINATE = 10000000.0;

	// Atomic validation keeps the previous preset on failure. Pass the same
	// arrays again safely; unchanged profiles are not rebuilt.
	bool configure(const PackedFloat32Array &p_sizes, const PackedFloat32Array &p_ranges);
	int get_pair_count() const { return configured_sizes.size(); }
	void clear_profile();

	// Reuses a configured profile: only bounds and authored cap are validated
	// per instance. Returns -1 if never configured or invalid.
	double get_cached_cull_distance(const AABB &p_bounds,
			double p_authored_distance = 0.0) const;

	double get_cull_distance(const AABB &p_bounds,
			const PackedFloat32Array &p_sizes,
			const PackedFloat32Array &p_ranges,
			double p_authored_distance = 0.0) const;
};
