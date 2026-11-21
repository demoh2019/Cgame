/**************************************************************************/
/*  cgame_physics_core.cpp                                                */
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

#include "cgame_physics_core.h"

#include <algorithm>
#include <cstring>
#include <limits>
#include <utility>

namespace CgamePhysicsCore {

// --- math ------------------------------------------------------------------------------------

Quat Quat::from_axis_angle(const V3 &p_axis, double p_angle) {
	double d = p_axis.length();
	if (d == 0.0) {
		return Quat(0.0, 0.0, 0.0, 0.0);
	}
	double sin_angle = std::sin(p_angle * 0.5);
	double cos_angle = std::cos(p_angle * 0.5);
	double s = sin_angle / d;
	return Quat(p_axis.x * s, p_axis.y * s, p_axis.z * s, cos_angle);
}

Quat Quat::normalized() const {
	double l = std::sqrt(length_squared());
	if (l == 0.0) {
		return Quat();
	}
	return Quat(x / l, y / l, z / l, w / l);
}

Quat Quat::operator*(const Quat &p_q) const {
	return Quat(
			w * p_q.x + x * p_q.w + y * p_q.z - z * p_q.y,
			w * p_q.y + y * p_q.w + z * p_q.x - x * p_q.z,
			w * p_q.z + z * p_q.w + x * p_q.y - y * p_q.x,
			w * p_q.w - x * p_q.x - y * p_q.y - z * p_q.z);
}

Quat Quat::slerp(const Quat &p_to, double p_t) const {
	Quat to1 = p_to;
	double cosom = dot(p_to);
	if (cosom < 0.0) {
		cosom = -cosom;
		to1 = -p_to;
	}
	double scale0, scale1;
	if ((1.0 - cosom) > 1e-6) {
		double omega = std::acos(cosom);
		double sinom = std::sin(omega);
		scale0 = std::sin((1.0 - p_t) * omega) / sinom;
		scale1 = std::sin(p_t * omega) / sinom;
	} else {
		scale0 = 1.0 - p_t;
		scale1 = p_t;
	}
	return Quat(scale0 * x + scale1 * to1.x, scale0 * y + scale1 * to1.y, scale0 * z + scale1 * to1.z, scale0 * w + scale1 * to1.w);
}

M3 M3::diagonal(const V3 &p_d) {
	M3 r;
	r.m[0][0] = p_d.x;
	r.m[1][1] = p_d.y;
	r.m[2][2] = p_d.z;
	return r;
}

M3 M3::from_quat(const Quat &p_q) {
	double d = p_q.length_squared();
	M3 r;
	if (d == 0.0) {
		r.m[0][0] = r.m[1][1] = r.m[2][2] = 1.0;
		return r;
	}
	double s = 2.0 / d;
	double xs = p_q.x * s, ys = p_q.y * s, zs = p_q.z * s;
	double wx = p_q.w * xs, wy = p_q.w * ys, wz = p_q.w * zs;
	double xx = p_q.x * xs, xy = p_q.x * ys, xz = p_q.x * zs;
	double yy = p_q.y * ys, yz = p_q.y * zs, zz = p_q.z * zs;
	r.m[0][0] = 1.0 - (yy + zz);
	r.m[0][1] = xy - wz;
	r.m[0][2] = xz + wy;
	r.m[1][0] = xy + wz;
	r.m[1][1] = 1.0 - (xx + zz);
	r.m[1][2] = yz - wx;
	r.m[2][0] = xz - wy;
	r.m[2][1] = yz + wx;
	r.m[2][2] = 1.0 - (xx + yy);
	return r;
}

M3 M3::transposed() const {
	M3 r;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			r.m[i][j] = m[j][i];
		}
	}
	return r;
}

V3 M3::operator*(const V3 &p_v) const {
	return V3(
			m[0][0] * p_v.x + m[0][1] * p_v.y + m[0][2] * p_v.z,
			m[1][0] * p_v.x + m[1][1] * p_v.y + m[1][2] * p_v.z,
			m[2][0] * p_v.x + m[2][1] * p_v.y + m[2][2] * p_v.z);
}

M3 M3::operator*(const M3 &p_o) const {
	M3 r;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			r.m[i][j] = m[i][0] * p_o.m[0][j] + m[i][1] * p_o.m[1][j] + m[i][2] * p_o.m[2][j];
		}
	}
	return r;
}

// --- body ------------------------------------------------------------------------------------

