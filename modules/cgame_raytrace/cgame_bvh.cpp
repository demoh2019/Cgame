/**************************************************************************/
/*  cgame_bvh.cpp                                                         */
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

#include "cgame_bvh.h"

#include "core/object/class_db.h"
#include "core/os/os.h"

// Concepts re-implemented from public write-ups; no third-party source text was copied:
//  - Jacco Bikker, "How to build a BVH" series (binned SAH build, flat node layout).
//  - Tomas Moller and Ben Trumbore, "Fast, Minimum Storage Ray/Triangle Intersection", 1997.
//  - Peter Shirley, "Ray Tracing in One Weekend" series (CC0), slab AABB test.
//  - Pharr/Jakob/Humphreys, "Physically Based Rendering", SAH bucket cost model.

float CgameBVH::_area(const Vector3 &p_extent) {
	const float x = MAX(p_extent.x, 0.0f);
	const float y = MAX(p_extent.y, 0.0f);
	const float z = MAX(p_extent.z, 0.0f);
	return x * y + y * z + z * x;
}

Vector3 CgameBVH::_safe_inv(const Vector3 &p_dir) {
	const float eps = 0.000000001f;
	const float x = Math::abs(p_dir.x) > eps ? p_dir.x : eps;
	const float y = Math::abs(p_dir.y) > eps ? p_dir.y : eps;
	const float z = Math::abs(p_dir.z) > eps ? p_dir.z : eps;
	return Vector3(1.0f / x, 1.0f / y, 1.0f / z);
}

void CgameBVH::clear() {
	nodes.clear();
	tris.clear();
	tri_index.clear();
	tri_count = 0;
	leaf_count = 0;
	max_depth = 0;
	build_ms = 0.0;
}

CgameBVH::SplitResult CgameBVH::_find_split(int p_start, int p_cnt, const Vector3 &p_lo, const Vector3 &p_hi, const Vector3 &p_clo, const Vector3 &p_chi) const {
	const float leaf_cost = float(p_cnt) * _area(p_hi - p_lo);
	float best_cost = MISS;
	SplitResult res;
	const Vector3 ext = p_chi - p_clo;
	for (int axis = 0; axis < 3; axis++) {
		if (ext[axis] < 0.000000001f) {
			continue;
		}
		const float scale = float(BINS) / ext[axis];
		int bcount[BINS];
		Vector3 bmin[BINS];
		Vector3 bmax[BINS];
		for (int b = 0; b < BINS; b++) {
			bcount[b] = 0;
			bmin[b] = Vector3(MISS, MISS, MISS);
			bmax[b] = Vector3(-MISS, -MISS, -MISS);
		}
		for (int i = p_start; i < p_start + p_cnt; i++) {
			const int ti = tri_index[i];
			const int b = MIN(BINS - 1, int((b_cen[ti][axis] - p_clo[axis]) * scale));
			bcount[b]++;
			bmin[b] = bmin[b].min(b_lo[ti]);
			bmax[b] = bmax[b].max(b_hi[ti]);
		}
		float left_area[BINS - 1];
		int left_cnt[BINS - 1];
		Vector3 run_lo(MISS, MISS, MISS);
		Vector3 run_hi(-MISS, -MISS, -MISS);
		int run_n = 0;
		for (int b = 0; b < BINS - 1; b++) {
			run_n += bcount[b];
			run_lo = run_lo.min(bmin[b]);
			run_hi = run_hi.max(bmax[b]);
			left_cnt[b] = run_n;
			left_area[b] = run_n > 0 ? _area(run_hi - run_lo) : 0.0f;
		}
		run_lo = Vector3(MISS, MISS, MISS);
		run_hi = Vector3(-MISS, -MISS, -MISS);
		run_n = 0;
		for (int b = BINS - 1; b > 0; b--) {
			run_n += bcount[b];
			run_lo = run_lo.min(bmin[b]);
			run_hi = run_hi.max(bmax[b]);
			const int ln = left_cnt[b - 1];
			if (ln == 0 || run_n == 0) {
				continue;
			}
			const float cost = float(ln) * left_area[b - 1] + float(run_n) * _area(run_hi - run_lo);
			if (cost < best_cost) {
				best_cost = cost;
				res.axis = axis;
				res.bin = b - 1;
			}
		}
	}
	res.beats_leaf = best_cost < leaf_cost;
	return res;
}

