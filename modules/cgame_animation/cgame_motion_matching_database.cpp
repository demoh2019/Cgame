/**************************************************************************/
/*  cgame_motion_matching_database.cpp                                    */
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

#include "cgame_motion_matching_database.h"

#include "core/object/class_db.h"

static const float TRAJ_TIMES[CgameMotionMatchingDatabase::TRAJ_SAMPLES] = { 0.2f, 0.4f, 0.6f };

// ---- Feature extraction ----

PackedFloat32Array CgameMotionMatchingDatabase::frame_features(const Dictionary &p_frame) {
	PackedFloat32Array f;
	f.resize(DIMS);
	f.fill(0.0f);
	const Vector2 rv = p_frame.get("root_velocity", Vector2());
	f.write[0] = rv.x;
	f.write[1] = rv.y;
	f.write[2] = p_frame.get("root_facing", 0.0f);
	const Array traj = p_frame.get("trajectory", Array());
	for (int i = 0; i < TRAJ_SAMPLES && i < traj.size(); i++) {
		const Dictionary tp = traj[i];
		const Vector2 pos = tp.get("pos", Vector2());
		f.write[3 + i * 3] = pos.x;
		f.write[4 + i * 3] = pos.y;
		f.write[5 + i * 3] = tp.get("facing", 0.0f);
	}
	const char *keys[4] = { "left_foot", "right_foot", "left_foot_vel", "right_foot_vel" };
	for (int k = 0; k < 4; k++) {
		const Vector3 v = p_frame.get(keys[k], Vector3());
		f.write[12 + k * 3] = v.x;
		f.write[13 + k * 3] = v.y;
		f.write[14 + k * 3] = v.z;
	}
	return f;
}

void CgameMotionMatchingDatabase::_dim_weights(float *r_w) const {
	r_w[0] = weight_velocity;
	r_w[1] = weight_velocity;
	r_w[2] = weight_facing;
	for (int i = 0; i < TRAJ_SAMPLES; i++) {
		r_w[3 + i * 3] = weight_traj_pos;
		r_w[4 + i * 3] = weight_traj_pos;
		r_w[5 + i * 3] = weight_traj_facing;
	}
	for (int d = 12; d < 18; d++) {
		r_w[d] = weight_foot_pos;
	}
	for (int d = 18; d < 24; d++) {
		r_w[d] = weight_foot_vel;
	}
}

// ---- Authoring ----

void CgameMotionMatchingDatabase::add_clip(const String &p_name, const Array &p_frames, float p_fps, bool p_loop, const PackedStringArray &p_tags) {
	PackedFloat32Array flat;
	flat.resize(p_frames.size() * DIMS);
	for (int i = 0; i < p_frames.size(); i++) {
		const Dictionary frame = p_frames[i];
		const PackedFloat32Array f = frame_features(frame);
		for (int d = 0; d < DIMS; d++) {
			flat.write[i * DIMS + d] = f[d];
		}
	}
	add_clip_features(p_name, flat, p_fps, p_loop, p_tags);
}

void CgameMotionMatchingDatabase::add_clip_features(const String &p_name, const PackedFloat32Array &p_features, float p_fps, bool p_loop, const PackedStringArray &p_tags) {
	ERR_FAIL_COND_MSG(p_features.size() % DIMS != 0, vformat("Clip feature array size must be a multiple of %d.", DIMS));
	Clip c;
	c.name = p_name;
	c.raw.resize(p_features.size());
	for (int i = 0; i < p_features.size(); i++) {
		c.raw.write[i] = p_features[i];
	}
	c.fps = p_fps;
	c.loop = p_loop;
	c.tags = p_tags;
	c.frame_count = p_features.size() / DIMS;
	clips.push_back(c);
	built = false;
}

void CgameMotionMatchingDatabase::clear() {
	clips.clear();
	features.clear();
	mean.clear();
	stdev.clear();
	dim_scale.clear();
	clip_of.clear();
	frame_src.clear();
	clip_start.clear();
	clip_count.clear();
	centroids.clear();
	radius.clear();
	members.clear();
	clip_index.clear();
	built = false;
}

