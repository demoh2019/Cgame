// Real native FEM header: check scalar local damage in both Godot real_t modes.
#include "servers/physics_fem_tetra_damage.h"

#include <cmath>
#include <cstdio>

int main() {
	const Vector3 original[4] = {
		Vector3(), Vector3(1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	PhysicsFEMTetraRest rest;
	if (!physics_fem_tetra_make_rest(original[0], original[1],
			original[2], original[3], rest)) {
		return 1;
	}
	double strain = -1.0, damage = 0.0;
	if (!PhysicsFEMTetraDamage::equivalent_strain(original, rest, 0.3, strain)
			|| !(strain < 1e-8)) {
		return 2;
	}
	const Vector3 stretched[4] = {
		original[0], Vector3(real_t(1.5), 0, 0), original[2], original[3]
	};
	if (!PhysicsFEMTetraDamage::equivalent_strain(stretched, rest, 0.3, strain)
			|| !(strain > 0.25)) {
		return 3;
	}
	if (!PhysicsFEMTetraDamage::evolve(strain, 0.1, 5.0, 0.02, damage)) {
		return 4;
	}
	const double permanently_damaged = damage;
	if (PhysicsFEMTetraDamage::evolve(0.0, 0.1, 5.0, 0.02, damage) ||
			damage != permanently_damaged) {
		return 5;
	}
	double elastic = 0.0, softened = 0.0;
	if (!PhysicsFEMTetraDamage::effective_compliance(1e-4, 0.0, elastic)
			|| !PhysicsFEMTetraDamage::effective_compliance(1e-4, damage, softened)
			|| !(softened > elastic)) {
		return 6;
	}
	// Existing production XPBD tetra solver must respond less to a damaged
	// element with the same rest geometry and initial stretch.
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0), d(0, 0, 1);
	Vector3 a_soft = a, b_soft = b, c_soft = c, d_soft = d;
	double l0 = 0.0, l1 = 0.0;
	if (!physics_fem_tetra_solve(a, b, c, d, 0, 1, 0, 0,
			rest, 0.3, elastic, l0) ||
			!physics_fem_tetra_solve(a_soft, b_soft, c_soft, d_soft, 0, 1, 0, 0,
				rest, 0.3, softened, l1)) {
		return 7;
	}
	if (!(b_soft.x >= b.x && b_soft.x <= real_t(1.5))) {
		return 8;
	}
	// Full damage cap retains a positive stiffness of at least five percent.
	damage = 0.0;
	if (!PhysicsFEMTetraDamage::evolve(10, 0.1, 1e9, 10, damage)
			|| std::abs(damage - 0.95) > 1e-12) {
		return 9;
	}
	std::puts("Irreversible tetra FEM scalar damage smoke OK");
	return 0;
}
