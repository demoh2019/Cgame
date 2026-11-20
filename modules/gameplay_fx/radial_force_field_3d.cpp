/**************************************************************************/
/*  radial_force_field_3d.cpp                                           */
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
#include "radial_force_field_3d.h"

#include "core/config/engine.h"
#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/hash_set.h"
#include "core/templates/local_vector.h"
#include "scene/3d/physics/physical_bone_3d.h"
#include "scene/3d/physics/rigid_body_3d.h"
#include "scene/resources/3d/world_3d.h"
#include "servers/physics_3d/direct_states/physics_direct_space_state_3d.h"
#include "servers/physics_3d/physics_server_3d_types.h"

void RadialForceField3D::set_radius(float p_radius) {
	radius = MAX(0.0f, p_radius);
}

void RadialForceField3D::set_strength(float p_strength) {
	strength = p_strength;
}

void RadialForceField3D::set_falloff(Falloff p_falloff) {
	falloff = p_falloff;
}

void RadialForceField3D::set_upward_bias(float p_bias) {
	upward_bias = p_bias;
}

void RadialForceField3D::set_collision_mask(uint32_t p_mask) {
	collision_mask = p_mask;
}

void RadialForceField3D::set_occlusion_attenuation(float p_value) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_value), "Occlusion attenuation must be finite.");
	occlusion_attenuation = CLAMP(p_value, 0.0f, 1.0f);
}

void RadialForceField3D::set_max_occlusion_rays(int p_count) {
	max_occlusion_rays = CLAMP(p_count, 1, 64);
}

float RadialForceField3D::occlusion_scale(bool p_blocked, float p_attenuation) {
	return p_blocked ? CLAMP(p_attenuation, 0.0f, 1.0f) : 1.0f;
}

float RadialForceField3D::impulse_magnitude(float p_strength, float p_falloff, float p_mass, bool p_mass_independent) {
	return p_strength * p_falloff * (p_mass_independent ? p_mass : 1.0f);
}

void RadialForceField3D::set_collision_mask_value(int p_layer_number, bool p_value) {
	ERR_FAIL_COND_MSG(p_layer_number < 1, "Collision layer number must be between 1 and 32 inclusive.");
	ERR_FAIL_COND_MSG(p_layer_number > 32, "Collision layer number must be between 1 and 32 inclusive.");
	uint32_t mask = get_collision_mask();
	if (p_value) {
		mask |= 1u << (p_layer_number - 1);
	} else {
		mask &= ~(1u << (p_layer_number - 1));
	}
	set_collision_mask(mask);
}

bool RadialForceField3D::get_collision_mask_value(int p_layer_number) const {
	ERR_FAIL_COND_V_MSG(p_layer_number < 1, false, "Collision layer number must be between 1 and 32 inclusive.");
	ERR_FAIL_COND_V_MSG(p_layer_number > 32, false, "Collision layer number must be between 1 and 32 inclusive.");
	return get_collision_mask() & (1u << (p_layer_number - 1));
}

void RadialForceField3D::set_continuous(bool p_continuous) {
	continuous = p_continuous;
	set_physics_process(continuous || fire_pending);
}

void RadialForceField3D::set_max_bodies(int p_max) {
	max_bodies = CLAMP(p_max, 1, 1024);
}

float RadialForceField3D::falloff_scale(float p_distance, float p_radius, Falloff p_mode) {
	if (p_radius <= 0.0f) {
		return 0.0f;
	}
	const float t = CLAMP(p_distance / p_radius, 0.0f, 1.0f);
	switch (p_mode) {
		case FALLOFF_NONE: {
			return 1.0f;
		}
		case FALLOFF_LINEAR: {
			return 1.0f - t;
		}
		case FALLOFF_QUADRATIC: {
			const float inv = 1.0f - t;
			return inv * inv;
		}
	}
	return 0.0f;
}

