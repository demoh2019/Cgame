/**************************************************************************/
/*  cgame_road_network.cpp                                                */
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

#include "cgame_road_network.h"

#include "core/object/class_db.h"

#include "core/math/geometry_2d.h"
#include "core/math/math_funcs.h"
#include "core/math/random_number_generator.h"
#include "core/templates/hash_set.h"

namespace {
struct EdgeByLength {
	bool operator()(const CgameRoadNetwork::Edge &p_x, const CgameRoadNetwork::Edge &p_y) const {
		if (p_x.length == p_y.length) {
			if (p_x.a != p_y.a) {
				return p_x.a < p_y.a;
			}
			return p_x.b < p_y.b;
		}
		return p_x.length < p_y.length;
	}
};

int64_t edge_key(int p_a, int p_b, int p_n) {
	return (int64_t)MIN(p_a, p_b) * p_n + MAX(p_a, p_b);
}
} // namespace

CgameRoadNetwork::Edge CgameRoadNetwork::_make_edge(const PackedVector2Array &p_sites, int p_a, int p_b) {
	Edge e;
	e.a = MIN(p_a, p_b);
	e.b = MAX(p_a, p_b);
	e.length = p_sites[p_a].distance_to(p_sites[p_b]);
	return e;
}

Vector<CgameRoadNetwork::Edge> CgameRoadNetwork::_delaunay_edges(const PackedVector2Array &p_sites) {
	const int n = p_sites.size();
	HashSet<int64_t> seen;
	Vector<Edge> out;
	Vector<int> tris = Geometry2D::triangulate_delaunay(p_sites);
	int t = 0;
	while (t + 2 < tris.size()) {
		for (int k = 0; k < 3; k++) {
			const int a = tris[t + k];
			const int b = tris[t + (k + 1) % 3];
			const int64_t key = edge_key(a, b, n);
			if (a != b && !seen.has(key)) {
				seen.insert(key);
				out.push_back(_make_edge(p_sites, a, b));
			}
		}
		t += 3;
	}
	if (n == 2 && out.is_empty()) {
		out.push_back(_make_edge(p_sites, 0, 1));
	}
	return out;
}

Vector<CgameRoadNetwork::Edge> CgameRoadNetwork::_all_edges(const PackedVector2Array &p_sites) {
	Vector<Edge> out;
	for (int a = 0; a < p_sites.size(); a++) {
		for (int b = a + 1; b < p_sites.size(); b++) {
			out.push_back(_make_edge(p_sites, a, b));
		}
	}
	return out;
}

int CgameRoadNetwork::_find(Vector<int> &r_parent, int p_i) {
	int r = p_i;
	while (r_parent[r] != r) {
		r_parent.write[r] = r_parent[r_parent[r]];
		r = r_parent[r];
	}
	return r;
}

Vector<CgameRoadNetwork::Edge> CgameRoadNetwork::_kruskal(int p_n, const Vector<Edge> &p_edges) {
	Vector<Edge> sorted = p_edges;
	sorted.sort_custom<EdgeByLength>();
	Vector<int> parent;
	parent.resize(p_n);
	for (int i = 0; i < p_n; i++) {
		parent.write[i] = i;
	}
	Vector<Edge> out;
	for (const Edge &e : sorted) {
		const int ra = _find(parent, e.a);
		const int rb = _find(parent, e.b);
		if (ra != rb) {
			parent.write[ra] = rb;
			out.push_back(e);
			if (out.size() == p_n - 1) {
				break;
			}
		}
	}
	return out;
}

TypedArray<Dictionary> CgameRoadNetwork::connect_sites(const PackedVector2Array &p_sites, double p_extra_edge_ratio, int64_t p_seed) {
	const int n = p_sites.size();
	TypedArray<Dictionary> result;
	if (n < 2) {
		return result;
	}
	Vector<Edge> candidates = _delaunay_edges(p_sites);
	Vector<Edge> mst = _kruskal(n, candidates);
	if (mst.size() < n - 1) {
		// Degenerate input (collinear / duplicate sites): fall back to all pairs.
		candidates = _all_edges(p_sites);
		mst = _kruskal(n, candidates);
	}
	HashSet<int64_t> in_mst;
	for (const Edge &e : mst) {
		in_mst.insert(edge_key(e.a, e.b, n));
	}
	Vector<Edge> rest;
	for (const Edge &e : candidates) {
		if (!in_mst.has(edge_key(e.a, e.b, n))) {
			rest.push_back(e);
		}
	}
	rest.sort_custom<EdgeByLength>();

	Vector<Edge> chosen = mst;
	const int want = (int)Math::round(CLAMP(p_extra_edge_ratio, 0.0, 1.0) * (double)rest.size());
	if (want > 0) {
		// Pick randomly (seeded) among the shorter half so loops stay local.
		const int pool_size = CLAMP(MAX(want, (rest.size() + 1) / 2), 1, rest.size());
		Vector<Edge> pool;
		for (int i = 0; i < pool_size; i++) {
			pool.push_back(rest[i]);
		}
		Ref<RandomNumberGenerator> rng;
		rng.instantiate();
		rng->set_seed((uint64_t)p_seed);
		for (int i = pool.size() - 1; i > 0; i--) {
			const int j = rng->randi_range(0, i);
			SWAP(pool.write[i], pool.write[j]);
		}
		for (int i = 0; i < MIN(want, pool.size()); i++) {
			chosen.push_back(pool[i]);
		}
	}
	for (const Edge &e : chosen) {
		Dictionary d;
		d["a"] = e.a;
		d["b"] = e.b;
		d["length"] = e.length;
		result.push_back(d);
	}
	return result;
}

double CgameRoadNetwork::route_cost(const Vector2 &p_a, const Vector2 &p_b, const Callable &p_height_at, double p_slope_penalty) {
	const double dist = p_a.distance_to(p_b);
	if (dist <= 0.0001) {
		return 0.0;
	}
	ERR_FAIL_COND_V_MSG(!p_height_at.is_valid(), 0.0, "CgameRoadNetwork.route_cost: height_at is not a valid Callable.");
	const int steps = MAX(1, (int)Math::ceil(dist / SAMPLE_STEP));
	double cost = 0.0;
	Vector2 prev = p_a;
	double prev_h = p_height_at.call(p_a);
	for (int i = 1; i <= steps; i++) {
		const Vector2 p = p_a.lerp(p_b, (real_t)i / (real_t)steps);
		const double ph = p_height_at.call(p);
		cost += prev.distance_to(p) + p_slope_penalty * Math::abs(ph - prev_h);
		prev = p;
		prev_h = ph;
	}
	return cost;
}

void CgameRoadNetwork::_bind_methods() {
	ClassDB::bind_static_method("CgameRoadNetwork", D_METHOD("connect_sites", "sites", "extra_edge_ratio", "seed"), &CgameRoadNetwork::connect_sites, DEFVAL(0.15), DEFVAL(0));
	ClassDB::bind_static_method("CgameRoadNetwork", D_METHOD("route_cost", "a", "b", "height_at", "slope_penalty"), &CgameRoadNetwork::route_cost);
}
