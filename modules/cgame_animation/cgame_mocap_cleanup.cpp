/**************************************************************************/
/*  cgame_mocap_cleanup.cpp                                               */
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

#include "cgame_mocap_cleanup.h"

#include "core/object/class_db.h"

static double _oe_alpha(double p_te, double p_cutoff) {
	const double tau = 1.0 / (Math::TAU * MAX(p_cutoff, 0.000001));
	return 1.0 / (1.0 + tau / p_te);
}

static double _smoothstep01(double p_t) {
	const double c = CLAMP(p_t, 0.0, 1.0);
	return c * c * (3.0 - 2.0 * c);
}

static Quaternion _negated(const Quaternion &p_q) {
	return Quaternion(-p_q.x, -p_q.y, -p_q.z, -p_q.w);
}

PackedVector3Array CgameMocapCleanup::one_euro_positions(const PackedVector3Array &p_track, float p_fps, float p_min_cutoff, float p_beta, float p_d_cutoff) {
	const int n = p_track.size();
	PackedVector3Array out;
	out.resize(n);
	if (n == 0) {
		return out;
	}
	const double te = 1.0 / MAX((double)p_fps, 0.001);
	Vector3 x_prev = p_track[0];
	Vector3 dx_prev;
	out.write[0] = x_prev;
	const double a_d = _oe_alpha(te, p_d_cutoff);
	for (int i = 1; i < n; i++) {
		const Vector3 x = p_track[i];
		const Vector3 dx = (x - x_prev) / te;
		const Vector3 edx = dx_prev + (dx - dx_prev) * a_d;
		const double cutoff = p_min_cutoff + p_beta * edx.length();
		const double a = _oe_alpha(te, cutoff);
		const Vector3 xh = x_prev + (x - x_prev) * a;
		out.write[i] = xh;
		x_prev = xh;
		dx_prev = edx;
	}
	return out;
}

Vector<double> CgameMocapCleanup::_biquad(const Vector<double> &p_x, double p_fps, double p_cutoff) {
	const int n = p_x.size();
	Vector<double> out;
	out.resize(n);
	if (n == 0) {
		return out;
	}
	const double fc = CLAMP(p_cutoff, 0.001, p_fps * 0.45);
	const double w0 = Math::TAU * fc / p_fps;
	const double cs = Math::cos(w0);
	const double al = Math::sin(w0) / (2.0 * 0.7071067811865476);
	const double a0 = 1.0 + al;
	const double b0 = (1.0 - cs) * 0.5 / a0;
	const double b1 = (1.0 - cs) / a0;
	const double b2 = b0;
	const double a1 = -2.0 * cs / a0;
	const double a2 = (1.0 - al) / a0;
	double x1 = p_x[0];
	double x2 = p_x[0];
	double y1 = p_x[0];
	double y2 = p_x[0];
	for (int i = 0; i < n; i++) {
		const double xi = p_x[i];
		const double yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
		out.write[i] = yi;
		x2 = x1;
		x1 = xi;
		y2 = y1;
		y1 = yi;
	}
	return out;
}

static Vector<double> _reverse(const Vector<double> &p_a) {
	const int n = p_a.size();
	Vector<double> r;
	r.resize(n);
	for (int i = 0; i < n; i++) {
		r.write[i] = p_a[n - 1 - i];
	}
	return r;
}

Vector<double> CgameMocapCleanup::_filtfilt(const Vector<double> &p_x, double p_fps, double p_cutoff) {
	const int n = p_x.size();
	if (n < 3) {
		return p_x;
	}
	// Odd-reflection padding to suppress edge transients.
	const int pad = MIN(n - 1, int(3.0 * p_fps / MAX(p_cutoff, 0.001)) + 3);
	Vector<double> p;
	p.resize(n + 2 * pad);
	for (int i = 1; i <= pad; i++) {
		p.write[pad - i] = 2.0 * p_x[0] - p_x[i];
		p.write[pad + n - 1 + i] = 2.0 * p_x[n - 1] - p_x[n - 1 - i];
	}
	for (int i = 0; i < n; i++) {
		p.write[pad + i] = p_x[i];
	}
	Vector<double> f = _biquad(p, p_fps, p_cutoff);
	f = _reverse(f);
	f = _biquad(f, p_fps, p_cutoff);
	f = _reverse(f);
	Vector<double> out;
	out.resize(n);
	for (int i = 0; i < n; i++) {
		out.write[i] = f[pad + i];
	}
	return out;
}

