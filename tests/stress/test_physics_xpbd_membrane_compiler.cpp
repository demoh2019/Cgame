// Compile the REAL XPBD membrane solver header in both float and double
// configurations, without building the entire Godot editor. The stub
// vector3.h is restricted to this test's -I search path.
#include "servers/physics_xpbd_membrane.h"

#include <cmath>
#include <cstdio>
#include <initializer_list>

static bool approximately(double p_a, double p_b, double p_tol = 1e-5) {
	return std::abs(p_a - p_b) < p_tol;
}

int main() {
	PhysicsXPBDMembraneRest rest;
	if (!physics_xpbd_membrane_make_rest(Vector3(), Vector3(1, 0, 0),
				Vector3(0, 1, 0), rest) || !approximately(rest.area, 0.5)) {
		return 1;
	}
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0);
	double lambda = 0;
	if (!physics_xpbd_membrane_solve(a, b, c, 0.0, 1.0, 0.0,
				rest, 0.3, 0.0, lambda) || !(b.x > 1.0 && b.x < 1.5)) {
		return 2;
	}
	if (!approximately(a.x, 0.0) || !approximately(c.y, 1.0) ||
			!std::isfinite(lambda) || !(lambda < 0.0)) {
		return 3;
	}
	double energy = -1;
	Vector3 ga, gb, gc;
	if (!physics_xpbd_membrane_energy_gradient(Vector3(), Vector3(1, 0, 0),
				Vector3(0, 1, 0), rest, 0.3, energy, ga, gb, gc) ||
			!approximately(energy, 0)) {
		return 4;
	}
	for (real_t scale : { real_t(1e-8), real_t(1e20) }) {
		PhysicsXPBDMembraneRest scaled;
		if (!physics_xpbd_membrane_make_rest(Vector3(), Vector3(scale, 0, 0),
					Vector3(0, scale, 0), scaled)) {
			return 5;
		}
		Vector3 p0, p1(real_t(1.5) * scale, 0, 0), p2(0, scale, 0);
		double l = 0;
		if (!physics_xpbd_membrane_solve(p0, p1, p2, 0.0, 1.0, 0.0,
					scaled, 0.2, 0.0, l) ||
				!(p1.x / scale > 0.9 && p1.x / scale < 1.5) ||
				!std::isfinite(l)) {
			return 6;
		}
	}
	std::puts("StVK XPBD membrane header compile/runtime smoke OK");
	return 0;
}
