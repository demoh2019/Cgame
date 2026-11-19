/**************************************************************************/
/*  test_astar.cpp                                                        */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_astar)

#include "core/math/a_star.h"
#include "core/math/a_star_grid_2d.h"
#include "core/templates/hash_set.h"

namespace TestAStar {

class ABCX : public AStar3D {
public:
	enum {
		A,
		B,
		C,
		X,
	};

	ABCX() {
		add_point(A, Vector3(0, 0, 0));
		add_point(B, Vector3(1, 0, 0));
		add_point(C, Vector3(0, 1, 0));
		add_point(X, Vector3(0, 0, 1));
		connect_points(A, B);
		connect_points(A, C);
		connect_points(B, C);
		connect_points(X, A);
	}

	// Disable heuristic completely.
	real_t _compute_cost(int64_t p_from, int64_t p_to) {
		if (p_from == A && p_to == C) {
			return 1000;
		}
		return 100;
	}
};

class CountingHeuristic3D : public AStar3D {
public:
	int start_heuristic_calls = 0;

protected:
	real_t _estimate_cost(int64_t p_from, int64_t p_to) override {
		if (p_from == 1 && p_to == 2) {
			++start_heuristic_calls;
		}
		return AStar3D::_estimate_cost(p_from, p_to);
	}
};

TEST_CASE("[AStar3D] Start heuristic evaluated once per search") {
	CountingHeuristic3D graph;
	graph.add_point(1, Vector3(0, 0, 0));
	graph.add_point(2, Vector3(1, 0, 0));
	graph.connect_points(1, 2);

	const Vector<int64_t> path = graph.get_id_path(1, 2);
	REQUIRE(path.size() == 2);
	CHECK(graph.start_heuristic_calls == 1);

	graph.get_id_path(1, 2);
	CHECK(graph.start_heuristic_calls == 2);
}

TEST_CASE("[AStar3D] ABC path") {
	ABCX abcx;
	Vector<int64_t> path = abcx.get_id_path(ABCX::A, ABCX::C);
	REQUIRE(path.size() == 3);
	CHECK(path[0] == ABCX::A);
	CHECK(path[1] == ABCX::B);
	CHECK(path[2] == ABCX::C);
}

TEST_CASE("[AStar3D] ABCX path") {
	ABCX abcx;
	Vector<int64_t> path = abcx.get_id_path(ABCX::X, ABCX::C);
	REQUIRE(path.size() == 4);
	CHECK(path[0] == ABCX::X);
	CHECK(path[1] == ABCX::A);
	CHECK(path[2] == ABCX::B);
	CHECK(path[3] == ABCX::C);
}

TEST_CASE("[AStar3D] Add/Remove") {
	AStar3D a;

	// Manual tests.
	a.add_point(1, Vector3(0, 0, 0));
	a.add_point(2, Vector3(0, 1, 0));
	a.add_point(3, Vector3(1, 1, 0));
	a.add_point(4, Vector3(2, 0, 0));
	a.connect_points(1, 2, true);
	a.connect_points(1, 3, true);
	a.connect_points(1, 4, false);

	CHECK(a.are_points_connected(2, 1));
	CHECK(a.are_points_connected(4, 1));
	CHECK(a.are_points_connected(2, 1, false));
	CHECK_FALSE(a.are_points_connected(4, 1, false));

	a.disconnect_points(1, 2, true);
	CHECK(a.get_point_connections(1).size() == 2); // 3, 4
	CHECK(a.get_point_connections(2).size() == 0);

	a.disconnect_points(4, 1, false);
	CHECK(a.get_point_connections(1).size() == 2); // 3, 4
	CHECK(a.get_point_connections(4).size() == 0);

	a.disconnect_points(4, 1, true);
	CHECK(a.get_point_connections(1).size() == 1); // 3
	CHECK(a.get_point_connections(4).size() == 0);

	a.connect_points(2, 3, false);
	CHECK(a.get_point_connections(2).size() == 1); // 3
	CHECK(a.get_point_connections(3).size() == 1); // 1

	a.connect_points(2, 3, true);
	CHECK(a.get_point_connections(2).size() == 1); // 3
	CHECK(a.get_point_connections(3).size() == 2); // 1, 2

	a.disconnect_points(2, 3, false);
	CHECK(a.get_point_connections(2).size() == 0);
	CHECK(a.get_point_connections(3).size() == 2); // 1, 2

	a.connect_points(4, 3, true);
	CHECK(a.get_point_connections(3).size() == 3); // 1, 2, 4
	CHECK(a.get_point_connections(4).size() == 1); // 3

	a.disconnect_points(3, 4, false);
	CHECK(a.get_point_connections(3).size() == 2); // 1, 2
	CHECK(a.get_point_connections(4).size() == 1); // 3

	a.remove_point(3);
	CHECK(a.get_point_connections(1).size() == 0);
	CHECK(a.get_point_connections(2).size() == 0);
	CHECK(a.get_point_connections(4).size() == 0);

	a.add_point(0, Vector3(0, -1, 0));
	a.add_point(3, Vector3(2, 1, 0));
	// 0: (0, -1)
	// 1: (0, 0)
	// 2: (0, 1)
	// 3: (2, 1)
	// 4: (2, 0)

	// Tests for get_closest_position_in_segment.
	a.connect_points(2, 3);
	CHECK(a.get_closest_position_in_segment(Vector3(0.5, 0.5, 0)) == Vector3(0.5, 1, 0));

	a.connect_points(3, 4);
	a.connect_points(0, 3);
	a.connect_points(1, 4);
	a.disconnect_points(1, 4, false);
	a.disconnect_points(4, 3, false);
	a.disconnect_points(3, 4, false);
	// Remaining edges: <2, 3>, <0, 3>, <1, 4> (directed).
	CHECK(a.get_closest_position_in_segment(Vector3(2, 0.5, 0)) == Vector3(1.75, 0.75, 0));
	CHECK(a.get_closest_position_in_segment(Vector3(-1, 0.2, 0)) == Vector3(0, 0, 0));
	CHECK(a.get_closest_position_in_segment(Vector3(3, 2, 0)) == Vector3(2, 1, 0));

	Math::seed(0);

	// Random tests for connectivity checks
	for (int i = 0; i < 20000; i++) {
		int u = Math::rand() % 5;
		int v = Math::rand() % 4;
		if (u == v) {
			v = 4;
		}
		if (Math::rand() % 2 == 1) {
			// Add a (possibly existing) directed edge and confirm connectivity.
			a.connect_points(u, v, false);
			CHECK(a.are_points_connected(u, v, false));
		} else {
			// Remove a (possibly nonexistent) directed edge and confirm disconnectivity.
			a.disconnect_points(u, v, false);
			CHECK_FALSE(a.are_points_connected(u, v, false));
		}
	}

	// Random tests for point removal.
	for (int i = 0; i < 20000; i++) {
		a.clear();
		for (int j = 0; j < 5; j++) {
			a.add_point(j, Vector3(0, 0, 0));
		}

		// Add or remove random edges.
		for (int j = 0; j < 10; j++) {
			int u = Math::rand() % 5;
			int v = Math::rand() % 4;
			if (u == v) {
				v = 4;
			}
			if (Math::rand() % 2 == 1) {
				a.connect_points(u, v, false);
			} else {
				a.disconnect_points(u, v, false);
			}
		}

		// Remove point 0.
		a.remove_point(0);
		// White box: this will check all edges remaining in the segments set.
		for (int j = 1; j < 5; j++) {
			CHECK_FALSE(a.are_points_connected(0, j, true));
		}
	}
}

TEST_CASE("[AStar3D] Path from disabled point is empty") {
	AStar3D a;
	Vector3 p1(0, 0, 0);
	Vector3 p2(0, 1, 0);
	a.add_point(1, p1);
	a.add_point(2, p2);
	a.connect_points(1, 2);

	CHECK_EQ(a.get_id_path(1, 1), Vector<int64_t>{ 1 });
	CHECK_EQ(a.get_id_path(1, 2), Vector<int64_t>{ 1, 2 });

	CHECK_EQ(a.get_point_path(1, 1), Vector<Vector3>{ p1 });
	CHECK_EQ(a.get_point_path(1, 2), Vector<Vector3>{ p1, p2 });

	a.set_point_disabled(1, true);

	CHECK(a.get_id_path(1, 1).is_empty());
	CHECK(a.get_id_path(1, 2).is_empty());

	CHECK(a.get_point_path(1, 1).is_empty());
	CHECK(a.get_point_path(1, 2).is_empty());
}

TEST_CASE("[AStar3D] Known-size point IDs and connections preserve all entries") {
	AStar3D astar;
	for (int i = 0; i < 256; i++) {
		astar.add_point(i, Vector3(i, i % 7, 0));
		if (i > 0) {
			astar.connect_points(0, i, false);
		}
	}

	const PackedInt64Array ids = astar.get_point_ids();
	REQUIRE_EQ(ids.size(), 256);
	HashSet<int64_t> seen_ids;
	for (int i = 0; i < ids.size(); i++) {
		seen_ids.insert(ids[i]);
	}
	REQUIRE_EQ(seen_ids.size(), 256);
	for (int64_t i = 0; i < 256; i++) {
		CHECK(seen_ids.has(i));
	}

	const Vector<int64_t> connections = astar.get_point_connections(0);
	REQUIRE_EQ(connections.size(), 255);
	HashSet<int64_t> seen_connections;
	for (int64_t id : connections) {
		seen_connections.insert(id);
	}
	REQUIRE_EQ(seen_connections.size(), 255);
	for (int64_t i = 1; i < 256; i++) {
		CHECK(seen_connections.has(i));
	}

	astar.remove_point(255);
	CHECK_EQ(astar.get_point_ids().size(), 255);
	CHECK_EQ(astar.get_point_connections(0).size(), 254);
}

class CountingHeuristicGrid2D : public AStarGrid2D {
public:
	int start_heuristic_calls = 0;

protected:
	real_t _estimate_cost(const Vector2i &p_from, const Vector2i &p_to) override {
		if (p_from == Vector2i(0, 0) && p_to == Vector2i(1, 1)) {
			++start_heuristic_calls;
		}
		return AStarGrid2D::_estimate_cost(p_from, p_to);
	}
};

TEST_CASE("[AStarGrid2D] Start heuristic evaluated once per search") {
	CountingHeuristicGrid2D grid;
	grid.set_region(Rect2i(0, 0, 3, 3));
	grid.update();

	const Vector<Vector2> path = grid.get_point_path(Vector2i(0, 0), Vector2i(1, 1));
	REQUIRE(path.size() == 2);
	CHECK(grid.start_heuristic_calls == 1);

	grid.get_point_path(Vector2i(0, 0), Vector2i(1, 1));
	CHECK(grid.start_heuristic_calls == 2);
}

TEST_CASE("[AStarGrid2D] Fixed-capacity neighbors preserve corner policies and paths") {
	AStarGrid2D grid;
	grid.set_region(Rect2i(0, 0, 3, 3));
	grid.update();

	// The center cell has all eight neighbors. Exercise all four policies
	// through repeated searches, which also clear and refill the scratch list.
	for (int mode = 0; mode < AStarGrid2D::DIAGONAL_MODE_MAX; ++mode) {
		grid.set_diagonal_mode(static_cast<AStarGrid2D::DiagonalMode>(mode));
		for (int attempt = 0; attempt < 3; ++attempt) {
			const Vector<Vector2> path = grid.get_point_path(Vector2i(0, 0), Vector2i(2, 2));
			REQUIRE_FALSE(path.is_empty());
			CHECK(path[0] == grid.get_point_position(Vector2i(0, 0)));
			CHECK(path[path.size() - 1] == grid.get_point_position(Vector2i(2, 2)));
			CHECK(path.size() == (mode == AStarGrid2D::DIAGONAL_MODE_NEVER ? 5 : 3));
		}
	}

	// Both orthogonal neighbors blocked: only unconditional diagonals can
	// cross directly into (1, 1).
	grid.set_point_solid(Vector2i(0, 1), true);
	grid.set_point_solid(Vector2i(1, 0), true);
	for (int mode = 0; mode < AStarGrid2D::DIAGONAL_MODE_MAX; ++mode) {
		grid.set_diagonal_mode(static_cast<AStarGrid2D::DiagonalMode>(mode));
		const Vector<Vector2> path = grid.get_point_path(Vector2i(0, 0), Vector2i(1, 1));
		if (mode == AStarGrid2D::DIAGONAL_MODE_ALWAYS) {
			REQUIRE(path.size() == 2);
		} else {
			CHECK(path.is_empty());
		}
	}

	// With one side blocked, at-least-one-walkable still permits diagonal
	// traversal, whereas no-obstacles requires an orthogonal detour.
	grid.set_point_solid(Vector2i(0, 1), false);
	for (int mode = 0; mode < AStarGrid2D::DIAGONAL_MODE_MAX; ++mode) {
		grid.set_diagonal_mode(static_cast<AStarGrid2D::DiagonalMode>(mode));
		const Vector<Vector2> path = grid.get_point_path(Vector2i(0, 0), Vector2i(1, 1));
		const bool direct = mode == AStarGrid2D::DIAGONAL_MODE_ALWAYS || mode == AStarGrid2D::DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE;
		REQUIRE(path.size() == (direct ? 2 : 3));
	}
}

TEST_CASE("[AStarGrid2D][Performance] Dense obstacle search never revisits solid neighbors") {
	AStarGrid2D grid;
	constexpr int width = 37;
	constexpr int height = 29;
	grid.set_region(Rect2i(0, 0, width, height));
	grid.update();

	// Leave the border traversable so every diagonal mode has a valid path.
	for (int y = 1; y < height - 1; y++) {
		for (int x = 1; x < width - 1; x++) {
			if ((x * 17 + y * 11) % 7 < 2) {
				grid.set_point_solid(Vector2i(x, y), true);
			}
		}
	}

	const Vector2i start(0, 0);
	const Vector2i goal(width - 1, height - 1);
	for (int mode = 0; mode < AStarGrid2D::DIAGONAL_MODE_MAX; mode++) {
		grid.set_diagonal_mode(static_cast<AStarGrid2D::DiagonalMode>(mode));
		for (int repeat = 0; repeat < 8; repeat++) {
			const TypedArray<Vector2i> path = grid.get_id_path(start, goal);
			REQUIRE(path.size() >= 2);
			CHECK_EQ(Vector2i(path[0]), start);
			CHECK_EQ(Vector2i(path[path.size() - 1]), goal);
			for (int i = 0; i < path.size(); i++) {
				CHECK_FALSE(grid.is_point_solid(Vector2i(path[i])));
			}
		}
	}
}

TEST_CASE("[AStarGrid2D] Pre-sized region data respects grid intersections and order") {
	AStarGrid2D grid;
	grid.set_region(Rect2i(Vector2i(-12, -8), Vector2i(40, 32)));
	grid.update();
	grid.set_point_solid(Vector2i(0, 0), true);

	TypedArray<Dictionary> data = grid.get_point_data_in_region(Rect2i(Vector2i(-2, -2), Vector2i(16, 12)));
	REQUIRE_EQ(data.size(), 192);
	for (int i = 0; i < data.size(); i++) {
		Dictionary row = data[i];
		CHECK_EQ(row["id"], Variant(Vector2i(-2 + (i % 16), -2 + (i / 16))));
		if (row["id"] == Variant(Vector2i(0, 0))) {
			CHECK_EQ(row["solid"], Variant(true));
		}
	}

	TypedArray<Dictionary> clipped = grid.get_point_data_in_region(Rect2i(Vector2i(20, 20), Vector2i(16, 16)));
	REQUIRE_EQ(clipped.size(), 32);
	Dictionary first = clipped[0];
	Dictionary last = clipped[clipped.size() - 1];
	CHECK_EQ(first["id"], Variant(Vector2i(20, 20)));
	CHECK_EQ(last["id"], Variant(Vector2i(27, 23)));

	const TypedArray<Dictionary> outside = grid.get_point_data_in_region(Rect2i(Vector2i(100, 100), Vector2i(10, 10)));
	CHECK(outside.is_empty());
}

TEST_CASE("[AStarGrid2D] Repeated grid rebuild preserves padded mask and point coordinates") {
	AStarGrid2D grid;
	const Vector2i sizes[] = {
		Vector2i(1, 1),
		Vector2i(9, 64),
		Vector2i(128, 32),
		Vector2i(32, 128),
		Vector2i(0, 0),
		Vector2i(7, 3),
	};
	for (const Vector2i &size : sizes) {
		const Rect2i region(Vector2i(-4, -3), size);
		grid.set_region(region);
		grid.update();
		CHECK_FALSE(grid.is_dirty());

		TypedArray<Dictionary> data = grid.get_point_data_in_region(region);
		REQUIRE_EQ(data.size(), size.x * size.y);
		if (size.x == 0 || size.y == 0) {
			CHECK(data.is_empty());
			continue;
		}

		Dictionary first = data[0];
		Dictionary last = data[data.size() - 1];
		CHECK_EQ(first["id"], Variant(region.position));
		CHECK_EQ(last["id"], Variant(region.get_end() - Vector2i(1, 1)));
		CHECK_FALSE(grid.is_point_solid(region.position));
		grid.set_point_solid(region.position, true);
		CHECK(grid.is_point_solid(region.position));
		grid.update();
		CHECK(grid.is_point_solid(region.position)); // No unnecessary rebuild while clean.
	}
}


class ReprioritizedAStar3D : public AStar3D {
protected:
	real_t _estimate_cost(int64_t p_from, int64_t p_to) override {
		return 0;
	}

