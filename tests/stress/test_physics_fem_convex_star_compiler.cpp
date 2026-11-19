// Compile actual convex star FEM cook AND Neo-Hookean solver headers
// in float32 and float64, with the minimal stand-in core math containers.
// This is not a full Godot build; the native tests use the real classes.
#include "servers/physics_fem_convex_star.h"

#include <cmath>
#include <cstdio>
#include <initializer_list>

static bool approx(double x, double y, double tolerance = 1e-5) {
	return std::abs(x - y) < tolerance;
}

int main() {
	LocalVector<Vector3> positions;
	for (const Vector3 &vertex : {
			Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 1),
			Vector3(1, 1, 1), Vector3(0, 1, 1) }) {
		positions.push_back(vertex);
	}
	LocalVector<PhysicsFEMConvexFace> faces;
	for (const PhysicsFEMConvexFace &face : {
			PhysicsFEMConvexFace{0, 2, 1}, PhysicsFEMConvexFace{0, 3, 2},
			PhysicsFEMConvexFace{4, 5, 6}, PhysicsFEMConvexFace{4, 6, 7},
			PhysicsFEMConvexFace{0, 1, 5}, PhysicsFEMConvexFace{0, 5, 4},
			PhysicsFEMConvexFace{3, 7, 6}, PhysicsFEMConvexFace{3, 6, 2},
			PhysicsFEMConvexFace{0, 4, 7}, PhysicsFEMConvexFace{0, 7, 3},
			PhysicsFEMConvexFace{1, 2, 6}, PhysicsFEMConvexFace{1, 6, 5} }) {
		faces.push_back(face);
	}
	LocalVector<PhysicsFEMConvexTetra> cooked;
	if (!physics_fem_build_convex_star_tetrahedra(positions, faces, 1.0, cooked) ||
			cooked.size() != 6) {
		return 1;
	}
	double volume = 0;
	for (const PhysicsFEMConvexTetra &tetra : cooked) {
		volume += tetra.rest.volume;
	}
	if (!approx(volume, 1.0)) {
		return 2;
	}
	positions[6].z = real_t(1.25);
	uint32_t moved = 0;
	for (PhysicsFEMConvexTetra &tetra : cooked) {
		const real_t wb = tetra.b == 6 ? real_t(1) : real_t(0);
		const real_t wc = tetra.c == 6 ? real_t(1) : real_t(0);
		const real_t wd = tetra.d == 6 ? real_t(1) : real_t(0);
		if (wb + wc + wd == 0) {
			continue;
		}
		if (physics_fem_tetra_solve(
					positions[tetra.a], positions[tetra.b],
					positions[tetra.c], positions[tetra.d],
					0, wb, wc, wd, tetra.rest, .3, 0, tetra.lambda)) {
			moved++;
		}
	}
	if (moved < 2 || !(positions[6].z < real_t(1.25)) ||
			!positions[6].is_finite()) {
		return 3;
	}
	positions[6] = Vector3(real_t(.3), real_t(.3), real_t(.3));
	if (physics_fem_build_convex_star_tetrahedra(positions, faces, .5, cooked) ||
			cooked.size() != 6) {
		return 4;
	}
	std::puts("convex multi-tet FEM: mesh cooking and solver smoke OK");
	return 0;
}
