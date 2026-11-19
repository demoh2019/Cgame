/**************************************************************************/
/*  rope_3d.cpp                                             */
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

#include "rope_3d.h"

#include "core/config/engine.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "scene/3d/mesh_instance_3d.h"
#include "scene/3d/physics/collision_shape_3d.h"
#include "scene/3d/physics/joints/pin_joint_3d.h"
#include "scene/3d/physics/rigid_body_3d.h"
#include "scene/3d/rope_geometry.h"
#include "scene/resources/3d/capsule_shape_3d.h"
#include "scene/resources/mesh.h"

void Rope3D::_queue_rebuild() {
	built = false;
	if (!is_inside_tree() || rebuild_queued) {
		return;
	}
	rebuild_queued = true;
	callable_mp(this, &Rope3D::rebuild).call_deferred();
}

void Rope3D::_clear() {
	for (RigidBody3D *body : bodies) {
		if (body) {
			body->get_parent() ? body->get_parent()->remove_child(body) : void();
			memdelete(body);
		}
	}
	bodies.clear();
	PinJoint3D *all[2] = { start_joint, end_joint };
	for (PinJoint3D *joint : all) {
		if (joint) {
			joint->get_parent() ? joint->get_parent()->remove_child(joint) : void();
			memdelete(joint);
		}
	}
	start_joint = nullptr;
	end_joint = nullptr;
	for (PinJoint3D *joint : joints) {
		if (joint) {
			joint->get_parent() ? joint->get_parent()->remove_child(joint) : void();
			memdelete(joint);
		}
	}
	joints.clear();
	if (mesh_instance) {
		mesh_instance->get_parent() ? mesh_instance->get_parent()->remove_child(mesh_instance) : void();
		memdelete(mesh_instance);
		mesh_instance = nullptr;
	}
	built = false;
}

PinJoint3D *Rope3D::_make_joint(const Vector3 &p_position, Node *p_a, Node *p_b) {
	PinJoint3D *joint = memnew(PinJoint3D);
	add_child(joint, false, INTERNAL_MODE_BACK);
	joint->set_global_position(p_position);
	joint->set_solver_priority(solver_priority);
	joint->set_exclude_nodes_from_collision(true);
	if (p_a) {
		joint->set_node_a(joint->get_path_to(p_a));
	}
	if (p_b) {
		joint->set_node_b(joint->get_path_to(p_b));
	}
	if (break_force > 0.0) {
		joint->set_break_force(break_force);
	}
	return joint;
}

