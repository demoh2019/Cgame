/**************************************************************************/
/*  physics_fluid_box_3d.h                                                */
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

#include "servers/physics_fluid_convex_hull_3d.h"

// Exact displaced volume and first moment for a (possibly rotated,
// reflected, nonuniformly scaled or sheared) Godot BoxShape3D under the
// horizontal fluid plane. The six tetrahedra along cube diagonal 0->7
// partition a parallelepiped without needing a MeshData or any allocation.
//
// All clipping happens in the box's local coordinates and double volume
// accumulators. This also avoids large-coordinate cancellation for bodies
// positioned far from the origin.
_FORCE_INLINE_ bool godot_physics_fluid_box_sample_3d(const Vector3 &p_half_extents,
		const Transform3D &p_transform, real_t p_surface_y,
		GodotPhysicsFluidSample3D &r_sample, real_t &r_total_volume) {
	r_sample = GodotPhysicsFluidSample3D();
	r_total_volume = 0.0;
	if (!(p_half_extents.x > 0.0) || !(p_half_extents.y > 0.0) ||
			!(p_half_extents.z > 0.0) || !p_half_extents.is_finite() ||
			!p_transform.basis.is_finite() || !p_transform.origin.is_finite() ||
			!Math::is_finite(p_surface_y)) {
		return false;
	}

	const double local_volume = double(8.0) * double(p_half_extents.x) *
			double(p_half_extents.y) * double(p_half_extents.z);
	const double jacobian = Math::abs(double(p_transform.basis.determinant()));
	const double world_volume = local_volume * jacobian;
	if (!(world_volume > 0.0) || !Math::is_finite(world_volume)) {
		return false;
	}

	// Each index is a bitmask: bit 0 = +X, bit 1 = +Y, bit 2 = +Z.
	const Vector3 corners[8] = {
		Vector3(-p_half_extents.x, -p_half_extents.y, -p_half_extents.z),
		Vector3( p_half_extents.x, -p_half_extents.y, -p_half_extents.z),
		Vector3(-p_half_extents.x,  p_half_extents.y, -p_half_extents.z),
		Vector3( p_half_extents.x,  p_half_extents.y, -p_half_extents.z),
		Vector3(-p_half_extents.x, -p_half_extents.y,  p_half_extents.z),
		Vector3( p_half_extents.x, -p_half_extents.y,  p_half_extents.z),
		Vector3(-p_half_extents.x,  p_half_extents.y,  p_half_extents.z),
		Vector3( p_half_extents.x,  p_half_extents.y,  p_half_extents.z)
	};
	const uint8_t tetrahedra[6][4] = {
		{ 0, 1, 3, 7 }, { 0, 1, 5, 7 },
		{ 0, 2, 3, 7 }, { 0, 2, 6, 7 },
		{ 0, 4, 5, 7 }, { 0, 4, 6, 7 }
	};
	const Vector3 world_vertical(p_transform.basis.get_column(0).y,
			p_transform.basis.get_column(1).y, p_transform.basis.get_column(2).y);
	const real_t local_surface = p_surface_y - p_transform.origin.y;
	if (!world_vertical.is_finite() || !Math::is_finite(local_surface)) {
		return false;
	}
	real_t distances[8];
	for (int i = 0; i < 8; ++i) {
		distances[i] = local_surface - world_vertical.dot(corners[i]);
		if (!Math::is_finite(distances[i])) {
			return false;
		}
	}

	GodotPhysicsFluidTetraSum3D submerged;
	for (int i = 0; i < 6; ++i) {
		const uint8_t *ids = tetrahedra[i];
		const Vector3 tetra[4] = { corners[ids[0]], corners[ids[1]],
				corners[ids[2]], corners[ids[3]] };
		const real_t heights[4] = { distances[ids[0]], distances[ids[1]],
				distances[ids[2]], distances[ids[3]] };
		if (!godot_physics_fluid_clip_tetra_3d(tetra, heights, submerged)) {
			return false;
		}
	}

	const double wet_local_volume = MIN(MAX(submerged.volume, 0.0), local_volume);
	const double wet_world_volume = wet_local_volume * jacobian;
	if (!Math::is_finite(wet_world_volume)) {
		return false;
	}
	r_total_volume = real_t(world_volume);
	r_sample.submerged_volume = real_t(wet_world_volume);
	r_sample.submerged_fraction = real_t(wet_local_volume / local_volume);
	if (!Math::is_finite(r_total_volume) || !Math::is_finite(r_sample.submerged_volume) ||
			!Math::is_finite(r_sample.submerged_fraction) ||
			!(r_total_volume > 0.0)) {
		return false;
	}
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
