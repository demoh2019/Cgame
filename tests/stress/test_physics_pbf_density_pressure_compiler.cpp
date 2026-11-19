// Compile the ACTUAL native Cgame predictive density-pressure helper
// under float32 and float64 with only a minimal Vector3 math stub.
#include "servers/physics_pbf_density_pressure_3d.h"

#include <cmath>
#include <cstdio>
#include <limits>

static bool near(double a,double b,double tolerance=2e-5) {
	return std::abs(a-b) <= tolerance;
}

int main() {
	const double delta=1.0/60.0;
	const real_t predicted=PhysicsPBFDensityPressure3D::predicted_density(
			1020.,180.,delta);
	if (!near(predicted,1023.) ||
			!near(PhysicsPBFDensityPressure3D::positive_density_error(
					predicted,1000.),.023) ||
			!near(PhysicsPBFDensityPressure3D::pressure_rate_constraint(
					predicted,1000.,delta),1.38,1e-4)) {
		return 1;
	}
	if (PhysicsPBFDensityPressure3D::positive_density_error(990.,1000.)!=0 ||
			PhysicsPBFDensityPressure3D::pressure_rate_constraint(990.,1000.,delta)!=0 ||
			PhysicsPBFDensityPressure3D::predicted_density(1000.,-1000.,delta)>1000.) {
		return 2;
	}
	if (PhysicsPBFDensityPressure3D::predicted_density(1000.,0.,0.)!=0 ||
			PhysicsPBFDensityPressure3D::pressure_rate_constraint(1020.,1000.,0.)!=0 ||
			PhysicsPBFDensityPressure3D::positive_density_error(
					1000.,0.)!=0) {
		return 3;
	}
	const real_t inf=std::numeric_limits<real_t>::infinity();
	if (PhysicsPBFDensityPressure3D::predicted_density(1000.,inf,delta)!=0 ||
			PhysicsPBFDensityPressure3D::positive_density_error(inf,1000.)!=0 ||
			PhysicsPBFDensityPressure3D::pressure_rate_constraint(
					1200.,inf,delta)!=0) {
		return 4;
	}
	std::puts("Cgame native PBF predictive density pressure float/double passed");
	return 0;
}
