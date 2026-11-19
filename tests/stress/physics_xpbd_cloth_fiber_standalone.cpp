// Compiles the ACTUAL Cgame orthotropic fiber helper with a test-only
// Vector3. Does not replace an editor build or full soft-body scene test.
//
// c++ -std=c++17 -O2 -Wall -Wextra -Werror -pedantic \
//   -Itests/stress/mock_xpbd_cloth_fiber -I. \
//   tests/stress/physics_xpbd_cloth_fiber_standalone.cpp -o /tmp/cloth-fiber
// /tmp/cloth-fiber

#include "servers/physics_xpbd_cloth_fiber.h"

#include <cstdio>

static bool check(bool ok, const char *label) {
	if (!ok) {
		std::fprintf(stderr, "FAIL: %s\n", label);
	}
	return ok;
}

int main() {
	bool ok = true;
	real_t alpha = real_t(-1.0);
	ok &= check(physics_xpbd_cloth_fiber_alpha(
			Vector3(), Vector3(1, 0, 0), Vector3(1, 0, 0),
			real_t(0.25), real_t(4.0), alpha) && alpha == real_t(1.0),
			"stiff warp");
	ok &= check(physics_xpbd_cloth_fiber_alpha(
			Vector3(), Vector3(0, 1, 0), Vector3(1, 0, 0),
			real_t(0.25), real_t(4.0), alpha) && alpha == real_t(4.0),
			"unchanged weft");
	ok &= check(physics_xpbd_cloth_fiber_alpha(
			Vector3(), Vector3(1, 1, 0), Vector3(1, 0, 0),
			real_t(0.25), real_t(4.0), alpha) &&
			std::abs(alpha - real_t(2.5)) < real_t(1e-5),
			"diagonal interpolation");
	ok &= check(physics_xpbd_cloth_fiber_alpha(
			Vector3(), Vector3(1, 0, 0), Vector3(1, 0, 0),
			real_t(100.0), std::numeric_limits<real_t>::max(), alpha) &&
			alpha == std::numeric_limits<real_t>::max(),
			"float and double saturation");

	uint32_t rng = 0xC0FFEE81u;
	auto random = [&rng]() -> double {
		rng ^= rng << 13;
		rng ^= rng >> 17;
		rng ^= rng << 5;
		return double(rng % 100000u) / 100000.0;
	};
	const double tolerance = sizeof(real_t) == 4 ? 2e-5 : 1e-11;
	for (int iteration = 0; iteration < 25000 && ok; ++iteration) {
		const Vector3 a(real_t(random() * 4 - 2), real_t(random() * 4 - 2), real_t(random() * 4 - 2));
		const Vector3 b(real_t(random() * 4 - 2), real_t(random() * 4 - 2), real_t(random() * 4 - 2));
		const Vector3 axis(real_t(random() * 4 - 2), real_t(random() * 4 - 2), real_t(random() * 4 - 2));
		const real_t ratio = real_t(random() * 8.0);
		const real_t base_alpha = real_t(random() * 5.0);
		real_t output = real_t(-1.0);
		if (!physics_xpbd_cloth_fiber_alpha(a, b, axis, ratio, base_alpha, output)) {
			ok &= check(false, "valid random rest edge");
			break;
		}
		const double dx = double(b.x) - double(a.x);
		const double dy = double(b.y) - double(a.y);
		const double dz = double(b.z) - double(a.z);
		const double dot = dx * double(axis.x) + dy * double(axis.y) + dz * double(axis.z);
		const double len2 = dx * dx + dy * dy + dz * dz;
		const double axis2 = double(axis.x) * double(axis.x) +
				double(axis.y) * double(axis.y) + double(axis.z) * double(axis.z);
		const double cos2 = std::min(1.0, std::max(0.0, dot * dot / (len2 * axis2)));
		const double expected = double(base_alpha) * (1.0 + (double(ratio) - 1.0) * cos2);
		if (std::abs(double(output) - expected) >
				tolerance * std::max(1.0, std::abs(expected))) {
			ok &= check(false, "random orthotropic alpha parity");
			break;
		}
		real_t reversed = real_t(-1.0);
		if (!physics_xpbd_cloth_fiber_alpha(b, a,
					Vector3(-axis.x, -axis.y, -axis.z),
					ratio, base_alpha, reversed) ||
				std::abs(double(reversed - output)) >
					tolerance * std::max(1.0, std::abs(expected))) {
			ok &= check(false, "reversed edge and fiber axis parity");
			break;
		}
	}

	// Failed queries leave caller's alpha unchanged.
	alpha = real_t(42.0);
	ok &= check(!physics_xpbd_cloth_fiber_alpha(
			Vector3(), Vector3(), Vector3(1, 0, 0),
			real_t(0.25), real_t(4.0), alpha) && alpha == real_t(42.0),
			"zero rest edge atomic rejection");
	ok &= check(!physics_xpbd_cloth_fiber_alpha(
			Vector3(), Vector3(1, 0, 0), Vector3(),
			real_t(0.25), real_t(4.0), alpha) && alpha == real_t(42.0),
			"zero fiber axis atomic rejection");
	ok &= check(!physics_xpbd_cloth_fiber_alpha(
			Vector3(), Vector3(1, 0, 0), Vector3(1, 0, 0),
			real_t(-1.0), real_t(4.0), alpha) && alpha == real_t(42.0),
			"invalid compliance ratio atomic rejection");
	if (ok) {
		std::puts("PASS: 25,000 orthotropic rest edges, endpoint/axis reversal, finite saturation");
	}
	return ok ? 0 : 1;
}
