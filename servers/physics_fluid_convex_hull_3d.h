/**************************************************************************/
/*  physics_fluid_convex_hull_3d.h                                        */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
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

#include "core/math/geometry_3d.h"
#include "core/math/transform_3d.h"
#include "servers/physics_fluid_buoyancy_3d.h"

// Exact half-space displacement for a closed convex polygon mesh.
//
// Every face triangle and an interior point form a non-overlapping
// tetrahedron. Clip each tetrahedron by the horizontal water plane and
// accumulate its volume and first moment. Using local coordinates avoids
// loss of precision when a body is far from the world origin; the water
// plane is transformed into the same local coordinates.
//
// The routine does NOT allocate. Restrict high-poly hulls to bound worst
// case cost in the force integrator; those hulls use the old AABB estimate.
struct GodotPhysicsFluidTetraSum3D {
	double volume = 0.0;
	double moment_x = 0.0;
	double moment_y = 0.0;
	double moment_z = 0.0;

	_FORCE_INLINE_ bool add(const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c, const Vector3 &p_d) {
		const double abx = double(p_b.x) - double(p_a.x);
		const double aby = double(p_b.y) - double(p_a.y);
		const double abz = double(p_b.z) - double(p_a.z);
		const double acx = double(p_c.x) - double(p_a.x);
		const double acy = double(p_c.y) - double(p_a.y);
		const double acz = double(p_c.z) - double(p_a.z);
		const double adx = double(p_d.x) - double(p_a.x);
		const double ady = double(p_d.y) - double(p_a.y);
		const double adz = double(p_d.z) - double(p_a.z);
		const double six_volume = abx * (acy * adz - acz * ady) +
				aby * (acz * adx - acx * adz) +
				abz * (acx * ady - acy * adx);
		const double v = Math::abs(six_volume) / 6.0;
		if (!Math::is_finite(v)) {
			return false;
		}
		volume += v;
		moment_x += v * (double(p_a.x) + double(p_b.x) + double(p_c.x) + double(p_d.x)) * 0.25;
		moment_y += v * (double(p_a.y) + double(p_b.y) + double(p_c.y) + double(p_d.y)) * 0.25;
		moment_z += v * (double(p_a.z) + double(p_b.z) + double(p_c.z) + double(p_d.z)) * 0.25;
		return Math::is_finite(volume) && Math::is_finite(moment_x) &&
				Math::is_finite(moment_y) && Math::is_finite(moment_z);
	}
};

_FORCE_INLINE_ Vector3 godot_physics_fluid_tetra_water_edge_3d(const Vector3 &p_inside, const Vector3 &p_outside, real_t p_inside_distance, real_t p_outside_distance) {
	const real_t t = CLAMP(p_inside_distance / (p_inside_distance - p_outside_distance), real_t(0.0), real_t(1.0));
	return p_inside + (p_outside - p_inside) * t;
}

_FORCE_INLINE_ bool godot_physics_fluid_clip_tetra_3d(const Vector3 (&p_vertices)[4], const real_t (&p_distances)[4], GodotPhysicsFluidTetraSum3D &r_submerged) {
	int inside[4];
	int outside[4];
	int count_inside = 0;
	int count_outside = 0;
	for (int i = 0; i < 4; i++) {
		if (p_distances[i] >= 0.0) {
			inside[count_inside++] = i;
		} else {
			outside[count_outside++] = i;
		}
	}
	if (count_inside == 0) {
		return true;
	}
	if (count_inside == 4) {
		return r_submerged.add(p_vertices[0], p_vertices[1], p_vertices[2], p_vertices[3]);
	}

	auto intersection = [&](int p_inside, int p_outside) {
		return godot_physics_fluid_tetra_water_edge_3d(p_vertices[p_inside], p_vertices[p_outside],
				p_distances[p_inside], p_distances[p_outside]);
	};
	if (count_inside == 1) {
		const int a = inside[0];
		return r_submerged.add(p_vertices[a], intersection(a, outside[0]),
				intersection(a, outside[1]), intersection(a, outside[2]));
	}
	if (count_inside == 3) {
		const int a = outside[0];
		GodotPhysicsFluidTetraSum3D full;
		GodotPhysicsFluidTetraSum3D dry;
		if (!full.add(p_vertices[0], p_vertices[1], p_vertices[2], p_vertices[3]) ||
				!dry.add(p_vertices[a], intersection(inside[0], a),
						intersection(inside[1], a), intersection(inside[2], a))) {
			return false;
		}
		const double wet_volume = MAX(0.0, full.volume - dry.volume);
		if (wet_volume > 0.0) {
			r_submerged.volume += wet_volume;
			r_submerged.moment_x += full.moment_x - dry.moment_x;
			r_submerged.moment_y += full.moment_y - dry.moment_y;
			r_submerged.moment_z += full.moment_z - dry.moment_z;
		}
		return Math::is_finite(r_submerged.volume) && Math::is_finite(r_submerged.moment_x) &&
				Math::is_finite(r_submerged.moment_y) && Math::is_finite(r_submerged.moment_z);
	}

	// Two submerged corners (A,B) and two dry corners (C,D) form a
	// six-vertex clipped polyhedron. These three tetrahedra partition it.
	const int a = inside[0];
	const int b = inside[1];
	const int c = outside[0];
	const int d = outside[1];
	const Vector3 ac = intersection(a, c);
	const Vector3 ad = intersection(a, d);
	const Vector3 bc = intersection(b, c);
	const Vector3 bd = intersection(b, d);
	return r_submerged.add(p_vertices[a], p_vertices[b], bc, bd) &&
			r_submerged.add(p_vertices[a], ac, bc, bd) &&
			r_submerged.add(p_vertices[a], ac, bd, ad);
}

