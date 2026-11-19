/**************************************************************************/
/*  physics_fem_convex_tetra_fan.h                                        */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "servers/physics_fem_tetra_neo_hookean.h"

#include <cstdint>

// Preprocessor for an EXACT, convex, closed, consistently wound triangle
// surface. No extra interior nodes are invented: choose surface vertex 0 as a
// fan apex, then form volume tets against every boundary triangle that does
// not contain the apex or lie in its plane. A convex polytope is the union
// of these tets, with no overlaps and shared physical vertices.
//
// GodotSoftBody3D verifies closed 2-manifold topology BEFORE calling this
// function. This helper checks geometry (and cover volume), but deliberately
// does not re-run the mesh-edge manifold validator. Nonconvex meshes, holes,
// nonmanifold surfaces and meshes exceeding conservative setup limits need
// a separate tetrahedral mesher, not a guessed surface-to-centroid fan.
//
// All geometry math is double; the solver's Neo-Hookean element is reused.
// No heap allocations or data-dependent recursion occur here.
// r_count is unchanged on failure; output entries are scratch until true.
struct PhysicsFEMSurfaceTriangle {
	uint32_t a = 0;
	uint32_t b = 0;
	uint32_t c = 0;
};

struct PhysicsFEMConvexTetra {
	uint32_t nodes[4] = {};
	PhysicsFEMTetraRest rest;
	double lambda = 0.0;
};

_FORCE_INLINE_ double physics_fem_convex_signed_face_volume(
		const Vector3 &p_origin, const Vector3 &p_a,
		const Vector3 &p_b, const Vector3 &p_c) {
	const double ax = double(p_a.x) - double(p_origin.x);
	const double ay = double(p_a.y) - double(p_origin.y);
	const double az = double(p_a.z) - double(p_origin.z);
	const double bx = double(p_b.x) - double(p_origin.x);
	const double by = double(p_b.y) - double(p_origin.y);
	const double bz = double(p_b.z) - double(p_origin.z);
	const double cx = double(p_c.x) - double(p_origin.x);
	const double cy = double(p_c.y) - double(p_origin.y);
	const double cz = double(p_c.z) - double(p_origin.z);
	return (ax * (by * cz - bz * cy) +
			ay * (bz * cx - bx * cz) +
			az * (bx * cy - by * cx)) / 6.0;
}

