/**************************************************************************/
/*  test_convex_fracture.cpp                                              */
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

TEST_FORCE_LINK(test_convex_fracture)

#include "scene/3d/convex_fracture.h"
#include "core/math/geometry_3d.h"

namespace TestConvexFracture {

using namespace ConvexFracture;

static Vector<Vector3> box_corners(const Vector3 &p_half) {
	Vector<Vector3> points;
	for (int i = 0; i < 8; i++) {
		points.push_back(Vector3((i & 1) ? p_half.x : -p_half.x, (i & 2) ? p_half.y : -p_half.y, (i & 4) ? p_half.z : -p_half.z));
	}
	return points;
}

// Volume of the body when it is not broken (a single seed owns all of it).
static real_t body_volume(const Vector<Plane> &p_planes) {
	LocalVector<Vector3> seed;
	seed.push_back(Vector3(0, 0, 0));
	LocalVector<Piece> pieces;
	if (!fracture(p_planes, seed, pieces, 0.0) || pieces.size() != 1) {
		return -1.0;
	}
	return pieces[0].volume;
}

static bool piece_contains(const Piece &p_piece, const Vector3 &p_point) {
	for (const Face &face : p_piece.faces) {
		if (face.plane.normal.dot(p_point) - face.plane.d > real_t(1e-4)) {
			return false;
		}
	}
	return true;
}

TEST_CASE("[ConvexFracture] Planes and volume of a box") {
	Vector<Plane> planes;
	REQUIRE(planes_from_points(box_corners(Vector3(0.5, 1.0, 1.5)), planes));
	CHECK(planes.size() == 6);
	CHECK(body_volume(planes) == doctest::Approx(1.0 * 2.0 * 3.0).epsilon(0.001));
	CHECK(is_inside(planes, Vector3(0, 0, 0)));
	CHECK(is_inside(planes, Vector3(0.49, 0.99, -1.49)));
	CHECK_FALSE(is_inside(planes, Vector3(0.6, 0, 0)));

	// A tetrahedron works too, and degenerate input is rejected.
	Vector<Vector3> tetra;
	tetra.push_back(Vector3(0, 0, 0));
	tetra.push_back(Vector3(1, 0, 0));
	tetra.push_back(Vector3(0, 1, 0));
	tetra.push_back(Vector3(0, 0, 1));
	REQUIRE(planes_from_points(tetra, planes));
	CHECK(planes.size() == 4);
	{
		// The origin is a corner of this tetrahedron, so seed inside it instead.
		LocalVector<Vector3> inside;
		inside.push_back(Vector3(0.2, 0.2, 0.2));
		LocalVector<Piece> whole;
		REQUIRE(fracture(planes, inside, whole, 0.0));
		CHECK(whole[0].volume == doctest::Approx(1.0 / 6.0).epsilon(0.001));
	}
	Vector<Vector3> flat;
	flat.push_back(Vector3(0, 0, 0));
	flat.push_back(Vector3(1, 0, 0));
	flat.push_back(Vector3(0, 1, 0));
	flat.push_back(Vector3(1, 1, 0));
	ERR_PRINT_OFF;
	CHECK_FALSE(planes_from_points(flat, planes));
	ERR_PRINT_ON;
	CHECK_FALSE(planes_from_points(Vector<Vector3>(), planes));
}

TEST_CASE("[ConvexFracture] Pieces tile the body exactly") {
	Vector<Plane> planes;
	REQUIRE(planes_from_points(box_corners(Vector3(0.5, 1.0, 1.5)), planes));
	RandomPCG random;
	random.seed(1234);
	LocalVector<Vector3> seeds;
	generate_seeds(planes, 12, Vector3(), 0.0, random, seeds);
	REQUIRE(seeds.size() == 12);
	for (const Vector3 &seed : seeds) {
		CHECK(is_inside(planes, seed, real_t(1e-6)));
	}

	LocalVector<Piece> pieces;
	REQUIRE(fracture(planes, seeds, pieces, 0.0));
	CHECK(pieces.size() == 12);

	// Volume is conserved: the pieces add up to the original box.
	real_t total = 0.0;
	for (const Piece &piece : pieces) {
		total += piece.volume;
		CHECK(piece.volume > 0.0);
		CHECK(piece.points.size() >= 4);
		// Pieces never leave the body.
		for (const Vector3 &point : piece.points) {
			CHECK(is_inside(planes, point, real_t(1e-3)));
		}
		// The centroid is inside the piece.
		CHECK(piece_contains(piece, piece.centroid));
	}
	CHECK(total == doctest::Approx(6.0).epsilon(0.002));

	// Every point of the body lies in exactly one piece (up to the shared faces).
	RandomPCG samples;
	samples.seed(99);
	int checked = 0;
	for (int i = 0; i < 400; i++) {
		const Vector3 point(samples.random(real_t(-0.5), real_t(0.5)), samples.random(real_t(-1.0), real_t(1.0)), samples.random(real_t(-1.5), real_t(1.5)));
		int owners = 0;
		for (const Piece &piece : pieces) {
			if (piece_contains(piece, point)) {
				owners++;
			}
		}
		if (owners >= 1) {
			checked++;
			CHECK(owners <= 2); // Two only if the point sits on a shared face.
		} else {
			CHECK(owners == 1);
		}
	}
	CHECK(checked == 400);
}

TEST_CASE("[ConvexFracture] Single seed, two seeds and invalid input") {
	Vector<Plane> planes;
	REQUIRE(planes_from_points(box_corners(Vector3(1, 1, 1)), planes));
	LocalVector<Piece> pieces;

	// One seed owns everything and has no cut faces.
	LocalVector<Vector3> one;
	one.push_back(Vector3(0.2, 0.1, 0.3));
	REQUIRE(fracture(planes, one, pieces, 0.0));
	REQUIRE(pieces.size() == 1);
	CHECK(pieces[0].volume == doctest::Approx(8.0).epsilon(0.001));
	for (const Face &face : pieces[0].faces) {
		CHECK_FALSE(face.cut);
	}
	CHECK(pieces[0].faces.size() == 6);
	CHECK(pieces[0].centroid.is_equal_approx(Vector3()));

	// Two seeds along x split the cube in half at x = 0, each with exactly one cut face.
	LocalVector<Vector3> two;
	two.push_back(Vector3(-0.5, 0, 0));
	two.push_back(Vector3(0.5, 0, 0));
	REQUIRE(fracture(planes, two, pieces, 0.0));
	REQUIRE(pieces.size() == 2);
	for (const Piece &piece : pieces) {
		CHECK(piece.volume == doctest::Approx(4.0).epsilon(0.001));
		int cuts = 0;
		for (const Face &face : piece.faces) {
			if (face.cut) {
				cuts++;
				CHECK(Math::abs(face.plane.normal.x) > real_t(0.999));
				CHECK(face.plane.d == doctest::Approx(0.0).epsilon(0.001));
				CHECK(face.vertices.size() == 4); // A square slice through the cube.
			}
		}
		CHECK(cuts == 1);
	}
	CHECK(pieces[0].centroid.x < 0.0);
	CHECK(pieces[1].centroid.x > 0.0);

	// Coincident seeds collapse into one piece instead of producing empty cells.
	LocalVector<Vector3> same;
	same.push_back(Vector3(0.1, 0.1, 0.1));
	same.push_back(Vector3(0.1, 0.1, 0.1));
	REQUIRE(fracture(planes, same, pieces, 0.0));
	CHECK(pieces.size() == 1);

	// Invalid input.
	LocalVector<Vector3> none;
	CHECK_FALSE(fracture(planes, none, pieces));
	CHECK_FALSE(fracture(Vector<Plane>(), one, pieces));
	LocalVector<Vector3> bad;
	bad.push_back(Vector3(Math::NaN, 0, 0));
	CHECK_FALSE(fracture(planes, bad, pieces));
	CHECK(pieces.is_empty());
}

TEST_CASE("[ConvexFracture] Seeds are deterministic and cluster near the impact") {
	Vector<Plane> planes;
	REQUIRE(planes_from_points(box_corners(Vector3(2, 2, 2)), planes));
	const Vector3 impact(2, 0, 0);

	RandomPCG a;
	a.seed(5);
	RandomPCG b;
	b.seed(5);
	LocalVector<Vector3> first;
	LocalVector<Vector3> second;
	generate_seeds(planes, 20, impact, 2.0, a, first);
	generate_seeds(planes, 20, impact, 2.0, b, second);
	REQUIRE(first.size() == second.size());
	for (uint32_t i = 0; i < first.size(); i++) {
		CHECK(first[i] == second[i]);
	}

	// Mean distance to the impact point shrinks with the concentration.
	auto mean_distance = [&](real_t p_concentration) {
		RandomPCG random;
		random.seed(11);
		LocalVector<Vector3> seeds;
		generate_seeds(planes, 400, impact, p_concentration, random, seeds);
		real_t sum = 0.0;
		for (const Vector3 &seed : seeds) {
			sum += seed.distance_to(impact);
		}
		return sum / real_t(seeds.size());
	};
	const real_t uniform = mean_distance(0.0);
	const real_t clustered = mean_distance(3.0);
	CHECK(clustered < uniform * real_t(0.8));

	LocalVector<Vector3> none;
	generate_seeds(planes, 0, impact, 0.0, a, none);
	CHECK(none.is_empty());
	generate_seeds(Vector<Plane>(), 5, impact, 0.0, a, none);
	CHECK(none.is_empty());
}

TEST_CASE("[ConvexFracture] Tiny pieces are merged away and work for a non box body") {
	Vector<Vector3> tetra;
	tetra.push_back(Vector3(-1, -1, -1));
	tetra.push_back(Vector3(1, -1, -1));
	tetra.push_back(Vector3(0, 1, -1));
	tetra.push_back(Vector3(0, 0, 1));
	Vector<Plane> planes;
	REQUIRE(planes_from_points(tetra, planes));
	RandomPCG random;
	random.seed(3);
	LocalVector<Vector3> seeds;
	generate_seeds(planes, 6, Vector3(), 0.0, random, seeds);
	LocalVector<Piece> all;
	REQUIRE(fracture(planes, seeds, all, 0.0));
	real_t total = 0.0;
	for (const Piece &piece : all) {
		total += piece.volume;
	}
	const real_t expected = 4.0 / 3.0; // Base area 2 times height 2, over 3.
	CHECK(total == doctest::Approx(expected).epsilon(0.002));

	// A strict minimum volume only ever removes pieces.
	LocalVector<Piece> strict;
	fracture(planes, seeds, strict, 0.12);
	CHECK(strict.size() <= all.size());
	for (const Piece &piece : strict) {
		CHECK(piece.volume > expected * real_t(0.12));
	}
	// A minimum no piece can reach leaves nothing, and says so.
	CHECK_FALSE(fracture(planes, seeds, strict, 0.9));
	CHECK(strict.is_empty());
}

} // namespace TestConvexFracture