void CgameMotionMatchingDatabase::build() {
	features.clear();
	clip_of.clear();
	frame_src.clear();
	clip_start.clear();
	clip_count.clear();
	clip_index.clear();
	Vector<float> raw;
	int total = 0;
	for (int ci = 0; ci < clips.size(); ci++) {
		const Clip &c = clips[ci];
		clip_start.push_back(total);
		clip_count.push_back(c.frame_count);
		clip_index[c.name] = ci;
		for (int fi = 0; fi < c.frame_count; fi++) {
			clip_of.push_back(ci);
			frame_src.push_back(fi);
		}
		raw.append_array(c.raw);
		total += c.frame_count;
	}
	mean.resize_initialized(DIMS);
	stdev.resize_initialized(DIMS);
	dim_scale.resize_initialized(DIMS);
	float w[DIMS];
	_dim_weights(w);
	for (int d = 0; d < DIMS; d++) {
		dim_scale.write[d] = Math::sqrt(w[d]);
	}
	if (total > 0) {
		for (int d = 0; d < DIMS; d++) {
			double s = 0.0;
			for (int i = 0; i < total; i++) {
				s += raw[i * DIMS + d];
			}
			const double m = s / double(total);
			double v = 0.0;
			for (int i = 0; i < total; i++) {
				const double dv = raw[i * DIMS + d] - m;
				v += dv * dv;
			}
			double sd = Math::sqrt(v / double(total));
			if (sd < MIN_STD) {
				sd = 1.0;
			}
			mean.write[d] = m;
			stdev.write[d] = sd;
		}
	}
	features.resize(total * DIMS);
	for (int i = 0; i < total; i++) {
		for (int d = 0; d < DIMS; d++) {
			features.write[i * DIMS + d] = (raw[i * DIMS + d] - mean[d]) / stdev[d] * dim_scale[d];
		}
	}
	_build_index();
	built = true;
}

int CgameMotionMatchingDatabase::retain_frames(const PackedByteArray &p_keep) {
	const int n = clip_of.size();
	ERR_FAIL_COND_V_MSG(p_keep.size() != n, 0, "Keep mask size must match the frame count.");
	Vector<float> nf;
	Vector<int> nc;
	Vector<int> ns;
	Vector<int> counts;
	counts.resize_initialized(clips.size());
	int removed = 0;
	for (int i = 0; i < n; i++) {
		if (p_keep[i] == 0) {
			removed++;
			continue;
		}
		for (int d = 0; d < DIMS; d++) {
			nf.push_back(features[i * DIMS + d]);
		}
		nc.push_back(clip_of[i]);
		ns.push_back(frame_src[i]);
		counts.write[clip_of[i]]++;
	}
	features = nf;
	clip_of = nc;
	frame_src = ns;
	int run = 0;
	for (int ci = 0; ci < clips.size(); ci++) {
		clip_start.write[ci] = run;
		clip_count.write[ci] = counts[ci];
		run += counts[ci];
	}
	_build_index();
	return removed;
}

int CgameMotionMatchingDatabase::prune_redundant(float p_threshold) {
	if (!built) {
		build();
	}
	const int n = clip_of.size();
	PackedByteArray keep;
	keep.resize(n);
	keep.fill(0);
	const float thr_sq = p_threshold * p_threshold;
	for (int ci = 0; ci < clips.size(); ci++) {
		const int s = clip_start[ci];
		Vector<int> kept;
		for (int i = s; i < s + clip_count[ci]; i++) {
			bool dup = false;
			for (int j = 0; j < kept.size(); j++) {
				if (_dsq(&features[i * DIMS], &features[kept[j] * DIMS]) < thr_sq) {
					dup = true;
					break;
				}
			}
			if (!dup) {
				kept.push_back(i);
				keep.write[i] = 1;
			}
		}
	}
	return retain_frames(keep);
}

// ---- Index ----

float CgameMotionMatchingDatabase::_dsq(const float *p_a, const float *p_b) {
	float s = 0.0f;
	for (int d = 0; d < DIMS; d++) {
		const float x = p_a[d] - p_b[d];
		s += x * x;
	}
	return s;
}

void CgameMotionMatchingDatabase::_assign_all(Vector<int> &r_assign, int p_k) const {
	for (int i = 0; i < r_assign.size(); i++) {
		int best = 0;
		float bd = Math::INF;
		for (int c = 0; c < p_k; c++) {
			const float dd = _dsq(&features[i * DIMS], &centroids[c * DIMS]);
			if (dd < bd) {
				bd = dd;
				best = c;
			}
		}
		r_assign.write[i] = best;
	}
}

