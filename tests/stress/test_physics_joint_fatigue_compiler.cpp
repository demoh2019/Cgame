// Compile and execute the REAL Cgame joint-fatigue header without Godot deps.
#include "servers/physics_joint_fatigue.h"

#include <cstdio>
#include <limits>

int main() {
	double damage = 0.0;
	for (int step = 0; step < 16; ++step) {
		if (!physics_joint_accumulate_fatigue_damage(75, 0, 100, 0, .5, 10, .1, damage)) {
			return 1;
		}
	}
	if (damage != 1.0) {
		return 2;
	}
	double a = 0.0, b = 0.0;
	if (!physics_joint_accumulate_fatigue_damage(80, 0, 100, 0, .4, 2, .5, a)) {
		return 3;
	}
	for (int i = 0; i < 10; ++i) {
		if (!physics_joint_accumulate_fatigue_damage(80, 0, 100, 0, .4, 2, .05, b)) {
			return 4;
		}
	}
	if (std::abs(a-b) > 1e-12) {
		return 5;
	}
	double c = .3;
	if (physics_joint_accumulate_fatigue_damage(
			std::numeric_limits<double>::quiet_NaN(), 0, 100, 0, .5, 1, .1, c) || c != .3) {
		return 6;
	}
	std::puts("Cgame joint fatigue C++ header tests OK");
	return 0;
}
