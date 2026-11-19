// Compile the ACTUAL native impulse solver (not a duplicate) with float and
// double Godot configurations. Only Vector3/Basis are isolated stubs.
#include "servers/physics_pbf_rigid_coupling_3d.h"

#include <cmath>
#include <cstdio>
#include <limits>

static bool approximately(double a, double b, double tolerance=2e-5) {
	return std::abs(a-b) <= tolerance;
}

int main() {
	PhysicsPBFRigidContactResult3D result;
	if (!physics_pbf_rigid_contact_solve_3d(
				Vector3(0,-3,0),2.0,Vector3(),0.5,Basis(),
				Vector3(),Vector3(0,1,0),1.0,100.0,result)) {
		return 1;
	}
	if (!approximately(result.impulse_magnitude,6.0) ||
			!approximately(result.particle_velocity.y,0.0) ||
			!approximately(result.body_impulse.y,-6.0)) {
		return 2;
	}
	const Vector3 lever(1,0,0);
	const Basis inverse_inertia = Basis::from_scale(Vector3(1,1,0.25));
	if (!physics_pbf_rigid_contact_solve_3d(
				Vector3(0,-4,0),2.0,Vector3(),0.25,inverse_inertia,
				lever,Vector3(0,1,0),0.,100.,result) ||
			!approximately(result.impulse_magnitude,4.0) ||
			!(lever.cross(result.body_impulse).z < 0.0)) {
		return 3;
	}
	if (!physics_pbf_rigid_contact_solve_3d(
				Vector3(0,-100,0),5.0,Vector3(),0.01,Basis(),
				Vector3(),Vector3(0,1,0),1.,7.,result) ||
			!approximately(result.impulse_magnitude,7.0)) {
		return 4;
	}
	if (physics_pbf_rigid_contact_solve_3d(
				Vector3(0,1,0),1.,Vector3(),1.,Basis(),
				Vector3(),Vector3(0,1,0),.2,100.,result) ||
			result.impulse_magnitude != 0.0) {
		return 5;
	}
	if (physics_pbf_rigid_contact_solve_3d(
				Vector3(0,-1,0),1.,Vector3(),1.,Basis(),
				Vector3(),Vector3(0,1,0),2.0,100.,result) ||
			result.impulse_magnitude != 0.0) {
		return 6;
	}
	if (physics_pbf_rigid_contact_solve_3d(
				Vector3(0,-1,0),1.,Vector3(),1.,Basis(),
				Vector3(std::numeric_limits<real_t>::infinity(),0,0),
				Vector3(0,1,0),0.2,100.,result)) {
		return 7;
	}
	std::puts("Native PBF paired rigid-body impulse float/double smoke passed");
	return 0;
}
