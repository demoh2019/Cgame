/**************************************************************************/
/*  flock_3d.cpp                                                          */
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

#include "flock_3d.h"

#include "core/object/class_db.h"

Vector3 Flock3D::compute_steering(int p_index, const LocalVector<Vector3> &p_positions, const LocalVector<Vector3> &p_velocities, int p_count, const Vector3 &p_home, float p_neighbor_radius, float p_separation_radius, float p_cohesion, float p_alignment, float p_separation, float p_orbit) {
	const Vector3 self = p_positions[p_index];
	Vector3 center;
	Vector3 align;
	Vector3 separate;
	int neighbors = 0;
	const float neighbor_sq = p_neighbor_radius * p_neighbor_radius;
	for (int j = 0; j < p_count; j++) {
		if (j == p_index) {
			continue;
		}
		const Vector3 d = self - p_positions[j];
		const float dist_sq = d.length_squared();
		if (dist_sq >= neighbor_sq) {
			continue;
		}
		center += p_positions[j];
		align += p_velocities[j];
		neighbors++;
		if (dist_sq < p_separation_radius * p_separation_radius && dist_sq > 1e-6f) {
			separate += d / dist_sq;
		}
	}
	Vector3 force;
	if (neighbors > 0) {
		force += (center / float(neighbors) - self) * p_cohesion;
		force += (align / float(neighbors) - p_velocities[p_index]) * p_alignment;
	}
	force += separate * p_separation;
	// Soft home sphere: pull back horizontally plus a tangential swirl, hold altitude.
	Vector3 to_home = p_home - self;
	to_home.y = 0.0f;
	force += to_home * 0.04f;
	const Vector3 tangent(-to_home.z, 0.0f, to_home.x);
	if (tangent.length_squared() > 1e-6f) {
		force += tangent.normalized() * p_orbit;
	}
	force.y += (p_home.y - self.y) * 0.6f;
	return force;
}

void Flock3D::_reset_agents() {
	// Seeded procedural worlds must recreate the same flock after entering
	// a scene tree, changing quality/agent count or rebuilding a MultiMesh.
	// Unseeded legacy flocks retain their original evolving RNG behavior.
	if (seeded_simulation) {
		rng.seed(simulation_seed);
	}
	positions.resize(agent_count);
	velocities.resize(agent_count);
	for (int i = 0; i < agent_count; i++) {
		positions[i] = home_offset + Vector3(rng.random(-6.0f, 6.0f), rng.random(-2.0f, 2.0f), rng.random(-6.0f, 6.0f));
		Vector3 dir(rng.random(-1.0f, 1.0f), 0.0f, rng.random(-1.0f, 1.0f));
		if (dir.length_squared() < 1e-4f) {
			dir = Vector3(1, 0, 0);
		}
		velocities[i] = dir.normalized() * speed;
	}
}

void Flock3D::_update_process() {
	set_process_internal(active && agent_count > 0);
}

void Flock3D::step(double p_delta) {
	Ref<MultiMesh> mm = get_multimesh();
	if (mm.is_null() || agent_count <= 0) {
		return;
	}
	if ((int)positions.size() != agent_count) {
		_reset_agents();
	}
	const int count = MIN(agent_count, mm->get_instance_count());
	const float dt = float(MIN(p_delta, 0.1));
	const float max_speed = speed * 1.3f;
	const float min_speed = speed * 0.6f;
	for (int i = 0; i < count; i++) {
		Vector3 f = compute_steering(i, positions, velocities, count, home_offset, neighbor_radius, separation_radius, cohesion, alignment, separation, orbit);
		// Hard leash so a flock never drifts out of its home volume.
		const Vector3 offset = positions[i] - home_offset;
		if (offset.length() > home_radius) {
			f -= offset.normalized() * speed;
		}
		Vector3 v = velocities[i] + f * dt;
		const float len = v.length();
		if (len > max_speed) {
			v *= max_speed / len;
		} else if (len < min_speed) {
			v = (len > 1e-5f ? v / len : Vector3(1, 0, 0)) * min_speed;
		}
		velocities[i] = v;
		positions[i] += v * dt;

		const Vector3 forward = v.normalized();
		Basis basis;
		if (Math::abs(forward.y) < 0.98f) {
			basis = Basis::looking_at(forward, Vector3(0, 1, 0), true);
		}
		// Bank into turns.
		const float roll = CLAMP(-f.dot(basis.get_column(0)) * bank, -0.6f, 0.6f);
		basis = basis.rotated(forward, roll);
		basis.scale(Vector3(agent_scale, agent_scale, agent_scale));
		mm->set_instance_transform(i, Transform3D(basis, positions[i]));
	}
	mm->set_visible_instance_count(count);
}

