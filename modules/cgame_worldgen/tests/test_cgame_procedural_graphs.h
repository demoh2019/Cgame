/**************************************************************************/
/*  test_cgame_procedural_graphs.h                                        */
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

#include "../cgame_procedural_buildings.h"
#include "../cgame_procedural_caves.h"
#include "../cgame_road_network.h"

#include "core/math/math_funcs.h"
#include "core/object/callable_mp.h"
#include "core/math/random_number_generator.h"
#include "tests/test_macros.h"

// Mirrors tests/test_procedural_graphs.gd: procedural caves, buildings/settlements and road graphs.
namespace TestCgameProceduralGraphs {

static bool bytes_equal(const PackedByteArray &p_a, const PackedByteArray &p_b) {
	if (p_a.size() != p_b.size()) {
		return false;
	}
	for (int i = 0; i < p_a.size(); i++) {
		if (p_a[i] != p_b[i]) {
			return false;
		}
	}
	return true;
}

TEST_CASE("[CgameProceduralCaves] Caves are deterministic and connected") {
	const int w = 64;
	const int h = 48;
	const PackedByteArray a = CgameProceduralCaves::generate(w, h, 1234);
	const PackedByteArray b = CgameProceduralCaves::generate(w, h, 1234);
	const PackedByteArray c = CgameProceduralCaves::generate(w, h, 99);
	CHECK_MESSAGE(bytes_equal(a, b), "same seed gives identical cave");
	CHECK_FALSE_MESSAGE(bytes_equal(a, c), "different seed gives a different cave");
	int open = 0;
	for (int i = 0; i < a.size(); i++) {
		if (a[i] == 0) {
			open++;
		}
	}
	CHECK_MESSAGE(open > 200, "cave has open floor");
	CHECK_MESSAGE(CgameProceduralCaves::regions(a, w, h).size() == 1, "cave is a single connected region");
	for (int seed = 1; seed <= 6; seed++) {
		const PackedByteArray g = CgameProceduralCaves::generate(w, h, seed, 0.55, 3);
		CHECK_MESSAGE(CgameProceduralCaves::regions(g, w, h).size() == 1, vformat("dense cave connected for seed %d", seed));
	}
	bool border_rock = true;
	for (int x = 0; x < w; x++) {
		if (a[x] != 1 || a[(h - 1) * w + x] != 1) {
			border_rock = false;
		}
	}
	CHECK_MESSAGE(border_rock, "border stays rock");
}

TEST_CASE("[CgameProceduralCaves] Regions and chambers on a hand-made grid") {
	// Two rooms split by rock.
	PackedByteArray tiny;
	tiny.resize(10 * 5);
	tiny.fill(1);
	const int xs[5] = { 1, 2, 6, 7, 8 };
	for (int y = 1; y < 4; y++) {
		for (int x : xs) {
			tiny.set(y * 10 + x, 0);
		}
	}
	CHECK_MESSAGE(CgameProceduralCaves::regions(tiny, 10, 5).size() == 2, "regions finds two rooms");
	CHECK_MESSAGE(CgameProceduralCaves::chambers(tiny, 10, 5, 8).size() == 1, "chambers filters by size");
	CHECK_MESSAGE(CgameProceduralCaves::chambers(tiny, 10, 5, 1).size() == 2, "chambers returns both rooms");
	const Array ch = CgameProceduralCaves::chambers(tiny, 10, 5, 8);
	const Vector2 p = ch[0];
	CHECK_MESSAGE(tiny[(int)p.y * 10 + (int)p.x] == 0, "chamber centre is on open floor");
	// The larger (9-cell) room comes first.
	CHECK(p.x >= 6.0f);

	const PackedByteArray real = CgameProceduralCaves::generate(64, 48, 1234);
	CHECK_MESSAGE(CgameProceduralCaves::chambers(real, 64, 48, 20).size() >= 1, "generated cave has a chamber");

	// Large maps take the threaded smoothing path and must still be deterministic.
	const PackedByteArray big1 = CgameProceduralCaves::generate(200, 200, 5);
	const PackedByteArray big2 = CgameProceduralCaves::generate(200, 200, 5);
	CHECK(bytes_equal(big1, big2));
	CHECK(CgameProceduralCaves::regions(big1, 200, 200).size() == 1);
}

TEST_CASE("[CgameProceduralBuildings] Buildings tile their footprint with reachable rooms") {
	const Vector2i fp(16, 12);
	const Dictionary b1 = CgameProceduralBuildings::building(7, fp, 3);
	const Dictionary b2 = CgameProceduralBuildings::building(7, fp, 3);
	CHECK_MESSAGE(b1 == b2, "same seed gives identical building");
	const Array rooms = b1["rooms"];
	CHECK_MESSAGE(rooms.size() >= 3, "building has several rooms");
	const Array doors = b1["doors"];
	for (int f = 0; f < 3; f++) {
		Vector<Rect2i> floor_rects;
		int area = 0;
		bool min_ok = true;
		Vector<int> ids;
		for (int i = 0; i < rooms.size(); i++) {
			const Dictionary rd = rooms[i];
			if ((int)rd["floor"] != f) {
				continue;
			}
			const Rect2i r = rd["rect"];
			floor_rects.push_back(r);
			ids.push_back((int)rd["id"]);
			area += r.get_area();
			if (r.size.x < 3 || r.size.y < 3) {
				min_ok = false;
			}
			CHECK_MESSAGE(Rect2i(Vector2i(), fp).encloses(r), "room inside footprint");
		}
		CHECK_MESSAGE(area == fp.x * fp.y, vformat("rooms cover footprint on floor %d", f));
		CHECK_MESSAGE(min_ok, vformat("rooms at least 3x3 on floor %d", f));
		bool overlap = false;
		for (int i = 0; i < floor_rects.size(); i++) {
			for (int j = i + 1; j < floor_rects.size(); j++) {
				if (floor_rects[i].intersects(floor_rects[j])) {
					overlap = true;
				}
			}
		}
		CHECK_MESSAGE(!overlap, vformat("rooms do not overlap on floor %d", f));

		// Reachability through doors.
		HashSet<int> seen;
		seen.insert(ids[0]);
		bool changed = true;
		while (changed) {
			changed = false;
			for (int i = 0; i < doors.size(); i++) {
				const Dictionary dd = doors[i];
				if ((int)dd["floor"] != f) {
					continue;
				}
				const int da = dd["a"];
				const int db = dd["b"];
				if (seen.has(da) != seen.has(db)) {
					seen.insert(da);
					seen.insert(db);
					changed = true;
				}
			}
		}
		CHECK_MESSAGE((int)seen.size() == ids.size(), vformat("every room reachable via doors on floor %d", f));
	}
	const Array stairs = b1["stairs"];
	CHECK_MESSAGE(stairs.size() == 2, "stairs between each pair of floors");
	for (int i = 0; i < stairs.size(); i++) {
		const Dictionary sd = stairs[i];
		CHECK_MESSAGE((int)sd["room_to"] >= 0, "stairs land in a room above");
	}
	const Array single_stairs = CgameProceduralBuildings::building(7, fp, 1)["stairs"];
	CHECK_MESSAGE(single_stairs.size() == 0, "single floor has no stairs");

	const Array windows = b1["windows"];
	CHECK_MESSAGE(windows.size() > 0, "building has windows");
	bool wall_ok = true;
	for (int i = 0; i < windows.size(); i++) {
		const Dictionary wd = windows[i];
		const Vector2i cell = wd["cell"];
		if (cell.x != 0 && cell.y != 0 && cell.x != fp.x - 1 && cell.y != fp.y - 1) {
			wall_ok = false;
		}
	}
	CHECK_MESSAGE(wall_ok, "windows only on exterior walls");
	const Dictionary entrance = b1["entrance"];
	CHECK_MESSAGE(Vector2i(entrance["cell"]).y == fp.y - 1, "entrance on the south wall");

	const Dictionary tiny = CgameProceduralBuildings::building(1, Vector2i(2, 2), 1);
	CHECK_MESSAGE(Array(tiny["rooms"]).size() == 1, "tiny footprint is one room");
}

TEST_CASE("[CgameProceduralBuildings] Settlement lots avoid the plaza and each other") {
	const Vector2 center(100.0, -50.0);
	const double radius = 80.0;
	const Array s1 = CgameProceduralBuildings::settlement(5, center, radius, 12);
	const Array s2 = CgameProceduralBuildings::settlement(5, center, radius, 12);
	CHECK_MESSAGE(s1 == s2, "same seed gives identical settlement");
	const Dictionary plaza = s1[0];
	CHECK_MESSAGE(String(plaza["kind"]) == "plaza", "first entry is the plaza");
	CHECK_MESSAGE(Vector2(plaza["center"]).is_equal_approx(center), "plaza at centre");
	const int lot_count = s1.size() - 1;
	CHECK_MESSAGE((lot_count >= 3 && lot_count <= 12), vformat("lot count within bounds (%d)", lot_count));
	const double plaza_r = plaza["radius"];
	bool inside = true;
	bool clear_of_plaza = true;
	bool overlap = false;
	for (int i = 1; i < s1.size(); i++) {
		const Dictionary li = s1[i];
		const Rect2 ri = li["rect"];
		const Vector2 corners[4] = { ri.position, ri.get_end(), Vector2(ri.position.x, ri.get_end().y), Vector2(ri.get_end().x, ri.position.y) };
		for (const Vector2 &cp : corners) {
			if (cp.distance_to(center) > radius) {
				inside = false;
			}
		}
		if (ri.get_center().distance_to(center) < plaza_r) {
			clear_of_plaza = false;
		}
		for (int j = i + 1; j < s1.size(); j++) {
			const Dictionary lj = s1[j];
			const Rect2 rj = lj["rect"];
			if (ri.intersects(rj)) {
				overlap = true;
			}
		}
	}
	CHECK_MESSAGE(inside, "lots lie within the radius");
	CHECK_MESSAGE(clear_of_plaza, "lots avoid the plaza");
	CHECK_MESSAGE(!overlap, "lots do not overlap");
	CHECK_MESSAGE(CgameProceduralBuildings::settlement(1, center, radius, 0).size() == 1, "zero count gives plaza only");
	CHECK(CgameProceduralBuildings::settlement(1, center, 0.0, 5).size() == 0);
}

static int find_root(Vector<int> &r_parent, int p_i) {
	int r = p_i;
	while (r_parent[r] != r) {
		r = r_parent[r];
	}
	return r;
}

static int components(int p_n, const TypedArray<Dictionary> &p_edges, int p_limit = -1) {
	Vector<int> parent;
	parent.resize(p_n);
	for (int i = 0; i < p_n; i++) {
		parent.write[i] = i;
	}
	int comps = p_n;
	const int count = p_limit < 0 ? (int)p_edges.size() : MIN(p_limit, (int)p_edges.size());
	for (int i = 0; i < count; i++) {
		const Dictionary ed = p_edges[i];
		const int ra = find_root(parent, ed["a"]);
		const int rb = find_root(parent, ed["b"]);
		if (ra != rb) {
			parent.write[ra] = rb;
			comps--;
		}
	}
	return comps;
}

static bool acyclic(int p_n, const TypedArray<Dictionary> &p_edges, int p_limit) {
	Vector<int> parent;
	parent.resize(p_n);
	for (int i = 0; i < p_n; i++) {
		parent.write[i] = i;
	}
	for (int i = 0; i < MIN(p_limit, (int)p_edges.size()); i++) {
		const Dictionary ed = p_edges[i];
		const int ra = find_root(parent, ed["a"]);
		const int rb = find_root(parent, ed["b"]);
		if (ra == rb) {
			return false;
		}
		parent.write[ra] = rb;
	}
	return true;
}

static double flat_height(const Vector2 &p_p) {
	return 0.0;
}

static double hill_height(const Vector2 &p_p) {
	return p_p.x * 0.5;
}

TEST_CASE("[CgameRoadNetwork] Delaunay MST with extra loop edges") {
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed(42);
	PackedVector2Array sites;
	for (int i = 0; i < 25; i++) {
		const real_t x = rng->randf_range(0.0, 500.0);
		const real_t y = rng->randf_range(0.0, 500.0);
		sites.push_back(Vector2(x, y));
	}
	const int n = sites.size();
	const TypedArray<Dictionary> e0 = CgameRoadNetwork::connect_sites(sites, 0.0, 1);
	CHECK_MESSAGE(e0.size() == n - 1, "MST has n-1 edges");
	CHECK_MESSAGE(components(n, e0) == 1, "MST connects all sites");
	const TypedArray<Dictionary> e1 = CgameRoadNetwork::connect_sites(sites, 0.3, 1);
	const TypedArray<Dictionary> e2 = CgameRoadNetwork::connect_sites(sites, 0.3, 1);
	CHECK_MESSAGE(e1 == e2, "road graph deterministic");
	CHECK_MESSAGE(e1.size() > n - 1, "extra edges add loops");
	CHECK_MESSAGE((components(n, e1, n - 1) == 1 && acyclic(n, e1, n - 1)), "first n-1 edges form an acyclic tree");
	CHECK_MESSAGE(components(n, e1) == 1, "graph with loops stays connected");
	bool good = true;
	for (int i = 0; i < e1.size(); i++) {
		const Dictionary ed = e1[i];
		const double expected = sites[(int)ed["a"]].distance_to(sites[(int)ed["b"]]);
		if (Math::abs((double)ed["length"] - expected) > 0.001) {
			good = false;
		}
	}
	CHECK_MESSAGE(good, "edge lengths match geometry");

	PackedVector2Array line;
	for (int i = 0; i < 4; i++) {
		line.push_back(Vector2(i * 10.0f, 0));
	}
	CHECK_MESSAGE(CgameRoadNetwork::connect_sites(line, 0.0, 0).size() == 3, "collinear sites still connect");
	PackedVector2Array two;
	two.push_back(Vector2());
	two.push_back(Vector2(5, 5));
	CHECK_MESSAGE(CgameRoadNetwork::connect_sites(two).size() == 1, "two sites give one road");
	PackedVector2Array one;
	one.push_back(Vector2());
	CHECK_MESSAGE(CgameRoadNetwork::connect_sites(one).size() == 0, "one site gives no roads");
}

TEST_CASE("[CgameRoadNetwork] Route cost penalises slopes") {
	const Callable flat = callable_mp_static(&flat_height);
	const Callable hill = callable_mp_static(&hill_height);
	const Vector2 a(0, 0);
	const Vector2 b(100, 0);
	CHECK_MESSAGE(Math::abs(CgameRoadNetwork::route_cost(a, b, flat, 5.0) - 100.0) <= 0.01, "flat ground costs its length");
	const double steep = CgameRoadNetwork::route_cost(a, b, hill, 5.0);
	CHECK_MESSAGE(steep > 100.0 * 1.5, "slopes are penalised");
	CHECK_MESSAGE(CgameRoadNetwork::route_cost(a, b, hill, 10.0) > steep, "bigger penalty costs more");
	CHECK_MESSAGE(Math::abs(CgameRoadNetwork::route_cost(a, a, hill, 5.0)) <= 0.0001, "zero-length route is free");
}

} // namespace TestCgameProceduralGraphs
