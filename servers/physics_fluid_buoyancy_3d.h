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
	if (!(p_volume > 0.0) || !p_world_bounds.is_finite() || !Math::is_finite(p_surface_y)) {
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
	return -p_relative_velocity * (real_t(0.5) * p_density * p_drag_coefficient * projected_area * p_submerged_fraction * speed);
}

_FORCE_INLINE_ real_t godot_physics_fluid_angular_damping_3d(real_t p_coefficient, real_t p_submerged_fraction, real_t p_step) {
	if (!(p_coefficient > 0.0) || !(p_submerged_fraction > 0.0) || !(p_step > 0.0)) {
		return 1.0;
	}
	// Implicit damping cannot reverse spin at large delta or drag values.
	return real_t(1.0) / (real_t(1.0) + p_coefficient * p_submerged_fraction * p_step);
}
