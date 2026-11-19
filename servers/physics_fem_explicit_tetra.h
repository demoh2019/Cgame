/**************************************************************************/
/*  physics_fem_explicit_tetra.h                                         */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "servers/physics_fem_convex_star.h"

#include <algorithm>
#include <utility>

// Explicit tetrahedral connectivity for concave/heterogeneous closed shells.
// These vertices belong to the SAME welded surface-particle array as the
// surrounding SoftBody3D faces. This is NOT yet a separate simulation mesh,
// and unused/interior-only vertices are intentionally rejected.
//
// Validation:
//  * each element has 4 distinct in-range nodes and positive rest volume;
//  * every element face occurs once (boundary) or twice with opposite winding
//    (internal), never three or more times;
//  * boundary faces match the exact oriented *surface triangles*;
//  * all vertices participate and sum(tet volumes) matches closed volume.
//
// The solver receives positively oriented tetrahedra, even when input tet
// corners are in negative order. The surface can be entirely reversed.
// No auto fallback to convex cooking on malformed explicit connectivity.
// Rejected inputs leave r_tetrahedra UNCHANGED. O((T+F) log(T+F)) setup;
// the physics-tick solve itself remains linear in the tetra count.
//
// These checks do not prove the absence of geometric self-intersections or
// every possible pathological non-conforming tetra intersection. Importers
// should still supply an overlap-free conforming tetrahedral mesh.
struct PhysicsFEMExplicitFace {
	uint32_t a = 0;
	uint32_t b = 0;
	uint32_t c = 0;
	uint32_t tet = 0;
	bool odd = false;
};

// Map a directed triangle to a sorted vertex triple and parity. Cyclic
// permutations keep parity; reversing a face toggles parity.
_FORCE_INLINE_ PhysicsFEMExplicitFace physics_fem_explicit_face(
		uint32_t p_a, uint32_t p_b, uint32_t p_c, uint32_t p_tet) {
	PhysicsFEMExplicitFace face;
	face.a = p_a;
	face.b = p_b;
	face.c = p_c;
	face.tet = p_tet;
	if (face.a > face.b) {
		std::swap(face.a, face.b);
		face.odd = !face.odd;
	}
	if (face.b > face.c) {
		std::swap(face.b, face.c);
		face.odd = !face.odd;
	}
	if (face.a > face.b) {
		std::swap(face.a, face.b);
		face.odd = !face.odd;
	}
	return face;
}

struct PhysicsFEMExplicitFaceLess {
	_FORCE_INLINE_ bool operator()(const PhysicsFEMExplicitFace &p_a,
			const PhysicsFEMExplicitFace &p_b) const {
		if (p_a.a != p_b.a) {
			return p_a.a < p_b.a;
		}
		if (p_a.b != p_b.b) {
			return p_a.b < p_b.b;
		}
		if (p_a.c != p_b.c) {
			return p_a.c < p_b.c;
		}
		return p_a.tet < p_b.tet;
	}
};

_FORCE_INLINE_ bool physics_fem_explicit_face_same(
		const PhysicsFEMExplicitFace &p_a,
		const PhysicsFEMExplicitFace &p_b) {
	return p_a.a == p_b.a && p_a.b == p_b.b && p_a.c == p_b.c;
}

