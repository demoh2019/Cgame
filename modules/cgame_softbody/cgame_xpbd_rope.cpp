/**************************************************************************/
/*  cgame_xpbd_rope.cpp                                                   */
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

#include "cgame_xpbd_rope.h"

#include "core/object/class_db.h"

static const real_t EPS = 0.0000001;

void CgameXPBDRope::setup(const Vector3 &p_start, const Vector3 &p_end, int p_segments, real_t p_particle_mass) {
	const int count = MAX(p_segments, 1) + 1;
	Vector<Vector3> pts;
	pts.resize(count);
	for (int k = 0; k < count; k++) {
		pts.write[k] = p_start.lerp(p_end, real_t(k) / real_t(count - 1));
	}
	setup_points(pts, p_particle_mass);
}

void CgameXPBDRope::setup_points(const Vector<Vector3> &p_points, real_t p_particle_mass) {
	const int n = p_points.size();
	pos = p_points;
	prev = p_points;
	vel.resize(n);
	inv_mass.resize(n);
	base_inv_mass.resize(n);
	pin_mode.resize(n);
	pin_pos.resize(n);
	drive_from.resize(n);
	pin_fn.clear();
	pin_fn.resize(n);
	const float w = 1.0f / MAX((float)p_particle_mass, 0.000001f);
	for (int k = 0; k < n; k++) {
		vel.write[k] = Vector3();
		inv_mass.write[k] = w;
		base_inv_mass.write[k] = w;
		pin_mode.write[k] = PIN_FREE;
		pin_pos.write[k] = p_points[k];
		drive_from.write[k] = p_points[k];
	}
	seg_rest.resize(MAX(n - 1, 0));
	rest_len = 0.0;
	for (int k = 0; k < n - 1; k++) {
		seg_rest.write[k] = p_points[k].distance_to(p_points[k + 1]);
		rest_len += seg_rest[k];
	}
}

real_t CgameXPBDRope::length() const {
	real_t total = 0.0;
	for (int k = 0; k < pos.size() - 1; k++) {
		total += pos[k].distance_to(pos[k + 1]);
	}
	return total;
}

void CgameXPBDRope::pin(int p_index, const Vector3 &p_world_pos) {
	ERR_FAIL_INDEX(p_index, pos.size());
	pin_mode.write[p_index] = PIN_FIXED;
	pin_pos.write[p_index] = p_world_pos;
	inv_mass.write[p_index] = 0.0f;
	pos.write[p_index] = p_world_pos;
	prev.write[p_index] = p_world_pos;
	vel.write[p_index] = Vector3();
}

void CgameXPBDRope::attach(int p_index, const Callable &p_target_fn) {
	ERR_FAIL_INDEX(p_index, pos.size());
	ERR_FAIL_COND_MSG(!p_target_fn.is_valid(), "Rope attach target must be a valid Callable.");
	pin_mode.write[p_index] = PIN_CALLABLE;
	pin_fn.write[p_index] = p_target_fn;
	inv_mass.write[p_index] = 0.0f;
	const Variant ret = p_target_fn.call();
	const Vector3 p = ret.get_type() == Variant::VECTOR3 ? Vector3(ret) : pos[p_index];
	pin_pos.write[p_index] = p;
	pos.write[p_index] = p;
	prev.write[p_index] = p;
	vel.write[p_index] = Vector3();
}

void CgameXPBDRope::drive(int p_index, const Vector3 &p_world_pos) {
	ERR_FAIL_INDEX(p_index, pos.size());
	if (pin_mode[p_index] != PIN_DRIVEN) {
		pin_mode.write[p_index] = PIN_DRIVEN;
		inv_mass.write[p_index] = 0.0f;
		pos.write[p_index] = p_world_pos;
		prev.write[p_index] = p_world_pos;
		drive_from.write[p_index] = p_world_pos;
		vel.write[p_index] = Vector3();
	}
	pin_pos.write[p_index] = p_world_pos;
}

void CgameXPBDRope::attach_start(const Callable &p_target_fn) {
	attach(0, p_target_fn);
}

