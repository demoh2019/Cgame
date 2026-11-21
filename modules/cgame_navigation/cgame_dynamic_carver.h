/**************************************************************************/
/*  cgame_dynamic_carver.h                                                */
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
#include "core/templates/rid.h"
#include "core/variant/callable.h"
#include "core/variant/typed_array.h"
#include "scene/resources/3d/navigation_mesh_source_geometry_data_3d.h"

// Dynamic navmesh obstacle carving with a budgeted tile queue.
// Walkable space is a grid of tiles, each holding convex polygons. Obstacles (polygons or
// circles, grown by the agent radius) are subtracted from the tiles they touch; destroying an
// obstacle re-carves only those tiles. Tile re-carving happens through `update(budget)`.
//
// Engine integration:
//  - Obstacles can be mirrored as NavigationServer3D obstacles on a map (avoidance).
//  - Obstacles can be exported as carving projected obstructions into
//    NavigationMeshSourceGeometryData3D so that Godot's Recast bake carves them natively
//    (the same data NavigationObstacle3D with affect_navigation_mesh produces).
//  - A rebake callable is invoked for every tile re-carved, so the game can queue a native
//    tile rebake under the same budget.
class CgameDynamicCarver : public RefCounted {
	GDCLASS(CgameDynamicCarver, RefCounted);

	static constexpr real_t EPS = 0.002;

	struct Link {
		int to = 0;
		Vector2 a;
		Vector2 b;
	};

	struct Obstacle {
		Vector<Vector<Vector2>> carvers;
		Rect2 rect;
		Vector<Vector2> outline; // Un-grown outline (circle approximated), used for the server.
		real_t circle_radius = 0.0;
		Vector2 circle_center;
		bool is_circle = false;
		RID server_obstacle;
	};

	Rect2 bounds;
	real_t tile_size = 10.0;
	real_t agent_radius = 0.5;
	int version = 0;
	int tiles_rebuilt_total = 0;
	int tiles_x = 0;
	int tiles_y = 0;

	HashMap<Vector2i, Vector<Vector<Vector2>>> base;
	HashMap<Vector2i, Vector<int>> tile_nodes;
	HashMap<Vector2i, int> tile_versions;
	HashMap<int, Vector<Vector2>> node_poly;
	HashMap<int, Rect2> node_rect;
	HashMap<int, Vector2i> node_tile;
	HashMap<int, Vector<Link>> links;
	int next_node = 1;
	Dictionary id_to_slot; // obstacle id (any Variant) -> slot in `obstacles`
	HashMap<int, Obstacle> obstacles;
	int next_slot = 1;
	Vector<Vector2i> dirty;
	HashSet<Vector2i> dirty_set;
	Vector<Vector2i> events;

	RID server_map;
	real_t server_y = 0.0;
	real_t server_height = 2.0;
	Callable rebake_callable;

	void _clear_nodes();
	void _rebuild_all();
	Rect2 _tile_rect(const Vector2i &p_tile) const;
	void _mark_rect_dirty(const Rect2 &p_rect);
	Vector<Vector<Vector2>> _make_carvers(const Variant &p_shape, Obstacle &r_obstacle) const;
	void _rebuild_tile(const Vector2i &p_tile);
	void _remove_tile_nodes(const Vector2i &p_tile);
	void _try_link(int p_a, int p_b);
	const Link *_link_between(int p_a, int p_b) const;
	int _node_at(const Vector2 &p_point) const;
	static bool _inside(const Vector<Vector2> &p_poly, const Vector2 &p_point);
	Vector<Vector<Vector2>> _subtract(const Vector<Vector<Vector2>> &p_polys, const Vector<Vector2> &p_carver) const;
	void _clip_into(const Vector<Vector2> &p_poly, const Vector<Vector2> &p_carver, const Rect2 &p_carver_rect, Vector<Vector<Vector2>> &r_out, int p_depth) const;
	static Vector<Vector2> _funnel(const Vector2 &p_start, const Vector2 &p_goal, const Vector<Vector2> &p_lefts, const Vector<Vector2> &p_rights);
	static real_t _tri2(const Vector2 &p_a, const Vector2 &p_b, const Vector2 &p_c);
	static Vector<Vector2> _rect_poly(const Rect2 &p_rect);
	static Rect2 _bounds_of(const Vector<Vector2> &p_poly);
	static real_t _area(const Vector<Vector2> &p_poly);
	static Vector2 _centroid(const Vector<Vector2> &p_poly);
	void _create_server_obstacle(Obstacle &r_obstacle);
	void _free_server_obstacle(Obstacle &r_obstacle);
	void _release_server_obstacles();

protected:
	static void _bind_methods();

public:
	void setup(const Rect2 &p_bounds, real_t p_tile_size, real_t p_agent_radius);
	// Restricts walkable space to the given polygons (Array of PackedVector2Array).
	void set_walkable(const Array &p_polys);

	// shape: PackedVector2Array polygon, or {"center": Vector2, "radius": float, "segments": int}.
	void add_obstacle(const Variant &p_id, const Variant &p_shape);
	bool remove_obstacle(const Variant &p_id);
	bool on_destroyed(const Variant &p_id);
	bool has_obstacle(const Variant &p_id) const;
	int get_obstacle_count() const { return obstacles.size(); }

	int pending_tiles() const { return dirty.size(); }
	// Re-carves up to max_tiles_per_call dirty tiles (<= 0 means all). Returns tiles rebuilt.
	int update(int p_max_tiles_per_call = 4);
	TypedArray<Vector2i> consume_changed_tiles();
	int tile_version(const Vector2i &p_tile) const;
	Vector2i tile_count() const { return Vector2i(tiles_x, tiles_y); }
	Vector2i tile_of(const Vector2 &p_point) const;
	TypedArray<PackedVector2Array> polygons_in_tile(const Vector2i &p_tile) const;
	bool is_walkable(const Vector2 &p_point) const;
	static bool is_convex(const PackedVector2Array &p_poly);

	PackedVector2Array find_path(const Vector2 &p_from, const Vector2 &p_to) const;
	bool path_affected(const PackedVector2Array &p_path, const TypedArray<Vector2i> &p_changed) const;

	int get_version() const { return version; }
	int get_tiles_rebuilt_total() const { return tiles_rebuilt_total; }
	real_t get_tile_size() const { return tile_size; }
	real_t get_agent_radius() const { return agent_radius; }
	Rect2 get_bounds() const { return bounds; }

	// Engine integration.
	void set_server_map(const RID &p_map, real_t p_y = 0.0, real_t p_height = 2.0);
	RID get_server_map() const { return server_map; }
	int get_server_obstacle_count() const;
	// Adds every obstacle intersecting p_rect (all when p_rect has no area) as a carving
	// projected obstruction. Returns the number of obstructions added.
	int export_obstructions(const Ref<NavigationMeshSourceGeometryData3D> &p_source, real_t p_elevation, real_t p_height, const Rect2 &p_rect = Rect2()) const;
	// Called as callable(tile: Vector2i, tile_rect: Rect2) for every tile re-carved by update().
	void set_rebake_callable(const Callable &p_callable) { rebake_callable = p_callable; }
	Callable get_rebake_callable() const { return rebake_callable; }

	~CgameDynamicCarver();
};
