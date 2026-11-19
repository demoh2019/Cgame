/**************************************************************************/
/*  destructible_body_3d.h                                             */
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

#include "scene/3d/physics/rigid_body_3d.h"
#include "scene/resources/material.h"

// A rigid body that shatters into convex debris. The shape of the first box or convex collision
// shape among the children is cut with a Voronoi diagram into [member piece_count] pieces, which
// become new rigid bodies sharing the mass of the original and carrying its motion. The break can
// be triggered by an impact, by damage, or from code.
class DestructibleBody3D : public RigidBody3D {
	GDCLASS(DestructibleBody3D, RigidBody3D);

private:
	int piece_count = 8;
	real_t break_impulse = 0.0;
	real_t health = 0.0;
	real_t seed_concentration = 1.0;
	real_t scatter_speed = 2.0;
	real_t debris_lifetime = 10.0;
	Ref<Material> inner_material;
	int random_seed = 0;

	bool broken = false;
	bool break_queued = false;
	bool has_previous_velocity = false;
	Vector3 previous_velocity;
	Vector3 pending_point;
	Vector3 pending_impulse;

	bool _collect_points(Vector<Vector3> &r_points) const;
	Ref<Material> _find_outer_material() const;
	Array _fracture_now(const Vector3 &p_global_point, const Vector3 &p_impulse);
	void _deferred_fracture();

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	void set_piece_count(int p_count);
	int get_piece_count() const { return piece_count; }
	void set_break_impulse(real_t p_impulse);
	real_t get_break_impulse() const { return break_impulse; }
	void set_health(real_t p_health);
	real_t get_health() const { return health; }
	void set_seed_concentration(real_t p_value);
	real_t get_seed_concentration() const { return seed_concentration; }
	void set_scatter_speed(real_t p_speed);
	real_t get_scatter_speed() const { return scatter_speed; }
	void set_debris_lifetime(real_t p_seconds);
	real_t get_debris_lifetime() const { return debris_lifetime; }
	void set_inner_material(const Ref<Material> &p_material) { inner_material = p_material; }
	Ref<Material> get_inner_material() const { return inner_material; }
	void set_random_seed(int p_seed) { random_seed = p_seed; }
	int get_random_seed() const { return random_seed; }

	// Breaks the body now. `p_global_point` is where it is hit (the pieces nearby become smaller and
	// fly faster) and `p_impulse` an extra impulse shared by all pieces, in N*s. Returns the debris
	// bodies; the original is removed. Does nothing and returns an empty array if it is already broken
	// or has no usable shape.
	Array fracture(const Vector3 &p_global_point, const Vector3 &p_impulse = Vector3());
	// Reduces health; breaks the body when it reaches zero. Only has an effect with health > 0.
	void apply_damage(real_t p_amount, const Vector3 &p_global_point);
	bool is_broken() const { return broken; }

	DestructibleBody3D() {}
};
