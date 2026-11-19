// Compile and run the real production tetrahedral cycle-fatigue header.
#include "servers/physics_fem_tetra_cycle_fatigue.h"

#include <cmath>
#include <cstdio>

static bool append(PhysicsFEMTetraCycleFatigueState &s, double x, double &d) {
	return PhysicsFEMTetraCycleFatigue::evolve(x, 0.1, 0.3, 10.0, 2.0, 0.0, s, d);
}

int main() {
	PhysicsFEMTetraRest rest;
	if (!physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest)) {
		return 1;
	}
	const Vector3 x[4] = { Vector3(), Vector3(real_t(1.3), 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1) };
	double signed_strain = 0.0;
	if (!PhysicsFEMTetraCycleFatigue::measure_strain(x, rest, signed_strain) ||
			std::abs(signed_strain-std::log(1.3)) > 1e-5) {
		return 2;
	}
	const Vector3 rotated[4] = { Vector3(3, 4, 5),
		Vector3(3, real_t(5.3), 5), Vector3(2, 4, 5), Vector3(3, 4, 6) };
	double rotated_strain = 0.0;
	if (!PhysicsFEMTetraCycleFatigue::measure_strain(rotated, rest, rotated_strain) ||
			std::abs(signed_strain-rotated_strain) > 1e-5) {
		return 3;
	}
	PhysicsFEMTetraCycleFatigueState fatigue;
	double damage = 0.0;
	if (!append(fatigue, 0.0, damage)) {
		return 4;
	}
	for (int i=0; i<4; ++i) {
		if (!append(fatigue, 0.6, damage) || !append(fatigue, 0.0, damage)) {
			return 5;
		}
	if (fatigue.cycles != 3 || std::abs(damage - 0.3) > 1e-7) {
		return 6;
	}
	for (int i=0; i<10; ++i) {
		if (!append(fatigue, 0.0, damage)) {
			return 7;
		}
	}
	if (fatigue.cycles != 3 || std::abs(damage - 0.3) > 1e-7) {
		return 8;
	}
	const Vector3 flipped[4] = { Vector3(), Vector3(1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, -1) };
	if (PhysicsFEMTetraCycleFatigue::measure_strain(flipped, rest, signed_strain)) {
		return 9;
	}
	std::puts("Native FEM cycle fatigue float/double header smoke OK");
	return 0;
}