void CgameXPBDRope::attach_end(const Callable &p_target_fn) {
	attach(pos.size() - 1, p_target_fn);
}

void CgameXPBDRope::unpin(int p_index) {
	ERR_FAIL_INDEX(p_index, pos.size());
	pin_mode.write[p_index] = PIN_FREE;
	pin_fn.write[p_index] = Callable();
	inv_mass.write[p_index] = base_inv_mass[p_index];
}

bool CgameXPBDRope::is_pinned(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, pos.size(), false);
	return pin_mode[p_index] != PIN_FREE;
}

int CgameXPBDRope::add_sphere(const Vector3 &p_center, real_t p_radius) {
	sphere_c.push_back(p_center);
	sphere_r.push_back(p_radius);
	return sphere_c.size() - 1;
}

void CgameXPBDRope::set_sphere_center(int p_index, const Vector3 &p_center) {
	ERR_FAIL_INDEX(p_index, sphere_c.size());
	sphere_c.write[p_index] = p_center;
}

int CgameXPBDRope::add_plane(const Vector3 &p_normal, real_t p_offset) {
	plane_n.push_back(p_normal.normalized());
	plane_d.push_back(p_offset);
	return plane_n.size() - 1;
}

void CgameXPBDRope::clear_colliders() {
	sphere_c.clear();
	sphere_r.clear();
	plane_n.clear();
	plane_d.clear();
}

void CgameXPBDRope::step(real_t p_dt, int p_substeps) {
	if (p_dt <= 0.0 || pos.size() < 2) {
		return;
	}
	const int sub = MAX(p_substeps, 1);
	const real_t sdt = p_dt / real_t(sub);
	{
		const uint8_t *mode = pin_mode.ptr();
		const Vector3 *p = pos.ptr();
		Vector3 *from = drive_from.ptrw();
		for (int k = 0; k < pos.size(); k++) {
			if (mode[k] == PIN_DRIVEN) {
				from[k] = p[k];
			}
		}
	}
	for (int s = 0; s < sub; s++) {
		_integrate(sdt, real_t(s + 1) / real_t(sub));
		for (int it = 0; it < MAX(iterations, 1); it++) {
			_solve_distance(sdt);
		}
		if (self_collision_enabled) {
			_solve_self_collision();
		}
		_collide();
		const float *w = inv_mass.ptr();
		const Vector3 *p = pos.ptr();
		const Vector3 *pv = prev.ptr();
		Vector3 *v = vel.ptrw();
		for (int k = 0; k < pos.size(); k++) {
			if (w[k] > 0.0f) {
				v[k] = (p[k] - pv[k]) / sdt;
			}
		}
	}
}

void CgameXPBDRope::_integrate(real_t p_sdt, real_t p_drive_t) {
	const int n = pos.size();
	for (int k = 0; k < n; k++) {
		if (pin_mode[k] == PIN_CALLABLE) {
			const Variant ret = pin_fn[k].call();
			if (ret.get_type() == Variant::VECTOR3) {
				pin_pos.write[k] = ret;
			}
		}
	}
	const real_t damp = CLAMP(drag * p_sdt, 0.0, 1.0);
	const uint8_t *mode = pin_mode.ptr();
	const Vector3 *target = pin_pos.ptr();
	const Vector3 *from = drive_from.ptr();
	Vector3 *p = pos.ptrw();
	Vector3 *pv = prev.ptrw();
	Vector3 *v = vel.ptrw();
	for (int k = 0; k < n; k++) {
		if (mode[k] != PIN_FREE) {
			Vector3 t = target[k];
			if (mode[k] == PIN_DRIVEN) {
				t = from[k].lerp(target[k], p_drive_t);
			}
			pv[k] = t;
			p[k] = t;
			v[k] = Vector3();
			continue;
		}
		Vector3 nv = v[k] + gravity * p_sdt;
		nv += (wind - nv) * damp;
		pv[k] = p[k];
		p[k] += nv * p_sdt;
		v[k] = nv;
	}
}