_FORCE_INLINE_ bool physics_fem_build_convex_tetra_fan(
		const Vector3 *p_vertices, uint32_t p_vertex_count,
		const PhysicsFEMSurfaceTriangle *p_faces, uint32_t p_face_count,
		PhysicsFEMConvexTetra *r_elements, uint32_t p_capacity,
		uint32_t &r_count) {
	// O(V*F) half-space validation at rest, not in the solver loop.
	// Bound it to avoid expensive project import on huge surface meshes.
	if (!p_vertices || !p_faces || !r_elements ||
			p_vertex_count < 4 || p_vertex_count > 1024 ||
			p_face_count < 4 || p_face_count > 2048 ||
			p_capacity < p_face_count) {
		return false;
	}
	const Vector3 &origin = p_vertices[0];
	if (!origin.is_finite()) {
		return false;
	}
	double scale = 0.0;
	for (uint32_t v = 0; v < p_vertex_count; ++v) {
		const Vector3 &position = p_vertices[v];
		if (!position.is_finite()) {
			return false;
		}
		const double x = Math::abs(double(position.x) - double(origin.x));
		const double y = Math::abs(double(position.y) - double(origin.y));
		const double z = Math::abs(double(position.z) - double(origin.z));
		scale = MAX(scale, MAX(x, MAX(y, z)));
	}
	if (!(scale > 0.0) || !Math::is_finite(scale)) {
		return false;
	}
	const double cube = scale * scale * scale;
	if (!(cube > 0.0) || !Math::is_finite(cube)) {
		return false;
	}
	double boundary_volume = 0.0;
	for (uint32_t i = 0; i < p_face_count; ++i) {
		const PhysicsFEMSurfaceTriangle &face = p_faces[i];
		if (face.a >= p_vertex_count || face.b >= p_vertex_count ||
				face.c >= p_vertex_count || face.a == face.b ||
				face.b == face.c || face.c == face.a) {
			return false;
		}
		const double signed_volume = physics_fem_convex_signed_face_volume(
				origin, p_vertices[face.a], p_vertices[face.b],
				p_vertices[face.c]);
		if (!Math::is_finite(signed_volume)) {
			return false;
		}
		boundary_volume += signed_volume;
	}
	if (!Math::is_finite(boundary_volume) ||
			!(Math::abs(boundary_volume) > cube * 1e-10)) {
		return false;
	}
	const double orientation = boundary_volume > 0.0 ? 1.0 : -1.0;
	const double plane_tolerance = scale * 1e-6;
	const double fan_tolerance = cube * 1e-10;
	uint32_t result_count = 0;
	double fan_volume = 0.0;

	for (uint32_t i = 0; i < p_face_count; ++i) {
		const PhysicsFEMSurfaceTriangle &face = p_faces[i];
		const Vector3 &a = p_vertices[face.a];
		const Vector3 &b = p_vertices[face.b];
		const Vector3 &c = p_vertices[face.c];
		const double ux = double(b.x) - double(a.x);
		const double uy = double(b.y) - double(a.y);
		const double uz = double(b.z) - double(a.z);
		const double vx = double(c.x) - double(a.x);
		const double vy = double(c.y) - double(a.y);
		const double vz = double(c.z) - double(a.z);
		const double nx = uy * vz - uz * vy;
		const double ny = uz * vx - ux * vz;
		const double nz = ux * vy - uy * vx;
		const double n_sq = nx * nx + ny * ny + nz * nz;
		const double u_sq = ux * ux + uy * uy + uz * uz;
		const double v_sq = vx * vx + vy * vy + vz * vz;
		if (!(n_sq > u_sq * v_sq * 1e-16) || !Math::is_finite(n_sq) ||
				!Math::is_finite(u_sq) || !Math::is_finite(v_sq)) {
			return false;
		}
		const double n_len = Math::sqrt(n_sq);
		// For a convex outward-wound surface every other vertex must be
		// behind every boundary face, within float-mesh plane tolerance.
		for (uint32_t j = 0; j < p_vertex_count; ++j) {
			const Vector3 &p = p_vertices[j];
			const double side = (nx * (double(p.x) - double(a.x)) +
					ny * (double(p.y) - double(a.y)) +
					nz * (double(p.z) - double(a.z))) * orientation;
			if (!Math::is_finite(side) || side > plane_tolerance * n_len) {
				return false;
			}
		}

		// Boundary triangles containing the apex contribute no volume.
		if (face.a == 0 || face.b == 0 || face.c == 0) {
			continue;
		}
		const double contribution = physics_fem_convex_signed_face_volume(
				origin, a, b, c) * orientation;
		if (contribution < -fan_tolerance) {
			return false;
		}
		// Other triangles on the apex's coplanar boundary face also do
		// not form valid volume tets, and must be omitted.
		if (!(contribution > fan_tolerance)) {
			continue;
		}
		PhysicsFEMConvexTetra element;
		element.nodes[0] = 0;
		element.nodes[1] = face.a;
		element.nodes[2] = face.b;
		element.nodes[3] = face.c;
		if (!physics_fem_tetra_make_rest(origin, a, b, c, element.rest)) {
			return false;
		}
		if (element.rest.signed_det * orientation <= 0.0) {
			return false;
		}
		r_elements[result_count++] = element;
		fan_volume += element.rest.volume;
	}
	const double expected = Math::abs(boundary_volume);
	if (result_count == 0 || !Math::is_finite(fan_volume) ||
			Math::abs(fan_volume - expected) > expected * 1e-5) {
		return false;
	}
	r_count = result_count;
	return true;
}
