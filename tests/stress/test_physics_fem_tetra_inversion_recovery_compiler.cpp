// Smoke-compile actual tetrahedral inversion recovery + FEM headers.
// Compile with both float32 and float64 Godot real_t stubs.
#include "servers/physics_fem_tetra_inversion_recovery.h"

#include <cmath>
#include <cstdio>

static bool run(double scale, bool negative_winding, bool pinned) {
	const real_t s = real_t(scale);
	const real_t direction = negative_winding ? real_t(-1) : real_t(1);
	PhysicsFEMTetraRest rest;
	if (!physics_fem_tetra_make_rest(Vector3(), Vector3(s, 0, 0),
			Vector3(0, s, 0), Vector3(0, 0, s * direction), rest)) {
		return false;
	}
	Vector3 a, b(s, 0, 0), c(0, s, 0), d(0, 0, -s * direction);
	const real_t w = pinned ? real_t(0) : real_t(1);
	if (!physics_fem_tetra_recover_orientation(a, b, c, d,
			w, w, w, 1, rest, .05)) {
		return false;
	}
	const Vector3 x[4] = { a, b, c, d };
	double jacobian, gradients[4][3];
	if (!physics_fem_tetra_recovery_jacobian(x, rest, jacobian, gradients) ||
			!(jacobian >= .05 - 1e-5 && jacobian <= 1.0 + 1e-5)) {
		return false;
	}
	double energy;
	Vector3 ga, gb, gc, gd;
	return physics_fem_tetra_energy_gradient(a, b, c, d, rest, .3,
			energy, ga, gb, gc, gd) && std::isfinite(energy);
}

int main() {
	for (double scale : { 1e-3, 1.0, 1e3 }) {
		for (bool negative : { false, true }) {
			for (bool pinned : { false, true }) {
				if (!run(scale, negative, pinned)) {
					return 1;
				}
			}
		}
	}
	PhysicsFEMTetraRest rest;
	if (!physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest)) {
		return 2;
	}
	Vector3 a, b(1, 0, 0), c(0, 1, 0), d(0, 0, -1);
	if (physics_fem_tetra_recover_orientation(a, b, c, d,
			0, 0, 0, 0, rest, .05)) {
		return 3;
	}
	if (!physics_fem_tetra_recover_orientation(a, b, c, d,
			1, 1, 1, 1, rest, .05)) {
		return 4;
	}
	if (physics_fem_tetra_recover_orientation(a, b, c, d,
			1, 1, 1, 1, rest, .05)) {
		return 5; // No change is needed after successful recovery.
	}
	std::puts("FEM tetrahedral inversion recovery compiler/runtime smoke OK");
	return 0;
}