void CgameXPBDRope::_project(int p_a, int p_b, real_t p_rest, real_t p_alpha) {
	const real_t wa = inv_mass[p_a];
	const real_t wb = inv_mass[p_b];
	const real_t w = wa + wb;
	if (w == 0.0) {
		return;
	}
	Vector3 *p = pos.ptrw();
	const Vector3 d = p[p_a] - p[p_b];
	const real_t dist = d.length();
	if (dist < EPS) {
		return;
	}
	const real_t s = -(dist - p_rest) / (w + p_alpha);
	const Vector3 n = d / dist;
	p[p_a] += n * (s * wa);
	p[p_b] -= n * (s * wb);
}

void CgameXPBDRope::_solve_distance(real_t p_sdt) {
	const real_t inv_dt2 = 1.0 / (p_sdt * p_sdt);
	const real_t alpha = compliance * inv_dt2;
	const int n = pos.size();
	for (int k = 0; k < n - 1; k++) {
		_project(k, k + 1, seg_rest[k], alpha);
	}
	if (bend_compliance >= 0.0) {
		const real_t alpha_b = bend_compliance * inv_dt2;
		for (int k = 0; k < n - 2; k++) {
			_project(k, k + 2, seg_rest[k] + seg_rest[k + 1], alpha_b);
		}
	}
}

void CgameXPBDRope::_collide() {
	if (sphere_c.is_empty() && plane_n.is_empty()) {
		return;
	}
	const int n = pos.size();
	const float *w = inv_mass.ptr();
	Vector3 *p = pos.ptrw();
	Vector3 *pv = prev.ptrw();
	auto contact = [&](int k, const Vector3 &p_n, real_t p_depth) {
		p[k] += p_n * p_depth;
		if (friction > 0.0) {
			const Vector3 dp = p[k] - pv[k];
			pv[k] += (dp - p_n * dp.dot(p_n)) * friction;
		}
	};
	for (int k = 0; k < n; k++) {
		if (w[k] == 0.0f) {
			continue;
		}
		for (int s = 0; s < sphere_c.size(); s++) {
			const real_t min_d = sphere_r[s] + radius;
			const Vector3 d = p[k] - sphere_c[s];
			const real_t l2 = d.length_squared();
			if (l2 < min_d * min_d) {
				const real_t l = Math::sqrt(l2);
				const Vector3 nrm = l > EPS ? d / l : Vector3(0, 1, 0);
				contact(k, nrm, min_d - l);
			}
		}
		for (int s = 0; s < plane_n.size(); s++) {
			const real_t dist = plane_n[s].dot(p[k]) - plane_d[s] - radius;
			if (dist < 0.0) {
				contact(k, plane_n[s], -dist);
			}
		}
	}
}

Vector2 CgameXPBDRope::closest_params(const Vector3 &p_p1, const Vector3 &p_q1, const Vector3 &p_p2, const Vector3 &p_q2) {
	const Vector3 d1 = p_q1 - p_p1;
	const Vector3 d2 = p_q2 - p_p2;
	const Vector3 r = p_p1 - p_p2;
	const real_t a = d1.dot(d1);
	const real_t e = d2.dot(d2);
	const real_t f = d2.dot(r);
	real_t s = 0.0;
	real_t t = 0.0;
	if (a <= EPS && e <= EPS) {
		return Vector2();
	}
	if (a <= EPS) {
		t = CLAMP(f / e, 0.0, 1.0);
	} else {
		const real_t c = d1.dot(r);
		if (e <= EPS) {
			s = CLAMP(-c / a, 0.0, 1.0);
		} else {
			const real_t b = d1.dot(d2);
			const real_t denom = a * e - b * b;
			if (denom > EPS) {
				s = CLAMP((b * f - c * e) / denom, 0.0, 1.0);
			}
			t = (b * s + f) / e;
			if (t < 0.0) {
				t = 0.0;
				s = CLAMP(-c / a, 0.0, 1.0);
			} else if (t > 1.0) {
				t = 1.0;
				s = CLAMP((b - c) / a, 0.0, 1.0);
			}
		}
	}
	return Vector2(s, t);
}