void CgameMotionMatchingDatabase::_build_index() {
	centroids.clear();
	radius.clear();
	members.clear();
	const int n = clip_of.size();
	if (n == 0) {
		return;
	}
	int k = CLAMP(int(Math::sqrt(float(n)) * 0.5f), 1, 64);
	// Deterministic farthest-point initialization.
	Vector<int> seeds;
	seeds.push_back(0);
	Vector<float> mind;
	mind.resize(n);
	for (int i = 0; i < n; i++) {
		mind.write[i] = _dsq(&features[i * DIMS], &features[0]);
	}
	while (seeds.size() < k) {
		int bi = 0;
		float bd = -1.0f;
		for (int i = 0; i < n; i++) {
			if (mind[i] > bd) {
				bd = mind[i];
				bi = i;
			}
		}
		if (bd <= 0.0f) {
			break;
		}
		seeds.push_back(bi);
		for (int i = 0; i < n; i++) {
			const float dd = _dsq(&features[i * DIMS], &features[bi * DIMS]);
			if (dd < mind[i]) {
				mind.write[i] = dd;
			}
		}
	}
	k = seeds.size();
	centroids.resize(k * DIMS);
	for (int c = 0; c < k; c++) {
		for (int d = 0; d < DIMS; d++) {
			centroids.write[c * DIMS + d] = features[seeds[c] * DIMS + d];
		}
	}
	Vector<int> assign;
	assign.resize_initialized(n);
	for (int it = 0; it < 6; it++) {
		_assign_all(assign, k);
		Vector<float> sums;
		sums.resize_initialized(k * DIMS);
		Vector<int> cnt;
		cnt.resize_initialized(k);
		for (int i = 0; i < n; i++) {
			const int c = assign[i];
			cnt.write[c]++;
			for (int d = 0; d < DIMS; d++) {
				sums.write[c * DIMS + d] += features[i * DIMS + d];
			}
		}
		for (int c = 0; c < k; c++) {
			if (cnt[c] > 0) {
				for (int d = 0; d < DIMS; d++) {
					centroids.write[c * DIMS + d] = sums[c * DIMS + d] / float(cnt[c]);
				}
			}
		}
	}
	_assign_all(assign, k);
	radius.resize_initialized(k);
	members.resize(k);
	for (int i = 0; i < n; i++) {
		const int c = assign[i];
		members.write[c].push_back(i);
		const float r = Math::sqrt(_dsq(&features[i * DIMS], &centroids[c * DIMS]));
		if (r > radius[c]) {
			radius.write[c] = r;
		}
	}
}

// ---- Search ----

void CgameMotionMatchingDatabase::_normalize_query(const Vector<float> &p_raw, float *r_q) const {
	for (int d = 0; d < DIMS; d++) {
		r_q[d] = (p_raw[d] - mean[d]) / stdev[d] * dim_scale[d];
	}
}

float CgameMotionMatchingDatabase::_partial_dsq(const float *p_q, int p_i, float p_limit) const {
	float s = 0.0f;
	const float *base = &features[p_i * DIMS];
	for (int d = 0; d < DIMS; d++) {
		const float x = p_q[d] - base[d];
		s += x * x;
		if (s >= p_limit) {
			return s;
		}
	}
	return s;
}

int CgameMotionMatchingDatabase::_next_index(int p_clip, int p_frame) const {
	if (p_frame < 0 || p_clip < 0 || p_clip >= clips.size()) {
		return -1;
	}
	const int cnt = clip_count[p_clip];
	if (cnt == 0) {
		return -1;
	}
	const int s = clip_start[p_clip];
	for (int i = s; i < s + cnt; i++) {
		if (frame_src[i] > p_frame) {
			return i;
		}
	}
	return clips[p_clip].loop ? s : -1;
}

