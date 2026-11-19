/**************************************************************************/
/*  physics_fem_convex_star.h                                             */
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
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
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

#include "servers/physics_fem_tetra_neo_hookean.h"

#include "core/templates/local_vector.h"

#include <algorithm>
#include <utility>

// Conservative CPU tetrahedralization for a CLOSED, consistently oriented,
// strictly convex triangulated SoftBody3D surface. Both this cooker AND
// GodotSoftBody3D validate oriented manifold topology independently.
//
// A fan from surface vertex 0 produces one tetrahedron per triangle not
// incident to that vertex. For convex bodies, tetra interiors are disjoint,
// apart from shared faces; coplanar source faces create zero-volume tets
// and are skipped. This does NOT handle concave/star-shaped meshes,
// holes, disconnected shells or arbitrary tetrahedral input.
//
// The convexity prepass is O(face_count * vertex_count), once at setup, and
// is bounded at 2048 vertices / 4096 triangles. The hot solver remains
// O(tetra_count) without dynamic allocations.
//
// LocalVector assignment is move-only on successful completion; failures
// leave the caller's existing output unchanged. Per-tet lambda persists
// only across solver iterations within a physics tick.
struct PhysicsFEMConvexFace {
	uint32_t a = 0;
	uint32_t b = 0;
	uint32_t c = 0;
};

struct PhysicsFEMConvexTetra {
	uint32_t a = 0;
	uint32_t b = 0;
	uint32_t c = 0;
	uint32_t d = 0;
	PhysicsFEMTetraRest rest;
	double lambda = 0.0;
	double plastic_volume_scale = 1.0; // Irreversible local rest-volume ratio (0.2..5), default intact.
	double plastic_deviatoric_strain = 0.0; // Accumulated tensorial isochoric plastic strain budget.
};

