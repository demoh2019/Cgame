// Compile the real Kelvin-Voigt tetra FEM viscosity header in both float
// and double mode. The Vector3 stub is test-only and never used by Godot.
#include "servers/physics_fem_tetra_viscosity.h"

#include <cmath>
#include <cstdio>

static double norm_squared(const Vector3 &p) {
	return double(p.x) * p.x + double(p.y) * p.y + double(p.z) * p.z;
}

static double kinetic(const Vector3 (&p)[4]) {
	double e = 0.0;
	for (const Vector3 &v : p) {
		e += 0.5 * norm_squared(v);
	}
	return e;
}

int main() {
	const Vector3 x[4] = { Vector3(), Vector3(1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1) };
	PhysicsFEMTetraRest rest;
	if (!physics_fem_tetra_make_rest(x[0], x[1], x[2], x[3], rest)) {
		return 1;
	}
	Vector3 v[4] = { Vector3(), Vector3(2, 0, 0), Vector3(), Vector3() };
	Vector3 forces[4];
	if (!physics_fem_tetra_viscous_forces(x, v, rest, 0.3, 10.0, forces)) {
		return 2;
	}
	for (int axis = 0; axis < 3; ++axis) {
		const double net = double(forces[0][axis]) + forces[1][axis] +
				forces[2][axis] + forces[3][axis];
		if (std::abs(net) > 1e-5) {
			return 3;
		}
	}
	const real_t inv[4] = { 1, 1, 1, 1 };
	const double before = kinetic(v);
	if (!physics_fem_tetra_viscous_damp(x, v, inv, rest, 0.3, 1e6, 1.0)) {
		return 4;
	}
	if (kinetic(v) > before + 1e-5) {
		return 5;
	}

	// Objectivity: a pure spin has zero Green strain rate.
	const Vector3 deformed[4] = { Vector3(), Vector3(real_t(1.25), real_t(0.1), 0),
		Vector3(0, real_t(0.75), real_t(0.1)), Vector3(0, 0, 1) };
	Vector3 spin[4];
	for (int i = 0; i < 4; ++i) {
		spin[i] = Vector3(-deformed[i].y, deformed[i].x, 0);
	}
	if (!physics_fem_tetra_viscous_forces(
			deformed, spin, rest, 0.3, 10.0, forces)) {
		return 6;
	}
	for (const Vector3 &f : forces) {
		if (norm_squared(f) > 1e-8) {
			return 7;
		}
	}
	Vector3 invalid[4] = { x[0], x[1], x[2], Vector3(0, 0, -1) };
	if (physics_fem_tetra_viscous_forces(invalid, spin, rest, 0.3, 10, forces)) {
		return 8;
	}
	std::puts("Objective FEM viscosity compile/runtime smoke OK");
	return 0;
}