void Body::setup_mass() {
	if (mass <= 0.0) {
		inv_mass = 0.0;
		inv_i_local = V3();
		return;
	}
	inv_mass = 1.0 / mass;
	if (shape == SHAPE_SPHERE) {
		double i = 0.4 * mass * size.x * size.x;
		inv_i_local = V3(1.0 / i, 1.0 / i, 1.0 / i);
	} else {
		double k = mass / 3.0;
		inv_i_local = V3(1.0 / (k * (size.y * size.y + size.z * size.z)),
				1.0 / (k * (size.x * size.x + size.z * size.z)),
				1.0 / (k * (size.x * size.x + size.y * size.y)));
	}
}

void Body::update_derived() {
	if (inv_mass == 0.0) {
		inv_iw = M3();
	} else {
		M3 r = M3::from_quat(rot);
		inv_iw = r * M3::diagonal(inv_i_local) * r.transposed();
	}
	if (shape == SHAPE_SPHERE) {
		V3 e(size.x, size.x, size.x);
		lo = pos - e;
		hi = pos + e;
	} else {
		M3 r2 = M3::from_quat(rot);
		V3 ax = r2.column(0).abs();
		V3 ay = r2.column(1).abs();
		V3 az = r2.column(2).abs();
		V3 e2 = ax * size.x + ay * size.y + az * size.z;
		lo = pos - e2;
		hi = pos + e2;
	}
}

// --- body management -------------------------------------------------------------------------

bool World::add_body(int32_t p_id, int p_shape, double p_mass, const V3 &p_position, const V3 &p_size,
		const Quat &p_rotation, double p_friction, double p_restitution) {
	if (has_body(p_id)) {
		return false;
	}
	Body b;
	b.id = p_id;
	b.shape = p_shape == SHAPE_BOX ? SHAPE_BOX : SHAPE_SPHERE;
	b.mass = p_mass > 0.0 ? p_mass : 0.0;
	b.size = p_size;
	b.pos = p_position;
	b.rot = p_rotation.normalized();
	b.friction = p_friction;
	b.restitution = p_restitution;
	b.setup_mass();
	b.update_derived();
	size_t i = 0;
	while (i < bodies.size() && bodies[i].id < b.id) {
		i++;
	}
	bodies.insert(bodies.begin() + i, b);
	return true;
}

bool World::remove_body(int32_t p_id) {
	int i = find(p_id);
	if (i < 0) {
		return false;
	}
	bodies.erase(bodies.begin() + i);
	return true;
}

int World::find(int32_t p_id) const {
	int lo_i = 0;
	int hi_i = int(bodies.size()) - 1;
	while (lo_i <= hi_i) {
		int mid = lo_i + ((hi_i - lo_i) >> 1);
		int32_t mid_id = bodies[mid].id;
		if (mid_id == p_id) {
			return mid;
		}
		if (mid_id < p_id) {
			lo_i = mid + 1;
		} else {
			hi_i = mid - 1;
		}
	}
	return -1;
}

Body *World::get_body(int32_t p_id) {
	int i = find(p_id);
	return i >= 0 ? &bodies[i] : nullptr;
}

const Body *World::get_body(int32_t p_id) const {
	int i = find(p_id);
	return i >= 0 ? &bodies[i] : nullptr;
}

int World::sleeping_count() const {
	int n = 0;
	for (const Body &b : bodies) {
		if (b.asleep) {
			n++;
		}
	}
	return n;
}

void World::wake(Body &p_b) {
	p_b.asleep = false;
	p_b.sleep_t = 0.0;
}

void World::set_velocity(int32_t p_id, const V3 &p_v) {
	Body *b = get_body(p_id);
	if (b && !b->is_static()) {
		b->vel = p_v;
		wake(*b);
	}
}

void World::set_pose(int32_t p_id, const V3 &p_position, const Quat &p_rotation) {
	Body *b = get_body(p_id);
	if (b) {
		b->pos = p_position;
		b->rot = p_rotation.normalized();
		b->update_derived();
	}
}

void World::apply_force(int32_t p_id, const V3 &p_f) {
	Body *b = get_body(p_id);
	if (b && !b->is_static()) {
		b->force += p_f;
		wake(*b);
	}
}

void World::apply_impulse(int32_t p_id, const V3 &p_impulse) {
	Body *b = get_body(p_id);
	if (b && !b->is_static()) {
		b->vel += p_impulse * b->inv_mass;
		wake(*b);
	}
}

// --- snapshot / restore ----------------------------------------------------------------------

