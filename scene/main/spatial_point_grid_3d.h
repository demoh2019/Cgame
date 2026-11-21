/**************************************************************************/
/*  spatial_point_grid_3d.h                                               */
/*  Cgame: bounded 3D spatial occupancy queries (data-only, no physics).  */
/**************************************************************************/

#pragma once

#include "core/math/vector3.h"
#include "core/math/vector3i.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"
#include "core/variant/variant.h"

// Native, reusable server-side 3D relevance/count broadphase. Unlike a 2D
// ground grid, height separation always contributes to true Euclidean range.
// No actors, networking, SceneTree or mutation of queried game state.
class SpatialPointGrid3D : public RefCounted {
	GDCLASS(SpatialPointGrid3D, RefCounted);

	static constexpr int MAX_POINTS = 8192;
	static constexpr int MAX_PROBES = 1024;
	static constexpr int MAX_BUCKET_VISITS = 4096;
	Vector<Vector3> positions;
	HashMap<Vector3i, Vector<Vector3>> cells;
	real_t cell_size = 64.0;
	bool indexed_mode = false;
	uint64_t queries = 0;
	uint64_t batch_calls = 0;
	uint64_t candidate_checks = 0;
	uint64_t bucket_lookups = 0;

	static Vector3i _cell_of(const Vector3 &p_point, real_t p_size);
	bool _safe_cell(const Vector3 &p_point) const;
	void _reindex();
	int _direct_count(const Vector3 &p_center, real_t p_squared_radius, int p_limit);
protected:
	static void _bind_methods();

public:
	bool set_cell_size(real_t p_cell_size);
	real_t get_cell_size() const { return cell_size; }
	bool rebuild(const TypedArray<Vector3> &p_positions);
	void clear();
	// Count exact 3D matches, stop at limit. -1 means invalid query.
	// No truncation beyond caller-specified cap and no cross-layer XZ hits.
	int count_within(const Vector3 &p_center, real_t p_radius, int p_limit = 20);
	// One result per probe, in order. Invalid individual probe -> zero.
	// Invalid global arguments -> empty array (fail closed).
	PackedInt32Array count_within_batch(const PackedVector3Array &p_centers, real_t p_radius, int p_limit = 20);
	int get_point_count() const { return positions.size(); }
	Dictionary get_stats() const;
};