void CgameBVH::build(const PackedVector3Array &p_triangles) {
	const uint64_t t0 = OS::get_singleton() ? OS::get_singleton()->get_ticks_usec() : 0;
	clear();
	tri_count = int(p_triangles.size() / 3);
	if (tri_count == 0) {
		return;
	}
	const Vector3 *src = p_triangles.ptr();

	b_lo.resize(tri_count);
	b_hi.resize(tri_count);
	b_cen.resize(tri_count);
	tri_index.resize(tri_count);
	for (int i = 0; i < tri_count; i++) {
		const Vector3 &a = src[i * 3];
		const Vector3 &b = src[i * 3 + 1];
		const Vector3 &c = src[i * 3 + 2];
		b_lo[i] = a.min(b).min(c);
		b_hi[i] = a.max(b).max(c);
		b_cen[i] = (b_lo[i] + b_hi[i]) * 0.5f;
		tri_index[i] = i;
	}

	nodes.push_back(Node());
	LocalVector<BuildJob> jobs;
	jobs.push_back({ 0, 0, tri_count, 0 });
	while (!jobs.is_empty()) {
		const BuildJob job = jobs[jobs.size() - 1];
		jobs.resize(jobs.size() - 1);
		max_depth = MAX(max_depth, job.depth);

		Vector3 lo(MISS, MISS, MISS);
		Vector3 hi(-MISS, -MISS, -MISS);
		Vector3 clo = lo;
		Vector3 chi = hi;
		for (int i = job.start; i < job.start + job.cnt; i++) {
			const int ti = tri_index[i];
			lo = lo.min(b_lo[ti]);
			hi = hi.max(b_hi[ti]);
			clo = clo.min(b_cen[ti]);
			chi = chi.max(b_cen[ti]);
		}
		nodes[job.node].bmin = lo;
		nodes[job.node].bmax = hi;

		if (job.cnt <= MAX_LEAF || job.depth >= MAX_DEPTH) {
			nodes[job.node].first = job.start;
			nodes[job.node].cnt = job.cnt;
			leaf_count++;
			continue;
		}
		const SplitResult split = _find_split(job.start, job.cnt, lo, hi, clo, chi);
		if (!split.beats_leaf && job.cnt <= FORCE_SPLIT) {
			nodes[job.node].first = job.start;
			nodes[job.node].cnt = job.cnt;
			leaf_count++;
			continue;
		}
		int mid = job.start + (job.cnt >> 1);
		if (split.axis >= 0) {
			const int axis = split.axis;
			const float scale = float(BINS) / (chi[axis] - clo[axis]);
			int i = job.start;
			int j = job.start + job.cnt - 1;
			while (i <= j) {
				const int b = MIN(BINS - 1, int((b_cen[tri_index[i]][axis] - clo[axis]) * scale));
				if (b <= split.bin) {
					i++;
				} else {
					SWAP(tri_index[i], tri_index[j]);
					j--;
				}
			}
			if (i > job.start && i < job.start + job.cnt) {
				mid = i;
			}
		}
		const int left = int(nodes.size());
		nodes.push_back(Node());
		nodes.push_back(Node());
		nodes[job.node].first = left;
		nodes[job.node].cnt = 0;
		jobs.push_back({ left, job.start, mid - job.start, job.depth + 1 });
		jobs.push_back({ left + 1, mid, job.start + job.cnt - mid, job.depth + 1 });
	}

	tris.resize(tri_count);
	for (int k = 0; k < tri_count; k++) {
		const int ti = tri_index[k];
		const Vector3 &v0 = src[ti * 3];
		tris[k].v0 = v0;
		tris[k].e1 = src[ti * 3 + 1] - v0;
		tris[k].e2 = src[ti * 3 + 2] - v0;
	}
	b_lo.reset();
	b_hi.reset();
	b_cen.reset();
	if (OS::get_singleton()) {
		build_ms = double(OS::get_singleton()->get_ticks_usec() - t0) / 1000.0;
	}
}