namespace {

void put_u64(std::vector<uint8_t> &r_out, uint64_t p_v) {
	for (int i = 0; i < 8; i++) {
		r_out.push_back(uint8_t((p_v >> (8 * i)) & 0xFF));
	}
}

void put_u32(std::vector<uint8_t> &r_out, uint32_t p_v) {
	for (int i = 0; i < 4; i++) {
		r_out.push_back(uint8_t((p_v >> (8 * i)) & 0xFF));
	}
}

void put_double(std::vector<uint8_t> &r_out, double p_v) {
	uint64_t u;
	std::memcpy(&u, &p_v, sizeof(u));
	put_u64(r_out, u);
}

uint64_t get_u64(const uint8_t *p_in, size_t &r_pos) {
	uint64_t v = 0;
	for (int i = 0; i < 8; i++) {
		v |= uint64_t(p_in[r_pos + i]) << (8 * i);
	}
	r_pos += 8;
	return v;
}

uint32_t get_u32(const uint8_t *p_in, size_t &r_pos) {
	uint32_t v = 0;
	for (int i = 0; i < 4; i++) {
		v |= uint32_t(p_in[r_pos + i]) << (8 * i);
	}
	r_pos += 4;
	return v;
}

double get_double(const uint8_t *p_in, size_t &r_pos) {
	uint64_t u = get_u64(p_in, r_pos);
	double d;
	std::memcpy(&d, &u, sizeof(d));
	return d;
}

} // namespace

std::vector<uint8_t> World::snapshot() const {
	std::vector<uint8_t> out;
	out.reserve(SNAPSHOT_HEADER_SIZE + bodies.size() * SNAPSHOT_BODY_SIZE);
	put_u32(out, uint32_t(SNAPSHOT_VERSION));
	put_u32(out, uint32_t(bodies.size()));
	put_u64(out, uint64_t(step_count));
	for (const Body &b : bodies) {
		put_u32(out, uint32_t(b.id));
		out.push_back(uint8_t(b.shape));
		out.push_back(b.asleep ? 1 : 0);
		const double vals[20] = { b.mass, b.size.x, b.size.y, b.size.z, b.friction, b.restitution,
			b.pos.x, b.pos.y, b.pos.z, b.rot.x, b.rot.y, b.rot.z, b.rot.w,
			b.vel.x, b.vel.y, b.vel.z, b.ang.x, b.ang.y, b.ang.z, b.sleep_t };
		for (int i = 0; i < 20; i++) {
			put_double(out, vals[i]);
		}
	}
	return out;
}

bool World::restore(const uint8_t *p_bytes, size_t p_size) {
	if (p_bytes == nullptr || p_size < SNAPSHOT_HEADER_SIZE) {
		return false;
	}
	size_t pos = 0;
	if (int32_t(get_u32(p_bytes, pos)) != SNAPSHOT_VERSION) {
		return false;
	}
	uint32_t n = get_u32(p_bytes, pos);
	if (n > (p_size - SNAPSHOT_HEADER_SIZE) / SNAPSHOT_BODY_SIZE) {
		return false;
	}
	int64_t steps = int64_t(get_u64(p_bytes, pos));
	std::vector<Body> restored;
	restored.reserve(n);
	for (uint32_t i = 0; i < n; i++) {
		Body b;
		b.id = int32_t(get_u32(p_bytes, pos));
		b.shape = p_bytes[pos++] == SHAPE_BOX ? SHAPE_BOX : SHAPE_SPHERE;
		b.asleep = p_bytes[pos++] != 0;
		b.mass = get_double(p_bytes, pos);
		b.size.x = get_double(p_bytes, pos);
		b.size.y = get_double(p_bytes, pos);
		b.size.z = get_double(p_bytes, pos);
		b.friction = get_double(p_bytes, pos);
		b.restitution = get_double(p_bytes, pos);
		b.pos.x = get_double(p_bytes, pos);
		b.pos.y = get_double(p_bytes, pos);
		b.pos.z = get_double(p_bytes, pos);
		b.rot.x = get_double(p_bytes, pos);
		b.rot.y = get_double(p_bytes, pos);
		b.rot.z = get_double(p_bytes, pos);
		b.rot.w = get_double(p_bytes, pos);
		b.vel.x = get_double(p_bytes, pos);
		b.vel.y = get_double(p_bytes, pos);
		b.vel.z = get_double(p_bytes, pos);
		b.ang.x = get_double(p_bytes, pos);
		b.ang.y = get_double(p_bytes, pos);
		b.ang.z = get_double(p_bytes, pos);
		b.sleep_t = get_double(p_bytes, pos);
		b.setup_mass();
		b.update_derived();
		restored.push_back(b);
	}
	step_count = steps;
	bodies = std::move(restored);
	contacts.clear();
	return true;
}

