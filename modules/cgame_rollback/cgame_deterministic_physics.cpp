/**************************************************************************/
/*  cgame_deterministic_physics.cpp                                       */
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

#include "cgame_deterministic_physics.h"

#include "core/object/class_db.h"
#include "core/templates/hashfuncs.h"

#include <cstring>

using namespace CgamePhysicsCore;

bool CgameDeterministicPhysics::add_body(int p_id, Shape p_shape, double p_mass, const Vector3 &p_position, const Vector3 &p_size,
		const Quaternion &p_rotation, double p_friction, double p_restitution) {
	return core.add_body(p_id, p_shape == SHAPE_BOX ? CgamePhysicsCore::SHAPE_BOX : CgamePhysicsCore::SHAPE_SPHERE, p_mass, _to_v3(p_position), _to_v3(p_size),
			Quat(p_rotation.x, p_rotation.y, p_rotation.z, p_rotation.w), p_friction, p_restitution);
}

void CgameDeterministicPhysics::remove_body(int p_id) {
	core.remove_body(p_id);
}

bool CgameDeterministicPhysics::has_body(int p_id) const {
	return core.has_body(p_id);
}

PackedInt32Array CgameDeterministicPhysics::body_ids() const {
	PackedInt32Array out;
	for (const Body &b : core.bodies) {
		out.push_back(b.id);
	}
	return out;
}

int CgameDeterministicPhysics::body_count() const {
	return int(core.bodies.size());
}

Dictionary CgameDeterministicPhysics::get_body_info(int p_id) const {
	const Body *b = core.get_body(p_id);
	if (!b) {
		return Dictionary();
	}
	Dictionary d;
	d["id"] = b->id;
	d["shape"] = b->shape;
	d["mass"] = b->mass;
	d["size"] = _to_vector3(b->size);
	d["friction"] = b->friction;
	d["restitution"] = b->restitution;
	d["position"] = _to_vector3(b->pos);
	d["rotation"] = Quaternion(b->rot.x, b->rot.y, b->rot.z, b->rot.w);
	d["velocity"] = _to_vector3(b->vel);
	d["angular_velocity"] = _to_vector3(b->ang);
	d["asleep"] = b->asleep;
	d["static"] = b->is_static();
	return d;
}

Vector3 CgameDeterministicPhysics::get_position(int p_id) const {
	const Body *b = core.get_body(p_id);
	return b ? _to_vector3(b->pos) : Vector3();
}

Quaternion CgameDeterministicPhysics::get_rotation(int p_id) const {
	const Body *b = core.get_body(p_id);
	return b ? Quaternion(b->rot.x, b->rot.y, b->rot.z, b->rot.w) : Quaternion();
}

Vector3 CgameDeterministicPhysics::get_velocity(int p_id) const {
	const Body *b = core.get_body(p_id);
	return b ? _to_vector3(b->vel) : Vector3();
}

bool CgameDeterministicPhysics::is_asleep(int p_id) const {
	const Body *b = core.get_body(p_id);
	return b && b->asleep;
}

void CgameDeterministicPhysics::set_velocity(int p_id, const Vector3 &p_velocity) {
	core.set_velocity(p_id, _to_v3(p_velocity));
}

void CgameDeterministicPhysics::set_pose(int p_id, const Vector3 &p_position, const Quaternion &p_rotation) {
	core.set_pose(p_id, _to_v3(p_position), Quat(p_rotation.x, p_rotation.y, p_rotation.z, p_rotation.w));
}

// Forces apply to the next step() only and are not part of the snapshot.
void CgameDeterministicPhysics::apply_force(int p_id, const Vector3 &p_force) {
	core.apply_force(p_id, _to_v3(p_force));
}

void CgameDeterministicPhysics::apply_impulse(int p_id, const Vector3 &p_impulse) {
	core.apply_impulse(p_id, _to_v3(p_impulse));
}

int CgameDeterministicPhysics::sleeping_count() const {
	return core.sleeping_count();
}

PackedByteArray CgameDeterministicPhysics::snapshot() const {
	std::vector<uint8_t> bytes = core.snapshot();
	PackedByteArray out;
	out.resize(bytes.size());
	if (!bytes.empty()) {
		memcpy(out.ptrw(), bytes.data(), bytes.size());
	}
	return out;
}

bool CgameDeterministicPhysics::restore(const PackedByteArray &p_bytes) {
	return core.restore(p_bytes.ptr(), size_t(p_bytes.size()));
}

int64_t CgameDeterministicPhysics::checksum() const {
	std::vector<uint8_t> bytes = core.snapshot();
	return int64_t(hash_murmur3_buffer(bytes.data(), int(bytes.size())));
}

void CgameDeterministicPhysics::step(double p_dt) {
	core.step(p_dt);
}

// Ray cast against all bodies. Returns {"hit": bool, "id": int, "t": float, "point": Vector3}.
Dictionary CgameDeterministicPhysics::raycast(const Vector3 &p_origin, const Vector3 &p_dir, double p_max_dist) const {
	RayHit hit = core.raycast(_to_v3(p_origin), _to_v3(p_dir), p_max_dist);
	Dictionary d;
	d["hit"] = hit.hit;
	d["id"] = hit.id;
	d["t"] = hit.t;
	d["point"] = _to_vector3(hit.point);
	return d;
}

