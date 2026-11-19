// Standalone compile and runtime smoke of the REAL explicit tetra cooker.
// Build both float and double variants with minimal test-only core stubs.
#include "servers/physics_fem_explicit_tetra.h"
#include "servers/physics_fem_lumped_mass.h"

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
	// One interior node + eight surface vertices, with twelve conforming
	// volumetric elements. The interior particle has no surface triangle.
	LocalVector<Vector3> cube_vertices;
	for (const Vector3 &v : {
			Vector3(-1, -1, -1), Vector3(1, -1, -1),
			Vector3(1, 1, -1), Vector3(-1, 1, -1),
			Vector3(-1, -1, 1), Vector3(1, -1, 1),
			Vector3(1, 1, 1), Vector3(-1, 1, 1),
			Vector3(0, 0, 0) }) {
		cube_vertices.push_back(v);
	}
	LocalVector<PhysicsFEMConvexFace> cube_surface;
	LocalVector<uint32_t> cube_tet_indices;
	for (const PhysicsFEMConvexFace &face : {
			PhysicsFEMConvexFace{0, 2, 1}, PhysicsFEMConvexFace{0, 3, 2},
			PhysicsFEMConvexFace{4, 5, 6}, PhysicsFEMConvexFace{4, 6, 7},
			PhysicsFEMConvexFace{0, 1, 5}, PhysicsFEMConvexFace{0, 5, 4},
			PhysicsFEMConvexFace{3, 7, 6}, PhysicsFEMConvexFace{3, 6, 2},
			PhysicsFEMConvexFace{0, 4, 7}, PhysicsFEMConvexFace{0, 7, 3},
			PhysicsFEMConvexFace{1, 2, 6}, PhysicsFEMConvexFace{1, 6, 5} }) {
		cube_surface.push_back(face);
		cube_tet_indices.push_back(8);
		cube_tet_indices.push_back(face.a);
		cube_tet_indices.push_back(face.b);
		cube_tet_indices.push_back(face.c);
	}
	LocalVector<PhysicsFEMConvexTetra> cube_tets;
	if (!physics_fem_build_explicit_tetrahedra(
				cube_vertices, cube_surface, cube_tet_indices, 8.0, cube_tets) ||
			cube_tets.size() != 12) {
		return 6;
	}
	LocalVector<double> fractions;
	LocalVector<real_t> inverse_masses;
	if (!physics_fem_build_lumped_masses(
				cube_vertices.size(), cube_tets, real_t(12.0),
				fractions, inverse_masses) ||
			fractions.size() != 9 || !near(fractions[8], .25) ||
			!near(inverse_masses[8], 1.0 / 3.0)) {
		return 7;
	}
	cube_vertices[8] = Vector3(3, 3, 3);
	if (physics_fem_build_explicit_tetrahedra(
				cube_vertices, cube_surface, cube_tet_indices, 8.0, cube_tets) ||
			cube_tets.size() != 12) {
		return 8;
	}
	std::puts("explicit concave multi-tet FEM validation smoke OK");
	return 0;
}
