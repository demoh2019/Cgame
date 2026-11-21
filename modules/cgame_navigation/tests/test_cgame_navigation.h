/**************************************************************************/
/*  test_cgame_navigation.h                                               */
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

#include "../cgame_dynamic_carver.h"
#include "../cgame_hierarchical_pathfinder.h"
#include "../cgame_navigation_util.h"
#include "../cgame_navmesh_baker.h"
#include "../cgame_off_mesh_link_generator.h"

#include "tests/test_macros.h"

namespace TestCgameNavigation {

static PackedByteArray _open_grid(int p_w, int p_h) {
	PackedByteArray cells;
	cells.resize(p_w * p_h);
	for (int i = 0; i < p_w * p_h; i++) {
		cells.write[i] = 1;
	}
	return cells;
}

static bool _is_valid_cell_path(const Vector<Vector2i> &p_path, const PackedByteArray &p_cells, int p_w, const Vector2i &p_start, const Vector2i &p_goal) {
	if (p_path.is_empty() || p_path[0] != p_start || p_path[p_path.size() - 1] != p_goal) {
		return false;
	}
	for (int i = 0; i < p_path.size(); i++) {
		const Vector2i &c = p_path[i];
		if (p_cells[c.y * p_w + c.x] == 0) {
			return false;
		}
		if (i > 0) {
			Vector2i d = c - p_path[i - 1];
			if (Math::abs(d.x) + Math::abs(d.y) != 1) {
				return false;
			}
		}
	}
	return true;
}

// Reference BFS: shortest 4-connected length or -1.
static int _bfs(const PackedByteArray &p_cells, int p_w, int p_h, const Vector2i &p_start, const Vector2i &p_goal) {
	HashMap<int, int> dist;
	Vector<Vector2i> queue;
	queue.push_back(p_start);
	dist[p_start.y * p_w + p_start.x] = 0;
	int head = 0;
	const Vector2i dirs[4] = { Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1) };
	while (head < queue.size()) {
		Vector2i c = queue[head++];
		int d = dist[c.y * p_w + c.x];
		if (c == p_goal) {
			return d;
		}
		for (const Vector2i &dir : dirs) {
			Vector2i n = c + dir;
			if (n.x < 0 || n.y < 0 || n.x >= p_w || n.y >= p_h || p_cells[n.y * p_w + n.x] == 0 || dist.has(n.y * p_w + n.x)) {
				continue;
			}
			dist[n.y * p_w + n.x] = d + 1;
			queue.push_back(n);
		}
	}
	return -1;
}

// ------------------------------------------------------------------ HPA*

TEST_CASE("[CgameNavigation][HPA] Path around a wall is valid and near optimal") {
	const int w = 24;
	const int h = 24;
	PackedByteArray cells = _open_grid(w, h);
	for (int y = 0; y < 20; y++) {
		cells.write[y * w + 11] = 0;
	}
	Ref<CgameHierarchicalPathfinder> pf;
	pf.instantiate();
	pf->build_from_grid(w, h, 8, cells);
	CHECK(pf->node_count() > 0);

	Vector2i start(1, 1);
	Vector2i goal(22, 2);
	Vector<Vector2i> path = pf->find_path_cells(start, goal);
	CHECK(_is_valid_cell_path(path, cells, w, start, goal));
	int best = _bfs(cells, w, h, start, goal);
	CHECK(best > 0);
	// HPA* is not optimal, but must stay reasonably close on this layout.
	CHECK((path.size() - 1) <= best * 2);

	PackedVector2Array as_floats = pf->find_path(start, goal);
	CHECK(as_floats.size() == path.size());
	CHECK(Vector2i(as_floats[0]) == start);
}

