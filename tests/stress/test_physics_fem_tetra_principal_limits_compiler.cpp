// Compile the actual production principal FEM stretch cap under float/double.
#include "servers/physics_fem_tetra_principal_limits.h"

#include <cmath>
#include <cstdio>

static bool stretches(const Vector3 (&x)[4], const PhysicsFEMTetraRest &r,
		double (&s)[3]) {
	double v[3][3], f[3][3];
	return physics_fem_tetra_principal_spectrum(x, r, s, v, f);
}

int main() {
	const Vector3 unit[4] = {
		Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	PhysicsFEMTetraRest r;
	if (!physics_fem_tetra_make_rest(unit[0], unit[1], unit[2], unit[3], r)) {
		return 1;
	}
	double s[3];
	if (!stretches(unit, r, s) ||
			std::abs(s[0] - 1) > 1e-7 ||
			std::abs(s[2] - 1) > 1e-7) {
		return 2;
	}
	const Vector3 sheared[4] = {
		Vector3(), Vector3(1, 0, 0), Vector3(real_t(0.6), 1, 0), Vector3(0, 0, 1)
	};
	if (!stretches(sheared, r, s) || !(s[0] < 1.0 && s[2] > 1.0)) {
		return 3;
	}
	// Upper cap, pin anchor, and guarantee non-positive XPBD multiplier.
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	if (!physics_fem_tetra_principal_solve(a, b, c, d, 0, 1, 0, 0,
			r, false, 1.2, 0.0, lambda) || !(b.x < 1.5) ||
			!(lambda < 0.0)) {
		return 4;
	}
	const Vector3 compressed[4] = {
		Vector3(), Vector3(real_t(0.5), 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	a = compressed[0]; b = compressed[1]; c = compressed[2]; d = compressed[3];
	lambda = 0.0;
	if (!physics_fem_tetra_principal_solve(a, b, c, d, 0, 1, 0, 0,
			r, true, 0.8, 0.0, lambda) || !(b.x > real_t(0.5))) {
		return 5;
	}
	// Compare production analytic gradient with an independent finite difference.
	const Vector3 deformed[4] = {
		Vector3(), Vector3(real_t(1.3), real_t(0.15), 0),
		Vector3(real_t(0.2), real_t(0.85), 0), Vector3(0, 0, real_t(1.1))
	};
	Vector3 gradients[4], scratch[4];
	double violation, plus, minus;
	if (!physics_fem_tetra_principal_constraint(deformed, r, false,
			1.1, violation, gradients)) {
		return 6;
	}
	const real_t eps = real_t(0.0005);
	const Vector3 up[4] = {
		deformed[0], Vector3(deformed[1].x + eps, deformed[1].y, deformed[1].z),
		deformed[2], deformed[3]
	};
	const Vector3 down[4] = {
		deformed[0], Vector3(deformed[1].x - eps, deformed[1].y, deformed[1].z),
		deformed[2], deformed[3]
	};
	if (!physics_fem_tetra_principal_constraint(up, r, false, 1.1, plus, scratch) ||
			!physics_fem_tetra_principal_constraint(down, r, false, 1.1, minus, scratch) ||
			std::abs(double(gradients[1].x) - (plus - minus) / (2.0 * double(eps))) > 0.005) {
		return 7;
	}
	const Vector3 inverted[4] = {
		Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)
	};
	if (stretches(inverted, r, s)) {
		return 8;
	}
	std::puts("FEM tetrahedral principal stretch caps C++ smoke OK");
	return 0;
}
