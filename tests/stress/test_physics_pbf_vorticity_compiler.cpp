// Real Cgame vorticity helper compiled under float32/float64 against
// isolated Vector3/Basis stubs; the physics algorithm is NOT reimplemented.
#include "servers/physics_pbf_vorticity_3d.h"

#include <cmath>
#include <cstdio>
#include <limits>

static bool approx(double a, double b, double tol=1e-5) {
	return std::abs(a-b)<tol;
}

int main() {
	const Vector3 grad(1,0,0);
	const Vector3 velocity_difference(0,2,0);
	const Vector3 curl = PhysicsPBFVorticity3D::curl_pair(velocity_difference,grad,0.5);
	if (!curl.is_finite() || !approx(curl.z,1) || !approx(curl.x,0) ||
			PhysicsPBFVorticity3D::curl_pair(velocity_difference,grad,0.0).length_squared()!=0) {
		return 1;
	}
	const Vector3 eta=PhysicsPBFVorticity3D::magnitude_gradient_pair(
			5.,3.,Vector3(2,-1,0),0.1);
	if (!approx(eta.x,0.4) || !approx(eta.y,-0.2)) {
		return 2;
	}
	const Vector3 increment=PhysicsPBFVorticity3D::velocity_increment(
			Vector3(1,0,0),Vector3(0,0,4),0.5,real_t(1./60.),1.0);
	if (!(increment.y<0) || !approx(increment.y,-2./60.,1e-4) ||
			!approx(increment.z,0) || !increment.is_finite()) {
		return 3;
	}
	const Vector3 limited=PhysicsPBFVorticity3D::velocity_increment(
			Vector3(1,0,0),Vector3(0,0,real_t(1e7)),
			real_t(5.),real_t(0.1),real_t(0.12));
	if (!(limited.y<0) || !approx(std::sqrt(limited.length_squared()),0.12,1e-5)) {
		return 4;
	}
	if (PhysicsPBFVorticity3D::velocity_increment(
			Vector3(),Vector3(0,0,5),0.5,0.016,0.12).length_squared()!=0 ||
			PhysicsPBFVorticity3D::velocity_increment(
			Vector3(1,0,0),Vector3(0,0,5),0.,0.016,0.12).length_squared()!=0 ||
			PhysicsPBFVorticity3D::velocity_increment(
			Vector3(1,0,0),Vector3(std::numeric_limits<real_t>::infinity(),0,0),
			0.5,0.016,0.12).length_squared()!=0) {
		return 5;
	}
	std::puts("Native PBF vorticity confinement float/double helper passed");
	return 0;
}