// --- stepping --------------------------------------------------------------------------------

void World::phase_begin(const char *p_name) {
	if (observer) {
		observer->on_phase_begin(p_name);
	}
}

void World::phase_end() {
	if (observer) {
		observer->on_phase_end();
	}
}

void World::step(double p_dt) {
	if (observer) {
		observer->on_step_begin(step_count);
	}
	for (size_t i = 0; i < bodies.size(); i++) {
		bodies[i].index = int(i);
	}

	phase_begin("integrate");
	for (Body &b : bodies) {
		b.update_derived();
		if (b.is_static() || b.asleep) {
			continue;
		}
		b.vel += (gravity + b.force * b.inv_mass) * p_dt;
		b.ang += (b.inv_iw * b.torque) * p_dt;
		b.vel *= 1.0 / (1.0 + LINEAR_DAMPING * p_dt);
		b.ang *= 1.0 / (1.0 + ANGULAR_DAMPING * p_dt);
	}
	phase_end();

	phase_begin("broadphase");
	std::vector<std::pair<int, int>> pairs;
	broadphase(pairs);
	phase_end();

	phase_begin("narrowphase");
	contacts.clear();
	for (const std::pair<int, int> &pr : pairs) {
		collide(bodies[pr.first], bodies[pr.second]);
	}
	phase_end();

	phase_begin("solve");
	solve(p_dt);
	phase_end();

	phase_begin("integrate");
	for (Body &b : bodies) {
		if (b.is_static() || b.asleep) {
			continue;
		}
		b.pos += b.vel * p_dt;
		double wl = b.ang.length();
		if (wl > 1e-12) {
			b.rot = (Quat::from_axis_angle(b.ang / wl, wl * p_dt) * b.rot).normalized();
		}
		b.update_derived();
	}
	update_sleep(p_dt);
	for (Body &b : bodies) {
		b.force = V3();
		b.torque = V3();
	}
	phase_end();

	step_count += 1;
	last_pair_count = int(pairs.size());
	last_contact_count = int(contacts.size());
	last_sleeping_count = sleeping_count();
	if (observer) {
		StepStats st;
		st.contacts = last_contact_count;
		st.pairs = last_pair_count;
		st.sleeping = last_sleeping_count;
		st.bodies = int(bodies.size());
		observer->on_step_end(st);
	}
	contacts.clear();
}

// --- broadphase: sorted sweep on x -----------------------------------------------------------

void World::broadphase(std::vector<std::pair<int, int>> &r_pairs) const {
	std::vector<int> order(bodies.size());
	for (size_t i = 0; i < order.size(); i++) {
		order[i] = int(i);
	}
	std::sort(order.begin(), order.end(), [this](int p_a, int p_b) {
		const Body &a = bodies[p_a];
		const Body &b = bodies[p_b];
		if (a.lo.x != b.lo.x) {
			return a.lo.x < b.lo.x;
		}
		return a.id < b.id;
	});
	for (size_t i = 0; i < order.size(); i++) {
		const Body &a = bodies[order[i]];
		for (size_t j = i + 1; j < order.size(); j++) {
			const Body &b = bodies[order[j]];
			if (b.lo.x > a.hi.x) {
				break;
			}
			if (a.is_static() && b.is_static()) {
				continue;
			}
			if ((a.asleep || a.is_static()) && (b.asleep || b.is_static())) {
				continue;
			}
			if (a.hi.y < b.lo.y || b.hi.y < a.lo.y || a.hi.z < b.lo.z || b.hi.z < a.lo.z) {
				continue;
			}
			// Body indices follow id order (bodies are sorted by id).
			if (a.id < b.id) {
				r_pairs.push_back(std::make_pair(order[i], order[j]));
			} else {
				r_pairs.push_back(std::make_pair(order[j], order[i]));
			}
		}
	}
	// Indices are monotonic in id, so sorting by index equals sorting by (id_a, id_b).
	std::sort(r_pairs.begin(), r_pairs.end());
}

// --- narrowphase -----------------------------------------------------------------------------

