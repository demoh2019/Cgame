/**************************************************************************/
/*  navmesh_carving.h                                                     */
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
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "core/templates/local_vector.h"
#include "core/variant/typed_array.h"

// Dynamic navmesh obstacle carving with a budgeted tile cache. Walkable space is a grid of tiles
// holding convex polygons; obstacles (polygons or circles grown by the agent radius) are
// subtracted from the tiles they touch and rebuilt tiles are re-linked to their neighbours.
class NavMeshCarving : public RefCounted {
	GDCLASS(NavMeshCarving, RefCounted);

	static constexpr real_t EPS = 0.002f;

	struct Link {
		int to = 0;
		Vector2 a;
		Vector2 b;
	};

	struct NavNode {
		PackedVector2Array poly;
		Rect2 rect;
		Vector2i tile;
		LocalVector<Link> links;
	};

	struct Obstacle {
		LocalVector<PackedVector2Array> carvers;
		Rect2 rect;
	};

	Rect2 bounds;
	real_t tile_size = 10.0;
	real_t agent_radius = 0.5;
	int version = 0;
	int tiles_rebuilt_total = 0;
	int tiles_x = 0;
	int tiles_y = 0;
	HashMap<Vector2i, Vector<PackedVector2Array>> base;
	HashMap<Vector2i, PackedInt32Array> tile_nodes;
	HashMap<Vector2i, int> tile_versions;
	HashMap<int, NavNode> nodes;
	int next_node = 1;
	HashMap<Variant, Obstacle, HashMapHasherDefault, StringLikeVariantComparator> obstacles;
	LocalVector<Vector2i> dirty;
	HashSet<Vector2i> dirty_set;
	LocalVector<Vector2i> events;

	void _clear_nodes();
	void _rebuild_all();
	Rect2 _tile_rect(const Vector2i &p_tile) const;
	void _mark_rect_dirty(const Rect2 &p_rect);
	LocalVector<PackedVector2Array> _make_carvers(const Variant &p_shape) const;
	void _rebuild_tile(const Vector2i &p_tile);
	void _remove_tile_nodes(const Vector2i &p_tile);
	void _try_link(int p_a, int p_b);
	const Link *_link_between(int p_a, int p_b) const;
	int _node_at(const Vector2 &p_point) const;
	static bool _inside(const PackedVector2Array &p_poly, const Vector2 &p_point);
	Vector<PackedVector2Array> _subtract(const Vector<PackedVector2Array> &p_polys, const PackedVector2Array &p_carver) const;
	void _clip_into(const PackedVector2Array &p_poly, const PackedVector2Array &p_carver, const Rect2 &p_carver_rect, Vector<PackedVector2Array> &r_out, int p_depth) const;
	static PackedVector2Array _rect_poly(const Rect2 &p_rect);
	static Rect2 _bounds_of(const PackedVector2Array &p_poly);
	static real_t _area(const PackedVector2Array &p_poly);
	static Vector2 _centroid(const PackedVector2Array &p_poly);

protected:
	static void _bind_methods();

public:
	void set_agent_radius(real_t p_radius);
	real_t get_agent_radius() const;
	real_t get_tile_size() const;
	Rect2 get_bounds() const;
	int get_version() const;
	int get_tiles_rebuilt_total() const;

	void setup(const Rect2 &p_bounds, real_t p_tile_size, real_t p_agent_radius);
	void set_walkable(const Array &p_polys);
	void add_obstacle(const Variant &p_id, const Variant &p_shape);
	bool remove_obstacle(const Variant &p_id);
	bool on_destroyed(const Variant &p_id);
	bool has_obstacle(const Variant &p_id) const;
	int pending_tiles() const;
	int update(int p_max_tiles_per_call = 4);
	TypedArray<Vector2i> consume_changed_tiles();
	int tile_version(const Vector2i &p_tile) const;
	Vector2i tile_count() const;
	Vector2i tile_of(const Vector2 &p_point) const;
	TypedArray<PackedVector2Array> polygons_in_tile(const Vector2i &p_tile) const;
	bool is_walkable(const Vector2 &p_point) const;
	static bool is_convex(const PackedVector2Array &p_poly);
	static real_t polygon_area(const PackedVector2Array &p_poly);
	PackedVector2Array find_path(const Vector2 &p_from, const Vector2 &p_to) const;
	bool path_affected(const PackedVector2Array &p_path, const TypedArray<Vector2i> &p_changed) const;
};
