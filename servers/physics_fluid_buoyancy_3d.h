/**************************************************************************/
/*  physics_fluid_buoyancy_3d.h                                           */
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

#include "core/math/aabb.h"
#include "core/math/basis.h"

// Approximate fluid integration for GodotPhysics' rigid bodies. A horizontal
// free surface clips each shape's *world AABB* to estimate submerged volume
// and center of buoyancy. This does not claim exact submerged polyhedra:
// rotated, concave and compound shapes need a higher-order clipping solver.
//
// This helper is separate from the body integrator to allow deterministic
// geometry and drag tests without constructing a physics space.
struct GodotPhysicsFluidSample3D {
	real_t submerged_volume = 0.0;
	real_t submerged_fraction = 0.0;
	Vector3 center_of_buoyancy;
};

_FORCE_INLINE_ GodotPhysicsFluidSample3D godot_physics_fluid_sample_3d(const AABB &p_world_bounds, real_t p_volume, real_t p_surface_y) {
	GodotPhysicsFluidSample3D sample;
	if (!(p_volume > 0.0) || !Math::is_finite(p_volume) || !p_world_bounds.is_finite() || !Math::is_finite(p_surface_y)) {
		return sample;
	}

	const real_t bottom = p_world_bounds.position.y;
	const real_t height = p_world_bounds.size.y;
	if (!(height > 0.0)) {
		// Zero-height bounds have no meaningful partial submerged fraction.
		return sample;
	}

	const real_t submerged_height = CLAMP(p_surface_y - bottom, real_t(0.0), height);
	if (!(submerged_height > 0.0)) {
		return sample;
	}

	sample.submerged_fraction = submerged_height / height;
	sample.submerged_volume = p_volume * sample.submerged_fraction;
	sample.center_of_buoyancy = p_world_bounds.get_center();
	sample.center_of_buoyancy.y = bottom + submerged_height * real_t(0.5);
	return sample;
}

// A similarity transform maps a sphere to a sphere and a capsule to a
// uniformly scaled capsule. Skew and nonuniform scale change the
// hydrostatic cross section, so those cases use the existing AABB fallback.
// The tolerance scales with the squared size of the basis, not world units.
_FORCE_INLINE_ bool godot_physics_fluid_uniform_scale_3d(const Basis &p_basis, real_t &r_scale) {
	const Vector3 x = p_basis.get_column(0);
	const Vector3 y = p_basis.get_column(1);
	const Vector3 z = p_basis.get_column(2);
	const real_t xx = x.length_squared();
	const real_t yy = y.length_squared();
	const real_t zz = z.length_squared();
	if (!(xx > 0.0) || !Math::is_finite(xx) || !Math::is_finite(yy) || !Math::is_finite(zz)) {
		return false;
	}
	const real_t tol = xx * real_t(0.00001);
	if (Math::abs(yy - xx) > tol || Math::abs(zz - xx) > tol ||
			Math::abs(x.dot(y)) > tol || Math::abs(x.dot(z)) > tol || Math::abs(y.dot(z)) > tol) {
		return false;
	}
	r_scale = Math::sqrt(xx);
	return Math::is_finite(r_scale) && r_scale > 0.0;
}

// This analytic form integrates the circular cross-sectional area of a
// sphere under y = surface_y. h is depth measured upward from its bottom.
// V_cap/V_sphere = t^2(3 - t)/4, t = h/r in [0,2].
// Its centroid lies at y_c - 3r(2 - t)^2 / [4(3 - t)].
// The caller supplies the cached shape volume, including its world scale,
// so the returned submerged_volume is consistent with the body's density.
_FORCE_INLINE_ GodotPhysicsFluidSample3D godot_physics_fluid_sphere_sample_3d(const Vector3 &p_world_center, real_t p_world_radius, real_t p_world_volume, real_t p_surface_y) {
	GodotPhysicsFluidSample3D sample;
	if (!(p_world_radius > 0.0) || !(p_world_volume > 0.0) ||
			!Math::is_finite(p_world_radius) || !Math::is_finite(p_world_volume) ||
			!Math::is_finite(p_surface_y) || !p_world_center.is_finite()) {
		return sample;
	}
	const real_t height_ratio = CLAMP((p_surface_y - (p_world_center.y - p_world_radius)) / p_world_radius, real_t(0.0), real_t(2.0));
	if (!(height_ratio > 0.0)) {
		return sample;
	}
	sample.submerged_fraction = height_ratio * height_ratio * (real_t(3.0) - height_ratio) * real_t(0.25);
	sample.submerged_volume = p_world_volume * sample.submerged_fraction;
	sample.center_of_buoyancy = p_world_center;
	const real_t remaining = real_t(2.0) - height_ratio;
	sample.center_of_buoyancy.y -= real_t(0.75) * p_world_radius * remaining * remaining / (real_t(3.0) - height_ratio);
	return sample;
}