TEST_CASE("[CgameNavigation][HPA] Unreachable goals and blocked end points return empty paths") {
	const int w = 24;
	const int h = 16;
	PackedByteArray cells = _open_grid(w, h);
	for (int y = 0; y < h; y++) {
		cells.write[y * w + 11] = 0; // Full wall.
	}
	cells.write[5 * w + 3] = 0;
	Ref<CgameHierarchicalPathfinder> pf;
	pf.instantiate();
	pf->build_from_grid(w, h, 8, cells);
	CHECK(pf->find_path_cells(Vector2i(1, 1), Vector2i(22, 2)).is_empty());
	CHECK(pf->find_path_cells(Vector2i(3, 5), Vector2i(2, 2)).is_empty()); // Start inside a wall.
	CHECK(pf->find_path_cells(Vector2i(2, 2), Vector2i(-1, 0)).is_empty()); // Out of bounds.
	// Same side still works, including the single cell and within-cluster cases.
	CHECK(pf->find_path_cells(Vector2i(2, 2), Vector2i(2, 2)).size() == 1);
	CHECK(_is_valid_cell_path(pf->find_path_cells(Vector2i(0, 0), Vector2i(9, 15)), cells, w, Vector2i(0, 0), Vector2i(9, 15)));
}

TEST_CASE("[CgameNavigation][HPA] Dynamic obstacles rebuild only the affected cluster") {
	const int w = 24;
	const int h = 24;
	PackedByteArray cells = _open_grid(w, h);
	for (int y = 0; y < h; y++) {
		cells.write[y * w + 11] = 0;
	}
	cells.write[10 * w + 11] = 1; // One gap.
	Ref<CgameHierarchicalPathfinder> pf;
	pf.instantiate();
	pf->build_from_grid(w, h, 8, cells);
	Vector2i start(1, 1);
	Vector2i goal(22, 20);
	CHECK(_is_valid_cell_path(pf->find_path_cells(start, goal), cells, w, start, goal));

	pf->set_cell_walkable(Vector2i(11, 10), false);
	cells.write[10 * w + 11] = 0;
	CHECK(pf->find_path_cells(start, goal).is_empty());
	CHECK(!pf->is_cell_walkable(Vector2i(11, 10)));

	pf->set_cell_walkable(Vector2i(11, 10), true);
	cells.write[10 * w + 11] = 1;
	CHECK(_is_valid_cell_path(pf->find_path_cells(start, goal), cells, w, start, goal));
}

TEST_CASE("[CgameNavigation][HPA] Abstract routes are cached between queries") {
	const int w = 32;
	const int h = 32;
	PackedByteArray cells = _open_grid(w, h);
	Ref<CgameHierarchicalPathfinder> pf;
	pf.instantiate();
	pf->build_from_grid(w, h, 8, cells);
	CHECK(pf->get_cache_hits() == 0);
	CHECK(!pf->find_path_cells(Vector2i(1, 1), Vector2i(30, 30)).is_empty());
	CHECK(!pf->find_path_cells(Vector2i(2, 1), Vector2i(29, 30)).is_empty());
	CHECK(pf->get_cache_hits() >= 1);
}

TEST_CASE("[CgameNavigation][HPA] World-space waypoints follow region corridors") {
	const int w = 40;
	const int h = 8;
	PackedByteArray cells = _open_grid(w, h);
	Ref<CgameHierarchicalPathfinder> pf;
	pf.instantiate();
	pf->build_from_grid(w, h, 8, cells);
	pf->set_world_mapping(Vector2(100.0, 50.0), 2.0);
	CHECK(pf->world_to_cell(Vector3(101.0, 0.0, 51.0)) == Vector2i(0, 0));
	CHECK(pf->cell_to_world(Vector2i(1, 2), 5.0).is_equal_approx(Vector3(103.0, 5.0, 55.0)));

	Vector3 from = pf->cell_to_world(Vector2i(0, 3));
	Vector3 to = pf->cell_to_world(Vector2i(39, 3));
	Vector<Vector3> waypoints = pf->plan_waypoints(from, to, 16.0);
	CHECK(waypoints.size() >= 3);
	CHECK(waypoints[0].is_equal_approx(from));
	CHECK(waypoints[waypoints.size() - 1].is_equal_approx(to));

	// A full wall makes the coarse plan fail.
	for (int y = 0; y < h; y++) {
		cells.write[y * w + 20] = 0;
	}
	pf->build_from_grid(w, h, 8, cells);
	CHECK(pf->plan_waypoints(from, to, 16.0).is_empty());
}