real_t CgameXPBDRope::segment_distance(int p_i, int p_j) const {
	ERR_FAIL_INDEX_V(p_i, pos.size() - 1, 0.0);
	ERR_FAIL_INDEX_V(p_j, pos.size() - 1, 0.0);
	const Vector2 st = closest_params(pos[p_i], pos[p_i + 1], pos[p_j], pos[p_j + 1]);
	const Vector3 c1 = pos[p_i].lerp(pos[p_i + 1], st.x);
	const Vector3 c2 = pos[p_j].lerp(pos[p_j + 1], st.y);
	return c1.distance_to(c2);
}

real_t CgameXPBDRope::min_self_distance() const {
	real_t best = Math::INF;
	const int segs = segment_count();
	for (int i = 0; i < segs; i++) {
		for (int j = i + 2; j < segs; j++) {
			best = MIN(best, segment_distance(i, j));
		}
	}
	return best;
}

void CgameXPBDRope::_solve_self_collision() {
	const int segs = segment_count();
	real_t longest = 0.0;
	for (int k = 0; k < segs; k++) {
		longest = MAX(longest, (real_t)seg_rest[k]);
	}
	const real_t cell = MAX(longest * 1.25 + 2.0 * radius, 0.0001);
	for (KeyValue<uint64_t, LocalVector<int>> &kv : grid) {
		kv.value.clear();
	}
	for (int k = 0; k < segs; k++) {
		const Vector3 m = (pos[k] + pos[k + 1]) * 0.5;
		grid[_cell_key((int64_t)Math::floor(m.x / cell), (int64_t)Math::floor(m.y / cell), (int64_t)Math::floor(m.z / cell))].push_back(k);
	}
	const real_t min_d = 2.0 * radius;
	for (int i = 0; i < segs; i++) {
		const Vector3 mi = (pos[i] + pos[i + 1]) * 0.5;
		const int64_t cx = (int64_t)Math::floor(mi.x / cell);
		const int64_t cy = (int64_t)Math::floor(mi.y / cell);
		const int64_t cz = (int64_t)Math::floor(mi.z / cell);
		for (int dx = -1; dx <= 1; dx++) {
			for (int dy = -1; dy <= 1; dy++) {
				for (int dz = -1; dz <= 1; dz++) {
					HashMap<uint64_t, LocalVector<int>>::Iterator it = grid.find(_cell_key(cx + dx, cy + dy, cz + dz));
					if (!it) {
						continue;
					}
					const LocalVector<int> &bucket = it->value;
					for (uint32_t bi = 0; bi < bucket.size(); bi++) {
						const int j = bucket[bi];
						if (j < i + 2) {
							continue;
						}
						_separate_segments(i, j, min_d);
					}
				}
			}
		}
	}
}

void CgameXPBDRope::_separate_segments(int p_i, int p_j, real_t p_min_d) {
	Vector3 *p = pos.ptrw();
	const Vector2 st = closest_params(p[p_i], p[p_i + 1], p[p_j], p[p_j + 1]);
	const real_t s = st.x;
	const real_t t = st.y;
	const Vector3 c1 = p[p_i].lerp(p[p_i + 1], s);
	const Vector3 c2 = p[p_j].lerp(p[p_j + 1], t);
	const Vector3 d = c1 - c2;
	const real_t dist = d.length();
	if (dist >= p_min_d) {
		return;
	}
	Vector3 n = Vector3(0, 1, 0);
	if (dist > EPS) {
		n = d / dist;
	} else {
		const Vector3 cr = (p[p_i + 1] - p[p_i]).cross(p[p_j + 1] - p[p_j]);
		if (cr.length_squared() > EPS) {
			n = cr.normalized();
		}
	}
	const real_t wa = inv_mass[p_i] * (1.0 - s);
	const real_t wb = inv_mass[p_i + 1] * s;
	const real_t wc = inv_mass[p_j] * (1.0 - t);
	const real_t wd = inv_mass[p_j + 1] * t;
	const real_t denom = wa * (1.0 - s) + wb * s + wc * (1.0 - t) + wd * t;
	if (denom <= 0.0) {
		return;
	}
	const real_t lam = (p_min_d - dist) / denom;
	p[p_i] += n * (lam * wa);
	p[p_i + 1] += n * (lam * wb);
	p[p_j] -= n * (lam * wc);
	p[p_j + 1] -= n * (lam * wd);
}