CgameMotionMatchingDatabase::SearchResult CgameMotionMatchingDatabase::_search_impl(const Vector<float> &p_raw_query, int p_current_clip, int p_current_frame, const PackedStringArray &p_required_tags, bool p_indexed) const {
	SearchResult none;
	if (!built || clip_of.is_empty() || p_raw_query.size() != DIMS) {
		return none;
	}
	float q[DIMS];
	_normalize_query(p_raw_query, q);
	Vector<uint8_t> ok;
	ok.resize(clips.size());
	for (int ci = 0; ci < clips.size(); ci++) {
		bool good = true;
		for (const String &tag : p_required_tags) {
			if (!clips[ci].tags.has(tag)) {
				good = false;
				break;
			}
		}
		ok.write[ci] = good ? 1 : 0;
	}
	float best_sq = Math::INF;
	int best_i = -1;
	if (p_indexed) {
		const int nb = members.size();
		Vector<float> cd;
		cd.resize(nb);
		Vector<int> order;
		for (int b = 0; b < nb; b++) {
			cd.write[b] = Math::sqrt(_dsq(q, &centroids[b * DIMS]));
			order.push_back(b);
		}
		// Insertion sort by centroid distance (bucket count is capped at 64).
		for (int a = 1; a < order.size(); a++) {
			const int v = order[a];
			int j = a - 1;
			while (j >= 0 && cd[order[j]] > cd[v]) {
				order.write[j + 1] = order[j];
				j--;
			}
			order.write[j + 1] = v;
		}
		for (int oi = 0; oi < order.size(); oi++) {
			const int b = order[oi];
			const float lower = cd[b] - radius[b];
			if (lower > 0.0f && lower * lower >= best_sq) {
				continue;
			}
			const Vector<int> &mem = members[b];
			for (int mi = 0; mi < mem.size(); mi++) {
				const int i = mem[mi];
				if (ok[clip_of[i]] == 0) {
					continue;
				}
				const float s = _partial_dsq(q, i, best_sq);
				if (s < best_sq) {
					best_sq = s;
					best_i = i;
				}
			}
		}
	} else {
		for (int i = 0; i < clip_of.size(); i++) {
			if (ok[clip_of[i]] == 0) {
				continue;
			}
			const float s = _partial_dsq(q, i, best_sq);
			if (s < best_sq) {
				best_sq = s;
				best_i = i;
			}
		}
	}
	float cost = best_i >= 0 ? Math::sqrt(best_sq) : (float)Math::INF;
	bool continuing = false;
	const int ci_next = _next_index(p_current_clip, p_current_frame);
	if (ci_next >= 0 && ok[clip_of[ci_next]] == 1) {
		const float cc = Math::sqrt(_dsq(q, &features[ci_next * DIMS])) * continue_bias;
		if (best_i < 0 || cc < cost) {
			cost = cc;
			best_i = ci_next;
			continuing = true;
		}
	}
	if (best_i < 0) {
		return none;
	}
	SearchResult r;
	r.clip = clip_of[best_i];
	r.frame = frame_src[best_i];
	r.cost = cost;
	r.continuing = continuing;
	return r;
}

CgameMotionMatchingDatabase::SearchResult CgameMotionMatchingDatabase::search_native(const Vector<float> &p_raw_query, int p_current_clip, int p_current_frame, const PackedStringArray &p_required_tags, bool p_indexed) const {
	return _search_impl(p_raw_query, p_current_clip, p_current_frame, p_required_tags, p_indexed);
}

Dictionary CgameMotionMatchingDatabase::_result_to_dict(const SearchResult &p_result) const {
	Dictionary d;
	d["clip"] = p_result.clip >= 0 ? clips[p_result.clip].name : String();
	d["frame"] = p_result.frame;
	d["cost"] = p_result.cost;
	d["continuing"] = p_result.continuing;
	return d;
}

static Vector<float> _query_to_raw(const Dictionary &p_query) {
	PackedFloat32Array raw;
	if (p_query.has("features")) {
		raw = p_query["features"];
	} else {
		raw = CgameMotionMatchingDatabase::frame_features(p_query);
	}
	Vector<float> out;
	out.resize(raw.size());
	for (int i = 0; i < raw.size(); i++) {
		out.write[i] = raw[i];
	}
	return out;
}

Dictionary CgameMotionMatchingDatabase::search(const Dictionary &p_query, const String &p_current_clip, int p_current_frame, const PackedStringArray &p_required_tags) const {
	return _result_to_dict(_search_impl(_query_to_raw(p_query), find_clip(p_current_clip), p_current_frame, p_required_tags, true));
}

Dictionary CgameMotionMatchingDatabase::brute_force_search(const Dictionary &p_query, const String &p_current_clip, int p_current_frame, const PackedStringArray &p_required_tags) const {
	return _result_to_dict(_search_impl(_query_to_raw(p_query), find_clip(p_current_clip), p_current_frame, p_required_tags, false));
}

// ---- Spring trajectory prediction ----

static float _spring_y(float p_halflife) {
	return 2.0f * 0.69314718f / MAX(p_halflife, 0.0001f);
}