// The normal orientation is inferred from the already validated signed
// closed-shell volume. Face winding must agree with that sign.
_FORCE_INLINE_ bool physics_fem_build_convex_star_tetrahedra(
		const LocalVector<Vector3> &p_positions,
		const LocalVector<PhysicsFEMConvexFace> &p_faces,
		double p_closed_signed_volume,
		LocalVector<PhysicsFEMConvexTetra> &r_tetrahedra) {
	if (p_positions.size() < 4 || p_positions.size() > 2048 ||
			p_faces.size() < 4 || p_faces.size() > 4096 ||
			!Math::is_finite(p_closed_signed_volume) ||
			p_closed_signed_volume == 0.0) {
		return false;
	}

	const Vector3 &origin = p_positions[0];
	if (!origin.is_finite()) {
		return false;
	}
	double extent = 0.0;
	for (const Vector3 &p : p_positions) {
		if (!p.is_finite()) {
			return false;
		}
		extent = MAX(extent, Math::abs(double(p.x) - double(origin.x)));
		extent = MAX(extent, Math::abs(double(p.y) - double(origin.y)));
		extent = MAX(extent, Math::abs(double(p.z) - double(origin.z)));
	}
	if (!(extent > 0.0) || !Math::is_finite(extent)) {
		return false;
	}

	// Independently reject open edges, same-direction windings and
	// non-manifold shared edges. Sort compact edge keys rather than using
	// a per-face hash table; this work happens once at FEM setup.
	struct FEMOrientedEdge {
		uint32_t lo = 0;
		uint32_t hi = 0;
		uint8_t direction = 0;
	};
	LocalVector<FEMOrientedEdge> oriented_edges;
	oriented_edges.reserve(p_faces.size() * 3);
	for (const PhysicsFEMConvexFace &face : p_faces) {
		if (face.a >= p_positions.size() || face.b >= p_positions.size() ||
				face.c >= p_positions.size() || face.a == face.b ||
				face.b == face.c || face.c == face.a) {
			return false;
		}
		const uint32_t ids[3] = { face.a, face.b, face.c };
		for (int j = 0; j < 3; ++j) {
			const uint32_t a = ids[j];
			const uint32_t b = ids[(j + 1) % 3];
			FEMOrientedEdge edge;
			edge.lo = a < b ? a : b;
			edge.hi = a < b ? b : a;
			edge.direction = a < b ? uint8_t(1) : uint8_t(2);
			oriented_edges.push_back(edge);
		}
	}
	std::sort(oriented_edges.ptr(), oriented_edges.ptr() + oriented_edges.size(),
			[](const FEMOrientedEdge &a, const FEMOrientedEdge &b) {
				if (a.lo != b.lo) {
					return a.lo < b.lo;
				}
				if (a.hi != b.hi) {
					return a.hi < b.hi;
				}
				return a.direction < b.direction;
			});
	for (uint32_t i = 0; i < oriented_edges.size(); i += 2) {
		if (i + 1 >= oriented_edges.size()) {
			return false;
		}
		const FEMOrientedEdge &first = oriented_edges[i];
		const FEMOrientedEdge &second = oriented_edges[i + 1];
		if (first.lo != second.lo || first.hi != second.hi ||
				first.direction == second.direction ||
				(i + 2 < oriented_edges.size() &&
						oriented_edges[i + 2].lo == first.lo &&
						oriented_edges[i + 2].hi == first.hi)) {
			return false;
		}
	}

	// Strict convexity: every other point must be inside the halfspace
	// of EVERY surface triangle. Use wide relative coordinates to prevent
	// large world translations from overflowing float32 cross products.
	const double orientation = p_closed_signed_volume > 0.0 ? 1.0 : -1.0;
	const double halfspace_tolerance = extent * 1e-8;
	for (const PhysicsFEMConvexFace &face : p_faces) {
		if (face.a >= p_positions.size() || face.b >= p_positions.size() ||
				face.c >= p_positions.size() || face.a == face.b ||
				face.b == face.c || face.c == face.a) {
			return false;
		}
		const Vector3 &a = p_positions[face.a];
		const Vector3 &b = p_positions[face.b];
		const Vector3 &c = p_positions[face.c];
		const double ab[3] = { double(b.x) - double(a.x), double(b.y) - double(a.y), double(b.z) - double(a.z) };
		const double ac[3] = { double(c.x) - double(a.x), double(c.y) - double(a.y), double(c.z) - double(a.z) };
		const double normal[3] = {
			ab[1] * ac[2] - ab[2] * ac[1],
			ab[2] * ac[0] - ab[0] * ac[2],
			ab[0] * ac[1] - ab[1] * ac[0]
		};
		const double ab_sq = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2];
		const double ac_sq = ac[0] * ac[0] + ac[1] * ac[1] + ac[2] * ac[2];
		const double normal_sq = normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2];
		if (!(ab_sq > 0.0) || !(ac_sq > 0.0) ||
				!Math::is_finite(normal_sq) ||
				!(normal_sq > ab_sq * ac_sq * 1e-16)) {
			return false;
		}
		const double tolerated_dot = Math::sqrt(normal_sq) * halfspace_tolerance;
		for (const Vector3 &p : p_positions) {
			const double px = double(p.x) - double(a.x);
			const double py = double(p.y) - double(a.y);
			const double pz = double(p.z) - double(a.z);
			const double side = orientation * (normal[0] * px + normal[1] * py + normal[2] * pz);
			if (!Math::is_finite(side) || side > tolerated_dot) {
				return false;
			}
		}
	}

	LocalVector<PhysicsFEMConvexTetra> cooked;
	cooked.reserve(p_faces.size());
	double cooked_volume = 0.0;
	for (const PhysicsFEMConvexFace &face : p_faces) {
		if (face.a == 0 || face.b == 0 || face.c == 0) {
			continue;
		}
		PhysicsFEMConvexTetra tetra;
		tetra.a = 0;
		tetra.b = face.a;
		tetra.c = face.b;
		tetra.d = face.c;
		if (!physics_fem_tetra_make_rest(
					origin, p_positions[tetra.b], p_positions[tetra.c],
					p_positions[tetra.d], tetra.rest)) {
			// Convex hull faces coplanar with the chosen apex generate
			// zero-volume tetrahedra; only skip geometrically negligible
			// ones. A corrupted noncoplanar element must reject the mesh.
			const Vector3 &b = p_positions[tetra.b];
			const Vector3 &c = p_positions[tetra.c];
			const Vector3 &d = p_positions[tetra.d];
			const double ux = double(b.x) - double(origin.x);
			const double uy = double(b.y) - double(origin.y);
			const double uz = double(b.z) - double(origin.z);
			const double vx = double(c.x) - double(origin.x);
			const double vy = double(c.y) - double(origin.y);
			const double vz = double(c.z) - double(origin.z);
			const double wx = double(d.x) - double(origin.x);
			const double wy = double(d.y) - double(origin.y);
			const double wz = double(d.z) - double(origin.z);
			const double determinant = ux * (vy * wz - vz * wy) +
					uy * (vz * wx - vx * wz) + uz * (vx * wy - vy * wx);
			const double scale = Math::sqrt((ux * ux + uy * uy + uz * uz) *
					(vx * vx + vy * vy + vz * vz) *
					(wx * wx + wy * wy + wz * wz));
			if (!(scale > 0.0) || !Math::is_finite(scale) ||
					!Math::is_finite(determinant) ||
					Math::abs(determinant) > scale * 1e-10) {
				return false;
			}
			continue;
		}
		if (tetra.rest.signed_det * orientation <= 0.0) {
			return false;
		}
		cooked_volume += tetra.rest.volume;
		if (!Math::is_finite(cooked_volume)) {
			return false;
		}
		cooked.push_back(tetra);
	}
	const double required_volume = Math::abs(p_closed_signed_volume);
	if (cooked.is_empty() || !(required_volume > 0.0) ||
			Math::abs(cooked_volume - required_volume) > required_volume * 1e-5) {
		return false;
	}
	r_tetrahedra = std::move(cooked);
	return true;
}
