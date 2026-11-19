// Compile the actual Ogden finite-strain FEM header under both precisions.
#include "servers/physics_fem_tetra_ogden.h"

#include <cmath>
#include <cstdio>

int main() {
	PhysicsFEMTetraRest rest;
	const Vector3 a, b(1, 0, 0), c(0, 1, 0), d(0, 0, 1);
	if (!physics_fem_tetra_make_rest(a, b, c, d, rest)) {
		return 1;
	}
	double energy = 0.0;
	Vector3 ga, gb, gc, gd;
	if (!physics_fem_tetra_ogden_energy_gradient(
			a, b, c, d, rest, 0.3, 3.0, energy, ga, gb, gc, gd) ||
			std::abs(energy) > 1e-7) {
		return 2;
	}
	Vector3 stretched(real_t(1.45), 0, 0);
	if (!physics_fem_tetra_ogden_energy_gradient(
			a, stretched, c, d, rest, 0.3, 3.0, energy, ga, gb, gc, gd) ||
			!(energy > 0.0) || !(gb.x > 0.0)) {
		return 3;
	}
	const double old_energy = energy;
	double multiplier = 0.0;
	Vector3 x0 = a, x1 = stretched, x2 = c, x3 = d;
	if (!physics_fem_tetra_ogden_solve(
			x0, x1, x2, x3, 0, 1, 0, 0,
			rest, 0.3, 3.0, 0.001, multiplier) ||
			!(x1.x < stretched.x)) {
		return 4;
	}
	if (!physics_fem_tetra_ogden_energy_gradient(
			x0, x1, x2, x3, rest, 0.3, 3.0, energy, ga, gb, gc, gd) ||
			!(energy < old_energy)) {
		return 5;
	}
	// Check numerical finite difference against the analytic gradient.
	const Vector3 x(real_t(1.25), real_t(0.2), 0);
	const real_t eps = real_t(0.001);
	double plus, minus;
	Vector3 ha, hb, hc, hd;
	if (!physics_fem_tetra_ogden_energy_gradient(
			a, x, c, d, rest, 0.3, 5.0, energy, ga, gb, gc, gd) ||
			!physics_fem_tetra_ogden_energy_gradient(
				a, Vector3(x.x + eps, x.y, x.z), c, d,
				rest, 0.3, 5.0, plus, ha, hb, hc, hd) ||
			!physics_fem_tetra_ogden_energy_gradient(
				a, Vector3(x.x - eps, x.y, x.z), c, d,
				rest, 0.3, 5.0, minus, ha, hb, hc, hd)) {
		return 6;
	}
	if (std::abs(double(gb.x) - (plus-minus)/(2.0*double(eps))) > 0.01) {
		return 7;
	}
	if (physics_fem_tetra_ogden_energy_gradient(a, b, c,
			Vector3(0, 0, -1), rest, 0.3, 3.0,
			energy, ga, gb, gc, gd)) {
		return 8;
	}
	std::puts("Ogden FEM native float/double header smoke OK");
	return 0;
}
