/**************************************************************************/
/*  destructible_body_3d.cpp                                             */
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

#include "destructible_body_3d.h"

#include "core/math/random_pcg.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "scene/3d/convex_fracture.h"
#include "scene/3d/mesh_instance_3d.h"
#include "scene/3d/physics/collision_shape_3d.h"
#include "scene/main/scene_tree.h"
#include "scene/main/timer.h"
#include "scene/resources/3d/box_shape_3d.h"
#include "scene/resources/3d/convex_polygon_shape_3d.h"
#include "scene/resources/mesh.h"
#include "servers/physics_3d/physics_server_3d.h"

bool DestructibleBody3D::_collect_points(Vector<Vector3> &r_points) const {
	r_points.clear();
	for (int i = 0; i < get_child_count(); i++) {
		const CollisionShape3D *collider = Object::cast_to<CollisionShape3D>(get_child(i));
		if (!collider || collider->is_disabled() || collider->get_shape().is_null()) {
			continue;
		}
		const Transform3D transform = collider->get_transform();
		if (const BoxShape3D *box = Object::cast_to<BoxShape3D>(collider->get_shape().ptr())) {
			const Vector3 half = box->get_size() * real_t(0.5);
			for (int corner = 0; corner < 8; corner++) {
				r_points.push_back(transform.xform(Vector3((corner & 1) ? half.x : -half.x, (corner & 2) ? half.y : -half.y, (corner & 4) ? half.z : -half.z)));
			}
			return true;
		}
		if (const ConvexPolygonShape3D *convex = Object::cast_to<ConvexPolygonShape3D>(collider->get_shape().ptr())) {
			for (const Vector3 &point : convex->get_points()) {
				r_points.push_back(transform.xform(point));
			}
			return r_points.size() >= 4;
		}
	}
	return false;
}

Ref<Material> DestructibleBody3D::_find_outer_material() const {
	for (int i = 0; i < get_child_count(); i++) {
		const MeshInstance3D *mesh_instance = Object::cast_to<MeshInstance3D>(get_child(i));
		if (!mesh_instance) {
			continue;
		}
		if (mesh_instance->get_material_override().is_valid()) {
			return mesh_instance->get_material_override();
		}
		Ref<Mesh> mesh = mesh_instance->get_mesh();
		if (mesh.is_valid() && mesh->get_surface_count() > 0) {
			return mesh_instance->get_active_material(0);
		}
	}
	return Ref<Material>();
}

namespace {
struct PolygonMesh {
	PackedVector3Array vertices;
	PackedVector3Array normals;
	PackedVector2Array uvs;
};
} // namespace

// Triangles of a convex polygon, clockwise seen from outside (Godot's front face), fan from the first vertex.
static void append_face(const ConvexFracture::Face &p_face, const Vector3 &p_origin, real_t p_uv_scale, PolygonMesh &r_mesh) {
	const uint32_t count = p_face.vertices.size();
	if (count < 3) {
		return;
	}
	Vector3 center;
	for (const Vector3 &vertex : p_face.vertices) {
		center += vertex;
	}
	center /= real_t(count);
	const Vector3 normal = p_face.plane.normal;
	const Vector3 u_axis = (p_face.vertices[0] - center).normalized();
	const Vector3 v_axis = normal.cross(u_axis);
	LocalVector<Pair<real_t, Vector3>> ordered;
	for (const Vector3 &vertex : p_face.vertices) {
		const Vector3 offset = vertex - center;
		ordered.push_back(Pair<real_t, Vector3>(Math::atan2(offset.dot(v_axis), offset.dot(u_axis)), vertex));
	}
	for (uint32_t i = 1; i < ordered.size(); i++) {
		Pair<real_t, Vector3> item = ordered[i];
		int32_t j = int32_t(i) - 1;
		while (j >= 0 && ordered[j].first > item.first) {
			ordered[j + 1] = ordered[j];
			j--;
		}
		ordered[j + 1] = item;
	}
	// Angles increase counter-clockwise around the normal, i.e. counter-clockwise from outside, so
	// reverse the fan to get the clockwise winding Godot wants for front faces.
	// Planar UVs from the two axes least aligned with the normal.
	const Vector3 absolute = normal.abs();
	int drop = 0;
	if (absolute.y > absolute.x && absolute.y >= absolute.z) {
		drop = 1;
	} else if (absolute.z > absolute.x && absolute.z > absolute.y) {
		drop = 2;
	}
	auto uv_of = [&](const Vector3 &p_point) {
		const Vector3 shifted = p_point + p_origin; // Back into the space of the whole body.
		switch (drop) {
			case 0:
				return Vector2(shifted.y, shifted.z) * p_uv_scale;
			case 1:
				return Vector2(shifted.x, shifted.z) * p_uv_scale;
			default:
				return Vector2(shifted.x, shifted.y) * p_uv_scale;
		}
	};
	for (uint32_t i = 1; i + 1 < ordered.size(); i++) {
		const Vector3 *triangle[3] = { &ordered[0].second, &ordered[i + 1].second, &ordered[i].second };
		for (int k = 0; k < 3; k++) {
			r_mesh.vertices.push_back(*triangle[k] - p_origin);
			r_mesh.normals.push_back(normal);
			r_mesh.uvs.push_back(uv_of(*triangle[k] - p_origin));
		}
	}
}