Vector3 RadialForceField3D::impulse_direction(const Vector3 &p_center, const Vector3 &p_body_position, float p_upward_bias) {
	Vector3 dir = p_body_position - p_center;
	if (dir.length_squared() > CMP_EPSILON2) {
		dir.normalize();
	} else {
		dir = Vector3(0, 1, 0);
	}
	dir += Vector3(0, p_upward_bias, 0);
	if (dir.length_squared() <= CMP_EPSILON2) {
		return Vector3(0, 1, 0);
	}
	return dir.normalized();
}

int RadialForceField3D::_apply(float p_scale) {
	ERR_FAIL_COND_V(!is_inside_tree(), 0);
	if (radius <= 0.0f || strength == 0.0f) {
		return 0;
	}
	Ref<World3D> world = get_world_3d();
	ERR_FAIL_COND_V(world.is_null(), 0);
	PhysicsDirectSpaceState3D *space = world->get_direct_space_state();
	ERR_FAIL_NULL_V(space, 0);

	if (query_shape.is_null()) {
		query_shape.instantiate();
	}
	query_shape->set_radius(radius);

	const Vector3 center = get_global_position();

	PS3DT::ShapeParameters params;
	params.shape_rid = query_shape->get_rid();
	params.transform = Transform3D(Basis(), center);
	params.collision_mask = collision_mask;
	params.collide_with_bodies = true;
	params.collide_with_areas = false;

	LocalVector<PS3DT::ShapeResult> results;
	results.resize(max_bodies);
	const int hits = space->intersect_shape(params, results.ptr(), max_bodies);

	HashSet<ObjectID> seen;
	int affected = 0;
	int occlusion_rays = 0;
	for (int i = 0; i < hits; i++) {
		const ObjectID id = results[i].collider_id;
		if (!id.is_valid() || seen.has(id)) {
			continue;
		}
		seen.insert(id);

		Node3D *target = nullptr;
		RigidBody3D *rigid = affect_rigid_bodies ? ObjectDB::get_instance<RigidBody3D>(id) : nullptr;
		PhysicalBone3D *bone = nullptr;
		if (rigid) {
			target = rigid;
		} else if (affect_physical_bones) {
			bone = ObjectDB::get_instance<PhysicalBone3D>(id);
			target = bone;
		}
		if (!target || !target->is_inside_tree()) {
			continue;
		}

		const Vector3 body_pos = target->get_global_position();
		const float scale = falloff_scale(body_pos.distance_to(center), radius, falloff);
		if (scale <= 0.0f) {
			continue;
		}
		float shielding = 1.0f;
		if (occlusion_mask != 0 && body_pos.distance_squared_to(center) > CMP_EPSILON2) {
			// At most max_occlusion_rays additional synchronous physics queries
			// per field activation, regardless of the number of overlapping
			// shapes. Untested overflow targets are conservatively shielded.
			bool blocked = true;
			if (occlusion_rays < max_occlusion_rays) {
				PS3DT::RayParameters ray;
				ray.from = center;
				ray.to = body_pos;
				ray.collision_mask = occlusion_mask;
				ray.collide_with_bodies = true;
				ray.collide_with_areas = false;
				// A body may belong to both the push and occlusion masks.
				// It must never block its own shockwave ray.
				ray.exclude.insert(rigid ? rigid->get_rid() : bone->get_rid());
				PS3DT::RayResult hit;
				blocked = space->intersect_ray(ray, hit);
				occlusion_rays++;
			}
			shielding = occlusion_scale(blocked, occlusion_attenuation);
		}
		if (shielding <= 0.0f) {
			continue;
		}
		const float body_mass = rigid ? rigid->get_mass() : bone->get_mass();
		const float magnitude = impulse_magnitude(strength * p_scale, scale * shielding, body_mass, mass_independent);
		const Vector3 impulse = impulse_direction(center, body_pos, upward_bias) * magnitude;
		if (rigid) {
			rigid->apply_central_impulse(impulse);
		} else {
			bone->apply_central_impulse(impulse);
		}
		affected++;
	}
	return affected;
}

