/**************************************************************************/
/*  test_navmesh.h                                                        */
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

#include "../navmesh_carving.h"
#include "../navmesh_stitching.h"

#include "tests/test_macros.h"

namespace TestCgameNavMesh {

static Dictionary make_tile(const Vector2 &p_origin, float p_size) {
	Vector2 o = p_origin;
	float s = p_size;
	float h = p_size * 0.5f;
	PackedVector2Array p0;
	p0.push_back(o);
	p0.push_back(o + Vector2(h, 0));
	p0.push_back(o + Vector2(h, s));
	p0.push_back(o + Vector2(0, s));
	PackedVector2Array p1;
	p1.push_back(o + Vector2(h, 0));
	p1.push_back(o + Vector2(s, 0));
	p1.push_back(o + Vector2(s, s));
	p1.push_back(o + Vector2(h, s));
	Array polys;
	polys.push_back(p0);
	polys.push_back(p1);
	Dictionary t;
	t["origin"] = p_origin;
	t["size"] = p_size;
	t["polygons"] = polys;
	return t;
}

static float path_len(const PackedVector2Array &p_path) {
	float s = 0.0f;
	for (int i = 0; i + 1 < p_path.size(); i++) {
		s += p_path[i].distance_to(p_path[i + 1]);
	}
	return s;
}

static PackedVector2Array make_wall() {
	PackedVector2Array w;
	w.push_back(Vector2(19.5, 0.0));
	w.push_back(Vector2(20.5, 0.0));
	w.push_back(Vector2(20.5, 30.0));
	w.push_back(Vector2(19.5, 30.0));
	return w;
}

TEST_CASE("[NavMeshStitching] Portals across tile borders") {
	Dictionary ta = make_tile(Vector2(0, 0), 10.0);
	Dictionary tb = make_tile(Vector2(10, 0), 10.0);
	Array portals = NavMeshStitching::stitch(ta, tb, 0.01);
	CHECK(portals.size() == 1);
	Dictionary p = portals[0];
	CHECK((int)p["poly_a"] == 1);
	CHECK((int)p["poly_b"] == 0);
	Vector2 pl = p["left"];
	Vector2 pr = p["right"];
	CHECK(pl.x == doctest::Approx(10.0));
	CHECK(pl.y - pr.y == doctest::Approx(10.0));
	CHECK(NavMeshStitching::stitch(ta, make_tile(Vector2(30, 0), 10.0), 0.01).size() == 0);
}

TEST_CASE("[NavMeshStitching] Graph and funnel path") {
	Dictionary ta = make_tile(Vector2(0, 0), 10.0);
	Dictionary tb = make_tile(Vector2(10, 0), 10.0);
	Array tiles;
	tiles.push_back(ta);
	tiles.push_back(tb);
	Dictionary graph = NavMeshStitching::build_graph(tiles, 0.01);
	CHECK(Array(graph["polys"]).size() == 4);
	PackedVector2Array path = NavMeshStitching::find_path(graph, Vector2(1, 5), Vector2(19, 5));
	CHECK(path.size() == 2);
	CHECK(path[0].is_equal_approx(Vector2(1, 5)));
	CHECK(path[path.size() - 1].is_equal_approx(Vector2(19, 5)));
	bool crosses = false;
	for (int i = 0; i + 1 < path.size(); i++) {
		if (path[i].x < 10.0f && path[i + 1].x > 10.0f) {
			crosses = true;
		}
	}
	CHECK(crosses);
	PackedVector2Array diag = NavMeshStitching::find_path(graph, Vector2(1, 1), Vector2(19, 9));
	CHECK(diag.size() == 2);
}

TEST_CASE("[NavMeshCarving] Obstacles carve and destruction reopens") {
	Ref<NavMeshCarving> nav;
	nav.instantiate();
	nav->setup(Rect2(0, 0, 40, 40), 10.0, 0.5);
	CHECK(nav->is_walkable(Vector2(5, 5)));
	Dictionary pillar;
	pillar["center"] = Vector2(5, 5);
	pillar["radius"] = 1.0;
	pillar["segments"] = 12;
	nav->add_obstacle("pillar", pillar);
	nav->update(0);
	CHECK_FALSE(nav->is_walkable(Vector2(5, 5)));
	CHECK_FALSE(nav->is_walkable(Vector2(6.3, 5)));
	CHECK(nav->is_walkable(Vector2(1, 1)));
	float area = 0.0f;
	bool all_convex = true;
	TypedArray<PackedVector2Array> polys = nav->polygons_in_tile(Vector2i(0, 0));
	for (int i = 0; i < polys.size(); i++) {
		PackedVector2Array p = polys[i];
		area += NavMeshCarving::polygon_area(p);
		all_convex = all_convex && NavMeshCarving::is_convex(p);
	}
	CHECK(area > 91.5f);
	CHECK(area < 94.0f);
	CHECK(all_convex);
	CHECK(polys.size() > 1);
	nav->on_destroyed("pillar");
	nav->update(0);
	CHECK(nav->is_walkable(Vector2(5, 5)));
	CHECK(nav->polygons_in_tile(Vector2i(0, 0)).size() == 1);
}

TEST_CASE("[NavMeshCarving] Detour around a barricade and reopening") {
	Ref<NavMeshCarving> n2;
	n2.instantiate();
	n2->setup(Rect2(0, 0, 40, 40), 10.0, 0.5);
	PackedVector2Array straight = n2->find_path(Vector2(5, 20), Vector2(35, 20));
	CHECK(straight.size() == 2);
	n2->add_obstacle("barricade", make_wall());
	n2->update(0);
	CHECK_FALSE(n2->is_walkable(Vector2(20, 10)));
	PackedVector2Array detour = n2->find_path(Vector2(5, 20), Vector2(35, 20));
	CHECK(detour.size() >= 3);
	CHECK(path_len(detour) > 35.0f);
	CHECK(path_len(detour) < 52.0f);
	bool clear = true;
	for (int i = 0; i + 1 < detour.size(); i++) {
		for (int s = 0; s <= 10; s++) {
			clear = clear && n2->is_walkable(detour[i].lerp(detour[i + 1], (float)s / 10.0f));
		}
	}
	CHECK(clear);
	n2->consume_changed_tiles();
	n2->on_destroyed("barricade");
	n2->update(0);
	PackedVector2Array reopened = n2->find_path(Vector2(5, 20), Vector2(35, 20));
	CHECK(reopened.size() == 2);
	CHECK(path_len(reopened) == doctest::Approx(30.0).epsilon(0.001));
	CHECK(n2->path_affected(detour, n2->consume_changed_tiles()));
	CHECK(n2->find_path(Vector2(-5, 20), Vector2(35, 20)).size() == 0);
	PackedVector2Array full;
	full.push_back(Vector2(19.5, -1));
	full.push_back(Vector2(20.5, -1));
	full.push_back(Vector2(20.5, 41));
	full.push_back(Vector2(19.5, 41));
	n2->add_obstacle("full", full);
	n2->update(0);
	CHECK(n2->find_path(Vector2(5, 20), Vector2(35, 20)).size() == 0);
}

TEST_CASE("[NavMeshCarving] Budget and locality") {
	Ref<NavMeshCarving> n3;
	n3.instantiate();
	n3->setup(Rect2(0, 0, 40, 40), 10.0, 0.5);
	int v_far = n3->tile_version(Vector2i(3, 3));
	int v_hit = n3->tile_version(Vector2i(1, 1));
	n3->add_obstacle("w", make_wall());
	int pending = n3->pending_tiles();
	CHECK(pending >= 4);
	CHECK(pending < 16);
	CHECK(n3->update(2) == 2);
	CHECK(n3->pending_tiles() == pending - 2);
	CHECK(n3->consume_changed_tiles().size() == 2);
	while (n3->pending_tiles() > 0) {
		n3->update(2);
	}
	CHECK(n3->tile_version(Vector2i(3, 3)) == v_far);
	CHECK(n3->tile_version(Vector2i(0, 0)) == 0);
	CHECK(n3->tile_version(Vector2i(1, 1)) > v_hit);
	CHECK(n3->update(2) == 0);
	n3->add_obstacle("w", make_wall());
	CHECK(n3->pending_tiles() > 0);
}

} //namespace TestCgameNavMesh