// Exact cross-sectional integration for a *vertical*, uniformly scaled
// capsule (a cylinder of length L plus two radius-r hemispheres).
// Use dimensionless quantities to avoid large powers of the world radius.
// The first moment is measured from the bottom of the capsule, in r units.
_FORCE_INLINE_ GodotPhysicsFluidSample3D godot_physics_fluid_vertical_capsule_sample_3d(const Vector3 &p_world_center, real_t p_world_radius, real_t p_world_height, real_t p_world_volume, real_t p_surface_y) {
	GodotPhysicsFluidSample3D sample;
	if (!(p_world_radius > 0.0) || !(p_world_height >= real_t(2.0) * p_world_radius) ||
			!(p_world_volume > 0.0) || !p_world_center.is_finite() ||
			!Math::is_finite(p_world_radius) || !Math::is_finite(p_world_height) ||
			!Math::is_finite(p_world_volume) || !Math::is_finite(p_surface_y)) {
		return sample;
	}
	const real_t cylinder_ratio = p_world_height / p_world_radius - real_t(2.0);
	const real_t bottom = p_world_center.y - p_world_height * real_t(0.5);
	const real_t height_ratio = CLAMP((p_surface_y - bottom) / p_world_radius,
			real_t(0.0), real_t(2.0) + cylinder_ratio);
	if (!(height_ratio > 0.0)) {
		return sample;
	}

	real_t volume_units; // volume / (pi * r^3)
	real_t moment_units; // first moment / (pi * r^4), relative to bottom
	if (height_ratio < real_t(1.0)) {
		const real_t t = height_ratio;
		volume_units = t * t * (real_t(1.0) - t / real_t(3.0));
		const real_t remaining = real_t(2.0) - t;
		const real_t centroid_from_bottom = real_t(1.0) -
				real_t(0.75) * remaining * remaining / (real_t(3.0) - t);
		moment_units = volume_units * centroid_from_bottom;
	} else if (height_ratio <= real_t(1.0) + cylinder_ratio) {
		const real_t length = height_ratio - real_t(1.0);
		volume_units = real_t(2.0 / 3.0) + length;
		moment_units = real_t(5.0 / 12.0) + length * (real_t(1.0) + length * real_t(0.5));
	} else {
		const real_t u = height_ratio - real_t(1.0) - cylinder_ratio;
		const real_t upper_volume = u - u * u * u / real_t(3.0);
		volume_units = real_t(2.0 / 3.0) + cylinder_ratio + upper_volume;
		moment_units = real_t(5.0 / 12.0) +
				cylinder_ratio * (real_t(1.0) + cylinder_ratio * real_t(0.5)) +
				(real_t(1.0) + cylinder_ratio) * upper_volume +
				u * u * real_t(0.5) - u * u * u * u * real_t(0.25);
	}

	sample.submerged_fraction = CLAMP(volume_units / (real_t(4.0 / 3.0) + cylinder_ratio), real_t(0.0), real_t(1.0));
	sample.submerged_volume = p_world_volume * sample.submerged_fraction;
	sample.center_of_buoyancy = p_world_center;
	sample.center_of_buoyancy.y = bottom + (moment_units / volume_units) * p_world_radius;
	return sample;
}

// A capsule axis must be aligned to world Y for the horizontal slices
// above to be circular. Reversed Y is equivalent for a symmetric capsule.
_FORCE_INLINE_ bool godot_physics_fluid_capsule_vertical_3d(const Basis &p_basis, real_t p_uniform_scale) {
	if (!(p_uniform_scale > 0.0)) {
		return false;
	}
	const Vector3 axis = p_basis.get_column(1) / p_uniform_scale;
	return Math::abs(axis.x) <= real_t(0.00001) && Math::abs(axis.z) <= real_t(0.00001);
}

// F = -1/2 rho C_d A |v_rel| v_rel, with the projected AABB area as a
// conservative, low-cost substitute for an exact shape projection.
// The result is zero for stationary objects relative to the moving fluid.
_FORCE_INLINE_ Vector3 godot_physics_fluid_quadratic_drag_3d(const Vector3 &p_relative_velocity, const Vector3 &p_bounds_size, real_t p_submerged_fraction, real_t p_density, real_t p_drag_coefficient) {
	if (!(p_submerged_fraction > 0.0) || !(p_density > 0.0) || !(p_drag_coefficient > 0.0) || !p_relative_velocity.is_finite()) {
		return Vector3();
	}
	const real_t speed_squared = p_relative_velocity.length_squared();
	if (!(speed_squared > 0.0) || !Math::is_finite(speed_squared)) {
		return Vector3();
	}

	const real_t speed = Math::sqrt(speed_squared);
	const Vector3 dir = p_relative_velocity / speed;
	const real_t projected_area = (
			Math::abs(dir.x) * p_bounds_size.y * p_bounds_size.z +
			Math::abs(dir.y) * p_bounds_size.x * p_bounds_size.z +
			Math::abs(dir.z) * p_bounds_size.x * p_bounds_size.y);
	if (!(projected_area > 0.0) || !Math::is_finite(projected_area)) {
		return Vector3();
	}
	const Vector3 force = -p_relative_velocity * (real_t(0.5) * p_density * p_drag_coefficient * projected_area * p_submerged_fraction * speed);
	return force.is_finite() ? force : Vector3();
}

_FORCE_INLINE_ real_t godot_physics_fluid_angular_damping_3d(real_t p_coefficient, real_t p_submerged_fraction, real_t p_step) {
	if (!(p_coefficient > 0.0) || !(p_submerged_fraction > 0.0) || !(p_step > 0.0)) {
		return 1.0;
	}
	// Implicit damping cannot reverse spin at large delta or drag values.
	return real_t(1.0) / (real_t(1.0) + p_coefficient * p_submerged_fraction * p_step);
}