void CgameDeterministicPhysics::set_timeline(const Ref<CgamePhysicsTimeline> &p_timeline) {
	timeline = p_timeline;
	core.observer = timeline.is_valid() ? static_cast<StepObserver *>(timeline.ptr()) : nullptr;
}

CgameDeterministicPhysics::~CgameDeterministicPhysics() {
	core.observer = nullptr;
}

void CgameDeterministicPhysics::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_body", "id", "shape", "mass", "position", "size", "rotation", "friction", "restitution"), &CgameDeterministicPhysics::add_body, DEFVAL(Quaternion()), DEFVAL(0.5), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("remove_body", "id"), &CgameDeterministicPhysics::remove_body);
	ClassDB::bind_method(D_METHOD("has_body", "id"), &CgameDeterministicPhysics::has_body);
	ClassDB::bind_method(D_METHOD("body_ids"), &CgameDeterministicPhysics::body_ids);
	ClassDB::bind_method(D_METHOD("body_count"), &CgameDeterministicPhysics::body_count);
	ClassDB::bind_method(D_METHOD("get_body_info", "id"), &CgameDeterministicPhysics::get_body_info);
	ClassDB::bind_method(D_METHOD("get_position", "id"), &CgameDeterministicPhysics::get_position);
	ClassDB::bind_method(D_METHOD("get_rotation", "id"), &CgameDeterministicPhysics::get_rotation);
	ClassDB::bind_method(D_METHOD("get_velocity", "id"), &CgameDeterministicPhysics::get_velocity);
	ClassDB::bind_method(D_METHOD("is_asleep", "id"), &CgameDeterministicPhysics::is_asleep);
	ClassDB::bind_method(D_METHOD("set_velocity", "id", "velocity"), &CgameDeterministicPhysics::set_velocity);
	ClassDB::bind_method(D_METHOD("set_pose", "id", "position", "rotation"), &CgameDeterministicPhysics::set_pose);
	ClassDB::bind_method(D_METHOD("apply_force", "id", "force"), &CgameDeterministicPhysics::apply_force);
	ClassDB::bind_method(D_METHOD("apply_impulse", "id", "impulse"), &CgameDeterministicPhysics::apply_impulse);
	ClassDB::bind_method(D_METHOD("sleeping_count"), &CgameDeterministicPhysics::sleeping_count);
	ClassDB::bind_method(D_METHOD("snapshot"), &CgameDeterministicPhysics::snapshot);
	ClassDB::bind_method(D_METHOD("restore", "bytes"), &CgameDeterministicPhysics::restore);
	ClassDB::bind_method(D_METHOD("checksum"), &CgameDeterministicPhysics::checksum);
	ClassDB::bind_method(D_METHOD("step", "dt"), &CgameDeterministicPhysics::step);
	ClassDB::bind_method(D_METHOD("raycast", "origin", "direction", "max_distance"), &CgameDeterministicPhysics::raycast, DEFVAL(1000.0));

	ClassDB::bind_method(D_METHOD("set_gravity", "gravity"), &CgameDeterministicPhysics::set_gravity);
	ClassDB::bind_method(D_METHOD("get_gravity"), &CgameDeterministicPhysics::get_gravity);
	ClassDB::bind_method(D_METHOD("set_iterations", "iterations"), &CgameDeterministicPhysics::set_iterations);
	ClassDB::bind_method(D_METHOD("get_iterations"), &CgameDeterministicPhysics::get_iterations);
	ClassDB::bind_method(D_METHOD("get_step_count"), &CgameDeterministicPhysics::get_step_count);
	ClassDB::bind_method(D_METHOD("get_last_contact_count"), &CgameDeterministicPhysics::get_last_contact_count);
	ClassDB::bind_method(D_METHOD("get_last_pair_count"), &CgameDeterministicPhysics::get_last_pair_count);
	ClassDB::bind_method(D_METHOD("get_last_sleeping_count"), &CgameDeterministicPhysics::get_last_sleeping_count);
	ClassDB::bind_method(D_METHOD("set_timeline", "timeline"), &CgameDeterministicPhysics::set_timeline);
	ClassDB::bind_method(D_METHOD("get_timeline"), &CgameDeterministicPhysics::get_timeline);

	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "gravity"), "set_gravity", "get_gravity");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "iterations", PROPERTY_HINT_RANGE, "1,64,1,or_greater"), "set_iterations", "get_iterations");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "step_count"), "", "get_step_count");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "last_contact_count"), "", "get_last_contact_count");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "last_pair_count"), "", "get_last_pair_count");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "last_sleeping_count"), "", "get_last_sleeping_count");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "timeline", PROPERTY_HINT_RESOURCE_TYPE, "CgamePhysicsTimeline", PROPERTY_USAGE_NONE), "set_timeline", "get_timeline");

	BIND_ENUM_CONSTANT(SHAPE_SPHERE);
	BIND_ENUM_CONSTANT(SHAPE_BOX);
}