Vector2 CgameMotionMatchingDatabase::predict_velocity(const Vector2 &p_v0, const Vector2 &p_goal, float p_halflife, float p_t) {
	const float y = _spring_y(p_halflife);
	const Vector2 j0 = p_v0 - p_goal;
	const float e = Math::exp(-y * p_t);
	return p_goal + e * (j0 + (j0 * y) * p_t);
}

float CgameMotionMatchingDatabase::predict_facing(float p_facing, float p_goal, float p_halflife, float p_t) {
	const float y = _spring_y(p_halflife);
	const float j0 = Math::wrapf(p_facing - p_goal, -(float)Math::PI, (float)Math::PI);
	const float e = Math::exp(-y * p_t);
	return p_goal + e * (j0 + j0 * y * p_t);
}

Vector<float> CgameMotionMatchingDatabase::query_features_from(const Vector2 &p_velocity, float p_facing, const Vector2 &p_desired_velocity, float p_desired_facing, const Vector3 &p_left_foot, const Vector3 &p_right_foot, const Vector3 &p_left_vel, const Vector3 &p_right_vel) const {
	Vector<float> f;
	f.resize_initialized(DIMS);
	Vector2 pos;
	float t = 0.0f;
	const float step = 0.02f;
	const float goal_facing = p_facing + Math::wrapf(p_desired_facing - p_facing, -(float)Math::PI, (float)Math::PI);
	for (int i = 0; i < TRAJ_SAMPLES; i++) {
		while (t < TRAJ_TIMES[i] - 0.0001f) {
			pos += predict_velocity(p_velocity, p_desired_velocity, spring_halflife, t + step * 0.5f) * step;
			t += step;
		}
		const float pf = predict_facing(p_facing, goal_facing, spring_halflife, TRAJ_TIMES[i]);
		f.write[3 + i * 3] = pos.x;
		f.write[4 + i * 3] = pos.y;
		f.write[5 + i * 3] = pf - p_facing;
	}
	f.write[0] = p_velocity.x;
	f.write[1] = p_velocity.y;
	f.write[2] = p_facing;
	const Vector3 vs[4] = { p_left_foot, p_right_foot, p_left_vel, p_right_vel };
	for (int k = 0; k < 4; k++) {
		f.write[12 + k * 3] = vs[k].x;
		f.write[13 + k * 3] = vs[k].y;
		f.write[14 + k * 3] = vs[k].z;
	}
	return f;
}

Dictionary CgameMotionMatchingDatabase::query_from(const Vector2 &p_velocity, float p_facing, const Vector2 &p_desired_velocity, float p_desired_facing, const Vector3 &p_left_foot, const Vector3 &p_right_foot, const Vector3 &p_left_vel, const Vector3 &p_right_vel) const {
	const Vector<float> f = query_features_from(p_velocity, p_facing, p_desired_velocity, p_desired_facing, p_left_foot, p_right_foot, p_left_vel, p_right_vel);
	Array traj;
	for (int i = 0; i < TRAJ_SAMPLES; i++) {
		Dictionary tp;
		tp["pos"] = Vector2(f[3 + i * 3], f[4 + i * 3]);
		tp["facing"] = f[5 + i * 3];
		traj.push_back(tp);
	}
	PackedFloat32Array packed;
	packed.resize(DIMS);
	for (int d = 0; d < DIMS; d++) {
		packed.write[d] = f[d];
	}
	Dictionary frame;
	frame["root_velocity"] = p_velocity;
	frame["root_facing"] = p_facing;
	frame["trajectory"] = traj;
	frame["left_foot"] = p_left_foot;
	frame["right_foot"] = p_right_foot;
	frame["left_foot_vel"] = p_left_vel;
	frame["right_foot_vel"] = p_right_vel;
	frame["features"] = packed;
	return frame;
}

// ---- Introspection ----

int CgameMotionMatchingDatabase::find_clip(const String &p_name) const {
	if (p_name.is_empty()) {
		return -1;
	}
	for (int i = 0; i < clips.size(); i++) {
		if (clips[i].name == p_name) {
			return i;
		}
	}
	return -1;
}

String CgameMotionMatchingDatabase::get_clip_name(int p_clip) const {
	ERR_FAIL_INDEX_V(p_clip, clips.size(), String());
	return clips[p_clip].name;
}

float CgameMotionMatchingDatabase::get_clip_fps(int p_clip) const {
	ERR_FAIL_INDEX_V(p_clip, clips.size(), 0.0f);
	return clips[p_clip].fps;
}

