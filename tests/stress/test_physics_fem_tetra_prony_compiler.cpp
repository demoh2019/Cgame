// Real generalized Maxwell/Prony FEM production header compiler and smoke.
#include "servers/physics_fem_tetra_prony.h"

#include <cmath>
#include <cstdio>

int main() {
	PhysicsFEMTetraRest rest;
	const Vector3 x[4] = { Vector3(), Vector3(real_t(1.5), 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1) };
	if (!physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest)) {
		return 1;
	}
	PhysicsFEMTetraSLSState base;
	PhysicsFEMTetraPronyState state;
	const PhysicsFEMTetraSLSState *arms[3] = { &base, &state.fast, &state.slow };
	const double comp[3] = { 0.02, 0.01, 0.04 };
	double initial_energy, relaxed_energy;
	Vector3 ga, gb, gc, gd;
	if (!physics_fem_tetra_prony_energy_gradient(x[0], x[1], x[2], x[3],
			rest, arms, comp, 0.3, initial_energy, ga, gb, gc, gd) ||
			!(initial_energy > 0.0)) {
		return 2;
	}
	if (!physics_fem_tetra_prony_relax(x, rest,
			true, 0.03, true, 2.0, 0.05, state)) {
		return 3;
	}
	if (!(state.fast.relaxing_strain[0][0] >
			state.slow.relaxing_strain[0][0])) {
		return 4;
	}
	if (!physics_fem_tetra_prony_energy_gradient(x[0], x[1], x[2], x[3],
			rest, arms, comp, 0.3, relaxed_energy, ga, gb, gc, gd) ||
			!(relaxed_energy > 0.0 && relaxed_energy < initial_energy)) {
		return 5;
	}
	Vector3 a=x[0], b=x[1], c=x[2], d=x[3];
	if (!physics_fem_tetra_prony_solve(a,b,c,d,0,1,0,0,
			rest,arms,comp,0.3,0.02,state.lambda) || !(b.x < x[1].x) ||
			state.lambda == 0.0) {
		return 6;
	}
	// A single Prony arm must exactly match the legacy one-arm SLS XPBD
	// constraint when the normalized energy is scaled by its compliance.
	const PhysicsFEMTetraSLSState *only[3] = { &base, nullptr, nullptr };
	const double one_comp[3] = { 0.02, 0.0, 0.0 };
	Vector3 sa=x[0], sb=x[1], sc=x[2], sd=x[3];
	Vector3 pa=x[0], pb=x[1], pc=x[2], pd=x[3];
	double sl=0, pl=0;
	const bool old_ok = physics_fem_tetra_sls_solve(sa,sb,sc,sd,0,1,0,0,
			rest,base,0.3,one_comp[0]/(0.02*0.02),sl);
	const bool new_ok = physics_fem_tetra_prony_solve(pa,pb,pc,pd,0,1,0,0,
			rest,only,one_comp,0.3,0.02,pl);
	if (!old_ok || !new_ok || std::abs(double(sb.x)-double(pb.x)) > 1e-5) {
		return 7;
	}
	std::puts("Prony generalized Maxwell FEM float/double smoke OK");
	return 0;
}