bool CgameXPBDRope::_proper_cross(const Vector2 &p_a, const Vector2 &p_b, const Vector2 &p_c, const Vector2 &p_d) {
	const real_t d1 = (p_b - p_a).cross(p_c - p_a);
	const real_t d2 = (p_b - p_a).cross(p_d - p_a);
	const real_t d3 = (p_d - p_c).cross(p_a - p_c);
	const real_t d4 = (p_d - p_c).cross(p_b - p_c);
	return ((d1 > 0.0 && d2 < 0.0) || (d1 < 0.0 && d2 > 0.0)) && ((d3 > 0.0 && d4 < 0.0) || (d3 < 0.0 && d4 > 0.0));
}

int CgameXPBDRope::crossing_number() const {
	const int n = pos.size();
	if (n < 4) {
		return 0;
	}
	Vector3 lo = pos[0];
	Vector3 hi = pos[0];
	for (int k = 0; k < n; k++) {
		lo = lo.min(pos[k]);
		hi = hi.max(pos[k]);
	}
	const Vector3 ext = hi - lo;
	int drop = 2;
	if (ext.x <= ext.y && ext.x <= ext.z) {
		drop = 0;
	} else if (ext.y <= ext.z) {
		drop = 1;
	}
	Vector<Vector2> pts;
	pts.resize(n);
	for (int k = 0; k < n; k++) {
		const Vector3 &p = pos[k];
		switch (drop) {
			case 0:
				pts.write[k] = Vector2(p.y, p.z);
				break;
			case 1:
				pts.write[k] = Vector2(p.x, p.z);
				break;
			default:
				pts.write[k] = Vector2(p.x, p.y);
				break;
		}
	}
	int crossings = 0;
	const int segs = n - 1;
	for (int i = 0; i < segs; i++) {
		for (int j = i + 2; j < segs; j++) {
			if (_proper_cross(pts[i], pts[i + 1], pts[j], pts[j + 1])) {
				crossings++;
			}
		}
	}
	return crossings;
}

