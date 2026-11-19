// Compile the ACTUAL native Cgame PBF kernel header in float32 AND float64.
// This file does not mock the algorithm; it only supplies a tiny Vector3
// stand-in when using -Itests/stress/physics_pbf_cpp_stubs before -I.
#include "servers/physics_pbf_3d.h"

#include <cmath>
#include <cstdio>

int main() {
	const double h = 0.4;
	const double center = PhysicsPBFKernel3D::poly6(0.0, h);
	if (!(center > 0.0) || !std::isfinite(center) ||
			PhysicsPBFKernel3D::poly6(h*h, h) != 0.0 ||
			PhysicsPBFKernel3D::poly6(-1.0, h) != 0.0) {
		return 1;
	}

	const Vector3 dx(real_t(0.10), real_t(0.05), real_t(-0.06));
	const Vector3 gradient = PhysicsPBFKernel3D::gradient(dx, h);
	if (!gradient.is_finite() || !(gradient.x < 0.0)) {
		return 2;
	}
	const double eps = 0.001;
	const double x = double(dx.x);
	const double y = double(dx.y);
	const double z = double(dx.z);
	const double d_plus = (x+eps)*(x+eps)+y*y+z*z;
	const double d_minus = (x-eps)*(x-eps)+y*y+z*z;
	const double numerical = (double(PhysicsPBFKernel3D::poly6(d_plus, h)) -
			double(PhysicsPBFKernel3D::poly6(d_minus, h))) / (2.0*eps);
	if (std::abs(gradient.x - numerical) > 0.03) {
		return 3;
	}

	double radial_integral = 0.0;
	for (int i = 0; i <= 512; ++i) {
		const double r = double(i)*h/512.0;
		const double value = 4.0*Math::PI*r*r*PhysicsPBFKernel3D::poly6(r*r, h);
		radial_integral += ((i==0 || i==512) ? 1 : (i & 1 ? 4 : 2)) * value;
	}
	radial_integral *= h/(3.0*512.0);
	if (std::abs(radial_integral-1.0) > 1e-4) {
		return 4;
	}

	if (!(PhysicsPBFKernel3D::artificial_pressure(0.,h,real_t(0.002)) < 0.0) ||
			PhysicsPBFKernel3D::artificial_pressure(h*h,h,real_t(0.002)) != 0.0) {
		return 5;
	}

	PhysicsPBFCell3D cells[5] = {};
	cells[0].x = -2; cells[0].y = -1; cells[0].index = 0;
	cells[1].x = -1; cells[1].y = 0; cells[1].z = 0; cells[1].index = 1;
	cells[2].x = -1; cells[2].y = 0; cells[2].z = 0; cells[2].index = 2;
	cells[3].x = 0; cells[3].y = 0; cells[3].z = 0; cells[3].index = 3;
	cells[4].x = 1; cells[4].y = 1; cells[4].z = 1; cells[4].index = 4;
	if (physics_pbf_find_cell_begin_3d(cells,5,-1,0,0) != 1 ||
			physics_pbf_find_cell_begin_3d(cells,5,0,0,0) != 3 ||
			physics_pbf_find_cell_begin_3d(cells,5,10,0,0) != 5) {
		return 6;
	}
	std::puts("Native PBF kernel header float/double compile smoke passed");
	return 0;
}
