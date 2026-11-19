// Header compile/run in float32 and float64 with test-only Vector3 stubs.
#include "servers/physics_fem_tetra_deviatoric_plasticity.h"

#include <cmath>
#include <cstdio>
#include <initializer_list>

static bool test(double size) {
	PhysicsFEMTetraRest rest;
	const real_t s = real_t(size);
	const Vector3 x[4] = { Vector3(), Vector3(s, 0, 0),
			Vector3(real_t(.6) * s, s, 0), Vector3(0, 0, s) };
	if (!physics_fem_tetra_make_rest(Vector3(), Vector3(s, 0, 0),
			Vector3(0, s, 0), Vector3(0, 0, s), rest)) {
		return false;
	}
	double dev[3], basis[3][3], before = 0.0, after = 1.0, plastic = 0.0;
	if (!physics_fem_tetra_deviatoric_strains(x, rest, dev, basis, before) ||
			!(before > .1)) {
		return false;
	}
	if (!physics_fem_tetra_creep_deviatoric_rest(x[0], x[1], x[2], x[3],
			0, 1, 3.0, rest, plastic)) {
		return false;
	}
	if (!physics_fem_tetra_deviatoric_strains(x, rest, dev, basis, after) ||
			!(after < 1e-5) || std::abs(plastic-before) > 1e-5 ||
			std::abs(rest.signed_det - size*size*size) > size*size*size*1e-5) {
		return false;
	}
	double energy; Vector3 ga, gb, gc, gd;
	if (!physics_fem_tetra_energy_gradient(x[0], x[1], x[2], x[3],
			rest, .3, energy, ga, gb, gc, gd) || energy > 1e-5) {
		return false;
	}
	return true;
}

int main() {
	for (double size : { .01, 1.0, 100.0 }) {
		if (!test(size)) {
			return 1;
		}
	}
	PhysicsFEMTetraRest rest;
	if (!physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest)) {
		return 2;
	}
	double plastic = 0;
	if (physics_fem_tetra_creep_deviatoric_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), 0, 1, 2, rest, plastic)) {
		return 3;
	}
	std::puts("FEM tetrahedral J2-like deviatoric plasticity compile/runtime smoke OK");
	return 0;
}