bool CgameMotionMatchingDatabase::is_clip_looping(int p_clip) const {
	ERR_FAIL_INDEX_V(p_clip, clips.size(), false);
	return clips[p_clip].loop;
}

int CgameMotionMatchingDatabase::get_clip_frame_count(int p_clip) const {
	ERR_FAIL_INDEX_V(p_clip, clips.size(), 0);
	return clips[p_clip].frame_count;
}

Dictionary CgameMotionMatchingDatabase::get_stats() const {
	Dictionary d;
	d["frames"] = clip_of.size();
	d["dimensions"] = DIMS;
	d["clips"] = clips.size();
	d["buckets"] = members.size();
	return d;
}

// ---- Serialization ----

void CgameMotionMatchingDatabase::set_clips(const Array &p_clips) {
	clips.clear();
	for (int i = 0; i < p_clips.size(); i++) {
		const Dictionary d = p_clips[i];
		add_clip_features(d.get("name", String()), d.get("features", PackedFloat32Array()), d.get("fps", 30.0f), d.get("loop", true), d.get("tags", PackedStringArray()));
	}
	build();
}

Array CgameMotionMatchingDatabase::get_clips() const {
	Array out;
	for (const Clip &c : clips) {
		Dictionary d;
		d["name"] = c.name;
		PackedFloat32Array f;
		f.resize(c.raw.size());
		for (int i = 0; i < c.raw.size(); i++) {
			f.write[i] = c.raw[i];
		}
		d["features"] = f;
		d["fps"] = c.fps;
		d["loop"] = c.loop;
		d["tags"] = c.tags;
		out.push_back(d);
	}
	return out;
}

void CgameMotionMatchingDatabase::_set_weight_dict(const Dictionary &p_weights) {
	weight_velocity = p_weights.get("velocity", weight_velocity);
	weight_facing = p_weights.get("facing", weight_facing);
	weight_traj_pos = p_weights.get("traj_pos", weight_traj_pos);
	weight_traj_facing = p_weights.get("traj_facing", weight_traj_facing);
	weight_foot_pos = p_weights.get("foot_pos", weight_foot_pos);
	weight_foot_vel = p_weights.get("foot_vel", weight_foot_vel);
}

Dictionary CgameMotionMatchingDatabase::_get_weight_dict() const {
	Dictionary d;
	d["velocity"] = weight_velocity;
	d["facing"] = weight_facing;
	d["traj_pos"] = weight_traj_pos;
	d["traj_facing"] = weight_traj_facing;
	d["foot_pos"] = weight_foot_pos;
	d["foot_vel"] = weight_foot_vel;
	return d;
}

void CgameMotionMatchingDatabase::set_weights(const Dictionary &p_weights) {
	_set_weight_dict(p_weights);
	if (!clips.is_empty()) {
		build(); // Weights are baked into the normalized features.
	}
}

Dictionary CgameMotionMatchingDatabase::get_weights() const {
	return _get_weight_dict();
}

// ---- Procedural locomotion clips ----

static Vector3 _synth_foot_pos(float p_t, const Vector2 &p_vel, float p_period, float p_side) {
	const float lateral = 0.1f * p_side;
	if (p_period <= 0.0f) {
		return Vector3(lateral + 0.002f * Math::sin(p_t * 2.0f + p_side), 0.0f, 0.0f);
	}
	const float phi = Math::TAU * p_t / p_period + (p_side > 0.0f ? (float)Math::PI : 0.0f);
	const float speed = p_vel.length();
	const Vector2 dir = speed > 0.0001f ? p_vel / speed : Vector2(0.0f, 1.0f);
	const float amp = speed * p_period * 0.25f;
	const float along = amp * Math::sin(phi);
	const float lift = 0.12f * MAX(0.0f, Math::cos(phi));
	return Vector3(lateral + dir.x * along, lift, dir.y * along);
}

