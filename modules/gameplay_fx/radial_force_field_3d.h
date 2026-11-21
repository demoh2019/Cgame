/**************************************************************************/
/*  radial_force_field_3d.h                                             */
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

#include "scene/3d/node_3d.h"
#include "scene/resources/3d/sphere_shape_3d.h"

/**
 * Radial impulse "physics field" (Unity AddExplosionForce / Chaos radial force).
 * fire() pushes every RigidBody3D and PhysicalBone3D within radius.
 */
class RadialForceField3D : public Node3D {
	GDCLASS(RadialForceField3D, Node3D);

public:
	enum Falloff {
		FALLOFF_NONE,
		FALLOFF_LINEAR,
		FALLOFF_QUADRATIC,
	};

private:
	float radius = 5.0f;
	float strength = 10.0f;
	Falloff falloff = FALLOFF_LINEAR;
	float upward_bias = 0.0f;
	uint32_t collision_mask = 1;
	// Optional ray-traced line-of-sight attenuation. Separate from the
	// physics overlap mask so walls can screen the explosion without being
	// pushed by it. Both are opt-in to preserve legacy scene behavior.
	uint32_t occlusion_mask = 0;
	float occlusion_attenuation = 0.25f;
	int max_occlusion_rays = 24;
	bool mass_independent = false;
	bool continuous = false;
	bool affect_rigid_bodies = true;
	bool affect_physical_bones = true;
	bool free_after_fire = false;
	int max_bodies = 64;

	bool fire_pending = false;
	Ref<SphereShape3D> query_shape;

	int _apply(float p_scale);

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	void set_radius(float p_radius);
	float get_radius() const { return radius; }
	void set_strength(float p_strength);
	float get_strength() const { return strength; }
	void set_falloff(Falloff p_falloff);
	Falloff get_falloff() const { return falloff; }
	void set_upward_bias(float p_bias);
	float get_upward_bias() const { return upward_bias; }
	void set_collision_mask(uint32_t p_mask);
	uint32_t get_collision_mask() const { return collision_mask; }
	void set_occlusion_mask(uint32_t p_mask) { occlusion_mask = p_mask; }
	uint32_t get_occlusion_mask() const { return occlusion_mask; }
	void set_occlusion_attenuation(float p_value);
	float get_occlusion_attenuation() const { return occlusion_attenuation; }
	void set_max_occlusion_rays(int p_count);
	int get_max_occlusion_rays() const { return max_occlusion_rays; }
	void set_mass_independent(bool p_enabled) { mass_independent = p_enabled; }
	bool is_mass_independent() const { return mass_independent; }
	void set_collision_mask_value(int p_layer_number, bool p_value);
	bool get_collision_mask_value(int p_layer_number) const;
	void set_continuous(bool p_continuous);
	bool is_continuous() const { return continuous; }
	void set_affect_rigid_bodies(bool p_enabled) { affect_rigid_bodies = p_enabled; }
	bool is_affecting_rigid_bodies() const { return affect_rigid_bodies; }
	void set_affect_physical_bones(bool p_enabled) { affect_physical_bones = p_enabled; }
	bool is_affecting_physical_bones() const { return affect_physical_bones; }
	void set_free_after_fire(bool p_enabled) { free_after_fire = p_enabled; }
	bool is_free_after_fire() const { return free_after_fire; }
	void set_max_bodies(int p_max);
	int get_max_bodies() const { return max_bodies; }

	// Applies the impulse now when inside a physics frame, otherwise at the next
	// physics frame (and returns 0). Returns the number of bodies pushed.
	int fire();

	// Pure logic (no physics server needed). Result is in 0..1.
	static float falloff_scale(float p_distance, float p_radius, Falloff p_mode);
	// Impulse direction from field center to body center, tilted by upward bias (normalized).
	static Vector3 impulse_direction(const Vector3 &p_center, const Vector3 &p_body_position, float p_upward_bias);
	// Pure helpers for deterministic gameplay parity and native regression tests.
	static float occlusion_scale(bool p_blocked, float p_attenuation);
	static float impulse_magnitude(float p_strength, float p_falloff, float p_mass, bool p_mass_independent);
};

VARIANT_ENUM_CAST(RadialForceField3D::Falloff);