void World::collide(Body &p_a, Body &p_b) {
	size_t before = contacts.size();
	if (p_a.shape == SHAPE_SPHERE && p_b.shape == SHAPE_SPHERE) {
		sphere_sphere(p_a, p_b);
	} else if (p_a.shape == SHAPE_SPHERE) {
		sphere_box(p_a, p_b, true);
	} else if (p_b.shape == SHAPE_SPHERE) {
		sphere_box(p_b, p_a, false);
	} else {
		box_box(p_a, p_b);
	}
	if (contacts.size() > before) {
		// Touching an awake body wakes a sleeper.
		if (p_a.asleep && !p_b.asleep && !p_b.is_static()) {
			wake(p_a);
		} else if (p_b.asleep && !p_a.asleep && !p_a.is_static()) {
			wake(p_b);
		}
	}
}

void World::emit(Body &p_a, Body &p_b, const V3 &p_p, const V3 &p_n, double p_depth) {
	Contact c;
	c.a = &p_a;
	c.b = &p_b;
	c.p = p_p;
	c.n = p_n;
	c.depth = p_depth;
	contacts.push_back(c);
}

void World::sphere_sphere(Body &p_a, Body &p_b) {
	V3 d = p_b.pos - p_a.pos;
	double rs = p_a.size.x + p_b.size.x;
	double l2 = d.length_squared();
	if (l2 >= rs * rs) {
		return;
	}
	double l = std::sqrt(l2);
	V3 n = l > 1e-9 ? d / l : V3(0, 1, 0);
	emit(p_a, p_b, p_a.pos + n * (p_a.size.x - 0.5 * (rs - l)), n, rs - l);
}

static double sign_or_one(double p_v) {
	if (p_v == 0.0) {
		return 1.0;
	}
	return p_v > 0.0 ? 1.0 : -1.0;
}

void World::sphere_box(Body &p_s, Body &p_box, bool p_sphere_first) {
	M3 basis = M3::from_quat(p_box.rot);
	V3 local = basis.transposed() * (p_s.pos - p_box.pos);
	const V3 &h = p_box.size;
	V3 clamped(std::fmin(std::fmax(local.x, -h.x), h.x), std::fmin(std::fmax(local.y, -h.y), h.y), std::fmin(std::fmax(local.z, -h.z), h.z));
	V3 n_box_to_sphere;
	double depth;
	V3 q_local;
	if (clamped == local) {
		// Centre inside the box: leave through the nearest face.
		double dx = h.x - std::fabs(local.x);
		double dy = h.y - std::fabs(local.y);
		double dz = h.z - std::fabs(local.z);
		q_local = local;
		V3 nl;
		if (dx <= dy && dx <= dz) {
			nl = V3(sign_or_one(local.x), 0.0, 0.0);
			q_local.x = nl.x * h.x;
			depth = dx + p_s.size.x;
		} else if (dy <= dz) {
			nl = V3(0.0, sign_or_one(local.y), 0.0);
			q_local.y = nl.y * h.y;
			depth = dy + p_s.size.x;
		} else {
			nl = V3(0.0, 0.0, sign_or_one(local.z));
			q_local.z = nl.z * h.z;
			depth = dz + p_s.size.x;
		}
		n_box_to_sphere = basis * nl;
	} else {
		V3 delta = local - clamped;
		double l2 = delta.length_squared();
		if (l2 >= p_s.size.x * p_s.size.x) {
			return;
		}
		double l = std::sqrt(l2);
		q_local = clamped;
		n_box_to_sphere = basis * (delta / l);
		depth = p_s.size.x - l;
	}
	V3 point = p_box.pos + basis * q_local;
	if (p_sphere_first) {
		emit(p_s, p_box, point, -n_box_to_sphere, depth);
	} else {
		emit(p_box, p_s, point, n_box_to_sphere, depth);
	}
}

namespace {

double box_extent(const V3 p_axes[3], const V3 &p_half, const V3 &p_dir) {
	return p_half.x * std::fabs(p_axes[0].dot(p_dir)) + p_half.y * std::fabs(p_axes[1].dot(p_dir)) + p_half.z * std::fabs(p_axes[2].dot(p_dir));
}

struct Poly {
	V3 p[16];
	int n = 0;

	void push(const V3 &p_v) {
		if (n < 16) {
			p[n++] = p_v;
		}
	}
};

Poly clip_poly(const Poly &p_poly, const V3 &p_n, double p_d) {
	Poly out;
	int cnt = p_poly.n;
	for (int i = 0; i < cnt; i++) {
		const V3 &p = p_poly.p[i];
		const V3 &q = p_poly.p[(i + 1) % cnt];
		double dp = p.dot(p_n) - p_d;
		double dq = q.dot(p_n) - p_d;
		if (dp <= 0.0) {
			out.push(p);
		}
		if ((dp < 0.0 && dq > 0.0) || (dp > 0.0 && dq < 0.0)) {
			out.push(p.lerp(q, dp / (dp - dq)));
		}
	}
	return out;
}

} // namespace