float CgameBVH::_box_t(const Node &p_node, const Vector3 &p_o, const Vector3 &p_inv, float p_t_max) const {
	float t1 = (p_node.bmin.x - p_o.x) * p_inv.x;
	float t2 = (p_node.bmax.x - p_o.x) * p_inv.x;
	float tn = MIN(t1, t2);
	float tf = MAX(t1, t2);
	t1 = (p_node.bmin.y - p_o.y) * p_inv.y;
	t2 = (p_node.bmax.y - p_o.y) * p_inv.y;
	tn = MAX(tn, MIN(t1, t2));
	tf = MIN(tf, MAX(t1, t2));
	t1 = (p_node.bmin.z - p_o.z) * p_inv.z;
	t2 = (p_node.bmax.z - p_o.z) * p_inv.z;
	tn = MAX(tn, MIN(t1, t2));
	tf = MIN(tf, MAX(t1, t2));
	if (tf < MAX(tn, 0.0f) || tn > p_t_max) {
		return MISS;
	}
	return MAX(tn, 0.0f);
}

bool CgameBVH::_tri_hit(const Tri &p_tri, const Vector3 &p_o, const Vector3 &p_d, float &r_t, float &r_u, float &r_v) const {
	const Vector3 pv = p_d.cross(p_tri.e2);
	const float det = p_tri.e1.dot(pv);
	if (Math::abs(det) < 0.000000000001f) {
		return false;
	}
	const float inv_det = 1.0f / det;
	const Vector3 tv = p_o - p_tri.v0;
	const float u = tv.dot(pv) * inv_det;
	if (u < 0.0f || u > 1.0f) {
		return false;
	}
	const Vector3 qv = tv.cross(p_tri.e1);
	const float v = p_d.dot(qv) * inv_det;
	if (v < 0.0f || u + v > 1.0f) {
		return false;
	}
	r_t = p_tri.e2.dot(qv) * inv_det;
	r_u = u;
	r_v = v;
	return true;
}

bool CgameBVH::intersect_native(const Vector3 &p_origin, const Vector3 &p_dir, float p_t_max, Hit &r_hit) const {
	r_hit = Hit();
	r_hit.t = p_t_max;
	if (nodes.is_empty()) {
		return false;
	}
	const Vector3 inv = _safe_inv(p_dir);
	float best_t = p_t_max;
	int best_k = -1;
	float best_u = 0.0f;
	float best_v = 0.0f;
	if (_box_t(nodes[0], p_origin, inv, best_t) < MISS) {
		int32_t stack[MAX_DEPTH * 2 + 8];
		int sp = 0;
		stack[sp++] = 0;
		while (sp > 0) {
			const Node &node = nodes[stack[--sp]];
			if (node.cnt > 0) {
				for (int k = node.first; k < node.first + node.cnt; k++) {
					float t, u, v;
					if (_tri_hit(tris[k], p_origin, p_dir, t, u, v) && t > T_MIN && t < best_t) {
						best_t = t;
						best_k = k;
						best_u = u;
						best_v = v;
					}
				}
			} else {
				const int l = node.first;
				const float tl = _box_t(nodes[l], p_origin, inv, best_t);
				const float tr = _box_t(nodes[l + 1], p_origin, inv, best_t);
				if (tl < MISS && tr < MISS) {
					if (tl <= tr) {
						stack[sp++] = l + 1;
						stack[sp++] = l;
					} else {
						stack[sp++] = l;
						stack[sp++] = l + 1;
					}
				} else if (tl < MISS) {
					stack[sp++] = l;
				} else if (tr < MISS) {
					stack[sp++] = l + 1;
				}
			}
		}
	}
	if (best_k < 0) {
		return false;
	}
	Vector3 n = tris[best_k].e1.cross(tris[best_k].e2).normalized();
	if (n.dot(p_dir) > 0.0f) {
		n = -n;
	}
	r_hit.hit = true;
	r_hit.t = best_t;
	r_hit.tri = tri_index[best_k];
	r_hit.u = best_u;
	r_hit.v = best_v;
	r_hit.normal = n;
	return true;
}

