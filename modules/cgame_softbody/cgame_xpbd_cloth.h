/**************************************************************************/
/*  cgame_xpbd_cloth.h                                                    */
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
#include "core/math/transform_3d.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "core/templates/local_vector.h"
#include "core/variant/binder_common.h"
#include "core/variant/callable.h"

class ArrayMesh;

// XPBD cloth: distance (stretch + shear) and bending constraints with compliance, sub-stepping,
// sphere/capsule/plane collision, spatial-hash self-collision and tearing.
//
// Algorithm: Macklin, Muller, Chentanez, "XPBD: Position-Based Simulation of Compliant
// Constrained Dynamics" (2016). Structure follows Matthias Muller's "Ten Minute Physics" cloth
// demo (small-steps XPBD, one solver iteration per substep, hash-grid self-collision).
// Reference: https://github.com/matthias-research/pages (tenMinutePhysics), MIT License,
// Copyright (c) Matthias Muller / NVIDIA. This is a clean re-implementation from the published
// algorithm, not a verbatim copy.
//
// Grid layout: particle (i, j) sits at origin * (i * spacing, -j * spacing, 0), so row 0 is the
// top edge, local -Y runs down the cloth and local +Z is the front-face normal.
class CgameXPBDCloth : public RefCounted {
	GDCLASS(CgameXPBDCloth, RefCounted);

public:
	enum ConstraintKind {
		KIND_STRETCH = 0,
		KIND_SHEAR = 1,
		KIND_BEND = 2,
	};

	enum PinMode {
		PIN_FREE = 0,
		PIN_FIXED = 1,
		PIN_CALLABLE = 2,
		PIN_DRIVEN = 3,
	};

private:
	Vector3 gravity = Vector3(0, -9.81, 0);
	Vector3 wind;
	real_t drag = 0.1;
	real_t compliance_stretch = 0.0;
	real_t compliance_shear = 0.0001;
	real_t compliance_bend = 0.02;
	int iterations = 1;
	real_t collision_margin = 0.01;
	real_t friction = 0.2;
	real_t tear_threshold = 0.0;
	bool self_collision_enabled = false;
	real_t thickness = 0.04;

	int cols = 0;
	int rows = 0;
	Vector<Vector3> pos;
	Vector<Vector3> prev;
	Vector<Vector3> vel;
	Vector<Vector3> rest_pos;
	Vector<Vector2> uv;
	Vector<float> inv_mass;
	Vector<float> base_inv_mass;
	Vector<uint8_t> pin_mode;
	Vector<Vector3> pin_pos;
	Vector<Vector3> drive_from;
	Vector<Callable> pin_fn;

	Vector<int> ca;
	Vector<int> cb;
	Vector<int> cmid;
	Vector<float> crest;
	Vector<uint8_t> ckind;

	Vector<int> tris;
	Vector<int> tri_cell;

	Vector<Vector3> sphere_c;
	Vector<float> sphere_r;
	Vector<Vector3> cap_a;
	Vector<Vector3> cap_b;
	Vector<float> cap_r;
	Vector<Vector3> plane_n;
	Vector<float> plane_d;

	int torn_count = 0;

	HashMap<uint64_t, LocalVector<int>> grid;

