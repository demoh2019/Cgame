// Smoke-compile the real volumetric FEM header in both real_t precisions.
// The Vector3 stub lives only on the test-specific include path.
#include "servers/physics_fem_tetra_neo_hookean.h"

#include <cmath>
#include <cstdio>

int main() {
	PhysicsFEMTetraRest rest;
	if (!physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest)) {
		return 1;
	}
	if (std::abs(rest.volume - 1.0 / 6.0) > 1e-9) {
		return 2;
	}
	double energy = -1;
	Vector3 g0, g1, g2, g3;
	if (!physics_fem_tetra_energy_gradient(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest,
			0.3, energy, g0, g1, g2, g3) || std::abs(energy) > 1e-8) {
		return 3;
	}
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	if (!physics_fem_tetra_solve(a, b, c, d, 0.0, 1.0, 0.0, 0.0,
			rest, 0.3, 0.0, lambda) ||
			!(b.x > 1.0 && b.x < 1.5) || !(lambda < 0.0)) {
		return 4;
	}
	if (!physics_fem_tetra_energy_gradient(a, b, c, d, rest, 0.3,
			energy, g0, g1, g2, g3) || !std::isfinite(energy)) {
		return 5;
	}
	// A rigid rotation of an undeformed tet does no elastic work.
	if (!physics_fem_tetra_energy_gradient(Vector3(3, 5, 2),
			Vector3(3, 6, 2), Vector3(2, 5, 2), Vector3(3, 5, 3),
			rest, 0.3, energy, g0, g1, g2, g3) || std::abs(energy) > 1e-8) {
		return 6;
	}
	if (physics_fem_tetra_energy_gradient(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, -1), rest, 0.3,
			energy, g0, g1, g2, g3)) {
		return 7;
	}
	std::puts("Neo-Hookean volumetric FEM C++ header smoke OK");
	return 0;
}