PackedVector3Array CgameMocapCleanup::butterworth(const PackedVector3Array &p_track, float p_fps, float p_cutoff_hz) {
	const int n = p_track.size();
	Vector<double> xs, ys, zs;
	xs.resize(n);
	ys.resize(n);
	zs.resize(n);
	for (int i = 0; i < n; i++) {
		xs.write[i] = p_track[i].x;
		ys.write[i] = p_track[i].y;
		zs.write[i] = p_track[i].z;
	}
	xs = _filtfilt(xs, p_fps, p_cutoff_hz);
	ys = _filtfilt(ys, p_fps, p_cutoff_hz);
	zs = _filtfilt(zs, p_fps, p_cutoff_hz);
	PackedVector3Array out;
	out.resize(n);
	for (int i = 0; i < n; i++) {
		out.write[i] = Vector3(xs[i], ys[i], zs[i]);
	}
	return out;
}

TypedArray<Quaternion> CgameMocapCleanup::make_continuous(const TypedArray<Quaternion> &p_rotations) {
	TypedArray<Quaternion> out;
	for (int i = 0; i < p_rotations.size(); i++) {
		Quaternion q = Quaternion(p_rotations[i]).normalized();
		if (i > 0 && Quaternion(out[i - 1]).dot(q) < 0.0) {
			q = _negated(q);
		}
		out.push_back(q);
	}
	return out;
}

Vector3 CgameMocapCleanup::_quat_log(const Quaternion &p_q) {
	Quaternion qq = p_q;
	if (qq.w < 0.0) {
		qq = _negated(qq);
	}
	const Vector3 v(qq.x, qq.y, qq.z);
	const double s = v.length();
	if (s < 0.00000001) {
		return v * 2.0;
	}
	const double angle = 2.0 * Math::atan2(s, (double)qq.w);
	return v / s * angle;
}

Quaternion CgameMocapCleanup::_quat_exp(const Vector3 &p_v) {
	const double angle = p_v.length();
	if (angle < 0.000000001) {
		return Quaternion(p_v.x * 0.5, p_v.y * 0.5, p_v.z * 0.5, 1.0).normalized();
	}
	return Quaternion(p_v / angle, angle);
}

TypedArray<Quaternion> CgameMocapCleanup::smooth_rotations(const TypedArray<Quaternion> &p_rotations, float p_fps, float p_cutoff) {
	TypedArray<Quaternion> out;
	if (p_rotations.is_empty()) {
		return out;
	}
	const TypedArray<Quaternion> cont = make_continuous(p_rotations);
	const Quaternion ref = cont[0];
	const Quaternion ref_inv = ref.inverse();
	PackedVector3Array logs;
	logs.resize(cont.size());
	for (int i = 0; i < cont.size(); i++) {
		logs.write[i] = _quat_log(ref_inv * Quaternion(cont[i]));
	}
	const PackedVector3Array sm = butterworth(logs, p_fps, p_cutoff);
	for (int i = 0; i < sm.size(); i++) {
		out.push_back((ref * _quat_exp(sm[i])).normalized());
	}
	return out;
}

double CgameMocapCleanup::_median(const Vector<double> &p_values) {
	const int n = p_values.size();
	if (n == 0) {
		return 0.0;
	}
	Vector<double> s = p_values;
	s.sort();
	if (n % 2 == 1) {
		return s[n / 2];
	}
	return 0.5 * (s[n / 2 - 1] + s[n / 2]);
}