TEST_CASE("[CgameNavigation][HPA] plan_on_map is guarded when the NavigationServer3D is a dummy") {
	Ref<CgameHierarchicalPathfinder> pf;
	pf.instantiate();
	pf->build_from_grid(8, 8, 4, _open_grid(8, 8));
	if (!CgameNavigationUtil::is_server_functional()) {
		CHECK(pf->plan_on_map(RID(), Vector3(), Vector3(5, 0, 5), 4.0).is_empty());
	} else {
		// Invalid map RID never yields a path.
		CHECK(pf->plan_on_map(RID(), Vector3(), Vector3(5, 0, 5), 4.0).is_empty());
	}
}

// ------------------------------------------------------------------ Off-mesh links

TEST_CASE("[CgameNavigation][OffMesh] Drop, jump and gap links from a heightfield") {
	// Row 0: heights 0, 0, 0.8 (jump), 0.8, 4.0? (rise 3.2 > max_drop: nothing)
	// Row 1: 3.0 | blocked | 3.0 (gap)   Row 2: 0, 2.0 (drop)
	const int w = 5;
	const int h = 3;
	PackedFloat32Array heights;
	PackedByteArray walk;
	heights.resize(w * h);
	walk.resize(w * h);
	for (int i = 0; i < w * h; i++) {
		heights.write[i] = 0.0f;
		walk.write[i] = 0;
	}
	auto set_cell = [&](int x, int y, float hh) {
		heights.write[y * w + x] = hh;
		walk.write[y * w + x] = 1;
	};
	set_cell(0, 0, 0.0f);
	set_cell(1, 0, 0.0f);
	set_cell(2, 0, 0.8f);
	set_cell(3, 0, 0.8f);
	set_cell(4, 0, 4.0f);
	set_cell(0, 2, 3.0f);
	set_cell(2, 2, 3.0f);
	set_cell(3, 2, 0.5f);
	set_cell(4, 2, 2.0f);

	Ref<CgameOffMeshLinkGenerator> gen;
	gen.instantiate();
	Array links = gen->generate_from_arrays(w, h, heights, walk);

	int jumps = 0;
	int drops = 0;
	int gaps = 0;
	for (int i = 0; i < links.size(); i++) {
		Dictionary l = links[i];
		String kind = l["kind"];
		Vector2i from = l["from"];
		Vector2i to = l["to"];
		bool bidir = l["bidirectional"];
		if (kind == "jump") {
			jumps++;
			CHECK(bidir);
			CHECK(from == Vector2i(1, 0)); // From the lower cell to the upper one.
			CHECK(to == Vector2i(2, 0));
		} else if (kind == "drop") {
			drops++;
			CHECK(!bidir);
			// A drop starts at the higher cell.
			CHECK(heights[from.y * w + from.x] > heights[to.y * w + to.x]);
		} else if (kind == "gap") {
			gaps++;
			CHECK(bidir);
			bool across_row = from == Vector2i(0, 2) && to == Vector2i(2, 2); // Over the blocked cell (1, 2).
			bool across_column = from == Vector2i(3, 0) && to == Vector2i(3, 2); // Over the blocked cell (3, 1).
			CHECK((across_row || across_column));
		}
	}
	CHECK(jumps == 1);
	CHECK(gaps == 2);
	// (2,2)=3.0 -> (3,2)=0.5 is a 2.5 drop and (3,2)=0.5 -> (4,2)=2.0 is a 1.5 drop... (4,2) is higher: drop from (4,2).
	CHECK(drops == 2);
	// (3,0)=0.8 -> (4,0)=4.0 rises 3.2, beyond max_drop: no link.
	for (int i = 0; i < links.size(); i++) {
		Dictionary l = links[i];
		Vector2i a = l["from"];
		Vector2i b = l["to"];
		CHECK(!((a == Vector2i(3, 0) && b == Vector2i(4, 0)) || (a == Vector2i(4, 0) && b == Vector2i(3, 0))));
	}

	// Server-side link creation is a no-op without a functioning server and never leaks.
	if (!CgameNavigationUtil::is_server_functional()) {
		CHECK(gen->create_links_on_map(RID(), Vector2(), 1.0) == 0);
		CHECK(gen->get_map_link_count() == 0);
	}
}