void Rope3D::rebuild() {
	rebuild_queued = false;
	_clear();
	if (!is_inside_tree() || Engine::get_singleton()->is_editor_hint()) {
		return;
	}
	const Vector3 start = get_global_position();
	const Vector3 end = to_global(end_point);
	const real_t distance = start.distance_to(end);
	if (!(distance > CMP_EPSILON) && !(length > 0.0)) {
		return;
	}
	const real_t rope_length = length > 0.0 ? length : distance;
	Vector<Vector3> points;
	if (!RopeGeometry::layout_points(start, end, rope_length, segments, Vector3(0, -1, 0), points)) {
		return;
	}

	segment_length = rope_length / real_t(segments);
	Ref<CapsuleShape3D> shape;
	shape.instantiate();
	shape->set_radius(radius);
	segment_length = MAX(segment_length, radius * real_t(2.0) + real_t(0.001));
	shape->set_height(segment_length);
	const real_t segment_mass = MAX(mass / real_t(segments), real_t(0.0001));

	const Transform3D to_global_inverse = get_global_transform().affine_inverse();
	for (int i = 0; i < segments; i++) {
		RigidBody3D *body = memnew(RigidBody3D);
		body->set_name(vformat("Segment%d", i));
		body->set_mass(segment_mass);
		body->set_linear_damp(damping);
		body->set_angular_damp(damping);
		body->set_collision_layer(collision_layer);
		body->set_collision_mask(collision_mask);
		CollisionShape3D *collider = memnew(CollisionShape3D);
		collider->set_shape(shape);
		body->add_child(collider);

		const Vector3 a = points[i];
		const Vector3 b = points[i + 1];
		const Vector3 axis = (b - a).normalized();
		// The capsule runs along local Y.
		Basis basis;
		const Vector3 up = Vector3(0, 1, 0);
		const real_t dot = CLAMP(up.dot(axis), real_t(-1.0), real_t(1.0));
		if (dot > real_t(0.99999)) {
			basis = Basis();
		} else if (dot < real_t(-0.99999)) {
			basis = Basis(Vector3(1, 0, 0), real_t(Math::PI));
		} else {
			basis = Basis(up.cross(axis).normalized(), Math::acos(dot));
		}
		// Position the body before it enters the tree: the physics server creates it with this
		// transform, and the joints created below measure their anchors against it.
		body->set_transform(to_global_inverse * Transform3D(basis, (a + b) * real_t(0.5)));
		add_child(body, false, INTERNAL_MODE_BACK);
		bodies.push_back(body);
	}

	// Segments never collide with their neighbours through the joint's exclusion; keep the rest of
	// the rope from colliding with itself unless asked to.
	if (!self_collision) {
		for (uint32_t i = 0; i < bodies.size(); i++) {
			for (uint32_t j = i + 1; j < bodies.size(); j++) {
				bodies[i]->add_collision_exception_with(bodies[j]);
				bodies[j]->add_collision_exception_with(bodies[i]);
			}
		}
	}

	for (int i = 1; i < segments; i++) {
		joints.push_back(_make_joint(points[i], bodies[i - 1], bodies[i]));
		const int index = int(joints.size()) - 1;
		joints[index]->connect("broken", callable_mp(this, &Rope3D::_on_joint_broken).bind(i));
	}

	Node *a_node = node_a.is_empty() ? nullptr : get_node_or_null(node_a);
	Node *b_node = node_b.is_empty() ? nullptr : get_node_or_null(node_b);
	// An end is attached to its body when one is given; otherwise it is pinned to the world if
	// pin_start / pin_end say so, and left free if not.
	// The rope reaches into the bodies it is attached to; those contacts would only fight the joint.
	for (Node *attached : { a_node, b_node }) {
		if (PhysicsBody3D *attached_body = Object::cast_to<PhysicsBody3D>(attached)) {
			for (RigidBody3D *segment : bodies) {
				segment->add_collision_exception_with(attached_body);
				attached_body->add_collision_exception_with(segment);
			}
		}
	}
	if (pin_start || a_node) {
		start_joint = _make_joint(points[0], a_node, bodies[0]);
	}
	if (pin_end || b_node) {
		end_joint = _make_joint(points[segments], bodies[segments - 1], b_node);
	}

	if (rope_visible) {
		mesh_instance = memnew(MeshInstance3D);
		mesh_instance->set_as_top_level(true);
		add_child(mesh_instance, false, INTERNAL_MODE_BACK);
		mesh_instance->set_global_transform(Transform3D());
		mesh_instance->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_ON);
	}
	built = true;
	set_process_internal(true);
	_update_mesh();
}

void Rope3D::_segment_ends(int p_index, Vector3 &r_start, Vector3 &r_end) const {
	const Transform3D transform = bodies[p_index]->get_global_transform();
	r_start = transform.xform(Vector3(0, -segment_length * real_t(0.5), 0));
	r_end = transform.xform(Vector3(0, segment_length * real_t(0.5), 0));
}

