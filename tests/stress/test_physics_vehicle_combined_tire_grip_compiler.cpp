// Strict C++ runtime check using the production header. No engine stubs needed.
#include "servers/physics_vehicle_combined_tire_grip.h"

#include <cmath>
#include <cstdio>
#include <limits>

int main() {
	double forward = -1, side = -1, skid = -1;
	if (!physics_vehicle_project_combined_tire_impulses(100, 0, 10, 1, 1, 1,
				forward, side, skid) || std::abs(forward - 20) > 1e-12 || side != 0 ||
			std::abs(skid - 0.2) > 1e-12) {
		return 1;
	}
	if (!physics_vehicle_project_combined_tire_impulses(0, 100, 10, 1, 1, 1,
				forward, side, skid) || forward != 0 || std::abs(side - 10) > 1e-12) {
		return 2;
	}
	if (!physics_vehicle_project_combined_tire_impulses(20, 10, 10, 1, 1, 1,
				forward, side, skid) || std::abs(forward - 20 / std::sqrt(2.0)) > 1e-12 ||
			std::abs(side - 10 / std::sqrt(2.0)) > 1e-12) {
		return 3;
	}
	if (!physics_vehicle_project_combined_tire_impulses(100, 6, 10, 1, 0, 1,
				forward, side, skid) || forward != 0 || side != 6 || skid != 0) {
		return 4;
	}
	if (physics_vehicle_project_combined_tire_impulses(
				std::numeric_limits<double>::infinity(), 0, 10, 1, 1, 1,
				forward, side, skid) || forward != 0 || side != 0 || skid != 0) {
		return 5;
	}
	std::puts("Cgame combined tire grip ellipse C++ header smoke OK");
	return 0;
}