Array DestructibleBody3D::fracture(const Vector3 &p_global_point, const Vector3 &p_impulse) {
	return _fracture_now(p_global_point, p_impulse);
}

Array DestructibleBody3D::_fracture_now(const Vector3 &p_global_point, const Vector3 &p_impulse) {
	Array debris_bodies;
	if (broken || !is_inside_tree() || !get_parent()) {
		return debris_bodies;
	}
	Vector<Vector3> points;
	Vector<Plane> planes;
	if (!_collect_points(points) || !ConvexFracture::planes_from_points(points, planes)) {
		WARN_PRINT("DestructibleBody3D needs a BoxShape3D or ConvexPolygonShape3D child to break.");
		return debris_bodies;
	}

	RandomPCG random;
	if (random_seed != 0) {
		random.seed(uint64_t(random_seed));
	} else {
		random.randomize();
	}
	const Transform3D body_transform = get_global_transform();
	const Vector3 impact_local = body_transform.affine_inverse().xform(p_global_point);
	LocalVector<Vector3> seeds;
	ConvexFracture::generate_seeds(planes, piece_count, impact_local, seed_concentration, random, seeds);
	LocalVector<ConvexFracture::Piece> pieces;
	if (!ConvexFracture::fracture(planes, seeds, pieces) || pieces.is_empty()) {
		return debris_bodies;
	}
	broken = true;

	real_t total_volume = 0.0;
	Vector3 center_of_mass_local;
	for (const ConvexFracture::Piece &piece : pieces) {
		total_volume += piece.volume;
		center_of_mass_local += piece.centroid * piece.volume;
	}
	center_of_mass_local /= total_volume;
	const AABB bounds = ConvexFracture::bounds_of_planes(planes);
	const real_t body_size = MAX(bounds.size.length(), real_t(0.001));
	const real_t uv_scale = real_t(1.0) / MAX(MAX(bounds.size.x, bounds.size.y), MAX(bounds.size.z, real_t(0.001)));

	const Vector3 body_velocity = get_linear_velocity();
	const Vector3 body_angular = get_angular_velocity();
	const Vector3 center_of_mass_global = body_transform.xform(center_of_mass_local);
	const real_t body_mass = get_mass();
	Ref<Material> outer = _find_outer_material();
	Ref<Material> inner = inner_material.is_valid() ? inner_material : outer;

	// Velocities: the rigid motion of the body plus a scatter away from the impact. The scatter is
	// made to carry no net momentum, so the debris keeps the momentum the body had.
	LocalVector<Vector3> velocities;
	LocalVector<real_t> masses;
	Vector3 scatter_momentum;
	real_t mass_sum = 0.0;
	for (const ConvexFracture::Piece &piece : pieces) {
		const real_t mass = body_mass * piece.volume / total_volume;
		const Vector3 centroid_global = body_transform.xform(piece.centroid);
		Vector3 away = centroid_global - p_global_point;
		real_t distance = away.length();
		away = distance > real_t(1e-4) ? away / distance : Vector3(random.randf() - 0.5, random.randf() - 0.5, random.randf() - 0.5).normalized();
		// Pieces near the impact are thrown the hardest.
		const real_t falloff = real_t(1.0) - CLAMP(distance / (body_size * real_t(1.5)), real_t(0.0), real_t(0.8));
		const Vector3 scatter = away * scatter_speed * falloff;
		scatter_momentum += scatter * mass;
		mass_sum += mass;
		masses.push_back(mass);
		velocities.push_back(scatter);
	}
	const Vector3 scatter_drift = mass_sum > 0.0 ? scatter_momentum / mass_sum : Vector3();
	const Vector3 impulse_velocity = body_mass > 0.0 ? p_impulse / body_mass : Vector3();

	Node *parent = get_parent();
	const Transform3D parent_inverse = parent->is_class("Node3D") ? Object::cast_to<Node3D>(parent)->get_global_transform().affine_inverse() : Transform3D();
	for (uint32_t i = 0; i < pieces.size(); i++) {
		const ConvexFracture::Piece &piece = pieces[i];
		RigidBody3D *debris = memnew(RigidBody3D);
		debris->set_name(vformat("%s_Debris%d", get_name(), int(i)));
		debris->set_mass(MAX(masses[i], real_t(0.0001)));
		debris->set_collision_layer(get_collision_layer());
		debris->set_collision_mask(get_collision_mask());
		debris->set_physics_material_override(get_physics_material_override());
		debris->set_linear_damp(get_linear_damp());
		debris->set_angular_damp(get_angular_damp());
		debris->set_use_continuous_collision_detection(is_using_continuous_collision_detection());

		// Collision: the convex hull of the piece, around its own center.
		Ref<ConvexPolygonShape3D> shape;
		shape.instantiate();
		Vector<Vector3> shape_points;
		for (const Vector3 &point : piece.points) {
			shape_points.push_back(point - piece.centroid);
		}
		shape->set_points(shape_points);
		CollisionShape3D *collider = memnew(CollisionShape3D);
		collider->set_shape(shape);
		debris->add_child(collider);

		// Visuals: outer surface and the new cut surface get their own material.
		PolygonMesh outer_mesh;
		PolygonMesh inner_mesh;
		for (const ConvexFracture::Face &face : piece.faces) {
			append_face(face, piece.centroid, uv_scale, face.cut ? inner_mesh : outer_mesh);
		}
		Ref<ArrayMesh> mesh;
		mesh.instantiate();
		for (int surface = 0; surface < 2; surface++) {
			const PolygonMesh &source = surface == 0 ? outer_mesh : inner_mesh;
			if (source.vertices.is_empty()) {
				continue;
			}
			Array arrays;
			arrays.resize(Mesh::ARRAY_MAX);
			arrays[Mesh::ARRAY_VERTEX] = source.vertices;
			arrays[Mesh::ARRAY_NORMAL] = source.normals;
			arrays[Mesh::ARRAY_TEX_UV] = source.uvs;
			mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
			const Ref<Material> &material = surface == 0 ? outer : inner;
			if (material.is_valid()) {
				mesh->surface_set_material(mesh->get_surface_count() - 1, material);
			}
		}
		MeshInstance3D *visual = memnew(MeshInstance3D);
		visual->set_mesh(mesh);
		debris->add_child(visual);

		// Position and motion, set before the debris enters the tree so physics creates it there.
		const Transform3D global(body_transform.basis, body_transform.xform(piece.centroid));
		debris->set_transform(parent_inverse * global);
		const Vector3 offset = global.origin - center_of_mass_global;
		debris->set_linear_velocity(body_velocity + body_angular.cross(offset) + velocities[i] - scatter_drift + impulse_velocity);
		debris->set_angular_velocity(body_angular);
		parent->add_child(debris);
		debris_bodies.push_back(debris);

		if (debris_lifetime > 0.0 && get_tree()) {
			get_tree()->create_timer(debris_lifetime)->connect("timeout", callable_mp((Node *)debris, &Node::queue_free), CONNECT_ONE_SHOT);
		}
	}

	emit_signal(SNAME("fractured"), debris_bodies);
	queue_free();
	return debris_bodies;
}