static Dictionary _synth_clip(const String &p_name, const Vector2 &p_vel, float p_turn_rate, float p_period, int p_cycles, const PackedStringArray &p_tags) {
	const float fps = 30.0f;
	int frame_n = int(Math::round(MAX(p_period, 1.0f) * fps)) * p_cycles;
	if (p_period > 0.0f) {
		frame_n = int(Math::round(p_period * fps)) * p_cycles;
	}
	Array frames;
	const float eps = 0.01f;
	for (int k = 0; k < frame_n; k++) {
		const float t = float(k) / fps;
		Array traj;
		for (int i = 0; i < CgameMotionMatchingDatabase::TRAJ_SAMPLES; i++) {
			Dictionary tp;
			tp["pos"] = p_vel * TRAJ_TIMES[i];
			tp["facing"] = p_turn_rate * TRAJ_TIMES[i];
			traj.push_back(tp);
		}
		Dictionary frame;
		frame["root_velocity"] = p_vel;
		frame["root_facing"] = 0.0f;
		frame["trajectory"] = traj;
		frame["left_foot"] = _synth_foot_pos(t, p_vel, p_period, -1.0f);
		frame["right_foot"] = _synth_foot_pos(t, p_vel, p_period, 1.0f);
		frame["left_foot_vel"] = (_synth_foot_pos(t + eps, p_vel, p_period, -1.0f) - _synth_foot_pos(t - eps, p_vel, p_period, -1.0f)) / (2.0f * eps);
		frame["right_foot_vel"] = (_synth_foot_pos(t + eps, p_vel, p_period, 1.0f) - _synth_foot_pos(t - eps, p_vel, p_period, 1.0f)) / (2.0f * eps);
		frames.push_back(frame);
	}
	Dictionary clip;
	clip["name"] = p_name;
	clip["frames"] = frames;
	clip["fps"] = fps;
	clip["loop"] = true;
	clip["tags"] = p_tags;
	return clip;
}

Array CgameMotionMatchingDatabase::synthesize_locomotion_clips() {
	Array clips_out;
	PackedStringArray idle_tags;
	idle_tags.push_back("idle");
	clips_out.push_back(_synth_clip("idle", Vector2(), 0.0f, 0.0f, 1, idle_tags));
	PackedStringArray loco;
	loco.push_back("locomotion");
	loco.push_back("walk");
	clips_out.push_back(_synth_clip("walk_forward", Vector2(0.0f, 1.4f), 0.0f, 1.0f, 2, loco));
	clips_out.push_back(_synth_clip("walk_back", Vector2(0.0f, -1.2f), 0.0f, 1.0f, 2, loco));
	PackedStringArray run;
	run.push_back("locomotion");
	run.push_back("run");
	clips_out.push_back(_synth_clip("run_forward", Vector2(0.0f, 4.0f), 0.0f, 0.6f, 3, run));
	PackedStringArray strafe;
	strafe.push_back("locomotion");
	strafe.push_back("strafe");
	clips_out.push_back(_synth_clip("strafe_left", Vector2(-1.4f, 0.0f), 0.0f, 1.0f, 2, strafe));
	clips_out.push_back(_synth_clip("strafe_right", Vector2(1.4f, 0.0f), 0.0f, 1.0f, 2, strafe));
	PackedStringArray turn;
	turn.push_back("turn");
	clips_out.push_back(_synth_clip("turn_left", Vector2(), -2.2f, 0.8f, 2, turn));
	clips_out.push_back(_synth_clip("turn_right", Vector2(), 2.2f, 0.8f, 2, turn));
	return clips_out;
}

Ref<CgameMotionMatchingDatabase> CgameMotionMatchingDatabase::build_default_database() {
	Ref<CgameMotionMatchingDatabase> db;
	db.instantiate();
	const Array synth = synthesize_locomotion_clips();
	for (int i = 0; i < synth.size(); i++) {
		const Dictionary c = synth[i];
		db->add_clip(c["name"], c["frames"], c["fps"], c["loop"], c["tags"]);
	}
	db->build();
	return db;
}

