// Standalone float32/float64 smoke compile of REAL Godot FEM volume plasticity.
// The fake Vector3 is only for this compiler test; production uses Godot's.
#include "servers/physics_fem_tetra_volume_plasticity.h"
#include "servers/physics_fem_tetra_neo_hookean.h"

#include <cmath>
#include <cstdio>
#include <limits>
#include <initializer_list>

static bool run(double size, bool inverse_winding) {
	PhysicsFEMTetraRest rest;
	const real_t s = real_t(size);
	const real_t winding = inverse_winding ? real_t(-1) : real_t(1);
	if (!physics_fem_tetra_make_rest(Vector3(), Vector3(s, 0, 0),
			Vector3(0, s, 0), Vector3(0, 0, s*winding), rest)) {
		return false;
	}
	double accumulated = 1.0;
	const real_t t = real_t(size * 1.1);
	if (!physics_fem_tetra_creep_volume_rest(
			Vector3(), Vector3(t, 0, 0), Vector3(0, t, 0),
			Vector3(0, 0, t*winding), 0, 1, rest, accumulated)) {
		return false;
	}
	if (std::abs(accumulated - 1.331) > 1e-4 || !(rest.volume > 0)) {
		return false;
	}
	double energy = 10.0;
	Vector3 ga, gb, gc, gd;
	if (!physics_fem_tetra_energy_gradient(Vector3(),
			Vector3(t, 0, 0), Vector3(0, t, 0), Vector3(0, 0, t*winding),
			rest, .3, energy, ga, gb, gc, gd) || energy > 1e-5) {
		return false;
	}
	const double before = accumulated;
	if (physics_fem_tetra_creep_volume_rest(Vector3(),
			Vector3(t, 0, 0), Vector3(0, t, 0), Vector3(0, 0, t*winding),
			0, 1, rest, accumulated) || before != accumulated) {
		return false;
	}
	return true;
}

int main() {
	for (double size : { .01, 1.0, 100.0 }) {
		if (!run(size, false) || !run(size, true)) {
			return 1;
		}
	}
	PhysicsFEMTetraRest rest;
	if (!physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest)) {
		return 2;
	}
	double scale = 1.0;
	if (physics_fem_tetra_creep_volume_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, -1), 0, 1, rest, scale)) {
		return 3;
	}
	std::puts("Tetrahedral FEM volumetric viscoplasticity C++ smoke OK");
	return 0;
}
