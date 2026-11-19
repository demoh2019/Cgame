// Compile REAL Cgame velocity-divergence helper in float32 and float64.
// Only core/math/vector3.h is an isolated test stub; algorithm is native.
#include "servers/physics_pbf_divergence_3d.h"

#include <cmath>
#include <cstdio>
#include <limits>

static bool approximately(double a, double b, double tol=1e-5) {
	return std::abs(a-b)<tol;
}

int main() {
	const Vector3 gradient(2,0,0);
	const real_t incoming = PhysicsPBFDivergence3D::density_rate_pair(
			Vector3(1,0,0),Vector3(-1,0,0),gradient,6.0);
	const real_t outgoing = PhysicsPBFDivergence3D::density_rate_pair(
			Vector3(-1,0,0),Vector3(1,0,0),gradient,6.0);
	if (!approximately(incoming,24.0) || !approximately(outgoing,-24.0) ||
			!approximately(PhysicsPBFDivergence3D::compressive_rate_fraction(incoming,1000.),.024) ||
			PhysicsPBFDivergence3D::compressive_rate_fraction(outgoing,1000.)!=0.0) {
		return 1;
	}
	const double grad_sq = 2.0*std::pow(2.0*6.0/1000.0,2);
	const real_t lambda = PhysicsPBFDivergence3D::lagrange_multiplier(.024,grad_sq);
	if (!(lambda<0.0) || !std::isfinite(lambda)) {
		return 2;
	}
	const Vector3 left=PhysicsPBFDivergence3D::pair_velocity_correction(
			gradient,lambda,lambda,real_t(.006));
	const Vector3 right=PhysicsPBFDivergence3D::pair_velocity_correction(
			-gradient,lambda,lambda,real_t(.006));
	if (!(left.x<0 && right.x>0) || !approximately(double(left.x+right.x),0.0)) {
		return 3;
	}
	const Vector3 capped=PhysicsPBFDivergence3D::bounded_correction(
			Vector3(100,-50,25),real_t(.8),real_t(.12));
	if (!capped.is_finite() ||
			!approximately(std::sqrt(capped.length_squared()),.12,2e-5)) {
		return 4;
	}
	if (PhysicsPBFDivergence3D::lagrange_multiplier(0.0,1.0)!=0.0 ||
			PhysicsPBFDivergence3D::lagrange_multiplier(1.0,-1.0)!=0.0 ||
			PhysicsPBFDivergence3D::bounded_correction(
					Vector3(),real_t(.8),real_t(.12)).length_squared()!=0.0) {
		return 5;
	}
	const real_t inf=std::numeric_limits<real_t>::infinity();
	if (PhysicsPBFDivergence3D::density_rate_pair(
				Vector3(inf,0,0),Vector3(),gradient,6.0)!=0.0 ||
			PhysicsPBFDivergence3D::bounded_correction(
					Vector3(inf,0,0),real_t(.8),real_t(.12)).length_squared()!=0.0) {
		return 6;
	}
	std::puts("Native PBF velocity-divergence kernel float/double smoke passed");
	return 0;
}