int RadialForceField3D::fire() {
	ERR_FAIL_COND_V(!is_inside_tree(), 0);
	if (!Engine::get_singleton()->is_in_physics_frame()) {
		// The space state is only safe to query during the physics frame.
		fire_pending = true;
		set_physics_process(true);
		return 0;
	}
	const int affected = _apply(1.0f);
	emit_signal(SNAME("fired"), affected);
	if (free_after_fire) {
		queue_free();
	}
	return affected;
}

void RadialForceField3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_PHYSICS_PROCESS: {
			if (Engine::get_singleton()->is_editor_hint()) {
				return;
			}
			if (fire_pending) {
				fire_pending = false;
				set_physics_process(continuous);
				const int affected = _apply(1.0f);
				emit_signal(SNAME("fired"), affected);
				if (free_after_fire) {
					queue_free();
				}
				return;
			}
			if (continuous) {
				// Strength is "impulse per second" in continuous mode.
				_apply((float)get_physics_process_delta_time());
			}
		} break;
	}
}

void RadialForceField3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_radius", "radius"), &RadialForceField3D::set_radius);
	ClassDB::bind_method(D_METHOD("get_radius"), &RadialForceField3D::get_radius);
	ClassDB::bind_method(D_METHOD("set_strength", "strength"), &RadialForceField3D::set_strength);
	ClassDB::bind_method(D_METHOD("get_strength"), &RadialForceField3D::get_strength);
	ClassDB::bind_method(D_METHOD("set_falloff", "falloff"), &RadialForceField3D::set_falloff);
	ClassDB::bind_method(D_METHOD("get_falloff"), &RadialForceField3D::get_falloff);
	ClassDB::bind_method(D_METHOD("set_upward_bias", "bias"), &RadialForceField3D::set_upward_bias);
	ClassDB::bind_method(D_METHOD("get_upward_bias"), &RadialForceField3D::get_upward_bias);
	ClassDB::bind_method(D_METHOD("set_collision_mask", "mask"), &RadialForceField3D::set_collision_mask);
	ClassDB::bind_method(D_METHOD("get_collision_mask"), &RadialForceField3D::get_collision_mask);
	ClassDB::bind_method(D_METHOD("set_occlusion_mask", "mask"), &RadialForceField3D::set_occlusion_mask);
	ClassDB::bind_method(D_METHOD("get_occlusion_mask"), &RadialForceField3D::get_occlusion_mask);
	ClassDB::bind_method(D_METHOD("set_occlusion_attenuation", "value"), &RadialForceField3D::set_occlusion_attenuation);
	ClassDB::bind_method(D_METHOD("get_occlusion_attenuation"), &RadialForceField3D::get_occlusion_attenuation);
	ClassDB::bind_method(D_METHOD("set_max_occlusion_rays", "count"), &RadialForceField3D::set_max_occlusion_rays);
	ClassDB::bind_method(D_METHOD("get_max_occlusion_rays"), &RadialForceField3D::get_max_occlusion_rays);
	ClassDB::bind_method(D_METHOD("set_mass_independent", "enabled"), &RadialForceField3D::set_mass_independent);
	ClassDB::bind_method(D_METHOD("is_mass_independent"), &RadialForceField3D::is_mass_independent);
	ClassDB::bind_method(D_METHOD("set_collision_mask_value", "layer_number", "value"), &RadialForceField3D::set_collision_mask_value);
	ClassDB::bind_method(D_METHOD("get_collision_mask_value", "layer_number"), &RadialForceField3D::get_collision_mask_value);
	ClassDB::bind_method(D_METHOD("set_continuous", "continuous"), &RadialForceField3D::set_continuous);
	ClassDB::bind_method(D_METHOD("is_continuous"), &RadialForceField3D::is_continuous);
	ClassDB::bind_method(D_METHOD("set_affect_rigid_bodies", "enabled"), &RadialForceField3D::set_affect_rigid_bodies);
	ClassDB::bind_method(D_METHOD("is_affecting_rigid_bodies"), &RadialForceField3D::is_affecting_rigid_bodies);
	ClassDB::bind_method(D_METHOD("set_affect_physical_bones", "enabled"), &RadialForceField3D::set_affect_physical_bones);
	ClassDB::bind_method(D_METHOD("is_affecting_physical_bones"), &RadialForceField3D::is_affecting_physical_bones);
	ClassDB::bind_method(D_METHOD("set_free_after_fire", "enabled"), &RadialForceField3D::set_free_after_fire);
	ClassDB::bind_method(D_METHOD("is_free_after_fire"), &RadialForceField3D::is_free_after_fire);
	ClassDB::bind_method(D_METHOD("set_max_bodies", "max_bodies"), &RadialForceField3D::set_max_bodies);
	ClassDB::bind_method(D_METHOD("get_max_bodies"), &RadialForceField3D::get_max_bodies);

	ClassDB::bind_method(D_METHOD("fire"), &RadialForceField3D::fire);

	ClassDB::bind_static_method("RadialForceField3D", D_METHOD("falloff_scale", "distance", "radius", "mode"), &RadialForceField3D::falloff_scale);
	ClassDB::bind_static_method("RadialForceField3D", D_METHOD("impulse_direction", "center", "body_position", "upward_bias"), &RadialForceField3D::impulse_direction);
	ClassDB::bind_static_method("RadialForceField3D", D_METHOD("occlusion_scale", "blocked", "attenuation"), &RadialForceField3D::occlusion_scale);
	ClassDB::bind_static_method("RadialForceField3D", D_METHOD("impulse_magnitude", "strength", "falloff", "mass", "mass_independent"), &RadialForceField3D::impulse_magnitude);

	ADD_SIGNAL(MethodInfo("fired", PropertyInfo(Variant::INT, "affected_count")));

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "radius", PROPERTY_HINT_RANGE, "0,100,0.01,or_greater,suffix:m"), "set_radius", "get_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "strength", PROPERTY_HINT_RANGE, "-1000,1000,0.01,or_less,or_greater"), "set_strength", "get_strength");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "falloff", PROPERTY_HINT_ENUM, "None,Linear,Quadratic"), "set_falloff", "get_falloff");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "upward_bias", PROPERTY_HINT_RANGE, "-2,2,0.01,or_less,or_greater"), "set_upward_bias", "get_upward_bias");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collision_mask", PROPERTY_HINT_LAYERS_3D_PHYSICS), "set_collision_mask", "get_collision_mask");
	ADD_GROUP("Blast Shielding", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "occlusion_mask", PROPERTY_HINT_LAYERS_3D_PHYSICS), "set_occlusion_mask", "get_occlusion_mask");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "occlusion_attenuation", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_occlusion_attenuation", "get_occlusion_attenuation");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_occlusion_rays", PROPERTY_HINT_RANGE, "1,64,1"), "set_max_occlusion_rays", "get_max_occlusion_rays");
	ADD_GROUP("Impulse", "");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "mass_independent"), "set_mass_independent", "is_mass_independent");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "continuous"), "set_continuous", "is_continuous");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "affect_rigid_bodies"), "set_affect_rigid_bodies", "is_affecting_rigid_bodies");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "affect_physical_bones"), "set_affect_physical_bones", "is_affecting_physical_bones");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "free_after_fire"), "set_free_after_fire", "is_free_after_fire");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_bodies", PROPERTY_HINT_RANGE, "1,1024,1"), "set_max_bodies", "get_max_bodies");

	BIND_ENUM_CONSTANT(FALLOFF_NONE);
	BIND_ENUM_CONSTANT(FALLOFF_LINEAR);
	BIND_ENUM_CONSTANT(FALLOFF_QUADRATIC);
}