	real_t _compute_cost(int64_t p_from, int64_t p_to) override {
		if (p_from == 0 && p_to == 1) {
			return 100;
		}
		if (p_from == 0 && p_to == 2) {
			return 1;
		}
		if (p_from == 2 && p_to == 1) {
			return 1;
		}
		if (p_from == 1 && p_to == 3) {
			return 1;
		}
		return 200;
	}
};

TEST_CASE("[AStar3D] Reprioritizing an open vertex retains shortest paths") {
	ReprioritizedAStar3D a;
	for (int i = 0; i < 128; ++i) {
		a.add_point(i, Vector3(i, 0, 0));
	}
	a.connect_points(0, 1, false);
	a.connect_points(0, 2, false);
	a.connect_points(2, 1, false);
	a.connect_points(1, 3, false);
	for (int i = 4; i < 128; ++i) {
		a.connect_points(0, i, false);
	}
	for (int repeat = 0; repeat < 12; ++repeat) {
		const Vector<int64_t> path = a.get_id_path(0, 3);
		REQUIRE_EQ(path.size(), 4);
		CHECK_EQ(path[0], 0);
		CHECK_EQ(path[1], 2);
		CHECK_EQ(path[2], 1);
		CHECK_EQ(path[3], 3);
	}
	a.set_point_disabled(2, true);
	const Vector<int64_t> detour = a.get_id_path(0, 3);
	REQUIRE_EQ(detour.size(), 3);
	CHECK_EQ(detour[0], 0);
	CHECK_EQ(detour[1], 1);
	CHECK_EQ(detour[2], 3);
	a.set_point_disabled(2, false);
	const Vector<int64_t> restored = a.get_id_path(0, 3);
	REQUIRE_EQ(restored.size(), 4);
	CHECK_EQ(restored[1], 2);
}


class ReprioritizedAStarGrid2D : public AStarGrid2D {
protected:
	real_t _estimate_cost(const Vector2i &, const Vector2i &) override {
		return 0;
	}

