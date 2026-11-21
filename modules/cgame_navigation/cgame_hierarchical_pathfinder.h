/**************************************************************************/
/*  cgame_hierarchical_pathfinder.h                                       */
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
#include "core/templates/local_vector.h"
#include "core/variant/callable.h"
#include "core/variant/typed_array.h"

// HPA*-style hierarchical pathfinding over a 4-connected walkability grid.
// The grid is cut into square clusters, entrance nodes are placed on shared cluster
// borders, and an abstract graph is searched with A* before the route is refined to cells.
// Paths are valid but not guaranteed to be globally shortest.
class CgameHierarchicalPathfinder : public RefCounted {
	GDCLASS(CgameHierarchicalPathfinder, RefCounted);

	static constexpr int LONG_RUN = 6;
	static constexpr int FAR = 1 << 30;

	struct HeapItem {
		double key = 0.0;
		int val = 0;
	};

	struct Heap {
		LocalVector<HeapItem> items;
		bool is_empty() const { return items.is_empty(); }
		void push(double p_key, int p_val);
		int pop();
	};

	int cache_hits = 0;
	int width = 0;
	int height = 0;
	int cluster_size = 8;
	int cw = 0;
	int ch = 0;

	Vector2 world_origin;
	real_t world_cell_size = 1.0;

	Vector<uint8_t> grid;
	Callable walkable_callable;

	LocalVector<Vector2i> n_cell;
	LocalVector<int> n_cluster;
	LocalVector<uint8_t> n_alive;
	LocalVector<HashMap<int, int>> adj;
	HashMap<Vector2i, int> node_at;
	LocalVector<Vector<int>> cluster_nodes;
	HashMap<Vector2i, Vector<int>> route_cache;

	bool _cell_in_bounds(const Vector2i &p_cell) const;
	bool _is_walkable(const Vector2i &p_cell) const;
	Vector2i _cluster_of(const Vector2i &p_cell) const;
	int _cidx(const Vector2i &p_cluster) const;
	Rect2i _cluster_rect(const Vector2i &p_cluster) const;
	int _add_node(const Vector2i &p_cell);
	void _remove_node(int p_id);
	bool _has_inter_edge(int p_id) const;
	void _link_pair(Vector2i p_a, Vector2i p_b);
	void _build_intra(const Vector2i &p_cluster);
	void _build_graph();
	HashMap<int, int> _flood(const Vector2i &p_from, const Rect2i &p_rect) const;
	HashMap<int, int> _reach(const Vector2i &p_cell, const Vector2i &p_cluster) const;
	bool _route_ok(const Vector<int> &p_route, const HashMap<int, int> &p_start_edges, const HashMap<int, int> &p_goal_costs) const;
	Vector<int> _abstract(const Vector2i &p_goal, const HashMap<int, int> &p_start_edges, const HashMap<int, int> &p_goal_costs) const;
	static int _manhattan(const Vector2i &p_a, const Vector2i &p_b);
	bool _astar(const Vector2i &p_start, const Vector2i &p_goal, const Rect2i &p_rect, Vector<Vector2i> &r_out) const;
	static bool _append_segment(Vector<Vector2i> &r_path, const Vector<Vector2i> &p_seg);
	Vector<Vector2i> _refine(const Vector2i &p_start, const Vector2i &p_goal, const Vector<int> &p_route) const;
	Vector<Vector2i> _find_cells(const Vector2i &p_start, const Vector2i &p_goal);

protected:
	static void _bind_methods();

public:
	// Builds the hierarchy from a callable `walkable(x, y) -> bool`.
	void build(int p_width, int p_height, int p_cluster_size, const Callable &p_walkable);
	// Builds the hierarchy from a row-major array (non-zero byte = walkable).
	void build_from_grid(int p_width, int p_height, int p_cluster_size, const PackedByteArray &p_cells);

	PackedVector2Array find_path(const Vector2i &p_start, const Vector2i &p_goal);
	// Cell path as Vector2i (same cells as find_path).
	Vector<Vector2i> find_path_cells(const Vector2i &p_start, const Vector2i &p_goal);

	void set_cell_walkable(const Vector2i &p_cell, bool p_walkable);
	void invalidate_cluster(const Vector2i &p_cell);
	bool is_cell_walkable(const Vector2i &p_cell) const;

	int node_count() const;
	int get_cache_hits() const { return cache_hits; }
	int get_width() const { return width; }
	int get_height() const { return height; }
	int get_cluster_size() const { return cluster_size; }

	void set_world_mapping(const Vector2 &p_origin_xz, real_t p_cell_size);
	Vector2i world_to_cell(const Vector3 &p_world) const;
	Vector3 cell_to_world(const Vector2i &p_cell, real_t p_y = 0.0) const;

	// Coarse waypoints (one per region crossed) between two world positions.
	Vector<Vector3> plan_waypoints(const Vector3 &p_from, const Vector3 &p_to, real_t p_region_size);
	// Chains NavigationServer3D.map_get_path over the region corridor. Empty when no server or unreachable.
	Vector<Vector3> plan_on_map(const RID &p_map, const Vector3 &p_from, const Vector3 &p_to, real_t p_region_size, uint32_t p_navigation_layers = 1);

	CgameHierarchicalPathfinder() {}
};