void CgameXPBDRope::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_gravity", "gravity"), &CgameXPBDRope::set_gravity);
	ClassDB::bind_method(D_METHOD("get_gravity"), &CgameXPBDRope::get_gravity);
	ClassDB::bind_method(D_METHOD("set_wind", "wind"), &CgameXPBDRope::set_wind);
	ClassDB::bind_method(D_METHOD("get_wind"), &CgameXPBDRope::get_wind);
	ClassDB::bind_method(D_METHOD("set_drag", "drag"), &CgameXPBDRope::set_drag);
	ClassDB::bind_method(D_METHOD("get_drag"), &CgameXPBDRope::get_drag);
	ClassDB::bind_method(D_METHOD("set_compliance", "compliance"), &CgameXPBDRope::set_compliance);
	ClassDB::bind_method(D_METHOD("get_compliance"), &CgameXPBDRope::get_compliance);
	ClassDB::bind_method(D_METHOD("set_bend_compliance", "compliance"), &CgameXPBDRope::set_bend_compliance);
	ClassDB::bind_method(D_METHOD("get_bend_compliance"), &CgameXPBDRope::get_bend_compliance);
	ClassDB::bind_method(D_METHOD("set_iterations", "iterations"), &CgameXPBDRope::set_iterations);
	ClassDB::bind_method(D_METHOD("get_iterations"), &CgameXPBDRope::get_iterations);
	ClassDB::bind_method(D_METHOD("set_radius", "radius"), &CgameXPBDRope::set_radius);
	ClassDB::bind_method(D_METHOD("get_radius"), &CgameXPBDRope::get_radius);
	ClassDB::bind_method(D_METHOD("set_friction", "friction"), &CgameXPBDRope::set_friction);
	ClassDB::bind_method(D_METHOD("get_friction"), &CgameXPBDRope::get_friction);
	ClassDB::bind_method(D_METHOD("set_self_collision_enabled", "enabled"), &CgameXPBDRope::set_self_collision_enabled);
	ClassDB::bind_method(D_METHOD("is_self_collision_enabled"), &CgameXPBDRope::is_self_collision_enabled);

	ClassDB::bind_method(D_METHOD("setup", "start", "end", "segments", "particle_mass"), &CgameXPBDRope::setup, DEFVAL(0.1));
	ClassDB::bind_method(D_METHOD("setup_points", "points", "particle_mass"), &CgameXPBDRope::setup_points, DEFVAL(0.1));
	ClassDB::bind_method(D_METHOD("particle_count"), &CgameXPBDRope::particle_count);
	ClassDB::bind_method(D_METHOD("segment_count"), &CgameXPBDRope::segment_count);
	ClassDB::bind_method(D_METHOD("positions"), &CgameXPBDRope::positions);
	ClassDB::bind_method(D_METHOD("length"), &CgameXPBDRope::length);
	ClassDB::bind_method(D_METHOD("rest_length"), &CgameXPBDRope::rest_length);

	ClassDB::bind_method(D_METHOD("pin", "index", "world_pos"), &CgameXPBDRope::pin);
	ClassDB::bind_method(D_METHOD("attach", "index", "target_fn"), &CgameXPBDRope::attach);
	ClassDB::bind_method(D_METHOD("drive", "index", "world_pos"), &CgameXPBDRope::drive);
	ClassDB::bind_method(D_METHOD("attach_start", "target_fn"), &CgameXPBDRope::attach_start);
	ClassDB::bind_method(D_METHOD("attach_end", "target_fn"), &CgameXPBDRope::attach_end);
	ClassDB::bind_method(D_METHOD("unpin", "index"), &CgameXPBDRope::unpin);
	ClassDB::bind_method(D_METHOD("is_pinned", "index"), &CgameXPBDRope::is_pinned);

	ClassDB::bind_method(D_METHOD("add_sphere", "center", "radius"), &CgameXPBDRope::add_sphere);
	ClassDB::bind_method(D_METHOD("set_sphere_center", "index", "center"), &CgameXPBDRope::set_sphere_center);
	ClassDB::bind_method(D_METHOD("add_plane", "normal", "offset"), &CgameXPBDRope::add_plane);
	ClassDB::bind_method(D_METHOD("clear_colliders"), &CgameXPBDRope::clear_colliders);

	ClassDB::bind_method(D_METHOD("step", "dt", "substeps"), &CgameXPBDRope::step, DEFVAL(8));

	ClassDB::bind_static_method("CgameXPBDRope", D_METHOD("closest_params", "p1", "q1", "p2", "q2"), &CgameXPBDRope::closest_params);
	ClassDB::bind_method(D_METHOD("segment_distance", "i", "j"), &CgameXPBDRope::segment_distance);
	ClassDB::bind_method(D_METHOD("min_self_distance"), &CgameXPBDRope::min_self_distance);
	ClassDB::bind_method(D_METHOD("crossing_number"), &CgameXPBDRope::crossing_number);
	ClassDB::bind_method(D_METHOD("knot_count"), &CgameXPBDRope::knot_count);

	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "gravity", PROPERTY_HINT_NONE, "suffix:m/s²"), "set_gravity", "get_gravity");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "wind", PROPERTY_HINT_NONE, "suffix:m/s"), "set_wind", "get_wind");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "drag", PROPERTY_HINT_RANGE, "0,20,0.001,or_greater"), "set_drag", "get_drag");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "compliance", PROPERTY_HINT_RANGE, "0,1,0.000001,or_greater"), "set_compliance", "get_compliance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "bend_compliance", PROPERTY_HINT_RANGE, "-1,1,0.000001,or_greater"), "set_bend_compliance", "get_bend_compliance");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "iterations", PROPERTY_HINT_RANGE, "1,16,1,or_greater"), "set_iterations", "get_iterations");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "radius", PROPERTY_HINT_RANGE, "0,1,0.001,or_greater,suffix:m"), "set_radius", "get_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "friction", PROPERTY_HINT_RANGE, "0,1,0.001"), "set_friction", "get_friction");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "self_collision_enabled"), "set_self_collision_enabled", "is_self_collision_enabled");
}
