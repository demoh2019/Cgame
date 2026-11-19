// Compiles the ACTUAL Cgame CCD header using a small test-only Vector3.
// This is a fast C++ syntax/numerical smoke, not a Godot engine build.
// g++ -std=c++17 -O2 -Wall -Wextra -Werror -pedantic \
//   -Itests/stress/mock_xpbd_edge_ccd -I. \
//   tests/stress/physics_xpbd_edge_ccd_standalone.cpp -o /tmp/edge-ccd
// /tmp/edge-ccd

#include "servers/physics_xpbd_edge_ccd.h"

#include <cstdio>

static bool check(bool p_condition, const char *p_reason) {
	if (!p_condition) {
		std::fprintf(stderr, "FAILED: %s\n", p_reason);
	}
	return p_condition;
}

int main() {
	bool ok = true;
	const Vector3 a(-1, 0, 0), b(1, 0, 0);
	const Vector3 c(0, -1, 1), d(0, 1, 1);
	const Vector3 displacement(0, 0, -2);
	PhysicsXPBDEdgeCCDHit hit;
	ok &= check(physics_xpbd_swept_edge_edge(a, a, b, b, c, c + displacement,
					d, d + displacement, hit), "crossed edges CCD");
	ok &= check(Math::abs(hit.time - 0.5f) < 0.0001f &&
					Math::abs(hit.s - 0.5f) < 0.0001f &&
					Math::abs(hit.t - 0.5f) < 0.0001f &&
					hit.normal.z < -0.9f, "crossed edge witness and orientation");
	const Vector3 safe_c = c.lerp(c + displacement, hit.time - 0.0001f);
	const Vector3 safe_d = d.lerp(d + displacement, hit.time - 0.0001f);
	Vector3 pinned_a = a, pinned_b = b, moved_c = safe_c, moved_d = safe_d;
	real_t lambda = 0.0f;
	ok &= check(physics_xpbd_solve_swept_edge_edge(pinned_a, pinned_b, moved_c,
					moved_d, 0, 0, 1, 1, 0.1f, 0, hit, lambda),
			"mass-weighted impact-time XPBD projection");
	ok &= check(pinned_a == a && pinned_b == b && moved_c.z > 0.099f &&
					moved_d.z > 0.099f && lambda > 0.0f, "pin-safe contact separation");

	PhysicsXPBDEdgeCCDHit miss;
	ok &= check(!physics_xpbd_swept_edge_edge(a, a, b, b,
					c, c + Vector3(0, 0, -0.3f),
					d, d + Vector3(0, 0, -0.3f), miss), "true non-hit");
	ok &= check(!physics_xpbd_swept_edge_edge(a, a, b, b,
					c + Vector3(2.5f, 0, 0), c + Vector3(2.5f, 0, -2),
					d + Vector3(2.5f, 0, 0), d + Vector3(2.5f, 0, -2), miss),
			"infinite-line intersection excluded");

	// 4000 deterministic randomized real segment crossings and 1000
	// distant false positives. A random global origin also probes
	// roundoff stability in normal-sized game worlds.
	uint32_t rng = 0xA12B56CDu;
	auto random01 = [&rng]() -> float {
		rng ^= rng << 13;
		rng ^= rng >> 17;
		rng ^= rng << 5;
		return float(rng % 100000u) / 100000.0f;
	};
	for (int test = 0; test < 4000 && ok; ++test) {
		const float before = 0.1f + random01() * 2.5f;
		const float travel = before + 0.1f + random01() * 2.5f;
		const float expected_time = before / travel;
		const Vector3 offset(random01() * 100.0f - 50.0f,
				random01() * 100.0f - 50.0f,
				random01() * 100.0f - 50.0f);
		const Vector3 ca = a + offset, cb = b + offset;
		const Vector3 cc = Vector3(0, -1, before) + offset;
		const Vector3 cd = Vector3(0, 1, before) + offset;
		const Vector3 shift(0, 0, -travel);
		PhysicsXPBDEdgeCCDHit sample;
		if (!physics_xpbd_swept_edge_edge(ca, ca, cb, cb,
					cc, cc + shift, cd, cd + shift, sample) ||
				Math::abs(sample.time - expected_time) > 0.00015f ||
				Math::abs(sample.s - 0.5f) > 0.0001f ||
				Math::abs(sample.t - 0.5f) > 0.0001f) {
			ok &= check(false, "randomized swept crossing");
			break;
		}
		if (test < 1000) {
			PhysicsXPBDEdgeCCDHit far_hit;
			ok &= check(!physics_xpbd_swept_edge_edge(ca, ca, cb, cb,
							cc + Vector3(3, 0, 0), cc + shift + Vector3(3, 0, 0),
							cd + Vector3(3, 0, 0), cd + shift + Vector3(3, 0, 0), far_hit),
					"randomized false positive on infinite lines");
		}
	}

	if (ok) {
		std::puts("PASS: 4000 swept structural-edge crossings, 1000 infinite-line misses, XPBD pins");
	}
	return ok ? 0 : 1;
}
