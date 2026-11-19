/**************************************************************************/
/*  rope_3d.h                                             */
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
#include "scene/resources/material.h"

class MeshInstance3D;
class PinJoint3D;
class RigidBody3D;

// A rope, chain or cable made of capsule shaped rigid bodies joined by ball joints. Because it is
// built from ordinary rigid bodies and joints it collides with the world, can be pulled by other
// bodies, can carry loads, and works with every 3D physics backend.
class Rope3D : public Node3D {
	GDCLASS(Rope3D, Node3D);

private:
	NodePath node_a;
	NodePath node_b;
	Vector3 end_point = Vector3(0, -5, 0);
	real_t length = 0.0;
	int segments = 12;
	real_t mass = 1.0;
	real_t radius = 0.05;
	real_t damping = 0.5;
	bool pin_start = true;
	bool pin_end = false;
	bool self_collision = false;
	uint32_t collision_layer = 1;
	uint32_t collision_mask = 1;
	real_t break_force = 0.0;
	int solver_priority = 4;
	bool rope_visible = true;
	int radial_segments = 6;
	Ref<Material> material;

	LocalVector<RigidBody3D *> bodies;
	PinJoint3D *start_joint = nullptr;
	PinJoint3D *end_joint = nullptr;
	LocalVector<PinJoint3D *> joints; // Between consecutive segments.
	MeshInstance3D *mesh_instance = nullptr;
	bool rebuild_queued = false;
	bool built = false;
	real_t segment_length = 0.0; // Length of the capsule of one segment.

	void _queue_rebuild();
	void _rebuild();
	void _clear();
	void _update_mesh();
	void _on_joint_broken(int p_index);
	PinJoint3D *_make_joint(const Vector3 &p_position, Node *p_a, Node *p_b);
	void _segment_ends(int p_index, Vector3 &r_start, Vector3 &r_end) const;

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	void set_node_a(const NodePath &p_path);
	NodePath get_node_a() const { return node_a; }
	void set_node_b(const NodePath &p_path);
	NodePath get_node_b() const { return node_b; }
	void set_end_point(const Vector3 &p_point);
	Vector3 get_end_point() const { return end_point; }
	void set_length(real_t p_length);
	real_t get_length() const { return length; }
	void set_segments(int p_segments);
	int get_segments() const { return segments; }
	void set_mass(real_t p_mass);
	real_t get_mass() const { return mass; }
	void set_radius(real_t p_radius);
	real_t get_radius() const { return radius; }
	void set_damping(real_t p_damping);
	real_t get_damping() const { return damping; }
	void set_pin_start(bool p_pin);
	bool is_pin_start() const { return pin_start; }
	void set_pin_end(bool p_pin);
	bool is_pin_end() const { return pin_end; }
	void set_self_collision(bool p_enabled);
	bool is_self_collision() const { return self_collision; }
	void set_collision_layer(uint32_t p_layer);
	uint32_t get_collision_layer() const { return collision_layer; }
	void set_collision_mask(uint32_t p_mask);
	uint32_t get_collision_mask() const { return collision_mask; }
	void set_break_force(real_t p_force);
	real_t get_break_force() const { return break_force; }
	void set_solver_priority(int p_priority);
	int get_solver_priority() const { return solver_priority; }
	void set_rope_visible(bool p_visible);
	bool is_rope_visible() const { return rope_visible; }
	void set_radial_segments(int p_count);
	int get_radial_segments() const { return radial_segments; }
	void set_material(const Ref<Material> &p_material);
	Ref<Material> get_material() const { return material; }

	int get_segment_count() const { return int(bodies.size()); }
	RigidBody3D *get_segment(int p_index) const;
	// Points of the rope in world space: segments + 1 positions from the start to the end.
	PackedVector3Array get_points() const;
	// Current length of the rope as laid out by the physics (stretches under load).
	real_t get_current_length() const;
	// Force the first / last joint exerts, as a measure of how hard the rope is being pulled.
	// Only available with Godot Physics; zero otherwise.
	real_t get_start_tension() const;
	real_t get_end_tension() const;
	// Whether any joint of the rope has been torn by break_force.
	bool is_broken() const;
	void rebuild();

	Rope3D() {}
	~Rope3D() {}
};