PackedVector3Array CgameMocapCleanup::remove_spikes(const PackedVector3Array &p_track, float p_threshold_sigma) {
	const int n = p_track.size();
	if (n < 5) {
		return p_track.duplicate();
	}
	Vector<double> res;
	res.resize(n);
	for (int i = 0; i < n; i++) {
		const int lo = MAX(0, i - 2);
		const int hi = MIN(n - 1, i + 2);
		Vector<double> mx, my, mz;
		for (int j = lo; j <= hi; j++) {
			mx.push_back(p_track[j].x);
			my.push_back(p_track[j].y);
			mz.push_back(p_track[j].z);
		}
		const Vector3 med(_median(mx), _median(my), _median(mz));
		res.write[i] = (p_track[i] - med).length();
	}
	const double med_r = _median(res);
	Vector<double> dev;
	dev.resize(n);
	for (int i = 0; i < n; i++) {
		dev.write[i] = Math::abs(res[i] - med_r);
	}
	const double sigma = 1.4826 * _median(dev) + 0.000001;
	PackedByteArray valid;
	valid.resize(n);
	for (int i = 0; i < n; i++) {
		valid.write[i] = res[i] > med_r + p_threshold_sigma * sigma ? 0 : 1;
	}
	return fill_gaps(p_track, valid);
}

Vector3 CgameMocapCleanup::_hermite(const Vector3 &p_p0, const Vector3 &p_p1, const Vector3 &p_m0, const Vector3 &p_m1, double p_t, double p_span) {
	const double t2 = p_t * p_t;
	const double t3 = t2 * p_t;
	return p_p0 * (2.0 * t3 - 3.0 * t2 + 1.0) + p_m0 * p_span * (t3 - 2.0 * t2 + p_t) + p_p1 * (-2.0 * t3 + 3.0 * t2) + p_m1 * p_span * (t3 - t2);
}

PackedVector3Array CgameMocapCleanup::fill_gaps(const PackedVector3Array &p_track, const PackedByteArray &p_valid) {
	const int n = p_track.size();
	PackedVector3Array out = p_track.duplicate();
	if (p_valid.size() != n || n == 0) {
		return out;
	}
	int i = 0;
	while (i < n) {
		if (p_valid[i] != 0) {
			i++;
			continue;
		}
		const int s = i;
		while (i < n && p_valid[i] == 0) {
			i++;
		}
		const int a = s - 1;
		const int b = i;
		if (a < 0 && b >= n) {
			return out;
		}
		if (a < 0) {
			for (int k = s; k < b; k++) {
				out.write[k] = p_track[b];
			}
		} else if (b >= n) {
			for (int k = s; k < n; k++) {
				out.write[k] = p_track[a];
			}
		} else {
			const double span = double(b - a);
			const Vector3 chord = (p_track[b] - p_track[a]) / span;
			Vector3 m0 = chord;
			if (a - 1 >= 0 && p_valid[a - 1] != 0) {
				m0 = p_track[a] - p_track[a - 1];
			}
			Vector3 m1 = chord;
			if (b + 1 < n && p_valid[b + 1] != 0) {
				m1 = p_track[b + 1] - p_track[b];
			}
			for (int k = s; k < b; k++) {
				out.write[k] = _hermite(p_track[a], p_track[b], m0, m1, double(k - a) / span, span);
			}
		}
	}
	return out;
}

