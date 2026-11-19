// Compile the REAL membrane dashpot in float32/float64 builds against
// the restricted standalone Vector3 stub. Not a full Godot engine build.
#include "servers/physics_softbody_membrane_damping.h"

#include <cmath>
#include <cstdio>
#include <initializer_list>

static bool approx(double a, double b, double tolerance = 1e-5) {
	return std::abs(a - b) <= tolerance;
}

int main() {
	PhysicsXPBDMembraneRest rest;
	const Vector3 a, b(1, 0, 0), c(0, 1, 0);
	if (!physics_xpbd_membrane_make_rest(a, b, c, rest)) {
		return 1;
	}

	Vector3 va, vb(2, 0, 0), vc;
	if (!physics_softbody_damp_membrane(a, b, c, va, vb, vc,
				1.0, 1.0, 1.0, rest, 0.8)) {
		return 2;
	}
	if (!approx(double(va.x) + vb.x + vc.x, 2.0) ||
			!approx(double(va.y) + vb.y + vc.y, 0.0) ||
			!va.is_finite() || !vb.is_finite() || !vc.is_finite()) {
		return 3;
	}
	const double initial_energy = 2.0;
	const double energy = 0.5 * (double(va.x) * va.x + double(va.y) * va.y +
			double(vb.x) * vb.x + double(vb.y) * vb.y +
			double(vc.x) * vc.x + double(vc.y) * vc.y);
	if (!(energy < initial_energy)) {
		return 4;
	}

	Vector3 stationary, spin_b(0, 1, 0), spin_c(-1, 0, 0);
	physics_softbody_damp_membrane(a, b, c, stationary, spin_b, spin_c,
			1.0, 1.0, 1.0, rest, 1.0);
	if (!approx(spin_b.y, 1.0) || !approx(spin_c.x, -1.0)) {
		return 5;
	}

	Vector3 v0(0, 0, 0), v1(0, 0, 0), v2(2, 0, 0);
	if (!physics_softbody_damp_membrane(a, b, c, v0, v1, v2,
				0.0, 0.0, 1.0, rest, 1.0) ||
			!approx(v0.x, 0.0) || !approx(v1.x, 0.0)) {
		return 6;
	}

	for (real_t scale : { real_t(1e-8), real_t(1e20) }) {
		PhysicsXPBDMembraneRest scaled;
		const Vector3 p0, p1(scale, 0, 0), p2(0, scale, 0);
		if (!physics_xpbd_membrane_make_rest(p0, p1, p2, scaled)) {
			return 7;
		}
		Vector3 u0, u1(2, 0, 0), u2;
		if (!physics_softbody_damp_membrane(p0, p1, p2, u0, u1, u2,
					1.0, 1.0, 1.0, scaled, 0.7) ||
				!u0.is_finite() || !u1.is_finite() || !u2.is_finite()) {
			return 8;
		}
	}
	std::puts("objective XPBD membrane damping smoke OK");
	return 0;
}