	real_t _compute_cost(const Vector2i &p_from, const Vector2i &p_to) override {
		if (p_from == Vector2i(0, 0) && p_to == Vector2i(1, 0)) {
			return 100;
		}
		if (p_from == Vector2i(0, 0) && p_to == Vector2i(0, 1)) {
			return 1;
		}
		if (p_from == Vector2i(0, 1) && p_to == Vector2i(1, 0)) {
			return 1;
		}
		if (p_from == Vector2i(1, 0) && p_to == Vector2i(2, 0)) {
			return 1;
		}
		return 200;
	}
};

TEST_CASE("[AStarGrid2D] Reprioritizing an open grid cell retains the shortest path") {
	Ref<ReprioritizedAStarGrid2D> grid;
	grid.instantiate();
	grid->set_region(Rect2i(0, 0, 8, 8));
	grid->set_diagonal_mode(AStarGrid2D::DIAGONAL_MODE_ALWAYS);
	grid->update();
	for (int repeat = 0; repeat < 12; ++repeat) {
		const TypedArray<Vector2i> path = grid->get_id_path(Vector2i(0, 0), Vector2i(2, 0));
		REQUIRE_EQ(path.size(), 4);
		CHECK_EQ(Vector2i(path[0]), Vector2i(0, 0));
		CHECK_EQ(Vector2i(path[1]), Vector2i(0, 1));
		CHECK_EQ(Vector2i(path[2]), Vector2i(1, 0));
		CHECK_EQ(Vector2i(path[3]), Vector2i(2, 0));
	}
	grid->set_point_solid(Vector2i(0, 1), true);
	const TypedArray<Vector2i> detour = grid->get_id_path(Vector2i(0, 0), Vector2i(2, 0));
	REQUIRE_EQ(detour.size(), 3);
	CHECK_EQ(Vector2i(detour[1]), Vector2i(1, 0));
	grid->set_point_solid(Vector2i(0, 1), false);
	const TypedArray<Vector2i> restored = grid->get_id_path(Vector2i(0, 0), Vector2i(2, 0));
	REQUIRE_EQ(restored.size(), 4);
	CHECK_EQ(Vector2i(restored[1]), Vector2i(0, 1));
}

} // namespace TestAStar