// Returns false for a degenerate or unusually expensive mesh so callers
// can use their existing approximate path without discarding buoyancy.
// The returned volume is geometrical volume (not the hull AABB volume).
_FORCE_INLINE_ bool godot_physics_fluid_convex_hull_sample_3d(const Geometry3D::MeshData &p_mesh, const Transform3D &p_transform, real_t p_surface_y, GodotPhysicsFluidSample3D &r_sample, real_t &r_total_volume) {
	r_sample = GodotPhysicsFluidSample3D();
	r_total_volume = 0.0;
	const uint32_t vertex_count = p_mesh.vertices.size();
	const uint32_t face_count = p_mesh.faces.size();
	if (vertex_count < 4 || face_count < 4 || vertex_count > 512 || face_count > 256 ||
			!p_transform.basis.is_finite() || !p_transform.origin.is_finite() ||
			!Math::is_finite(p_surface_y)) {
		return false;
	}
	const double jacobian = Math::abs(double(p_transform.basis.determinant()));
	if (!(jacobian > 0.0) || !Math::is_finite(jacobian)) {
		return false;
	}

	Vector3 interior;
	for (uint32_t i = 0; i < vertex_count; i++) {
		const Vector3 &point = p_mesh.vertices[i];
		if (!point.is_finite()) {
			return false;
		}
		interior += point;
	}
	interior /= real_t(vertex_count);
	const Vector3 world_vertical(
			p_transform.basis.get_column(0).y,
			p_transform.basis.get_column(1).y,
			p_transform.basis.get_column(2).y);
	const real_t local_surface = p_surface_y - p_transform.origin.y;
	const real_t interior_distance = local_surface - world_vertical.dot(interior);

	GodotPhysicsFluidTetraSum3D total;
	GodotPhysicsFluidTetraSum3D submerged;
	for (uint32_t f = 0; f < face_count; f++) {
		const Geometry3D::MeshData::Face &face = p_mesh.faces[f];
		const uint32_t n = face.indices.size();
		if (n < 3) {
			return false;
		}
		for (uint32_t j = 0; j < n; j++) {
			if (face.indices[j] < 0 || uint32_t(face.indices[j]) >= vertex_count) {
				return false;
			}
		}
		const Vector3 &first = p_mesh.vertices[face.indices[0]];
		for (uint32_t j = 1; j + 1 < n; j++) {
			const Vector3 corners[4] = { interior, first,
					p_mesh.vertices[face.indices[j]], p_mesh.vertices[face.indices[j + 1]] };
			const real_t distances[4] = { interior_distance,
				local_surface - world_vertical.dot(corners[1]),
				local_surface - world_vertical.dot(corners[2]),
				local_surface - world_vertical.dot(corners[3]) };
			if (!total.add(corners[0], corners[1], corners[2], corners[3]) ||
					!godot_physics_fluid_clip_tetra_3d(corners, distances, submerged)) {
				return false;
			}
		}
	}
	if (!(total.volume > 0.0) || !Math::is_finite(total.volume) ||
			!Math::is_finite(submerged.volume) || !Math::is_finite(submerged.moment_x) ||
			!Math::is_finite(submerged.moment_y) || !Math::is_finite(submerged.moment_z)) {
		return false;
	}
	const double world_total = total.volume * jacobian;
	const double world_wet = MIN(MAX(submerged.volume, 0.0), total.volume) * jacobian;
	if (!Math::is_finite(world_total) || !Math::is_finite(world_wet) || world_total <= 0.0) {
		return false;
	}
	r_total_volume = real_t(world_total);
	r_sample.submerged_volume = real_t(world_wet);
	// In single-precision builds a finite double can still overflow when
	// converted to real_t; never feed infinities to rigid-body forces.
	if (!Math::is_finite(r_total_volume) || !Math::is_finite(r_sample.submerged_volume) || !(r_total_volume > 0.0)) {
		return false;
	}
	r_sample.submerged_fraction = real_t(MIN(MAX(submerged.volume / total.volume, 0.0), 1.0));
	if (submerged.volume > 0.0) {
		const Vector3 local_center(
				real_t(submerged.moment_x / submerged.volume),
				real_t(submerged.moment_y / submerged.volume),
				real_t(submerged.moment_z / submerged.volume));
		r_sample.center_of_buoyancy = p_transform.xform(local_center);
		if (!r_sample.center_of_buoyancy.is_finite()) {
			return false;
		}
	}
	return true;
}
