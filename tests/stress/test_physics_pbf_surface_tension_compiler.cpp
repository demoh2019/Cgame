// Compile the ACTUAL Godot Cgame surface-tension helper for float32
// and float64. Minimal vector stubs provide types, NOT a copied solver.
#include "servers/physics_pbf_surface_tension_3d.h"

#include <cmath>
#include <cstdio>
#include <limits>

static bool approximately(double a, double b, double tolerance=2e-5) {
	return std::abs(a-b) <= tolerance;
}

int main() {
	const real_t h = 0.42;
	if (PhysicsPBFSurfaceTension3D::cohesion_kernel(0.0,h)!=0.0 ||
			PhysicsPBFSurfaceTension3D::cohesion_kernel(h,h)!=0.0 ||
			!(PhysicsPBFSurfaceTension3D::cohesion_kernel(0.02,h)<0.0) ||
			!(PhysicsPBFSurfaceTension3D::cohesion_kernel(0.30,h)>0.0)) {
		return 1;
	}
	const Vector3 left(-0.29,0,0);
	const Vector3 dv = PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			left,Vector3(),Vector3(),1000.,1000.,1000.,
			6.,h,0.15,0.,real_t(1./60.),0.02);
	const Vector3 reverse = PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			-left,Vector3(),Vector3(),1000.,1000.,1000.,
			6.,h,0.15,0.,real_t(1./60.),0.02);
	if (!(dv.x>0.0) || !approximately(double(dv.x+reverse.x),0.0) ||
			!approximately(double(dv.y),0.0)) {
		return 2;
	}
	const Vector3 curvature = PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			Vector3(.2,0,0), Vector3(0,1,0),Vector3(0,-1,0),
			1000.,1000.,1000.,6.,h,0.,.5,real_t(1./60.),.05);
	if (!(curvature.y<0.0) || !approximately(double(curvature.x),0.0)) {
		return 3;
	}
	const Vector3 capped = PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			left,Vector3(),Vector3(),50.,50.,1000.,
			100.,h,2.,0.,real_t(.1),real_t(.005));
	if (!capped.is_finite() ||
			!approximately(std::sqrt(double(capped.length_squared())),.005)) {
		return 4;
	}
	const real_t infinity=std::numeric_limits<real_t>::infinity();
	const Vector3 invalid = PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			left,Vector3(),Vector3(),infinity,1000.,1000.,
			6.,h,.1,.1,real_t(.016),real_t(.005));
	if (invalid.length_squared()!=0.0 ||
			PhysicsPBFSurfaceTension3D::cohesion_kernel(0.2,infinity)!=0.0 ||
			PhysicsPBFSurfaceTension3D::color_normal_pair(
					Vector3(infinity,0,0),.01,h).length_squared()!=0.0) {
		return 5;
	}
	std::puts("Native PBF SPH surface tension float/double helper passed");
	return 0;
}