_FORCE_INLINE_ bool physics_fem_build_explicit_tetrahedra(
		const LocalVector<Vector3> &p_positions,
		const LocalVector<PhysicsFEMConvexFace> &p_surface,
		const LocalVector<uint32_t> &p_indices,
		double p_closed_signed_volume,
		LocalVector<PhysicsFEMConvexTetra> &r_tetrahedra) {
	if (p_positions.size() < 4 || p_positions.size() > 2048 ||
			p_surface.size() < 4 || p_surface.size() > 4096 ||
			p_indices.is_empty() || p_indices.size() % 4 != 0 ||
			p_indices.size() / 4 > 4096 ||
			!Math::is_finite(p_closed_signed_volume) ||
			p_closed_signed_volume == 0.0) {
		return false;
	}
	for (const Vector3 &p : p_positions) {
		if (!p.is_finite()) {
			return false;
		}
	}
	LocalVector<PhysicsFEMExplicitFace> surface;
	surface.reserve(p_surface.size());
	for (const PhysicsFEMConvexFace &face : p_surface) {
		if (face.a >= p_positions.size() || face.b >= p_positions.size() ||
				face.c >= p_positions.size() ||
				face.a == face.b || face.a == face.c || face.b == face.c) {
			return false;
		}
		PhysicsFEMExplicitFace oriented = physics_fem_explicit_face(face.a, face.b, face.c, 0);
		if (p_closed_signed_volume < 0.0) {
			oriented.odd = !oriented.odd;
		}
		surface.push_back(oriented);
	}
	std::sort(surface.ptr(), surface.ptr() + surface.size(), PhysicsFEMExplicitFaceLess());
	for (uint32_t i = 1; i < surface.size(); ++i) {
		if (physics_fem_explicit_face_same(surface[i - 1], surface[i])) {
			return false;
		}
	}

	LocalVector<PhysicsFEMConvexTetra> cooked;
	cooked.reserve(p_indices.size() / 4);
	LocalVector<PhysicsFEMExplicitFace> tet_faces;
	tet_faces.reserve(p_indices.size()); // 4 faces per tetrahedron.
	LocalVector<uint8_t> used_vertices;
	used_vertices.resize(p_positions.size());
	for (uint8_t &used : used_vertices) {
		used = 0;
	}
	double total_volume = 0.0;
	for (uint32_t base = 0; base < p_indices.size(); base += 4) {
		PhysicsFEMConvexTetra tet;
		tet.a = p_indices[base + 0];
		tet.b = p_indices[base + 1];
		tet.c = p_indices[base + 2];
		tet.d = p_indices[base + 3];
		const uint32_t v[4] = { tet.a, tet.b, tet.c, tet.d };
		for (int i = 0; i < 4; ++i) {
			if (v[i] >= p_positions.size()) {
				return false;
			}
			for (int j = i + 1; j < 4; ++j) {
				if (v[i] == v[j]) {
					return false;
				}
			}
			used_vertices[v[i]] = 1;
		}
		if (!physics_fem_tetra_make_rest(
					p_positions[tet.a], p_positions[tet.b],
					p_positions[tet.c], p_positions[tet.d], tet.rest)) {
			return false;
		}
		if (tet.rest.signed_det < 0.0) {
			std::swap(tet.b, tet.c);
			if (!physics_fem_tetra_make_rest(
						p_positions[tet.a], p_positions[tet.b],
						p_positions[tet.c], p_positions[tet.d], tet.rest)) {
				return false;
			}
		}
		total_volume += tet.rest.volume;
		if (!Math::is_finite(total_volume)) {
			return false;
		}

		// Outward-oriented tet faces for signed det(a,b,c,d)>0.
		const uint32_t id = cooked.size();
		tet_faces.push_back(physics_fem_explicit_face(tet.b, tet.c, tet.d, id));
		tet_faces.push_back(physics_fem_explicit_face(tet.a, tet.d, tet.c, id));
		tet_faces.push_back(physics_fem_explicit_face(tet.a, tet.b, tet.d, id));
		tet_faces.push_back(physics_fem_explicit_face(tet.a, tet.c, tet.b, id));
		cooked.push_back(tet);
	}
	for (uint8_t used : used_vertices) {
		if (!used) {
			return false;
		}
	}
	const double closed_volume = Math::abs(p_closed_signed_volume);
	if (!(closed_volume > 0.0) ||
			Math::abs(total_volume - closed_volume) > closed_volume * 1e-5) {
		return false;
	}

	std::sort(tet_faces.ptr(), tet_faces.ptr() + tet_faces.size(), PhysicsFEMExplicitFaceLess());
	uint32_t shell_face = 0;
	for (uint32_t i = 0; i < tet_faces.size();) {
		const PhysicsFEMExplicitFace &first = tet_faces[i];
		const bool pair = i + 1 < tet_faces.size() &&
				physics_fem_explicit_face_same(first, tet_faces[i + 1]);
		if (pair) {
			const PhysicsFEMExplicitFace &second = tet_faces[i + 1];
			if (first.tet == second.tet || first.odd == second.odd ||
					(i + 2 < tet_faces.size() &&
							physics_fem_explicit_face_same(first, tet_faces[i + 2]))) {
				return false;
			}
			i += 2;
			continue;
		}
		// External tet triangles must equal the exact surface mesh.
		if (shell_face >= surface.size() ||
				!physics_fem_explicit_face_same(first, surface[shell_face]) ||
				first.odd != surface[shell_face].odd) {
			return false;
		}
		++shell_face;
		++i;
	}
	if (shell_face != surface.size()) {
		return false;
	}
	r_tetrahedra = std::move(cooked);
	return true;
}
