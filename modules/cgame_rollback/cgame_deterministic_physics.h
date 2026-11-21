/**************************************************************************/
/*  cgame_deterministic_physics.h                                         */
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

#include "cgame_physics_core.h"
#include "cgame_physics_timeline.h"

#include "core/math/quaternion.h"
#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/variant/binder_common.h"
#include "core/variant/dictionary.h"

// Small deterministic rigid-body solver (spheres and boxes) with snapshot / restore, built to be stepped inside
// a rollback netcode loop. The simulation runs in IEEE double precision on a fixed operation order (see
// cgame_physics_core.h): bodies are kept sorted by id, contact pairs are sorted, nothing iterates a hash map,
// and the solver has a fixed iteration count with no warm starting, so snapshot() serializes the complete state.
//
// Conventions: mass <= 0 means static. A sphere uses size.x as radius; a box uses size as the half extents.
class CgameDeterministicPhysics : public RefCounted {
	GDCLASS(CgameDeterministicPhysics, RefCounted);

public:
	enum Shape {
		SHAPE_SPHERE = 0,
		SHAPE_BOX = 1,
	};

private:
	CgamePhysicsCore::World core;
	Ref<CgamePhysicsTimeline> timeline;

	static CgamePhysicsCore::V3 _to_v3(const Vector3 &p_v) { return CgamePhysicsCore::V3(p_v.x, p_v.y, p_v.z); }
	static Vector3 _to_vector3(const CgamePhysicsCore::V3 &p_v) { return Vector3(p_v.x, p_v.y, p_v.z); }

protected:
	static void _bind_methods();

public:
	CgamePhysicsCore::World &get_core() { return core; }
	const CgamePhysicsCore::World &get_core() const { return core; }

	bool add_body(int p_id, Shape p_shape, double p_mass, const Vector3 &p_position, const Vector3 &p_size,
			const Quaternion &p_rotation = Quaternion(), double p_friction = 0.5, double p_restitution = 0.0);
	void remove_body(int p_id);
	bool has_body(int p_id) const;
	PackedInt32Array body_ids() const;
	int body_count() const;
	Dictionary get_body_info(int p_id) const;
	Vector3 get_position(int p_id) const;
	Quaternion get_rotation(int p_id) const;
	Vector3 get_velocity(int p_id) const;
	bool is_asleep(int p_id) const;
	void set_velocity(int p_id, const Vector3 &p_velocity);
	void set_pose(int p_id, const Vector3 &p_position, const Quaternion &p_rotation);
	void apply_force(int p_id, const Vector3 &p_force);
	void apply_impulse(int p_id, const Vector3 &p_impulse);
	int sleeping_count() const;

	PackedByteArray snapshot() const;
	bool restore(const PackedByteArray &p_bytes);
	int64_t checksum() const;

	void step(double p_dt);
	Dictionary raycast(const Vector3 &p_origin, const Vector3 &p_dir, double p_max_dist = 1000.0) const;

	void set_gravity(const Vector3 &p_gravity) { core.gravity = _to_v3(p_gravity); }
	Vector3 get_gravity() const { return _to_vector3(core.gravity); }
	void set_iterations(int p_iterations) { core.iterations = MAX(p_iterations, 1); }
	int get_iterations() const { return core.iterations; }
	int64_t get_step_count() const { return core.step_count; }
	int get_last_contact_count() const { return core.last_contact_count; }
	int get_last_pair_count() const { return core.last_pair_count; }
	int get_last_sleeping_count() const { return core.last_sleeping_count; }

	void set_timeline(const Ref<CgamePhysicsTimeline> &p_timeline);
	Ref<CgamePhysicsTimeline> get_timeline() const { return timeline; }

	~CgameDeterministicPhysics();
};

VARIANT_ENUM_CAST(CgameDeterministicPhysics::Shape);
