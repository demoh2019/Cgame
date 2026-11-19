// Compile the actual Cgame shape-matching header with test-only Vector3.
// This exercises math and C++17 syntax, NOT a full Godot editor build.
//
// c++ -std=c++17 -O2 -Wall -Wextra -Werror -pedantic \
//   -Itests/stress/mock_shape_matching -I. \
//   tests/stress/physics_softbody_shape_matching_standalone.cpp -o /tmp/shape-test
// /tmp/shape-test

#include "servers/physics_softbody_shape_matching.h"

#include <array>
#include <cstdio>
#include <limits>

struct ShapeNode {
	Vector3 s;
	Vector3 x;
	real_t im = 1.0f;
};

using ShapeNodes = std::array<ShapeNode, 8>;

static ShapeNodes make_box() {
	ShapeNodes nodes;
	for (int i = 0; i < 8; ++i) {
		const Vector3 source(i & 1 ? 1.0f : -1.0f,
				i & 2 ? 1.0f : -1.0f, i & 4 ? 1.0f : -1.0f);
		nodes[i] = { source, source, 1.0f };
	}
	return nodes;
}

static bool check(bool ok, const char *message) {
	if (!ok) {
		std::fprintf(stderr, "FAILED: %s\n", message);
	}
	return ok;
}

int main() {
	bool ok = true;
	ShapeNodes box = make_box();
	box[0].im = 0;
	const Vector3 pin = box[0].x;
	box[7].x += Vector3(0.7f, 0, 0);
	const float before = box[7].x.distance_to(box[7].s);
	ok &= check(physics_softbody_project_shape_matching(box, 0.75f),
			"shape matching accepts sheared box");
	ok &= check(box[0].x == pin && box[7].x.distance_to(box[7].s) < before,
			"pin invariant and sheared geometry recovers");
	ShapeNodes collapsed = make_box();
	const Vector3 position(3, 4, 5);
	for (ShapeNode &n : collapsed) {
		n.x = position;
	}
	ok &= check(physics_softbody_project_shape_matching(collapsed, 1.0f),
			"collapsed geometry is handled");
	for (ShapeNode &n : collapsed) {
		ok &= check(n.x.distance_to(position + n.s) < 1e-4f,
				"collapsed geometry deterministic rest recovery");
	}

	// 6000 seeded proper rigid-body rotations and translations. Input
	// positions are never modified apart from possible roundoff.
	uint32_t rng = 0x78CA9311u;
	auto random = [&rng]() -> float {
		rng ^= rng << 13;
		rng ^= rng >> 17;
		rng ^= rng << 5;
		return float(rng % 100000u) / 100000.0f;
	};
	for (int i = 0; i < 6000 && ok; ++i) {
		ShapeNodes nodes = make_box();
		const float theta = (random() - 0.5f) * 6.28f;
		const float c = std::cos(theta), s = std::sin(theta);
		const Vector3 translation((random() - 0.5f) * 50.0f,
				(random() - 0.5f) * 50.0f, (random() - 0.5f) * 50.0f);
		for (ShapeNode &node : nodes) {
			const Vector3 source = node.s;
			node.x = Vector3(c * source.x - s * source.y,
					s * source.x + c * source.y, source.z) + translation;
		}
		const ShapeNodes original = nodes;
		ok &= check(physics_softbody_project_shape_matching(nodes, 1.0f),
				"randomized shape matching fit");
		for (int j = 0; j < 8; ++j) {
			if (nodes[j].x.distance_to(original[j].x) > 0.0002f) {
				ok &= check(false, "rigid rotation and translation invariant");
				break;
			}
		}
	}
	ShapeNodes invalid = make_box();
	invalid[1].x.x = std::numeric_limits<float>::infinity();
	const ShapeNodes original = invalid;
	ok &= check(!physics_softbody_project_shape_matching(invalid, 0.5f),
			"nonfinite vertex rejected atomically");
	ok &= check(invalid[0].x == original[0].x && invalid[2].x == original[2].x,
			"nonfinite input never changes good vertices");
	ok &= check(!physics_softbody_project_shape_matching(invalid, -1.0f),
			"negative fraction rejected");

	if (ok) {
		std::puts("PASS: 6000 rigid transforms, collapse, pins, shear and bad inputs");
	}
	return ok ? 0 : 1;
}
