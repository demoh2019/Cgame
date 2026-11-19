// Compile and exercise real FEM Neo-Hookean and damage headers in both
// float32 and float64 using ONLY test-only Vector3 substitutes.
#include "servers/physics_fem_tetra_damage.h"
#include "servers/physics_fem_tetra_neo_hookean.h"

#include <cmath>
#include <cstdio>
#include <limits>

int main() {
	PhysicsFEMTetraRest rest;
	if (!physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest)) {
		return 1;
	}
	double energy = 0.0;
	Vector3 ga, gb, gc, gd;
	if (!physics_fem_tetra_energy_gradient(Vector3(), Vector3(1.5, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1),
			rest, 0.3, energy, ga, gb, gc, gd) || !(energy > 0.0)) {
		return 2;
	}
	double damage = 0.0;
	if (!physics_fem_tetra_accumulate_damage(energy/rest.volume, 0.05, 4, .1, damage) ||
			!(damage > 0.0 && damage <= 0.95)) {
		return 3;
	}
	if (!(physics_fem_tetra_damage_alpha(.001, damage) > .001)) {
		return 4;
	}
	const double before = damage;
	if (physics_fem_tetra_accumulate_damage(0.01, 0.05, 4, .1, damage) ||
			damage != before) {
		return 5;
	}
	double exact = 0.0, split = 0.0;
	physics_fem_tetra_accumulate_damage(.2, .1, 2, .1, exact);
	physics_fem_tetra_accumulate_damage(.2, .1, 2, .05, split);
	physics_fem_tetra_accumulate_damage(.2, .1, 2, .05, split);
	if (std::abs(exact - split) > 1e-10) {
		return 6;
	}
	double saturation = 0.0;
	if (!physics_fem_tetra_accumulate_damage(1e200, 1e-10, 1e3, 2, saturation) ||
			saturation != 0.95) {
		return 7;
	}
	if (!std::isfinite(physics_fem_tetra_damage_alpha(
			std::numeric_limits<double>::max(), saturation))) {
		return 8;
	}
	std::puts("FEM tetrahedral progressive damage compile/runtime smoke OK");
	return 0;
}