TEST_CASE("[CgameNavigation][OffMesh] Link world positions use cell centres and heights") {
	PackedFloat32Array heights;
	PackedByteArray walk;
	heights.push_back(0.0f);
	heights.push_back(1.0f);
	walk.push_back(1);
	walk.push_back(1);
	Ref<CgameOffMeshLinkGenerator> gen;
	gen.instantiate();
	Array links = gen->generate_from_arrays(2, 1, heights, walk, 3.0, 1.2, 2, 0.5);
	CHECK(links.size() == 1);
	Dictionary pos = gen->link_world_positions(links[0], Vector2(10.0, 20.0), 2.0);
	Vector3 start = pos["start"];
	Vector3 end = pos["end"];
	CHECK(start.is_equal_approx(Vector3(11.0, 0.0, 21.0)));
	CHECK(end.is_equal_approx(Vector3(13.0, 1.0, 21.0)));
}

TEST_CASE("[CgameNavigation][OffMesh] Rejects malformed input") {
	Ref<CgameOffMeshLinkGenerator> gen;
	gen.instantiate();
	ERR_PRINT_OFF;
	CHECK(gen->generate_from_arrays(0, 3, PackedFloat32Array(), PackedByteArray()).is_empty());
	CHECK(gen->generate_from_arrays(2, 2, PackedFloat32Array(), PackedByteArray()).is_empty());
	ERR_PRINT_ON;
}

// ------------------------------------------------------------------ Baker conversions

TEST_CASE("[CgameNavigation][Baker] Config maps onto NavigationMesh properties") {
	Ref<CgameNavmeshBaker> baker;
	baker.instantiate();
	Dictionary values;
	values["cell_size"] = 0.5;
	values["agent_radius"] = 0.75;
	values["agent_max_slope_deg"] = 30.0;
	values["max_verts_per_poly"] = 5;
	values["region_min_area"] = 16;
	values["max_simplification_error"] = 2.0;
	baker->configure(values);
	CHECK(float(baker->get_config()["tile_size"]) == 16.0f); // Defaults are kept.

	Ref<NavigationMesh> nm = baker->make_navigation_mesh();
	CHECK(nm.is_valid());
	CHECK(nm->get_cell_size() == doctest::Approx(0.5));
	CHECK(nm->get_agent_radius() == doctest::Approx(0.75));
	CHECK(nm->get_agent_max_slope() == doctest::Approx(30.0));
	CHECK(nm->get_vertices_per_polygon() == doctest::Approx(5.0));
	CHECK(nm->get_region_min_size() == doctest::Approx(4.0)); // sqrt(16 voxels).
	CHECK(nm->get_edge_max_error() == doctest::Approx(2.0));
	CHECK(nm->get_sample_partition_type() == NavigationMesh::SAMPLE_PARTITION_MONOTONE);
}

TEST_CASE("[CgameNavigation][Baker] Tile rectangles are row-major") {
	Ref<CgameNavmeshBaker> baker;
	baker.instantiate();
	Dictionary values;
	values["tile_size"] = 16.0;
	baker->configure(values);
	TypedArray<AABB> rects = baker->tile_rects(AABB(Vector3(-8, 0, 4), Vector3(32, 5, 20)));
	CHECK(rects.size() == 4); // 2 x 2 tiles.
	AABB first = rects[0];
	AABB second = rects[1];
	AABB third = rects[2];
	CHECK(first.position.is_equal_approx(Vector3(-8, 0, 4)));
	CHECK(second.position.is_equal_approx(Vector3(8, 0, 4)));
	CHECK(third.position.is_equal_approx(Vector3(-8, 0, 20)));
	CHECK(first.size.is_equal_approx(Vector3(16, 5, 16)));
}