TypedArray<Quaternion> CgameMocapCleanup::fill_gaps_rotations(const TypedArray<Quaternion> &p_rotations, const PackedByteArray &p_valid) {
	const int n = p_rotations.size();
	TypedArray<Quaternion> out = p_rotations.duplicate();
	if (p_valid.size() != n || n == 0) {
		return out;
	}
	int i = 0;
	while (i < n) {
		if (p_valid[i] != 0) {
			i++;
			continue;
		}
		const int s = i;
		while (i < n && p_valid[i] == 0) {
			i++;
		}
		const int a = s - 1;
		const int b = i;
		if (a < 0 && b >= n) {
			return out;
		}
		for (int k = s; k < b; k++) {
			if (a < 0) {
				out[k] = p_rotations[b];
			} else if (b >= n) {
				out[k] = p_rotations[a];
			} else {
				const Quaternion qa = p_rotations[a];
				Quaternion qb = p_rotations[b];
				if (qa.dot(qb) < 0.0) {
					qb = _negated(qb);
				}
				out[k] = qa.slerp(qb, double(k - a) / double(b - a)).normalized();
			}
		}
	}
	return out;
}

PackedByteArray CgameMocapCleanup::detect_contacts(const PackedVector3Array &p_foot_track, float p_fps, float p_height_threshold, float p_speed_threshold) {
	const int n = p_foot_track.size();
	PackedByteArray out;
	out.resize(n);
	out.fill(0);
	if (n == 0) {
		return out;
	}
	real_t ground = p_foot_track[0].y;
	for (int i = 0; i < n; i++) {
		ground = MIN(ground, p_foot_track[i].y);
	}
	for (int i = 0; i < n; i++) {
		const int lo = MAX(0, i - 1);
		const int hi = MIN(n - 1, i + 1);
		const double speed = (p_foot_track[hi] - p_foot_track[lo]).length() * p_fps / double(MAX(1, hi - lo));
		const bool low = p_foot_track[i].y - ground <= p_height_threshold;
		out.write[i] = (low && speed <= p_speed_threshold) ? 1 : 0;
	}
	// Drop contact runs shorter than 3 frames.
	int i2 = 0;
	while (i2 < n) {
		if (out[i2] == 0) {
			i2++;
			continue;
		}
		const int s = i2;
		while (i2 < n && out[i2] != 0) {
			i2++;
		}
		if (i2 - s < 3) {
			for (int k = s; k < i2; k++) {
				out.write[k] = 0;
			}
		}
	}
	return out;
}

PackedVector3Array CgameMocapCleanup::fix_foot_skate(const PackedVector3Array &p_foot_track, const PackedByteArray &p_contacts, int p_blend_frames) {
	const int n = p_foot_track.size();
	PackedVector3Array out = p_foot_track.duplicate();
	if (p_contacts.size() != n || n == 0) {
		return out;
	}
	Vector<int> starts;
	Vector<int> ends;
	int i = 0;
	while (i < n) {
		if (p_contacts[i] == 0) {
			i++;
			continue;
		}
		const int s = i;
		while (i < n && p_contacts[i] != 0) {
			i++;
		}
		starts.push_back(s);
		ends.push_back(i - 1);
	}
	const int runs = starts.size();
	for (int r = 0; r < runs; r++) {
		const int s = starts[r];
		const int e = ends[r];
		Vector3 plant;
		for (int k = s; k <= e; k++) {
			plant += p_foot_track[k];
		}
		plant /= double(e - s + 1);
		const Vector3 off_in = plant - p_foot_track[s];
		const Vector3 off_out = plant - p_foot_track[e];
		const int gap_before = r == 0 ? s : s - ends[r - 1] - 1;
		const int gap_after = (r == runs - 1) ? (n - 1 - e) : starts[r + 1] - e - 1;
		const int lb = MIN(p_blend_frames, r > 0 ? int(Math::floor(double(gap_before) * 0.5)) : gap_before);
		const int la = MIN(p_blend_frames, r < runs - 1 ? int(Math::floor(double(gap_after) * 0.5)) : gap_after);
		for (int k = s; k <= e; k++) {
			out.write[k] = plant;
		}
		for (int d = 1; d <= lb; d++) {
			const double w = _smoothstep01(1.0 - double(d) / double(lb + 1));
			out.write[s - d] += off_in * w;
		}
		for (int d = 1; d <= la; d++) {
			const double w = _smoothstep01(1.0 - double(d) / double(la + 1));
			out.write[e + d] += off_out * w;
		}
	}
	return out;
}

