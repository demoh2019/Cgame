/**************************************************************************/
/*  cgame_physics_core.h                                                  */
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

// Self-contained deterministic rigid-body solver core (spheres and boxes).
//
// This file deliberately depends on the C++ standard library only (no engine types, no real_t) so the
// simulation always runs in IEEE double precision with a fixed operation order, independent of whether the
// engine is built with single or double precision vectors. Determinism rules:
//  - bodies live in an array sorted by id; the sorted sweep breaks ties by id;
//  - contact pairs are sorted by (id_a, id_b);
//  - there is no hash-map iteration anywhere in the step;
//  - the solver has a fixed iteration count and no warm starting (contacts are rebuilt every step), so the
//    complete simulation state is exactly what snapshot() serializes.
//
// Design sources (ideas and algorithms only, independent 3D implementation, no code copied):
//  - Erin Catto, Box2D-Lite (MIT): sequential-impulse contact solver with accumulated impulses,
//    Baumgarte-style position bias, friction clamped by the normal impulse, SAT box-box with incident-face
//    clipping.
//  - Glenn Fiedler, "Networked Physics" / "Deterministic Lockstep" (snapshot, restore, resimulate).
//  - Christer Ericson, "Real-Time Collision Detection" (closest points between lines, slab ray test).
//
// Conventions: mass <= 0 means static. A sphere uses size.x as radius; a box uses size as the half extents.
// Contact normals point from body a to body b (a.id < b.id).

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <utility>
#include <vector>

namespace CgamePhysicsCore {

struct V3 {
	double x = 0.0, y = 0.0, z = 0.0;

	V3() {}
	V3(double p_x, double p_y, double p_z) :
			x(p_x), y(p_y), z(p_z) {}

	double &operator[](int p_i) { return p_i == 0 ? x : (p_i == 1 ? y : z); }
	double operator[](int p_i) const { return p_i == 0 ? x : (p_i == 1 ? y : z); }

	V3 operator+(const V3 &p_v) const { return V3(x + p_v.x, y + p_v.y, z + p_v.z); }
	V3 operator-(const V3 &p_v) const { return V3(x - p_v.x, y - p_v.y, z - p_v.z); }
	V3 operator*(double p_s) const { return V3(x * p_s, y * p_s, z * p_s); }
	V3 operator/(double p_s) const { return V3(x / p_s, y / p_s, z / p_s); }
	V3 operator-() const { return V3(-x, -y, -z); }
	V3 &operator+=(const V3 &p_v) {
		x += p_v.x;
		y += p_v.y;
		z += p_v.z;
		return *this;
	}
	V3 &operator-=(const V3 &p_v) {
		x -= p_v.x;
		y -= p_v.y;
		z -= p_v.z;
		return *this;
	}
	V3 &operator*=(double p_s) {
		x *= p_s;
		y *= p_s;
		z *= p_s;
		return *this;
	}
	bool operator==(const V3 &p_v) const { return x == p_v.x && y == p_v.y && z == p_v.z; }
	bool operator!=(const V3 &p_v) const { return !(*this == p_v); }

	double dot(const V3 &p_v) const { return x * p_v.x + y * p_v.y + z * p_v.z; }
	V3 cross(const V3 &p_v) const { return V3(y * p_v.z - z * p_v.y, z * p_v.x - x * p_v.z, x * p_v.y - y * p_v.x); }
	double length_squared() const { return dot(*this); }
	double length() const { return std::sqrt(length_squared()); }
	V3 normalized() const {
		double l = length();
		return l > 0.0 ? *this / l : V3();
	}
	V3 abs() const { return V3(std::fabs(x), std::fabs(y), std::fabs(z)); }
	V3 lerp(const V3 &p_to, double p_t) const { return V3(x + (p_to.x - x) * p_t, y + (p_to.y - y) * p_t, z + (p_to.z - z) * p_t); }
};

struct Quat {
	double x = 0.0, y = 0.0, z = 0.0, w = 1.0;

	Quat() {}
	Quat(double p_x, double p_y, double p_z, double p_w) :
			x(p_x), y(p_y), z(p_z), w(p_w) {}

	static Quat from_axis_angle(const V3 &p_axis, double p_angle);
	double dot(const Quat &p_q) const { return x * p_q.x + y * p_q.y + z * p_q.z + w * p_q.w; }
	double length_squared() const { return dot(*this); }
	Quat normalized() const;
	Quat operator*(const Quat &p_q) const;
	Quat operator-() const { return Quat(-x, -y, -z, -w); }
	Quat slerp(const Quat &p_to, double p_t) const;
};

// Row-major 3x3 matrix.
struct M3 {
	double m[3][3] = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } };

	static M3 diagonal(const V3 &p_d);
	static M3 from_quat(const Quat &p_q);
	M3 transposed() const;
	V3 column(int p_c) const { return V3(m[0][p_c], m[1][p_c], m[2][p_c]); }
	V3 operator*(const V3 &p_v) const;
	M3 operator*(const M3 &p_o) const;
};