TEST_CASE("[CgameNavigation][Baker] NavigationMesh converts to clipped positive-area tile polygons and back") {
	Ref<NavigationMesh> nm;
	nm.instantiate();
	Vector<Vector3> verts;
	verts.push_back(Vector3(0, 1, 0));
	verts.push_back(Vector3(10, 1, 0));
	verts.push_back(Vector3(10, 3, 10));
	verts.push_back(Vector3(0, 3, 10));
	// A second quad entirely outside the tile.
	verts.push_back(Vector3(20, 0, 0));
	verts.push_back(Vector3(30, 0, 0));
	verts.push_back(Vector3(30, 0, 10));
	verts.push_back(Vector3(20, 0, 10));
	nm->set_vertices(verts);
	Vector<int> quad_a;
	// Counter-clockwise in (x, z): the converter must normalise to positive shoelace area.
	quad_a.push_back(0);
	quad_a.push_back(3);
	quad_a.push_back(2);
	quad_a.push_back(1);
	nm->add_polygon(quad_a);
	Vector<int> quad_b;
	quad_b.push_back(4);
	quad_b.push_back(5);
	quad_b.push_back(6);
	quad_b.push_back(7);
	nm->add_polygon(quad_b);

	Ref<CgameNavmeshBaker> baker;
	baker.instantiate();
	Dictionary tile = baker->navigation_mesh_to_tile(nm, AABB(Vector3(0, 0, 0), Vector3(5, 10, 5)));
	CHECK(Vector2(tile["origin"]).is_equal_approx(Vector2(0, 0)));
	CHECK(float(tile["size"]) == 5.0f);
	Array polys = tile["polygons"];
	Array heights = tile["heights"];
	REQUIRE(polys.size() == 1); // The far quad is dropped.
	REQUIRE(heights.size() == 1);
	PackedVector2Array poly = polys[0];
	PackedFloat32Array hs = heights[0];
	CHECK(poly.size() == 4);
	CHECK(hs.size() == 4);
	float area = 0.0f;
	for (int i = 0; i < poly.size(); i++) {
		Vector2 a = poly[i];
		Vector2 b = poly[(i + 1) % poly.size()];
		area += a.x * b.y - b.x * a.y;
	}
	CHECK(area * 0.5f == doctest::Approx(25.0f));
	for (int i = 0; i < poly.size(); i++) {
		// Heights are interpolated along the slope (y = 1 + z / 5), so they stay inside [1, 2].
		CHECK(hs[i] >= 1.0f - 1e-4f);
		CHECK(hs[i] <= 2.0f + 1e-4f);
		CHECK(poly[i].x >= -1e-4f);
		CHECK(poly[i].x <= 5.0f + 1e-4f);
	}

	Ref<NavigationMesh> back = baker->tile_to_navigation_mesh(tile);
	CHECK(back->get_polygon_count() == 1);
	CHECK(back->get_vertices().size() == 4);
	CHECK(back->get_polygon(0).size() == 4);
}

TEST_CASE("[CgameNavigation][Baker] Source geometry holds the triangle soup and bake_tile is guarded") {
	PackedVector3Array tris;
	tris.push_back(Vector3(0, 0, 0));
	tris.push_back(Vector3(0, 0, 4));
	tris.push_back(Vector3(4, 0, 0));
	Ref<NavigationMeshSourceGeometryData3D> source = CgameNavmeshBaker::make_source_geometry(tris);
	CHECK(source->get_vertices().size() == 9); // 3 vertices x 3 floats.
	CHECK(source->get_indices().size() == 3);

	if (!CgameNavigationUtil::is_server_functional()) {
		Ref<CgameNavmeshBaker> baker;
		baker.instantiate();
		Dictionary tile = baker->bake_tile(tris, AABB(Vector3(0, 0, 0), Vector3(16, 0, 16)));
		CHECK(!bool(tile["baked"]));
		Array polys = tile["polygons"];
		CHECK(polys.is_empty());
		int job = baker->bake_async(tris, AABB(Vector3(0, 0, 0), Vector3(32, 0, 16)));
		Dictionary result = baker->poll(job);
		CHECK(bool(result["done"]));
		Array tiles = result["tiles"];
		CHECK(tiles.size() == 2);
	}
}

// ------------------------------------------------------------------ Dynamic carver

static Ref<CgameDynamicCarver> _make_carver(real_t p_agent_radius = 0.0) {
	Ref<CgameDynamicCarver> carver;
	carver.instantiate();
	carver->setup(Rect2(0, 0, 40, 40), 10.0, p_agent_radius);
	return carver;
}