void World::box_box(Body &p_a, Body &p_b) {
	M3 ba = M3::from_quat(p_a.rot);
	M3 bb = M3::from_quat(p_b.rot);
	V3 ax[3] = { ba.column(0), ba.column(1), ba.column(2) };
	V3 bx[3] = { bb.column(0), bb.column(1), bb.column(2) };
	V3 d = p_b.pos - p_a.pos;
	double best = std::numeric_limits<double>::infinity();
	int best_kind = -1; // 0 face of A, 1 face of B, 2 edge
	int best_i = 0;
	int best_j = 0;
	V3 best_n;
	for (int i = 0; i < 3; i++) {
		double ov = p_a.size[i] + box_extent(bx, p_b.size, ax[i]) - std::fabs(d.dot(ax[i]));
		if (ov < 0.0) {
			return;
		}
		if (ov < best) {
			best = ov;
			best_kind = 0;
			best_i = i;
			best_n = ax[i];
		}
	}
	for (int i = 0; i < 3; i++) {
		double ov = p_b.size[i] + box_extent(ax, p_a.size, bx[i]) - std::fabs(d.dot(bx[i]));
		if (ov < 0.0) {
			return;
		}
		if (ov < best) {
			best = ov;
			best_kind = 1;
			best_i = i;
			best_n = bx[i];
		}
	}
	double face_best = best;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			V3 cr = ax[i].cross(bx[j]);
			double l = cr.length();
			if (l < 1e-6) {
				continue;
			}
			V3 axis = cr / l;
			double ov = box_extent(ax, p_a.size, axis) + box_extent(bx, p_b.size, axis) - std::fabs(d.dot(axis));
			if (ov < 0.0) {
				return;
			}
			if (ov + EDGE_BIAS < face_best && ov + EDGE_BIAS < best) {
				best = ov;
				best_kind = 2;
				best_i = i;
				best_j = j;
				best_n = axis;
			}
		}
	}
	if (best_kind < 0) {
		return;
	}
	V3 n_ab = best_n;
	if (n_ab.dot(d) < 0.0) {
		n_ab = -n_ab;
	}
	if (best_kind == 2) {
		V3 pa = p_a.pos;
		V3 pb = p_b.pos;
		for (int k = 0; k < 3; k++) {
			if (k != best_i) {
				pa += ax[k] * (p_a.size[k] * (ax[k].dot(n_ab) > 0.0 ? 1.0 : -1.0));
			}
			if (k != best_j) {
				pb += bx[k] * (p_b.size[k] * (bx[k].dot(n_ab) < 0.0 ? 1.0 : -1.0));
			}
		}
		V3 da = ax[best_i];
		V3 db = bx[best_j];
		V3 r = pa - pb;
		double bdot = da.dot(db);
		double c = da.dot(r);
		double f = db.dot(r);
		double denom = 1.0 - bdot * bdot;
		double t = (f - bdot * c) / denom;
		double s = bdot * t - c;
		emit(p_a, p_b, ((pa + da * s) + (pb + db * t)) * 0.5, n_ab, best);
		return;
	}
	// Face contact: clip the incident face against the reference face side planes.
	bool ref_is_a = best_kind == 0;
	Body &ref = ref_is_a ? p_a : p_b;
	Body &inc = ref_is_a ? p_b : p_a;
	const V3 *rax = ref_is_a ? ax : bx;
	const V3 *iax = ref_is_a ? bx : ax;
	V3 n_ref = ref_is_a ? n_ab : -n_ab;
	int ri = best_i;
	// Incident face: most anti-parallel to the reference normal.
	int ii = 0;
	double most = 0.0;
	for (int k = 0; k < 3; k++) {
		double dd = std::fabs(iax[k].dot(n_ref));
		if (dd > most + 1e-12) {
			most = dd;
			ii = k;
		}
	}
	double isign = iax[ii].dot(n_ref) > 0.0 ? -1.0 : 1.0;
	V3 ic = inc.pos + iax[ii] * (isign * inc.size[ii]);
	int ja = (ii + 1) % 3;
	int jb = (ii + 2) % 3;
	V3 ua = iax[ja] * inc.size[ja];
	V3 ub = iax[jb] * inc.size[jb];
	Poly poly;
	poly.push(ic + ua + ub);
	poly.push(ic - ua + ub);
	poly.push(ic - ua - ub);
	poly.push(ic + ua - ub);
	for (int k = 0; k < 3; k++) {
		if (k == ri) {
			continue;
		}
		V3 side = rax[k];
		double base = ref.pos.dot(side);
		poly = clip_poly(poly, side, base + ref.size[k]);
		poly = clip_poly(poly, -side, -base + ref.size[k]);
		if (poly.n == 0) {
			return;
		}
	}
	int emitted = 0;
	for (int i = 0; i < poly.n; i++) {
		const V3 &p = poly.p[i];
		double dep = ref.size[ri] - (p - ref.pos).dot(n_ref);
		if (dep < -1e-9) {
			continue;
		}
		emit(p_a, p_b, p + n_ref * (dep * 0.5), n_ab, dep > 0.0 ? dep : 0.0);
		emitted++;
		if (emitted >= MAX_CONTACTS_PER_PAIR) {
			break;
		}
	}
}