void DestructibleBody3D::_deferred_fracture() {
	break_queued = false;
	_fracture_now(pending_point, pending_impulse);
}

void DestructibleBody3D::apply_damage(real_t p_amount, const Vector3 &p_global_point) {
	if (broken || health <= 0.0 || !(p_amount > 0.0)) {
		return;
	}
	health = MAX(health - p_amount, real_t(0.0));
	if (health <= 0.0) {
		_fracture_now(p_global_point, Vector3());
		// health stays at 0 so the body reads as destroyed.
	}
}

void DestructibleBody3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE: {
			set_physics_process_internal(true);
			has_previous_velocity = false;
		} break;

		case NOTIFICATION_INTERNAL_PHYSICS_PROCESS: {
			if (broken || break_queued) {
				return;
			}
			const Vector3 velocity = get_linear_velocity();
			if (break_impulse > 0.0 && has_previous_velocity) {
				// What changed the velocity besides gravity was an impact: impulse = m * dv.
				const real_t dt = real_t(get_physics_process_delta_time());
				Vector3 gravity;
				if (get_world_3d().is_valid()) {
					PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
					const RID space = get_world_3d()->get_space();
					gravity = Vector3(ps->area_get_param(space, PS3DE::AREA_PARAM_GRAVITY_VECTOR)) * real_t(ps->area_get_param(space, PS3DE::AREA_PARAM_GRAVITY)) * get_gravity_scale();
				}
				const Vector3 delta = velocity - previous_velocity - gravity * dt;
				const real_t impulse = get_mass() * delta.length();
				if (impulse >= break_impulse) {
					// The contact lies on the side the velocity change pushes away from.
					Vector3 direction = delta.is_zero_approx() ? Vector3(0, 1, 0) : delta.normalized();
					pending_point = get_global_position() - direction * MIN(get_global_transform().basis.get_scale().length(), real_t(1.0)) * real_t(0.5);
					pending_impulse = Vector3();
					break_queued = true;
					callable_mp(this, &DestructibleBody3D::_deferred_fracture).call_deferred();
				}
			}
			previous_velocity = velocity;
			has_previous_velocity = true;
		} break;
	}
}

