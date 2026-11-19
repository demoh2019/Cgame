// Compile the actual FEM mass-lumping helper in float32 and float64.
// Test-only Godot Vector3/LocalVector stubs are restricted to -I search path.
// This is a solver-header compiler test, NOT a full engine build.
#include "servers/physics_fem_lumped_mass.h"

#include <cmath>
#include <cstdio>

static bool near(double a, double b, double tolerance = 1.0e-6) {
	return std::abs(a - b) <= tolerance;
}

int main() {
	LocalVector<PhysicsFEMConvexTetra> tets;
	PhysicsFEMConvexTetra first;
	first.a = 0; first.b = 1; first.c = 2; first.d = 3;
	first.rest.volume = 1;
	tets.push_back(first);
	PhysicsFEMConvexTetra second;
	second.a = 0; second.b = 2; second.c = 3; second.d = 4;
	second.rest.volume = 3;
	tets.push_back(second);

	LocalVector<double> fractions;
	LocalVector<real_t> inverse;
	if (!physics_fem_build_lumped_masses(5, tets, real_t(8),
				fractions, inverse) || fractions.size() != 5 ||
			inverse.size() != 5) {
		return 1;
	}
	const double expected[5] = { .25, .0625, .25, .25, .1875 };
	double mass_sum = 0;
	for (uint32_t i = 0; i < 5; ++i) {
		if (!near(fractions[i], expected[i]) ||
				!near(inverse[i], 1.0 / (8.0 * expected[i]))) {
			return 2;
		}
		mass_sum += 1.0 / double(inverse[i]);
	}
	if (!near(mass_sum, 8.0)) {
		return 3;
	}

	// A pin has inverse mass 0, but its physical fraction must not disappear.
	real_t restored = -1;
	if (!physics_fem_unpinned_inverse_mass(fractions, 4, real_t(8), restored) ||
			!near(restored, inverse[4])) {
		return 4;
	}
	real_t doubled_mass = 0;
	if (!physics_fem_unpinned_inverse_mass(fractions, 4, real_t(16), doubled_mass) ||
			!near(doubled_mass, inverse[4] * .5)) {
		return 5;
	}

	// Fail atomically: invalid or unused physical nodes cannot silently
	// receive invalid inverse masses, and old buffers remain untouched.
	if (physics_fem_build_lumped_masses(6, tets, real_t(8),
				fractions, inverse) || fractions.size() != 5) {
		return 6;
	}
	tets[1].d = 9999;
	if (physics_fem_build_lumped_masses(5, tets, real_t(8),
				fractions, inverse) || !near(fractions[4], .1875)) {
		return 7;
	}
	std::puts("FEM volume lumped mass: native helper smoke OK");
	return 0;
}