void Rope3D::_update_mesh() {
	if (!mesh_instance || bodies.is_empty()) {
		return;
	}
	const PackedVector3Array points_array = get_points();
	Vector<Vector3> points;
	for (const Vector3 &point : points_array) {
		points.push_back(point);
	}
	RopeGeometry::TubeMesh tube;
	if (!RopeGeometry::build_tube(points, radius, radial_segments, MAX(radius * real_t(4.0), real_t(0.1)), tube)) {
		return;
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = tube.vertices;
	arrays[Mesh::ARRAY_NORMAL] = tube.normals;
	arrays[Mesh::ARRAY_TEX_UV] = tube.uvs;
	arrays[Mesh::ARRAY_INDEX] = tube.indices;
	Ref<ArrayMesh> mesh = mesh_instance->get_mesh();
	if (mesh.is_null()) {
		mesh.instantiate();
		mesh_instance->set_mesh(mesh);
	}
	mesh->clear_surfaces();
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	if (material.is_valid()) {
		mesh->surface_set_material(0, material);
	}
}

PackedVector3Array Rope3D::get_points() const {
	PackedVector3Array points;
	if (bodies.is_empty()) {
		return points;
	}
	points.resize(bodies.size() + 1);
	Vector3 *out = points.ptrw();
	Vector3 start;
	Vector3 end;
	_segment_ends(0, start, end);
	out[0] = start;
	for (uint32_t i = 1; i < bodies.size(); i++) {
		Vector3 previous_start;
		Vector3 previous_end;
		_segment_ends(i - 1, previous_start, previous_end);
		Vector3 next_start;
		Vector3 next_end;
		_segment_ends(i, next_start, next_end);
		out[i] = (previous_end + next_start) * real_t(0.5);
	}
	_segment_ends(bodies.size() - 1, start, end);
	out[bodies.size()] = end;
	return points;
}

real_t Rope3D::get_current_length() const {
	const PackedVector3Array points = get_points();
	real_t total = 0.0;
	for (int i = 1; i < points.size(); i++) {
		total += points[i].distance_to(points[i - 1]);
	}
	return total;
}

RigidBody3D *Rope3D::get_segment(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, int(bodies.size()), nullptr);
	return bodies[p_index];
}

real_t Rope3D::get_start_tension() const {
	return start_joint ? start_joint->get_reaction_force().length() : real_t(0.0);
}

real_t Rope3D::get_end_tension() const {
	return end_joint ? end_joint->get_reaction_force().length() : real_t(0.0);
}

bool Rope3D::is_broken() const {
	for (const PinJoint3D *joint : joints) {
		if (joint && joint->is_broken()) {
			return true;
		}
	}
	return (start_joint && start_joint->is_broken()) || (end_joint && end_joint->is_broken());
}

void Rope3D::_on_joint_broken(int p_index) {
	emit_signal(SNAME("broken"), p_index);
}

void Rope3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE: {
			_queue_rebuild();
		} break;
		case NOTIFICATION_EXIT_TREE: {
			set_process_internal(false);
			_clear();
		} break;
		case NOTIFICATION_INTERNAL_PROCESS: {
			_update_mesh();
		} break;
	}
}

#define ROPE_SETTER(m_name, m_type, m_member, m_expr) \
	void Rope3D::m_name(m_type p_value) {              \
		const m_type value = m_expr;                    \
		if (m_member == value) {                        \
			return;                                     \
		}                                               \
		m_member = value;                               \
		_queue_rebuild();                               \
	}

ROPE_SETTER(set_node_a, const NodePath &, node_a, p_value)
ROPE_SETTER(set_node_b, const NodePath &, node_b, p_value)
ROPE_SETTER(set_end_point, const Vector3 &, end_point, p_value)
ROPE_SETTER(set_length, real_t, length, MAX(p_value, real_t(0.0)))
ROPE_SETTER(set_segments, int, segments, CLAMP(p_value, 1, 256))
ROPE_SETTER(set_mass, real_t, mass, MAX(p_value, real_t(0.001)))
ROPE_SETTER(set_radius, real_t, radius, MAX(p_value, real_t(0.001)))
ROPE_SETTER(set_damping, real_t, damping, MAX(p_value, real_t(0.0)))
ROPE_SETTER(set_pin_start, bool, pin_start, p_value)
ROPE_SETTER(set_pin_end, bool, pin_end, p_value)
ROPE_SETTER(set_self_collision, bool, self_collision, p_value)
ROPE_SETTER(set_collision_layer, uint32_t, collision_layer, p_value)
ROPE_SETTER(set_collision_mask, uint32_t, collision_mask, p_value)
ROPE_SETTER(set_break_force, real_t, break_force, MAX(p_value, real_t(0.0)))
ROPE_SETTER(set_solver_priority, int, solver_priority, CLAMP(p_value, 1, 8))
ROPE_SETTER(set_rope_visible, bool, rope_visible, p_value)
ROPE_SETTER(set_radial_segments, int, radial_segments, CLAMP(p_value, 3, 32))