void DestructibleBody3D::set_piece_count(int p_count) {
	piece_count = CLAMP(p_count, 2, 64);
}

void DestructibleBody3D::set_break_impulse(real_t p_impulse) {
	break_impulse = MAX(p_impulse, real_t(0.0));
}

void DestructibleBody3D::set_health(real_t p_health) {
	health = MAX(p_health, real_t(0.0));
}

void DestructibleBody3D::set_seed_concentration(real_t p_value) {
	seed_concentration = MAX(p_value, real_t(0.0));
}

void DestructibleBody3D::set_scatter_speed(real_t p_speed) {
	scatter_speed = MAX(p_speed, real_t(0.0));
}

void DestructibleBody3D::set_debris_lifetime(real_t p_seconds) {
	debris_lifetime = MAX(p_seconds, real_t(0.0));
}

void DestructibleBody3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_piece_count", "count"), &DestructibleBody3D::set_piece_count);
	ClassDB::bind_method(D_METHOD("get_piece_count"), &DestructibleBody3D::get_piece_count);
	ClassDB::bind_method(D_METHOD("set_break_impulse", "impulse"), &DestructibleBody3D::set_break_impulse);
	ClassDB::bind_method(D_METHOD("get_break_impulse"), &DestructibleBody3D::get_break_impulse);
	ClassDB::bind_method(D_METHOD("set_health", "health"), &DestructibleBody3D::set_health);
	ClassDB::bind_method(D_METHOD("get_health"), &DestructibleBody3D::get_health);
	ClassDB::bind_method(D_METHOD("set_seed_concentration", "value"), &DestructibleBody3D::set_seed_concentration);
	ClassDB::bind_method(D_METHOD("get_seed_concentration"), &DestructibleBody3D::get_seed_concentration);
	ClassDB::bind_method(D_METHOD("set_scatter_speed", "speed"), &DestructibleBody3D::set_scatter_speed);
	ClassDB::bind_method(D_METHOD("get_scatter_speed"), &DestructibleBody3D::get_scatter_speed);
	ClassDB::bind_method(D_METHOD("set_debris_lifetime", "seconds"), &DestructibleBody3D::set_debris_lifetime);
	ClassDB::bind_method(D_METHOD("get_debris_lifetime"), &DestructibleBody3D::get_debris_lifetime);
	ClassDB::bind_method(D_METHOD("set_inner_material", "material"), &DestructibleBody3D::set_inner_material);
	ClassDB::bind_method(D_METHOD("get_inner_material"), &DestructibleBody3D::get_inner_material);
	ClassDB::bind_method(D_METHOD("set_random_seed", "seed"), &DestructibleBody3D::set_random_seed);
	ClassDB::bind_method(D_METHOD("get_random_seed"), &DestructibleBody3D::get_random_seed);

	ClassDB::bind_method(D_METHOD("fracture", "global_point", "impulse"), &DestructibleBody3D::fracture, DEFVAL(Vector3()));
	ClassDB::bind_method(D_METHOD("apply_damage", "amount", "global_point"), &DestructibleBody3D::apply_damage);
	ClassDB::bind_method(D_METHOD("is_broken"), &DestructibleBody3D::is_broken);

	ADD_GROUP("Destruction", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "piece_count", PROPERTY_HINT_RANGE, "2,64,1"), "set_piece_count", "get_piece_count");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "break_impulse", PROPERTY_HINT_RANGE, U"0,100000,0.1,or_greater,suffix:N\u22C5s"), "set_break_impulse", "get_break_impulse");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "health", PROPERTY_HINT_RANGE, "0,100000,0.1,or_greater"), "set_health", "get_health");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "seed_concentration", PROPERTY_HINT_RANGE, "0,10,0.1,or_greater"), "set_seed_concentration", "get_seed_concentration");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "scatter_speed", PROPERTY_HINT_RANGE, "0,100,0.1,or_greater,suffix:m/s"), "set_scatter_speed", "get_scatter_speed");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "debris_lifetime", PROPERTY_HINT_RANGE, "0,600,0.1,or_greater,suffix:s"), "set_debris_lifetime", "get_debris_lifetime");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "inner_material", PROPERTY_HINT_RESOURCE_TYPE, "BaseMaterial3D,ShaderMaterial"), "set_inner_material", "get_inner_material");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "random_seed"), "set_random_seed", "get_random_seed");

	ADD_SIGNAL(MethodInfo("fractured", PropertyInfo(Variant::ARRAY, "debris")));
}
