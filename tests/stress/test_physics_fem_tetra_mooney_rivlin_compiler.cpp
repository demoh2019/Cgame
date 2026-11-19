// Independent compile-and-run smoke for the actual Mooney-Rivlin C++ FEM
// header. Test-only Vector3 stub is selected by the compiler include path.
#include "servers/physics_fem_tetra_mooney_rivlin.h"

#include <cmath>
#include <cstdio>

static bool evaluate(const Vector3 &a, const Vector3 &b, const Vector3 &c,
		const Vector3 &d, const PhysicsFEMTetraRest &rest,
		double fraction, double &energy, Vector3 &g0, Vector3 &g1,
		Vector3 &g2, Vector3 &g3) {
	return physics_fem_tetra_mooney_rivlin_energy_gradient(
			a, b, c, d, rest, 0.3, fraction, energy, g0, g1, g2, g3);
}

int main() {
	PhysicsFEMTetraRest rest;
	const Vector3 a, b(1, 0, 0), c(0, 1, 0), d(0, 0, 1);
	if (!physics_fem_tetra_make_rest(a, b, c, d, rest)) {
		return 1;
	}
	double energy = -1;
	Vector3 ga, gb, gc, gd;
	if (!evaluate(a, b, c, d, rest, 0.5, energy, ga, gb, gc, gd) ||
			std::abs(energy) > 1e-8) {
		return 2;
	}
	if (!evaluate(Vector3(2, 3, 4), Vector3(2, 4, 4),
			Vector3(1, 3, 4), Vector3(2, 3, 5), rest, 0.5,
			energy, ga, gb, gc, gd) || std::abs(energy) > 1e-8) {
		return 3;
	}
	const Vector3 elongated(real_t(1.5), 0, 0);
	if (!evaluate(a, elongated, c, d, rest, 0.5, energy, ga, gb, gc, gd) ||
			!(energy > 0.0)) {
		return 4;
	}
	const double before = energy;
	Vector3 p0 = a, p1 = elongated, p2 = c, p3 = d;
	double lambda = 0.0;
	if (!physics_fem_tetra_mooney_rivlin_solve(p0, p1, p2, p3,
			0, 1, 0, 0, rest, 0.3, 0.5, 0.001, lambda) ||
			!(p1.x < elongated.x)) {
		return 5;
	}
	if (!evaluate(p0, p1, p2, p3, rest, 0.5, energy, ga, gb, gc, gd) ||
			!(energy < before)) {
		return 6;
	}
	// Check analytical first-Piola gradient on a nontrivial tetra.
	const Vector3 strained_b(real_t(1.2), real_t(0.15), 0);
	const Vector3 strained_c(real_t(0.1), 1, 0);
	if (!evaluate(a, strained_b, strained_c, d, rest, 0.7,
			energy, ga, gb, gc, gd)) {
		return 7;
	}
	const real_t eps = real_t(0.001);
	double plus = 0.0, minus = 0.0;
	Vector3 tmp0, tmp1, tmp2, tmp3;
	if (!evaluate(a, strained_b, Vector3(strained_c.x + eps, strained_c.y, strained_c.z),
			d, rest, 0.7, plus, tmp0, tmp1, tmp2, tmp3) ||
			!evaluate(a, strained_b, Vector3(strained_c.x - eps, strained_c.y, strained_c.z),
				d, rest, 0.7, minus, tmp0, tmp1, tmp2, tmp3)) {
		return 8;
	}
	if (std::abs(double(gc.x) - (plus - minus) / (2.0 * double(eps))) > 0.005) {
		return 9;
	}
	if (evaluate(a, b, c, Vector3(0, 0, -1), rest, 0.5,
			energy, ga, gb, gc, gd)) {
		return 10;
	}
	std::puts("Mooney-Rivlin FEM double/float native header smoke OK");
	return 0;
}