void Rope3D::set_material(const Ref<Material> &p_material) {
	material = p_material;
	if (mesh_instance) {
		Ref<ArrayMesh> mesh = mesh_instance->get_mesh();
		if (mesh.is_valid() && mesh->get_surface_count() > 0) {
			mesh->surface_set_material(0, material);
		}
	}
}

void Rope3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_node_a", "path"), &Rope3D::set_node_a);
	ClassDB::bind_method(D_METHOD("get_node_a"), &Rope3D::get_node_a);
	ClassDB::bind_method(D_METHOD("set_node_b", "path"), &Rope3D::set_node_b);
	ClassDB::bind_method(D_METHOD("get_node_b"), &Rope3D::get_node_b);
	ClassDB::bind_method(D_METHOD("set_end_point", "point"), &Rope3D::set_end_point);
	ClassDB::bind_method(D_METHOD("get_end_point"), &Rope3D::get_end_point);
	ClassDB::bind_method(D_METHOD("set_length", "length"), &Rope3D::set_length);
	ClassDB::bind_method(D_METHOD("get_length"), &Rope3D::get_length);
	ClassDB::bind_method(D_METHOD("set_segments", "segments"), &Rope3D::set_segments);
	ClassDB::bind_method(D_METHOD("get_segments"), &Rope3D::get_segments);
	ClassDB::bind_method(D_METHOD("set_mass", "mass"), &Rope3D::set_mass);
	ClassDB::bind_method(D_METHOD("get_mass"), &Rope3D::get_mass);
	ClassDB::bind_method(D_METHOD("set_radius", "radius"), &Rope3D::set_radius);
	ClassDB::bind_method(D_METHOD("get_radius"), &Rope3D::get_radius);
	ClassDB::bind_method(D_METHOD("set_damping", "damping"), &Rope3D::set_damping);
	ClassDB::bind_method(D_METHOD("get_damping"), &Rope3D::get_damping);
	ClassDB::bind_method(D_METHOD("set_pin_start", "pin"), &Rope3D::set_pin_start);
	ClassDB::bind_method(D_METHOD("is_pin_start"), &Rope3D::is_pin_start);
	ClassDB::bind_method(D_METHOD("set_pin_end", "pin"), &Rope3D::set_pin_end);
	ClassDB::bind_method(D_METHOD("is_pin_end"), &Rope3D::is_pin_end);
	ClassDB::bind_method(D_METHOD("set_self_collision", "enabled"), &Rope3D::set_self_collision);
	ClassDB::bind_method(D_METHOD("is_self_collision"), &Rope3D::is_self_collision);
	ClassDB::bind_method(D_METHOD("set_collision_layer", "layer"), &Rope3D::set_collision_layer);
	ClassDB::bind_method(D_METHOD("get_collision_layer"), &Rope3D::get_collision_layer);
	ClassDB::bind_method(D_METHOD("set_collision_mask", "mask"), &Rope3D::set_collision_mask);
	ClassDB::bind_method(D_METHOD("get_collision_mask"), &Rope3D::get_collision_mask);
	ClassDB::bind_method(D_METHOD("set_break_force", "force"), &Rope3D::set_break_force);
	ClassDB::bind_method(D_METHOD("get_break_force"), &Rope3D::get_break_force);
	ClassDB::bind_method(D_METHOD("set_solver_priority", "priority"), &Rope3D::set_solver_priority);
	ClassDB::bind_method(D_METHOD("get_solver_priority"), &Rope3D::get_solver_priority);
	ClassDB::bind_method(D_METHOD("set_rope_visible", "visible"), &Rope3D::set_rope_visible);
	ClassDB::bind_method(D_METHOD("is_rope_visible"), &Rope3D::is_rope_visible);
	ClassDB::bind_method(D_METHOD("set_radial_segments", "count"), &Rope3D::set_radial_segments);
	ClassDB::bind_method(D_METHOD("get_radial_segments"), &Rope3D::get_radial_segments);
	ClassDB::bind_method(D_METHOD("set_material", "material"), &Rope3D::set_material);
	ClassDB::bind_method(D_METHOD("get_material"), &Rope3D::get_material);

	ClassDB::bind_method(D_METHOD("get_segment_count"), &Rope3D::get_segment_count);
	ClassDB::bind_method(D_METHOD("get_segment", "index"), &Rope3D::get_segment);
	ClassDB::bind_method(D_METHOD("get_points"), &Rope3D::get_points);
	ClassDB::bind_method(D_METHOD("get_current_length"), &Rope3D::get_current_length);
	ClassDB::bind_method(D_METHOD("get_start_tension"), &Rope3D::get_start_tension);
	ClassDB::bind_method(D_METHOD("get_end_tension"), &Rope3D::get_end_tension);
	ClassDB::bind_method(D_METHOD("is_broken"), &Rope3D::is_broken);
	ClassDB::bind_method(D_METHOD("rebuild"), &Rope3D::rebuild);

	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "node_a", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "PhysicsBody3D"), "set_node_a", "get_node_a");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "node_b", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "PhysicsBody3D"), "set_node_b", "get_node_b");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "end_point", PROPERTY_HINT_NONE, "suffix:m"), "set_end_point", "get_end_point");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "length", PROPERTY_HINT_RANGE, "0,1000,0.01,or_greater,suffix:m"), "set_length", "get_length");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "segments", PROPERTY_HINT_RANGE, "1,256,1"), "set_segments", "get_segments");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "mass", PROPERTY_HINT_RANGE, "0.001,1000,0.001,or_greater,suffix:kg"), "set_mass", "get_mass");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "radius", PROPERTY_HINT_RANGE, "0.001,10,0.001,or_greater,suffix:m"), "set_radius", "get_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "damping", PROPERTY_HINT_RANGE, "0,10,0.01,or_greater"), "set_damping", "get_damping");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "pin_start"), "set_pin_start", "is_pin_start");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "pin_end"), "set_pin_end", "is_pin_end");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "self_collision"), "set_self_collision", "is_self_collision");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "break_force", PROPERTY_HINT_RANGE, "0,100000,0.01,or_greater,suffix:N"), "set_break_force", "get_break_force");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "solver_priority", PROPERTY_HINT_RANGE, "1,8,1"), "set_solver_priority", "get_solver_priority");
	ADD_GROUP("Collision", "collision_");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collision_layer", PROPERTY_HINT_LAYERS_3D_PHYSICS), "set_collision_layer", "get_collision_layer");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collision_mask", PROPERTY_HINT_LAYERS_3D_PHYSICS), "set_collision_mask", "get_collision_mask");
	ADD_GROUP("Appearance", "");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "rope_visible"), "set_rope_visible", "is_rope_visible");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "radial_segments", PROPERTY_HINT_RANGE, "3,32,1"), "set_radial_segments", "get_radial_segments");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "material", PROPERTY_HINT_RESOURCE_TYPE, "BaseMaterial3D,ShaderMaterial"), "set_material", "get_material");

	ADD_SIGNAL(MethodInfo("broken", PropertyInfo(Variant::INT, "joint_index")));
}