void CgameMotionMatchingDatabase::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_clip", "name", "frames", "fps", "loop", "tags"), &CgameMotionMatchingDatabase::add_clip, DEFVAL(PackedStringArray()));
	ClassDB::bind_method(D_METHOD("add_clip_features", "name", "features", "fps", "loop", "tags"), &CgameMotionMatchingDatabase::add_clip_features, DEFVAL(PackedStringArray()));
	ClassDB::bind_method(D_METHOD("clear"), &CgameMotionMatchingDatabase::clear);
	ClassDB::bind_method(D_METHOD("build"), &CgameMotionMatchingDatabase::build);
	ClassDB::bind_method(D_METHOD("is_built"), &CgameMotionMatchingDatabase::is_built);
	ClassDB::bind_method(D_METHOD("retain_frames", "keep"), &CgameMotionMatchingDatabase::retain_frames);
	ClassDB::bind_method(D_METHOD("prune_redundant", "threshold"), &CgameMotionMatchingDatabase::prune_redundant);

	ClassDB::bind_method(D_METHOD("set_clips", "clips"), &CgameMotionMatchingDatabase::set_clips);
	ClassDB::bind_method(D_METHOD("get_clips"), &CgameMotionMatchingDatabase::get_clips);
	ClassDB::bind_method(D_METHOD("set_weights", "weights"), &CgameMotionMatchingDatabase::set_weights);
	ClassDB::bind_method(D_METHOD("get_weights"), &CgameMotionMatchingDatabase::get_weights);
	ClassDB::bind_method(D_METHOD("set_continue_bias", "bias"), &CgameMotionMatchingDatabase::set_continue_bias);
	ClassDB::bind_method(D_METHOD("get_continue_bias"), &CgameMotionMatchingDatabase::get_continue_bias);
	ClassDB::bind_method(D_METHOD("set_spring_halflife", "halflife"), &CgameMotionMatchingDatabase::set_spring_halflife);
	ClassDB::bind_method(D_METHOD("get_spring_halflife"), &CgameMotionMatchingDatabase::get_spring_halflife);

	ClassDB::bind_method(D_METHOD("get_clip_count"), &CgameMotionMatchingDatabase::get_clip_count);
	ClassDB::bind_method(D_METHOD("find_clip", "name"), &CgameMotionMatchingDatabase::find_clip);
	ClassDB::bind_method(D_METHOD("get_clip_name", "clip"), &CgameMotionMatchingDatabase::get_clip_name);
	ClassDB::bind_method(D_METHOD("get_clip_fps", "clip"), &CgameMotionMatchingDatabase::get_clip_fps);
	ClassDB::bind_method(D_METHOD("is_clip_looping", "clip"), &CgameMotionMatchingDatabase::is_clip_looping);
	ClassDB::bind_method(D_METHOD("get_clip_frame_count", "clip"), &CgameMotionMatchingDatabase::get_clip_frame_count);
	ClassDB::bind_method(D_METHOD("get_frame_count"), &CgameMotionMatchingDatabase::get_frame_count);
	ClassDB::bind_method(D_METHOD("get_stats"), &CgameMotionMatchingDatabase::get_stats);

	ClassDB::bind_method(D_METHOD("search", "query", "current_clip", "current_frame", "required_tags"), &CgameMotionMatchingDatabase::search, DEFVAL(""), DEFVAL(-1), DEFVAL(PackedStringArray()));
	ClassDB::bind_method(D_METHOD("brute_force_search", "query", "current_clip", "current_frame", "required_tags"), &CgameMotionMatchingDatabase::brute_force_search, DEFVAL(""), DEFVAL(-1), DEFVAL(PackedStringArray()));
	ClassDB::bind_method(D_METHOD("query_from", "velocity", "facing", "desired_velocity", "desired_facing", "left_foot", "right_foot", "left_velocity", "right_velocity"), &CgameMotionMatchingDatabase::query_from);

	ClassDB::bind_static_method("CgameMotionMatchingDatabase", D_METHOD("frame_features", "frame"), &CgameMotionMatchingDatabase::frame_features);
	ClassDB::bind_static_method("CgameMotionMatchingDatabase", D_METHOD("predict_velocity", "velocity", "goal", "halflife", "time"), &CgameMotionMatchingDatabase::predict_velocity);
	ClassDB::bind_static_method("CgameMotionMatchingDatabase", D_METHOD("predict_facing", "facing", "goal", "halflife", "time"), &CgameMotionMatchingDatabase::predict_facing);
	ClassDB::bind_static_method("CgameMotionMatchingDatabase", D_METHOD("synthesize_locomotion_clips"), &CgameMotionMatchingDatabase::synthesize_locomotion_clips);
	ClassDB::bind_static_method("CgameMotionMatchingDatabase", D_METHOD("build_default_database"), &CgameMotionMatchingDatabase::build_default_database);

	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "clips", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_clips", "get_clips");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "weights"), "set_weights", "get_weights");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "continue_bias", PROPERTY_HINT_RANGE, "0.0,1.0,0.01,or_greater"), "set_continue_bias", "get_continue_bias");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "spring_halflife", PROPERTY_HINT_RANGE, "0.01,2.0,0.01,or_greater,suffix:s"), "set_spring_halflife", "get_spring_halflife");

	BIND_CONSTANT(DIMS);
}