Dictionary CgameMocapCleanup::extract_root_motion(const PackedVector3Array &p_hips_track) {
	const int n = p_hips_track.size();
	PackedVector3Array root;
	PackedFloat32Array yaw;
	PackedVector3Array local;
	root.resize(n);
	yaw.resize(n);
	local.resize(n);
	Vector<double> dirs;
	dirs.resize_initialized(n);
	Vector<uint8_t> known;
	known.resize_initialized(n);
	for (int i = 0; i < n; i++) {
		root.write[i] = Vector3(p_hips_track[i].x, 0.0, p_hips_track[i].z);
	}
	for (int i = 0; i < n; i++) {
		const int lo = MAX(0, i - 1);
		const int hi = MIN(n - 1, i + 1);
		const Vector3 d = root[hi] - root[lo];
		if (d.length() > 0.000001) {
			dirs.write[i] = Math::atan2(d.x, d.z);
			known.write[i] = 1;
		}
	}
	int first = -1;
	for (int i = 0; i < n; i++) {
		if (known[i] != 0) {
			first = i;
			break;
		}
	}
	if (first >= 0) {
		double prev = dirs[first];
		for (int i = 0; i < n; i++) {
			if (known[i] != 0) {
				double cur = dirs[i];
				cur = prev + Math::wrapf(cur - prev, -Math::PI, Math::PI);
				dirs.write[i] = cur;
				prev = cur;
			} else {
				dirs.write[i] = i > first ? prev : dirs[first];
			}
		}
	}
	for (int i = 0; i < n; i++) {
		yaw.write[i] = dirs[i];
		const Basis basis_inv = Basis(Vector3(0, 1, 0), yaw[i]).inverse();
		local.write[i] = basis_inv.xform(p_hips_track[i] - root[i]);
	}
	Dictionary out;
	out["root_positions"] = root;
	out["root_yaw"] = yaw;
	out["hips_local"] = local;
	return out;
}

PackedInt32Array CgameMocapCleanup::reduce_keys(const PackedVector3Array &p_track, float p_tolerance) {
	const int n = p_track.size();
	PackedInt32Array out;
	if (n == 0) {
		return out;
	}
	if (n <= 2) {
		for (int i = 0; i < n; i++) {
			out.push_back(i);
		}
		return out;
	}
	Vector<uint8_t> keep;
	keep.resize_initialized(n);
	keep.write[0] = 1;
	keep.write[n - 1] = 1;
	Vector<Vector2i> stack;
	stack.push_back(Vector2i(0, n - 1));
	while (!stack.is_empty()) {
		const Vector2i seg = stack[stack.size() - 1];
		stack.resize(stack.size() - 1);
		double worst = -1.0;
		int worst_i = -1;
		for (int i = seg.x + 1; i < seg.y; i++) {
			const double t = double(i - seg.x) / double(seg.y - seg.x);
			const double err = (p_track[i] - p_track[seg.x].lerp(p_track[seg.y], t)).length();
			if (err > worst) {
				worst = err;
				worst_i = i;
			}
		}
		if (worst > p_tolerance && worst_i >= 0) {
			keep.write[worst_i] = 1;
			stack.push_back(Vector2i(seg.x, worst_i));
			stack.push_back(Vector2i(worst_i, seg.y));
		}
	}
	for (int i = 0; i < n; i++) {
		if (keep[i] != 0) {
			out.push_back(i);
		}
	}
	return out;
}