enum Shape {
	SHAPE_SPHERE = 0,
	SHAPE_BOX = 1,
};

struct Body {
	int32_t id = 0;
	int shape = SHAPE_SPHERE;
	double mass = 0.0;
	double inv_mass = 0.0;
	V3 size = V3(1, 1, 1);
	double friction = 0.5;
	double restitution = 0.0;
	V3 pos;
	Quat rot;
	V3 vel;
	V3 ang;
	bool asleep = false;
	double sleep_t = 0.0;
	// Transient (not serialized).
	V3 inv_i_local;
	M3 inv_iw;
	V3 force;
	V3 torque;
	V3 lo;
	V3 hi;
	int index = 0;

	bool is_static() const { return inv_mass == 0.0; }
	void setup_mass();
	void update_derived();
};

struct Contact {
	Body *a = nullptr;
	Body *b = nullptr;
	V3 p, n;
	double depth = 0.0;
	V3 ra, rb, t1, t2;
	double mn = 0.0, m1 = 0.0, m2 = 0.0;
	double target = 0.0;
	double mu = 0.0;
	double jn = 0.0, j1 = 0.0, j2 = 0.0;
};

struct StepStats {
	int contacts = 0;
	int pairs = 0;
	int sleeping = 0;
	int bodies = 0;
};

// Optional profiling hooks; never part of the simulation state.
class StepObserver {
public:
	virtual ~StepObserver() {}
	virtual void on_step_begin(int64_t p_step) = 0;
	virtual void on_phase_begin(const char *p_phase) = 0;
	virtual void on_phase_end() = 0;
	virtual void on_step_end(const StepStats &p_stats) = 0;
};

struct RayHit {
	bool hit = false;
	int32_t id = -1;
	double t = 0.0;
	V3 point;
};

class World {
public:
	static constexpr int32_t SNAPSHOT_VERSION = 1;
	static constexpr size_t SNAPSHOT_HEADER_SIZE = 16;
	static constexpr size_t SNAPSHOT_BODY_SIZE = 4 + 1 + 1 + 20 * 8;
	static constexpr double BAUMGARTE = 0.2;
	static constexpr double SLOP = 0.005;
	static constexpr double MAX_BIAS_SPEED = 2.0;
	static constexpr double RESTITUTION_THRESHOLD = 1.0;
	static constexpr double SLEEP_LIN_SQ = 0.02;
	static constexpr double SLEEP_ANG_SQ = 0.05;
	static constexpr double SLEEP_TIME = 0.5;
	static constexpr double LINEAR_DAMPING = 0.01;
	static constexpr double ANGULAR_DAMPING = 0.05;
	static constexpr double EDGE_BIAS = 0.005;
	static constexpr int MAX_CONTACTS_PER_PAIR = 8;

	V3 gravity = V3(0.0, -9.81, 0.0);
	int iterations = 16;
	StepObserver *observer = nullptr;
	int64_t step_count = 0;

	std::vector<Body> bodies; // Sorted by id.
	int last_contact_count = 0;
	int last_pair_count = 0;
	int last_sleeping_count = 0;

	bool add_body(int32_t p_id, int p_shape, double p_mass, const V3 &p_position, const V3 &p_size,
			const Quat &p_rotation, double p_friction, double p_restitution);
	bool remove_body(int32_t p_id);
	bool has_body(int32_t p_id) const { return find(p_id) >= 0; }
	int find(int32_t p_id) const;
	Body *get_body(int32_t p_id);
	const Body *get_body(int32_t p_id) const;
	int sleeping_count() const;

	void set_velocity(int32_t p_id, const V3 &p_v);
	void set_pose(int32_t p_id, const V3 &p_position, const Quat &p_rotation);
	void apply_force(int32_t p_id, const V3 &p_f);
	void apply_impulse(int32_t p_id, const V3 &p_impulse);

	std::vector<uint8_t> snapshot() const;
	bool restore(const uint8_t *p_bytes, size_t p_size);

	void step(double p_dt);
	RayHit raycast(const V3 &p_origin, const V3 &p_dir, double p_max_dist) const;

private:
	std::vector<Contact> contacts;

	static void wake(Body &p_b);
	void phase_begin(const char *p_name);
	void phase_end();
	void broadphase(std::vector<std::pair<int, int>> &r_pairs) const;
	void collide(Body &p_a, Body &p_b);
	void emit(Body &p_a, Body &p_b, const V3 &p_p, const V3 &p_n, double p_depth);
	void sphere_sphere(Body &p_a, Body &p_b);
	void sphere_box(Body &p_s, Body &p_box, bool p_sphere_first);
	void box_box(Body &p_a, Body &p_b);
	void solve(double p_dt);
	void update_sleep(double p_dt);
};

} // namespace CgamePhysicsCore
