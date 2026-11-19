// Standalone compile and runtime smoke of the REAL explicit tetra cooker.
// Build both float and double variants with minimal test-only core stubs.
#include "servers/physics_fem_explicit_tetra.h"

#include <cmath>
#include <cstdio>
#include <initializer_list>
#include <utility>

static bool near(double a, double b) {
	return std::abs(a - b) < 1e-5;
}

int main() {
	LocalVector<Vector3> positions;
	for (const Vector3 &vertex : {
			Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
			Vector3(0, 0, 1), Vector3(real_t(.6), real_t(.8), real_t(-.25)) }) {
		positions.push_back(vertex);
	}
	LocalVector<PhysicsFEMConvexFace> shell;
	for (const PhysicsFEMConvexFace &face : {
			PhysicsFEMConvexFace{1, 2, 3},
			PhysicsFEMConvexFace{0, 3, 2},
			PhysicsFEMConvexFace{0, 1, 3},
			PhysicsFEMConvexFace{2, 1, 4},
			PhysicsFEMConvexFace{0, 4, 1},
			PhysicsFEMConvexFace{0, 2, 4} }) {
		shell.push_back(face);
	}
	LocalVector<uint32_t> indices;
	for (uint32_t idx : {0u,1u,2u,3u,0u,2u,1u,4u}) {
		indices.push_back(idx);
	}
	LocalVector<PhysicsFEMConvexTetra> cooked;
	const double total_volume = 1.25 / 6.0;
	if (!physics_fem_build_explicit_tetrahedra(
				positions, shell, indices, total_volume, cooked) ||
			cooked.size() != 2 || !near(
					cooked[0].rest.volume + cooked[1].rest.volume, total_volume)) {
		return 1;
	}
	std::swap(indices[1], indices[2]);
	if (!physics_fem_build_explicit_tetrahedra(
				positions, shell, indices, total_volume, cooked) ||
			cooked[0].rest.signed_det <= 0) {
		return 2;
	}
	std::swap(shell[0].b, shell[0].c);
	if (physics_fem_build_explicit_tetrahedra(
				positions, shell, indices, total_volume, cooked) ||
			cooked.size() != 2) {
		return 3;
	}
	std::swap(shell[0].b, shell[0].c);
	for (PhysicsFEMConvexFace &face : shell) {
		std::swap(face.b, face.c);
	}
	if (!physics_fem_build_explicit_tetrahedra(
				positions, shell, indices, -total_volume, cooked)) {
		return 4;
	}
	if (physics_fem_build_explicit_tetrahedra(
				positions, shell, indices, -0.5, cooked)) {
		return 5;
	}
	std::puts("explicit concave multi-tet FEM validation smoke OK");
	return 0;
}