void Flock3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY: {
			_reset_agents();
			_update_process();
		} break;
		case NOTIFICATION_INTERNAL_PROCESS: {
			if (is_visible_in_tree()) {
				step(get_process_delta_time());
			}
		} break;
	}
}

void Flock3D::set_agent_count(int p_count) {
	agent_count = CLAMP(p_count, 0, 1024);
	_reset_agents();
	_update_process();
}

int Flock3D::get_agent_count() const {
	return agent_count;
}

void Flock3D::set_simulation_seed(uint64_t p_seed) {
	if (seeded_simulation && simulation_seed == p_seed) {
		return;
	}
	seeded_simulation = true;
	simulation_seed = p_seed;
	_reset_agents();
}

void Flock3D::set_active(bool p_active) {
	active = p_active;
	_update_process();
}

bool Flock3D::is_active() const {
	return active;
}

#define FLOCK_FLOAT_ACCESSORS(m_name, m_min, m_max)       \
	void Flock3D::set_##m_name(float p_value) {           \
		m_name = CLAMP(p_value, float(m_min), float(m_max)); \
	}                                                     \
	float Flock3D::get_##m_name() const {                 \
		return m_name;                                    \
	}

FLOCK_FLOAT_ACCESSORS(speed, 0.0, 100.0)
FLOCK_FLOAT_ACCESSORS(cohesion, 0.0, 10.0)
FLOCK_FLOAT_ACCESSORS(alignment, 0.0, 10.0)
FLOCK_FLOAT_ACCESSORS(separation, 0.0, 50.0)
FLOCK_FLOAT_ACCESSORS(separation_radius, 0.0, 100.0)
FLOCK_FLOAT_ACCESSORS(neighbor_radius, 0.0, 200.0)
FLOCK_FLOAT_ACCESSORS(home_radius, 0.1, 10000.0)
FLOCK_FLOAT_ACCESSORS(orbit, -20.0, 20.0)
FLOCK_FLOAT_ACCESSORS(bank, 0.0, 1.0)
FLOCK_FLOAT_ACCESSORS(agent_scale, 0.001, 100.0)

#undef FLOCK_FLOAT_ACCESSORS

void Flock3D::set_home_offset(const Vector3 &p_offset) {
	home_offset = p_offset;
}

Vector3 Flock3D::get_home_offset() const {
	return home_offset;
}

void Flock3D::scatter_from(const Vector3 &p_global_point, float p_strength, float p_radius) {
	// Startle response: agents within the radius dart directly away, harder the closer they were.
	const Vector3 local = is_inside_tree() ? to_local(p_global_point) : p_global_point;
	const float radius = MAX(p_radius, 0.001f);
	for (uint32_t i = 0; i < positions.size(); i++) {
		Vector3 away = positions[i] - local;
		const float dist = away.length();
		if (dist >= radius) {
			continue;
		}
		if (dist < 1e-4f) {
			away = Vector3(1, 0, 0);
		}
		velocities[i] += away.normalized() * p_strength * (1.0f - dist / radius);
	}
}

Vector3 Flock3D::get_agent_position(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, (int)positions.size(), Vector3());
	return positions[p_index];
}