static Dictionary _circle(const Vector2 &p_center, real_t p_radius) {
	Dictionary d;
	d["center"] = p_center;
	d["radius"] = p_radius;
	return d;
}

TEST_CASE("[CgameNavigation][Carver] Fresh carver is fully walkable with one polygon per tile") {
	Ref<CgameDynamicCarver> carver = _make_carver();
	CHECK(carver->tile_count() == Vector2i(4, 4));
	CHECK(carver->pending_tiles() == 0);
	CHECK(carver->is_walkable(Vector2(20, 20)));
	CHECK(!carver->is_walkable(Vector2(-5, 5)));
	CHECK(carver->polygons_in_tile(Vector2i(1, 1)).size() == 1);
	CHECK(carver->tile_of(Vector2(25, 5)) == Vector2i(2, 0));
	CHECK(CgameDynamicCarver::is_convex(PackedVector2Array({ Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1) })));
	CHECK(!CgameDynamicCarver::is_convex(PackedVector2Array({ Vector2(0, 0), Vector2(2, 0), Vector2(1, 0.5), Vector2(2, 2), Vector2(0, 2) })));
}

TEST_CASE("[CgameNavigation][Carver] Tile rebake budget queue") {
	Ref<CgameDynamicCarver> carver = _make_carver();
	// A circle on a tile corner touches four tiles.
	carver->add_obstacle("pillar", _circle(Vector2(20, 20), 3.0));
	CHECK(carver->has_obstacle("pillar"));
	CHECK(carver->pending_tiles() == 4);
	// Nothing is carved until update() runs.
	CHECK(carver->is_walkable(Vector2(20, 20)));

	CHECK(carver->update(1) == 1);
	CHECK(carver->pending_tiles() == 3);
	CHECK(carver->update(2) == 2);
	CHECK(carver->pending_tiles() == 1);
	CHECK(carver->get_version() == 2);
	CHECK(carver->update(8) == 1); // Only what is left.
	CHECK(carver->pending_tiles() == 0);
	CHECK(carver->update(8) == 0);

	CHECK(!carver->is_walkable(Vector2(20, 20)));
	CHECK(carver->is_walkable(Vector2(25, 20)));
	CHECK(carver->tile_version(Vector2i(1, 1)) == 1);

	TypedArray<Vector2i> changed = carver->consume_changed_tiles();
	CHECK(changed.size() == 4);
	CHECK(carver->consume_changed_tiles().is_empty());
	CHECK(carver->tile_version(Vector2i(3, 3)) == 0); // Untouched tile.

	// Destroying the obstacle re-queues the same tiles; budget 0 means "all".
	CHECK(carver->on_destroyed("pillar"));
	CHECK(!carver->on_destroyed("pillar"));
	CHECK(carver->pending_tiles() == 4);
	CHECK(carver->update(0) == 4);
	CHECK(carver->is_walkable(Vector2(20, 20)));
	CHECK(carver->tile_version(Vector2i(1, 1)) == 2);
}

TEST_CASE("[CgameNavigation][Carver] Re-adding an obstacle does not queue duplicate tiles") {
	Ref<CgameDynamicCarver> carver = _make_carver();
	carver->add_obstacle(1, _circle(Vector2(5, 5), 1.0));
	carver->add_obstacle(2, _circle(Vector2(6, 6), 1.0));
	CHECK(carver->pending_tiles() == 1);
	carver->add_obstacle(1, _circle(Vector2(5, 5), 1.0)); // Replace.
	CHECK(carver->get_obstacle_count() == 2);
	CHECK(carver->pending_tiles() == 1);
}

