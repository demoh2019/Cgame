// Compile and execute the exact Cgame soft-contact header against a
// deliberately small test Vector3 ABI to catch pure C++/math regressions.
// This is NOT a full Godot engine build or cloth integration test.
//
// g++ -std=c++17 -O2 -Wall -Wextra -Werror -pedantic \
//   -Itests/stress/mock_physics -I. \
//   tests/stress/physics_softbody_edge_standalone.cpp -o /tmp/soft_edge_test
// /tmp/soft_edge_test
#include "servers/physics_softbody_self_collision.h"

#include <cstdint>
#include <cstdio>

static bool check(bool ok, const char *label) {
	if (!ok) {
		std::fprintf(stderr, "FAILED: %s\n", label);
	}
	return ok;
}

int main() {
	bool ok = true;
	const Vector3 a(-1, 0, 0), b(1, 0, 0);
	const Vector3 c(0, -1, 0), d(0, 1, 0);
	Vector3 on_ab, on_cd;
	real_t s = 0, t = 0;
	ok &= check(physics_softbody_closest_segment_points(a, b, c, d, on_ab, on_cd, s, t),
			"crossed segments accepted");
	ok &= check(on_ab.distance_to(on_cd) < 0.00001f &&
			Math::abs(s - 0.5f) < 0.00001f && Math::abs(t - 0.5f) < 0.00001f,
			"crossed segment midpoint");

	Vector3 movable_c = c, movable_d = d;
	Vector3 pinned_a = a, pinned_b = b;
	ok &= check(physics_softbody_project_edge_contact(pinned_a, pinned_b,
			movable_c, movable_d, 0, 0, 1, 1, 0.1f, 0,
			a, b, c + Vector3(0, 0, -0.2f), d + Vector3(0, 0, -0.2f)),
			"mass-weighted crossed edge separation");
	physics_softbody_closest_segment_points(pinned_a, pinned_b, movable_c, movable_d,
			on_ab, on_cd, s, t);
	ok &= check(Math::abs(on_ab.distance_to(on_cd) - 0.1f) < 0.00002f &&
			pinned_a == a && pinned_b == b, "pinned edge stays fixed");

	ok &= check(physics_softbody_closest_segment_points(a, b,
			Vector3(0, -1, 0.04f), Vector3(0, 1, 0.04f),
			on_ab, on_cd, s, t) && Math::abs(on_ab.distance_to(on_cd) - 0.04f) < 0.00002f,
			"skew segment closest points");
	ok &= check(physics_softbody_closest_segment_points(a, b,
			Vector3(-1, 0.04f, 0), Vector3(1, 0.04f, 0),
			on_ab, on_cd, s, t) && Math::abs(on_ab.distance_to(on_cd) - 0.04f) < 0.00002f,
			"parallel segment closest points");
	ok &= check(physics_softbody_closest_segment_points(a, b,
			Vector3(2, -1, 0), Vector3(2, 1, 0),
			on_ab, on_cd, s, t) && Math::abs(on_ab.distance_to(on_cd) - 1.0f) < 0.00002f,
			"finite endpoint clamp");
	ok &= check(!physics_softbody_closest_segment_points(a, a, c, d,
			on_ab, on_cd, s, t), "degenerate edge rejected");
	Vector3 ta(0, 0, 0), tb(1, 0, 0), tc(0, 1, 0), point(0.25f, 0.25f, 0.03f);
	Vector3 closest, bary;
	ok &= check(physics_softbody_closest_triangle_point(point, ta, tb, tc, closest, bary),
			"existing vertex-face math still compiles");
	ok &= check(physics_softbody_project_self_contact(point, ta, tb, tc,
			1, 0, 0, 0, 0.1f, 0, point) && Math::abs(point.z - 0.1f) < 0.00002f,
			"existing vertex-face projection still works");

	// For random finite segments, the analytical closest pair cannot be
	// farther apart than ANY sampled candidate on a coarse 9x9 grid.
	// The grid is independent of the analytical segment solver and
	// checks for incorrect endpoint clamping or parallel branches.
	uint32_t rng = 0xC0FFEE37u;
	auto sample = [&rng]() -> float {
		rng ^= rng << 13;
		rng ^= rng >> 17;
		rng ^= rng << 5;
		return float(int32_t(rng % 20001u) - 10000) / 5000.0f;
	};
	for (int iteration = 0; iteration < 20000 && ok; ++iteration) {
		Vector3 p(sample(), sample(), sample());
		Vector3 q(sample(), sample(), sample());
		Vector3 r(sample(), sample(), sample());
		Vector3 w(sample(), sample(), sample());
		// Explicit near-parallel population.
		if (iteration % 7 == 0) {
			w = r + (q - p) + Vector3(0.0000001f, 0, 0);
		}
		if (!physics_softbody_closest_segment_points(p, q, r, w,
					on_ab, on_cd, s, t)) {
			ok &= check(false, "random finite edge");
			break;
		}
		const float actual = on_ab.distance_squared_to(on_cd);
		float grid_best = 1.0e30f;
		for (int u = 0; u <= 8; ++u) {
			for (int v = 0; v <= 8; ++v) {
				const Vector3 sample_ab = p.lerp(q, float(u) / 8.0f);
				const Vector3 sample_cd = r.lerp(w, float(v) / 8.0f);
				grid_best = std::min(grid_best, sample_ab.distance_squared_to(sample_cd));
			}
		}
		if (!(s >= 0.0f && s <= 1.0f && t >= 0.0f && t <= 1.0f) ||
				!Math::is_finite(actual) || actual > grid_best + 0.0002f) {
			ok &= check(false, "random segment distance <= sampled distances");
			break;
		}
	}

	if (ok) {
		std::puts("PASS: standalone soft-body vertex/face and edge/edge C++ smoke checks; 20,000 random edge pairs");
	}
	return ok ? 0 : 1;
}