void Flock3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("step", "delta"), &Flock3D::step);
	ClassDB::bind_method(D_METHOD("get_agent_position", "index"), &Flock3D::get_agent_position);
	ClassDB::bind_method(D_METHOD("scatter_from", "global_point", "strength", "radius"), &Flock3D::scatter_from);
	ClassDB::bind_method(D_METHOD("set_agent_count", "count"), &Flock3D::set_agent_count);
	ClassDB::bind_method(D_METHOD("get_agent_count"), &Flock3D::get_agent_count);
	ClassDB::bind_method(D_METHOD("set_simulation_seed", "seed"), &Flock3D::set_simulation_seed);
	ClassDB::bind_method(D_METHOD("get_simulation_seed"), &Flock3D::get_simulation_seed);
	ClassDB::bind_method(D_METHOD("set_active", "active"), &Flock3D::set_active);
	ClassDB::bind_method(D_METHOD("is_active"), &Flock3D::is_active);
	ClassDB::bind_method(D_METHOD("set_speed", "speed"), &Flock3D::set_speed);
	ClassDB::bind_method(D_METHOD("get_speed"), &Flock3D::get_speed);
	ClassDB::bind_method(D_METHOD("set_cohesion", "value"), &Flock3D::set_cohesion);
	ClassDB::bind_method(D_METHOD("get_cohesion"), &Flock3D::get_cohesion);
	ClassDB::bind_method(D_METHOD("set_alignment", "value"), &Flock3D::set_alignment);
	ClassDB::bind_method(D_METHOD("get_alignment"), &Flock3D::get_alignment);
	ClassDB::bind_method(D_METHOD("set_separation", "value"), &Flock3D::set_separation);
	ClassDB::bind_method(D_METHOD("get_separation"), &Flock3D::get_separation);
	ClassDB::bind_method(D_METHOD("set_separation_radius", "radius"), &Flock3D::set_separation_radius);
	ClassDB::bind_method(D_METHOD("get_separation_radius"), &Flock3D::get_separation_radius);
	ClassDB::bind_method(D_METHOD("set_neighbor_radius", "radius"), &Flock3D::set_neighbor_radius);
	ClassDB::bind_method(D_METHOD("get_neighbor_radius"), &Flock3D::get_neighbor_radius);
	ClassDB::bind_method(D_METHOD("set_home_radius", "radius"), &Flock3D::set_home_radius);
	ClassDB::bind_method(D_METHOD("get_home_radius"), &Flock3D::get_home_radius);
	ClassDB::bind_method(D_METHOD("set_orbit", "value"), &Flock3D::set_orbit);
	ClassDB::bind_method(D_METHOD("get_orbit"), &Flock3D::get_orbit);
	ClassDB::bind_method(D_METHOD("set_bank", "value"), &Flock3D::set_bank);
	ClassDB::bind_method(D_METHOD("get_bank"), &Flock3D::get_bank);
	ClassDB::bind_method(D_METHOD("set_agent_scale", "scale"), &Flock3D::set_agent_scale);
	ClassDB::bind_method(D_METHOD("get_agent_scale"), &Flock3D::get_agent_scale);
	ClassDB::bind_method(D_METHOD("set_home_offset", "offset"), &Flock3D::set_home_offset);
	ClassDB::bind_method(D_METHOD("get_home_offset"), &Flock3D::get_home_offset);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "agent_count", PROPERTY_HINT_RANGE, "0,1024,1"), "set_agent_count", "get_agent_count");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "simulation_seed"), "set_simulation_seed", "get_simulation_seed");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "active"), "set_active", "is_active");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "speed", PROPERTY_HINT_RANGE, "0,100,0.01,suffix:m/s"), "set_speed", "get_speed");
	ADD_GROUP("Steering", "");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cohesion", PROPERTY_HINT_RANGE, "0,10,0.01"), "set_cohesion", "get_cohesion");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "alignment", PROPERTY_HINT_RANGE, "0,10,0.01"), "set_alignment", "get_alignment");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "separation", PROPERTY_HINT_RANGE, "0,50,0.01"), "set_separation", "get_separation");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "separation_radius", PROPERTY_HINT_RANGE, "0,100,0.01,suffix:m"), "set_separation_radius", "get_separation_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "neighbor_radius", PROPERTY_HINT_RANGE, "0,200,0.01,suffix:m"), "set_neighbor_radius", "get_neighbor_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "orbit", PROPERTY_HINT_RANGE, "-20,20,0.01"), "set_orbit", "get_orbit");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "bank", PROPERTY_HINT_RANGE, "0,1,0.001"), "set_bank", "get_bank");
	ADD_GROUP("Home", "");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "home_offset", PROPERTY_HINT_NONE, "suffix:m"), "set_home_offset", "get_home_offset");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "home_radius", PROPERTY_HINT_RANGE, "0.1,10000,0.1,suffix:m"), "set_home_radius", "get_home_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "agent_scale", PROPERTY_HINT_RANGE, "0.001,100,0.001"), "set_agent_scale", "get_agent_scale");
}

Flock3D::Flock3D() {
	rng.seed(simulation_seed);
}