// --- solver ----------------------------------------------------------------------------------

namespace {

double eff_mass(const Contact &p_c, const V3 &p_dir) {
	V3 ra_n = p_c.ra.cross(p_dir);
	V3 rb_n = p_c.rb.cross(p_dir);
	double k = p_c.a->inv_mass + p_c.b->inv_mass +
			p_dir.dot((p_c.a->inv_iw * ra_n).cross(p_c.ra) + (p_c.b->inv_iw * rb_n).cross(p_c.rb));
	return k > 1e-12 ? 1.0 / k : 0.0;
}

V3 rel_vel(const Contact &p_c) {
	return (p_c.b->vel + p_c.b->ang.cross(p_c.rb)) - (p_c.a->vel + p_c.a->ang.cross(p_c.ra));
}

void apply_impulse_to(Contact &p_c, const V3 &p_impulse) {
	p_c.a->vel -= p_impulse * p_c.a->inv_mass;
	p_c.a->ang -= p_c.a->inv_iw * p_c.ra.cross(p_impulse);
	p_c.b->vel += p_impulse * p_c.b->inv_mass;
	p_c.b->ang += p_c.b->inv_iw * p_c.rb.cross(p_impulse);
}

double clampd(double p_v, double p_lo, double p_hi) {
	return p_v < p_lo ? p_lo : (p_v > p_hi ? p_hi : p_v);
}

} // namespace

void World::solve(double p_dt) {
	for (Contact &c : contacts) {
		c.ra = c.p - c.a->pos;
		c.rb = c.p - c.b->pos;
		V3 n = c.n;
		if (std::fabs(n.x) >= 0.57735) {
			c.t1 = V3(n.y, -n.x, 0.0).normalized();
		} else {
			c.t1 = V3(0.0, n.z, -n.y).normalized();
		}
		c.t2 = n.cross(c.t1);
		c.mn = eff_mass(c, n);
		c.m1 = eff_mass(c, c.t1);
		c.m2 = eff_mass(c, c.t2);
		c.mu = std::sqrt(c.a->friction * c.b->friction);
		double e = std::fmax(c.a->restitution, c.b->restitution);
		double vn = rel_vel(c).dot(n);
		double bounce = vn < -RESTITUTION_THRESHOLD ? -e * vn : 0.0;
		double bias = std::fmin(BAUMGARTE / p_dt * std::fmax(c.depth - SLOP, 0.0), MAX_BIAS_SPEED);
		c.target = std::fmax(bounce, bias);
		c.jn = 0.0;
		c.j1 = 0.0;
		c.j2 = 0.0;
	}
	for (int it = 0; it < iterations; it++) {
		for (Contact &c : contacts) {
			V3 v = rel_vel(c);
			double lim = c.mu * c.jn;
			double l1 = -c.m1 * v.dot(c.t1);
			double n1 = clampd(c.j1 + l1, -lim, lim);
			double d1 = n1 - c.j1;
			c.j1 = n1;
			double l2 = -c.m2 * v.dot(c.t2);
			double n2 = clampd(c.j2 + l2, -lim, lim);
			double d2 = n2 - c.j2;
			c.j2 = n2;
			apply_impulse_to(c, c.t1 * d1 + c.t2 * d2);
			double vn = rel_vel(c).dot(c.n);
			double ln = c.mn * (c.target - vn);
			double nn = std::fmax(c.jn + ln, 0.0);
			double dn = nn - c.jn;
			c.jn = nn;
			apply_impulse_to(c, c.n * dn);
		}
	}
}

