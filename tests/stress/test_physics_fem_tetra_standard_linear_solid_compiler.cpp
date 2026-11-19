// Native C++ smoke compiles the real SLS FEM header against isolated Godot
// Vector3 stubs under both float and double math precision.
#include "servers/physics_fem_tetra_standard_linear_solid.h"

#include <cmath>
#include <cstdio>

int main() {
	PhysicsFEMTetraRest rest;
	const Vector3 original[4] = {
		Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	if (!physics_fem_tetra_make_rest(original[0], original[1],
			original[2], original[3], rest)) {
		return 1;
	}
	PhysicsFEMTetraSLSState state;
	double energy;
	Vector3 a, b, c, d;
	if (!physics_fem_tetra_sls_energy_gradient(original[0], original[1],
			original[2], original[3], rest, state, 0.3, energy,
			a, b, c, d) || std::abs(energy) > 1e-8) {
		return 2;
	}
	const Vector3 stretched[4] = {
		original[0], Vector3(real_t(1.4), 0, 0), original[2], original[3]
	};
	if (!physics_fem_tetra_sls_energy_gradient(stretched[0], stretched[1],
			stretched[2], stretched[3], rest, state, 0.3, energy,
			a, b, c, d) || !(energy > 0.0)) {
		return 3;
	}
	const double before = energy;
	if (!physics_fem_tetra_sls_relax(stretched, rest, 0.2, 0.1, state) ||
			!physics_fem_tetra_sls_energy_gradient(stretched[0], stretched[1],
				stretched[2], stretched[3], rest, state, 0.3,
				energy, a, b, c, d) ||
			!(energy < before && energy > 0.0) ||
			std::abs(energy - before * std::exp(-1.0)) > 0.0001) {
		return 4;
	}
	// Fixed-memory SLS projection must reduce overstress without moving pins.
	Vector3 x0 = stretched[0], x1 = stretched[1], x2 = stretched[2], x3 = stretched[3];
	if (!physics_fem_tetra_sls_solve(x0, x1, x2, x3,
			0, 1, 0, 0, rest, state, 0.3, 0.001, state.lambda) ||
			!(x1.x < stretched[1].x)) {
		return 5;
	}
	const double memory = state.relaxing_strain[0][0];
	const Vector3 inverted[4] = {
		original[0], original[1], original[2], Vector3(0, 0, -1)
	};
	if (physics_fem_tetra_sls_relax(inverted, rest, 0.2, 0.1, state) ||
			state.relaxing_strain[0][0] != memory) {
		return 6;
	}
	std::puts("Objective FEM standard linear solid smoke OK");
	return 0;
}