PackedVector3Array CgameMocapCleanup::retime(const PackedVector3Array &p_track, float p_src_fps, float p_dst_fps) {
	const int n = p_track.size();
	PackedVector3Array out;
	if (n == 0 || p_src_fps <= 0.0f || p_dst_fps <= 0.0f) {
		return out;
	}
	const int count = MAX(1, int(Math::round(double(n - 1) * p_dst_fps / p_src_fps)) + 1);
	out.resize(count);
	for (int k = 0; k < count; k++) {
		const double src_t = double(k) * p_src_fps / p_dst_fps;
		const int i1 = CLAMP(int(Math::floor(src_t)), 0, n - 1);
		const double f = src_t - double(i1);
		const int i0 = MAX(i1 - 1, 0);
		const int i2 = MIN(i1 + 1, n - 1);
		const int i3 = MIN(i1 + 2, n - 1);
		out.write[k] = p_track[i1].cubic_interpolate(p_track[i2], p_track[i0], p_track[i3], f);
	}
	return out;
}

TypedArray<Quaternion> CgameMocapCleanup::retime_rotations(const TypedArray<Quaternion> &p_rotations, float p_src_fps, float p_dst_fps) {
	TypedArray<Quaternion> out;
	const int n = p_rotations.size();
	if (n == 0 || p_src_fps <= 0.0f || p_dst_fps <= 0.0f) {
		return out;
	}
	const TypedArray<Quaternion> cont = make_continuous(p_rotations);
	const int count = MAX(1, int(Math::round(double(n - 1) * p_dst_fps / p_src_fps)) + 1);
	for (int k = 0; k < count; k++) {
		const double src_t = double(k) * p_src_fps / p_dst_fps;
		const int i1 = CLAMP(int(Math::floor(src_t)), 0, n - 1);
		const int i2 = MIN(i1 + 1, n - 1);
		out.push_back(Quaternion(cont[i1]).slerp(Quaternion(cont[i2]), src_t - double(i1)).normalized());
	}
	return out;
}

void CgameMocapCleanup::_bind_methods() {
	const StringName c = "CgameMocapCleanup";
	ClassDB::bind_static_method(c, D_METHOD("one_euro_positions", "track", "fps", "min_cutoff", "beta", "d_cutoff"), &CgameMocapCleanup::one_euro_positions, DEFVAL(1.0f), DEFVAL(0.0f), DEFVAL(1.0f));
	ClassDB::bind_static_method(c, D_METHOD("butterworth", "track", "fps", "cutoff_hz"), &CgameMocapCleanup::butterworth);
	ClassDB::bind_static_method(c, D_METHOD("make_continuous", "rotations"), &CgameMocapCleanup::make_continuous);
	ClassDB::bind_static_method(c, D_METHOD("smooth_rotations", "rotations", "fps", "cutoff"), &CgameMocapCleanup::smooth_rotations);
	ClassDB::bind_static_method(c, D_METHOD("remove_spikes", "track", "threshold_sigma"), &CgameMocapCleanup::remove_spikes, DEFVAL(4.0f));
	ClassDB::bind_static_method(c, D_METHOD("fill_gaps", "track", "valid"), &CgameMocapCleanup::fill_gaps);
	ClassDB::bind_static_method(c, D_METHOD("fill_gaps_rotations", "rotations", "valid"), &CgameMocapCleanup::fill_gaps_rotations);
	ClassDB::bind_static_method(c, D_METHOD("detect_contacts", "foot_track", "fps", "height_threshold", "speed_threshold"), &CgameMocapCleanup::detect_contacts);
	ClassDB::bind_static_method(c, D_METHOD("fix_foot_skate", "foot_track", "contacts", "blend_frames"), &CgameMocapCleanup::fix_foot_skate, DEFVAL(4));
	ClassDB::bind_static_method(c, D_METHOD("extract_root_motion", "hips_track"), &CgameMocapCleanup::extract_root_motion);
	ClassDB::bind_static_method(c, D_METHOD("reduce_keys", "track", "tolerance"), &CgameMocapCleanup::reduce_keys);
	ClassDB::bind_static_method(c, D_METHOD("retime", "track", "src_fps", "dst_fps"), &CgameMocapCleanup::retime);
	ClassDB::bind_static_method(c, D_METHOD("retime_rotations", "rotations", "src_fps", "dst_fps"), &CgameMocapCleanup::retime_rotations);
}