TEST_CASE("[CgameNavigation][Carver] Paths route around walls and fail when sealed") {
	Ref<CgameDynamicCarver> carver = _make_carver();
	PackedVector2Array wall;
	wall.push_back(Vector2(19, -1));
	wall.push_back(Vector2(21, -1));
	wall.push_back(Vector2(21, 34));
	wall.push_back(Vector2(19, 34));
	carver->add_obstacle("wall", wall);
	carver->update(0);

	Vector2 from(5, 10);
	Vector2 to(35, 10);
	CHECK(carver->is_walkable(from));
	CHECK(!carver->is_walkable(Vector2(20, 10)));
	PackedVector2Array path = carver->find_path(from, to);
	REQUIRE(path.size() >= 3);
	CHECK(path[0].is_equal_approx(from));
	CHECK(path[path.size() - 1].is_equal_approx(to));
	real_t max_y = 0.0;
	for (int i = 0; i < path.size(); i++) {
		max_y = MAX(max_y, path[i].y);
	}
	CHECK(max_y >= 33.9); // Goes around the top end of the wall.

	// A change in a tile on the path is reported.
	TypedArray<Vector2i> changed = carver->consume_changed_tiles();
	CHECK(carver->path_affected(path, changed));
	TypedArray<Vector2i> far_tile;
	far_tile.push_back(Vector2i(0, 3));
	CHECK(!carver->path_affected(PackedVector2Array({ Vector2(2, 2), Vector2(8, 2) }), far_tile));

	// Seal the gap: no path.
	PackedVector2Array cap;
	cap.push_back(Vector2(19, 33));
	cap.push_back(Vector2(21, 33));
	cap.push_back(Vector2(21, 41));
	cap.push_back(Vector2(19, 41));
	carver->add_obstacle("cap", cap);
	carver->update(0);
	CHECK(carver->find_path(from, to).is_empty());

	// Destruction reopens the route.
	CHECK(carver->on_destroyed("cap"));
	carver->update(0);
	CHECK(!carver->find_path(from, to).is_empty());
}

TEST_CASE("[CgameNavigation][Carver] Agent radius grows obstacles") {
	Ref<CgameDynamicCarver> carver = _make_carver(1.0);
	carver->add_obstacle("crate", _circle(Vector2(15, 15), 2.0));
	carver->update(0);
	CHECK(!carver->is_walkable(Vector2(17.8, 15))); // Inside radius 2 + agent 1 (circumscribed polygon).
	CHECK(carver->is_walkable(Vector2(19, 15)));
}

TEST_CASE("[CgameNavigation][Carver] Restricted walkable area") {
	Ref<CgameDynamicCarver> carver = _make_carver();
	PackedVector2Array island;
	island.push_back(Vector2(5, 5));
	island.push_back(Vector2(35, 5));
	island.push_back(Vector2(35, 35));
	island.push_back(Vector2(5, 35));
	Array walkable;
	walkable.push_back(island);
	carver->set_walkable(walkable);
	CHECK(carver->is_walkable(Vector2(20, 20)));
	CHECK(!carver->is_walkable(Vector2(2, 2)));
	CHECK(carver->find_path(Vector2(20, 20), Vector2(2, 2)).is_empty());
}

TEST_CASE("[CgameNavigation][Carver] Obstacles export as carving projected obstructions") {
	Ref<CgameDynamicCarver> carver = _make_carver();
	carver->add_obstacle("a", _circle(Vector2(5, 5), 1.0));
	carver->add_obstacle("b", _circle(Vector2(35, 35), 1.0));
	Ref<NavigationMeshSourceGeometryData3D> source;
	source.instantiate();
	CHECK(carver->export_obstructions(source, 0.0, 2.0) == 2);
	CHECK(source->get_projected_obstructions().size() == 2);
	Array first = source->get_projected_obstructions();
	Dictionary d = first[0];
	CHECK(bool(d["carve"]));
	source->clear_projected_obstructions();
	// Only obstacles overlapping the rectangle.
	CHECK(carver->export_obstructions(source, 0.0, 2.0, Rect2(0, 0, 10, 10)) == 1);
}

TEST_CASE("[CgameNavigation][Carver] Server obstacles are only created with a functioning server") {
	Ref<CgameDynamicCarver> carver = _make_carver();
	carver->add_obstacle("a", _circle(Vector2(5, 5), 1.0));
	carver->set_server_map(RID(), 0.0, 2.0);
	CHECK(carver->get_server_obstacle_count() == 0);
	if (!CgameNavigationUtil::is_server_functional()) {
		// Even with a (fake) valid map nothing may be created on a dummy server.
		CHECK(carver->get_server_obstacle_count() == 0);
	}
}

} // namespace TestCgameNavigation