// --- sleeping --------------------------------------------------------------------------------

namespace {

int uf_find(std::vector<int> &p_parent, int p_x) {
	int r = p_x;
	while (p_parent[r] != r) {
		r = p_parent[r];
	}
	while (p_parent[p_x] != r) {
		int nx = p_parent[p_x];
		p_parent[p_x] = r;
		p_x = nx;
	}
	return r;
}

} // namespace

void World::update_sleep(double p_dt) {
	int cnt = int(bodies.size());
	std::vector<int> parent(cnt);
	for (int i = 0; i < cnt; i++) {
		parent[i] = i;
		Body &b = bodies[i];
		if (b.is_static() || b.asleep) {
			continue;
		}
		if (b.vel.length_squared() < SLEEP_LIN_SQ && b.ang.length_squared() < SLEEP_ANG_SQ) {
			b.sleep_t += p_dt;
		} else {
			b.sleep_t = 0.0;
		}
	}
	for (const Contact &c : contacts) {
		if (c.a->is_static() || c.b->is_static()) {
			continue;
		}
		int ra = uf_find(parent, c.a->index);
		int rb = uf_find(parent, c.b->index);
		if (ra != rb) {
			// Lower index becomes the root: deterministic.
			if (ra < rb) {
				parent[rb] = ra;
			} else {
				parent[ra] = rb;
			}
		}
	}
	std::vector<double> min_t(cnt, std::numeric_limits<double>::infinity());
	for (int i = 0; i < cnt; i++) {
		const Body &b = bodies[i];
		if (b.is_static() || b.asleep) {
			continue;
		}
		int r = uf_find(parent, i);
		min_t[r] = std::fmin(min_t[r], b.sleep_t);
	}
	for (int i = 0; i < cnt; i++) {
		Body &b = bodies[i];
		if (b.is_static() || b.asleep) {
			continue;
		}
		if (min_t[uf_find(parent, i)] >= SLEEP_TIME) {
			b.asleep = true;
			b.vel = V3();
			b.ang = V3();
		}
	}
}

// --- queries ---------------------------------------------------------------------------------

static double ray_body(const Body &p_b, const V3 &p_o, const V3 &p_d, double p_max_t) {
	if (p_b.shape == SHAPE_SPHERE) {
		V3 m = p_o - p_b.pos;
		double bq = m.dot(p_d);
		double cq = m.dot(m) - p_b.size.x * p_b.size.x;
		if (cq > 0.0 && bq > 0.0) {
			return -1.0;
		}
		double disc = bq * bq - cq;
		if (disc < 0.0) {
			return -1.0;
		}
		double t = std::fmax(-bq - std::sqrt(disc), 0.0);
		return t <= p_max_t ? t : -1.0;
	}
	M3 inv = M3::from_quat(p_b.rot).transposed();
	V3 lo_p = inv * (p_o - p_b.pos);
	V3 ld = inv * p_d;
	double tmin = 0.0;
	double tmax = p_max_t;
	for (int i = 0; i < 3; i++) {
		double oi = lo_p[i];
		double di = ld[i];
		double hi_e = p_b.size[i];
		if (std::fabs(di) < 1e-12) {
			if (oi < -hi_e || oi > hi_e) {
				return -1.0;
			}
		} else {
			double t1 = (-hi_e - oi) / di;
			double t2 = (hi_e - oi) / di;
			if (t1 > t2) {
				double tmp = t1;
				t1 = t2;
				t2 = tmp;
			}
			tmin = std::fmax(tmin, t1);
			tmax = std::fmin(tmax, t2);
			if (tmin > tmax) {
				return -1.0;
			}
		}
	}
	return tmin;
}

RayHit World::raycast(const V3 &p_origin, const V3 &p_dir, double p_max_dist) const {
	RayHit out;
	out.t = p_max_dist;
	double dl = p_dir.length();
	if (dl < 1e-12) {
		return out;
	}
	V3 d = p_dir / dl;
	double best = p_max_dist;
	for (const Body &b : bodies) {
		double t = ray_body(b, p_origin, d, best);
		if (t >= 0.0 && t < best) {
			best = t;
			out.hit = true;
			out.id = b.id;
			out.t = t;
			out.point = p_origin + d * t;
		}
	}
	return out;
}

} // namespace CgamePhysicsCore