bool CgameBVH::occluded_native(const Vector3 &p_origin, const Vector3 &p_dir, float p_t_max) const {
	if (nodes.is_empty()) {
		return false;
	}
	const Vector3 inv = _safe_inv(p_dir);
	if (_box_t(nodes[0], p_origin, inv, p_t_max) >= MISS) {
		return false;
	}
	int32_t stack[MAX_DEPTH * 2 + 8];
	int sp = 0;
	stack[sp++] = 0;
	while (sp > 0) {
		const Node &node = nodes[stack[--sp]];
		if (node.cnt > 0) {
			for (int k = node.first; k < node.first + node.cnt; k++) {
				float t, u, v;
				if (_tri_hit(tris[k], p_origin, p_dir, t, u, v) && t > T_MIN && t < p_t_max) {
					return true;
				}
			}
		} else {
			const int l = node.first;
			if (_box_t(nodes[l], p_origin, inv, p_t_max) < MISS) {
				stack[sp++] = l;
			}
			if (_box_t(nodes[l + 1], p_origin, inv, p_t_max) < MISS) {
				stack[sp++] = l + 1;
			}
		}
	}
	return false;
}

Dictionary CgameBVH::intersect(const Vector3 &p_origin, const Vector3 &p_dir, float p_t_max) const {
	Hit h;
	intersect_native(p_origin, p_dir, p_t_max, h);
	Dictionary d;
	d["hit"] = h.hit;
	d["t"] = h.hit ? h.t : p_t_max;
	d["tri"] = h.tri;
	d["u"] = h.u;
	d["v"] = h.v;
	d["normal"] = h.normal;
	return d;
}

bool CgameBVH::occluded(const Vector3 &p_origin, const Vector3 &p_dir, float p_t_max) const {
	return occluded_native(p_origin, p_dir, p_t_max);
}

Dictionary CgameBVH::get_stats() const {
	float sah = 0.0f;
	float root_area = 1.0f;
	if (!nodes.is_empty()) {
		root_area = MAX(_area(nodes[0].bmax - nodes[0].bmin), 0.000001f);
		for (uint32_t i = 0; i < nodes.size(); i++) {
			sah += _area(nodes[i].bmax - nodes[i].bmin) * (nodes[i].cnt > 0 ? float(nodes[i].cnt) : 1.0f);
		}
	}
	Dictionary d;
	d["triangles"] = tri_count;
	d["nodes"] = int(nodes.size());
	d["leaves"] = leaf_count;
	d["max_depth"] = max_depth;
	d["avg_leaf_size"] = float(tri_count) / float(MAX(leaf_count, 1));
	d["sah_cost"] = sah / root_area;
	d["build_ms"] = build_ms;
	return d;
}

void CgameBVH::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build", "triangles"), &CgameBVH::build);
	ClassDB::bind_method(D_METHOD("clear"), &CgameBVH::clear);
	ClassDB::bind_method(D_METHOD("is_built"), &CgameBVH::is_built);
	ClassDB::bind_method(D_METHOD("intersect", "origin", "dir", "t_max"), &CgameBVH::intersect, DEFVAL(1.0e20f));
	ClassDB::bind_method(D_METHOD("occluded", "origin", "dir", "t_max"), &CgameBVH::occluded, DEFVAL(1.0e20f));
	ClassDB::bind_method(D_METHOD("get_stats"), &CgameBVH::get_stats);
	ClassDB::bind_method(D_METHOD("get_triangle_count"), &CgameBVH::get_triangle_count);
}