	void _add_constraint(int p_a, int p_b, int p_kind, int p_mid);
	void _integrate(real_t p_sdt, real_t p_drive_t);
	void _solve_constraints(real_t p_sdt);
	void _collide();
	void _solve_self_collision();
	void _tear();
	bool _cell_torn(int p_cell, const HashSet<int64_t> &p_torn) const;
	_FORCE_INLINE_ int64_t _edge_key(int p_a, int p_b) const { return int64_t(MIN(p_a, p_b)) * int64_t(pos.size()) + int64_t(MAX(p_a, p_b)); }
	_FORCE_INLINE_ static uint64_t _cell_key(int64_t p_cx, int64_t p_cy, int64_t p_cz) {
		return ((uint64_t(p_cx) & 0x1FFFFF) << 42) | ((uint64_t(p_cy) & 0x1FFFFF) << 21) | (uint64_t(p_cz) & 0x1FFFFF);
	}

protected:
	static void _bind_methods();

public:
	void set_gravity(const Vector3 &p_gravity) { gravity = p_gravity; }
	Vector3 get_gravity() const { return gravity; }
	void set_wind(const Vector3 &p_wind) { wind = p_wind; }
	Vector3 get_wind() const { return wind; }
	void set_drag(real_t p_drag) { drag = p_drag; }
	real_t get_drag() const { return drag; }
	void set_compliance_stretch(real_t p_value) { compliance_stretch = p_value; }
	real_t get_compliance_stretch() const { return compliance_stretch; }
	void set_compliance_shear(real_t p_value) { compliance_shear = p_value; }
	real_t get_compliance_shear() const { return compliance_shear; }
	void set_compliance_bend(real_t p_value) { compliance_bend = p_value; }
	real_t get_compliance_bend() const { return compliance_bend; }
	void set_iterations(int p_iterations) { iterations = MAX(p_iterations, 1); }
	int get_iterations() const { return iterations; }
	void set_collision_margin(real_t p_margin) { collision_margin = p_margin; }
	real_t get_collision_margin() const { return collision_margin; }
	void set_friction(real_t p_friction) { friction = p_friction; }
	real_t get_friction() const { return friction; }
	void set_tear_threshold(real_t p_threshold) { tear_threshold = p_threshold; }
	real_t get_tear_threshold() const { return tear_threshold; }
	void set_self_collision_enabled(bool p_enabled) { self_collision_enabled = p_enabled; }
	bool is_self_collision_enabled() const { return self_collision_enabled; }
	void set_thickness(real_t p_thickness) { thickness = p_thickness; }
	real_t get_thickness() const { return thickness; }
	int get_torn_count() const { return torn_count; }

	void setup_grid(int p_width_cells, int p_height_cells, real_t p_spacing, const Transform3D &p_origin, real_t p_particle_mass = 1.0);

	int particle_count() const { return pos.size(); }
	int constraint_count() const { return ca.size(); }
	int stretch_constraint_count() const;
	int columns() const { return cols; }
	int row_count() const { return rows; }
	int index_of(int p_i, int p_j) const { return p_j * cols + p_i; }
	real_t max_stretch_error() const;

	void pin(int p_index, const Vector3 &p_world_pos);
	void attach(int p_index, const Callable &p_target_fn);
	void drive(int p_index, const Vector3 &p_world_pos);
	void unpin(int p_index);
	bool is_pinned(int p_index) const;

	int add_sphere(const Vector3 &p_center, real_t p_radius);
	void set_sphere_center(int p_index, const Vector3 &p_center);
	int add_capsule(const Vector3 &p_a, const Vector3 &p_b, real_t p_radius);
	void set_capsule(int p_index, const Vector3 &p_a, const Vector3 &p_b);
	int add_plane(const Vector3 &p_normal, real_t p_offset);
	void clear_colliders();

	void set_particle(int p_index, const Vector3 &p_world_pos);
	Vector<Vector3> positions() const { return pos; }
	Vector<Vector3> velocities() const { return vel; }
	Vector<int> triangles() const { return tris; }
	Vector<Vector2> uvs() const { return uv; }

	void step(real_t p_dt, int p_substeps = 8);
	Vector<Vector3> normals() const;
	Ref<ArrayMesh> build_mesh(uint64_t p_flags = 0) const;

	// Fast path for ClothInstance3D: writes vertex positions (3 x float32 each) and octahedral
	// normals (2 x uint16 each) of all particles, transformed by p_xform, into caller buffers.
	void write_vertex_buffers(const Transform3D &p_xform, uint8_t *r_positions, uint8_t *r_normals, AABB &r_aabb) const;

	CgameXPBDCloth() {}
};

VARIANT_ENUM_CAST(CgameXPBDCloth::ConstraintKind);
