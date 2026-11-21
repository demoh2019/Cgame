/**************************************************************************/
/*  navmesh_stitching.cpp                                                 */
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

#include "navmesh_stitching.h"

#include "navmesh_funnel.h"

#include "core/math/geometry_2d.h"
#include "core/object/class_db.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"

namespace {
struct Link {
	int to = 0;
	Vector2 left;
	Vector2 right;
};

void tile_rect(const Dictionary &p_tile, real_t r_pos[2], real_t r_end[2]) {
	Vector2 o = p_tile["origin"];
	real_t s = p_tile["size"];
	r_pos[0] = o.x;
	r_pos[1] = o.y;
	r_end[0] = o.x + s;
	r_end[1] = o.y + s;
}
} //namespace

float NavMeshStitching::_cross(const Vector2 &p_a, const Vector2 &p_b) {
	return p_a.x * p_b.y - p_a.y * p_b.x;
}

void NavMeshStitching::_orient(const Vector2 &p_p1, const Vector2 &p_p2, const Vector2 &p_from, Vector2 &r_left, Vector2 &r_right) {
	Vector2 mid = (p_p1 + p_p2) * 0.5f;
	Vector2 d = mid - p_from;
	if (_cross(d, p_p1 - mid) >= 0.0f) {
		r_left = p_p1;
		r_right = p_p2;
	} else {
		r_left = p_p2;
		r_right = p_p1;
	}
}

Vector2 NavMeshStitching::_centroid(const PackedVector2Array &p_poly) {
	Vector2 c;
	for (const Vector2 &p : p_poly) {
		c += p;
	}
	return c / MAX((real_t)p_poly.size(), (real_t)1.0);
}

Array NavMeshStitching::stitch(const Dictionary &p_tile_a, const Dictionary &p_tile_b, double p_tolerance) {
	Array links;
	real_t a_lo_v[2], a_hi_v[2], b_lo_v[2], b_hi_v[2];
	tile_rect(p_tile_a, a_lo_v, a_hi_v);
	tile_rect(p_tile_b, b_lo_v, b_hi_v);
	Array polys_a = p_tile_a["polygons"];
	Array polys_b = p_tile_b["polygons"];
	// axis 0: border is a vertical line (x const), edges run along y; axis 1: the reverse.
	for (int axis = 0; axis < 2; axis++) {
		double a_hi = a_hi_v[axis];
		double b_lo = b_lo_v[axis];
		double a_lo = a_lo_v[axis];
		double b_hi = b_hi_v[axis];
		double border = 0.0;
		if (Math::abs(a_hi - b_lo) <= p_tolerance) {
			border = (a_hi + b_lo) * 0.5;
		} else if (Math::abs(b_hi - a_lo) <= p_tolerance) {
			border = (b_hi + a_lo) * 0.5;
		} else {
			continue;
		}
		int other = 1 - axis;
		if (MIN(a_hi_v[other], b_hi_v[other]) - MAX(a_lo_v[other], b_lo_v[other]) < -p_tolerance) {
			continue;
		}
		for (int ia = 0; ia < polys_a.size(); ia++) {
			PackedVector2Array pa = polys_a[ia];
			Vector2 ca = _centroid(pa);
			for (int ea = 0; ea < pa.size(); ea++) {
				Vector2 a0 = pa[ea];
				Vector2 a1 = pa[(ea + 1) % pa.size()];
				if (Math::abs(a0[axis] - border) > p_tolerance || Math::abs(a1[axis] - border) > p_tolerance) {
					continue;
				}
				double amin = MIN(a0[other], a1[other]);
				double amax = MAX(a0[other], a1[other]);
				for (int ib = 0; ib < polys_b.size(); ib++) {
					PackedVector2Array pb = polys_b[ib];
					for (int eb = 0; eb < pb.size(); eb++) {
						Vector2 b0 = pb[eb];
						Vector2 b1 = pb[(eb + 1) % pb.size()];
						if (Math::abs(b0[axis] - border) > p_tolerance || Math::abs(b1[axis] - border) > p_tolerance) {
							continue;
						}
						double lo = MAX(amin, (double)MIN(b0[other], b1[other]));
						double hi = MIN(amax, (double)MAX(b0[other], b1[other]));
						if (hi - lo <= p_tolerance) {
							continue;
						}
						Vector2 q0, q1;
						q0[axis] = border;
						q0[other] = lo;
						q1[axis] = border;
						q1[other] = hi;
						Vector2 l, r;
						_orient(q0, q1, ca, l, r);
						Dictionary link;
						link["poly_a"] = ia;
						link["poly_b"] = ib;
						link["left"] = l;
						link["right"] = r;
						links.push_back(link);
					}
				}
			}
		}
	}
	return links;
}

Dictionary NavMeshStitching::build_graph(const Array &p_tiles, double p_tolerance) {
	Array polys;
	PackedVector2Array centers;
	PackedInt32Array tile_of;
	PackedInt32Array offsets;
	for (int ti = 0; ti < p_tiles.size(); ti++) {
		Dictionary t = p_tiles[ti];
		offsets.push_back(polys.size());
		Array tp = t["polygons"];
		for (int i = 0; i < tp.size(); i++) {
			PackedVector2Array poly = tp[i];
			polys.push_back(poly);
			centers.push_back(_centroid(poly));
			tile_of.push_back(ti);
		}
	}
	LocalVector<LocalVector<Link>> links;
	links.resize(polys.size());
	auto add_link = [&](int p_from, int p_to, const Vector2 &p_p1, const Vector2 &p_p2) {
		Link l;
		l.to = p_to;
		_orient(p_p1, p_p2, centers[p_from], l.left, l.right);
		links[p_from].push_back(l);
	};
	// intra-tile adjacency: shared (reversed or equal) edges
	for (int ti = 0; ti < p_tiles.size(); ti++) {
		int off = offsets[ti];
		Array tp = Dictionary(p_tiles[ti])["polygons"];
		for (int i = 0; i < tp.size(); i++) {
			PackedVector2Array pi = tp[i];
			for (int j = i + 1; j < tp.size(); j++) {
				PackedVector2Array pj = tp[j];
				bool found = false;
				for (int ei = 0; ei < pi.size() && !found; ei++) {
					Vector2 a0 = pi[ei];
					Vector2 a1 = pi[(ei + 1) % pi.size()];
					for (int ej = 0; ej < pj.size(); ej++) {
						Vector2 b0 = pj[ej];
						Vector2 b1 = pj[(ej + 1) % pj.size()];
						bool rev = a0.distance_to(b1) <= p_tolerance && a1.distance_to(b0) <= p_tolerance;
						bool same = a0.distance_to(b0) <= p_tolerance && a1.distance_to(b1) <= p_tolerance;
						if (rev || same) {
							add_link(off + i, off + j, a0, a1);
							add_link(off + j, off + i, a0, a1);
							found = true;
							break;
						}
					}
				}
			}
		}
	}
	// cross-tile portals
	for (int ta = 0; ta < p_tiles.size(); ta++) {
		for (int tb = ta + 1; tb < p_tiles.size(); tb++) {
			Array portals = stitch(p_tiles[ta], p_tiles[tb], p_tolerance);
			for (int k = 0; k < portals.size(); k++) {
				Dictionary link = portals[k];
				int ga = offsets[ta] + (int)link["poly_a"];
				int gb = offsets[tb] + (int)link["poly_b"];
				add_link(ga, gb, link["left"], link["right"]);
				add_link(gb, ga, link["left"], link["right"]);
			}
		}
	}
	Array links_out;
	for (const LocalVector<Link> &lv : links) {
		Array arr;
		for (const Link &l : lv) {
			Dictionary d;
			d["to"] = l.to;
			d["left"] = l.left;
			d["right"] = l.right;
			arr.push_back(d);
		}
		links_out.push_back(arr);
	}
	Dictionary graph;
	graph["polys"] = polys;
	graph["centers"] = centers;
	graph["links"] = links_out;
	graph["tile_of"] = tile_of;
	graph["offsets"] = offsets;
	return graph;
}

int NavMeshStitching::_locate(const Dictionary &p_graph, const Vector2 &p_point) {
	Array polys = p_graph["polys"];
	for (int i = 0; i < polys.size(); i++) {
		PackedVector2Array poly = polys[i];
		if (Geometry2D::is_point_in_polygon(p_point, poly)) {
			return i;
		}
	}
	PackedVector2Array centers = p_graph["centers"];
	int best = -1;
	double best_d = Math::INF;
	for (int i = 0; i < centers.size(); i++) {
		double d = centers[i].distance_squared_to(p_point);
		if (d < best_d) {
			best_d = d;
			best = i;
		}
	}
	return best;
}

PackedVector2Array NavMeshStitching::find_path(const Dictionary &p_graph, const Vector2 &p_start, const Vector2 &p_goal) {
	PackedVector2Array path;
	int si = _locate(p_graph, p_start);
	int gi = _locate(p_graph, p_goal);
	if (si < 0 || gi < 0) {
		return path;
	}
	if (si == gi) {
		path.push_back(p_start);
		path.push_back(p_goal);
		return path;
	}
	Array links_arr = p_graph["links"];
	LocalVector<LocalVector<Link>> links;
	links.resize(links_arr.size());
	for (int i = 0; i < links_arr.size(); i++) {
		Array arr = links_arr[i];
		for (int k = 0; k < arr.size(); k++) {
			Dictionary d = arr[k];
			Link l;
			l.to = d["to"];
			l.left = d["left"];
			l.right = d["right"];
			links[i].push_back(l);
		}
	}
	HashMap<int, double> g;
	HashMap<int, Vector2> pos;
	HashMap<int, int> parent;
	HashMap<int, Link> parent_link;
	HashSet<int> closed;
	LocalVector<int> open;
	g[si] = 0.0;
	pos[si] = p_start;
	open.push_back(si);
	bool found = false;
	while (!open.is_empty()) {
		int bi = 0;
		double bf = Math::INF;
		for (uint32_t oi = 0; oi < open.size(); oi++) {
			int n = open[oi];
			double f = g[n] + pos[n].distance_to(p_goal);
			if (f < bf) {
				bf = f;
				bi = oi;
			}
		}
		int cur = open[bi];
		open.remove_at(bi);
		if (cur == gi) {
			found = true;
			break;
		}
		closed.insert(cur);
		Vector2 cp = pos[cur];
		for (const Link &link : links[cur]) {
			int to = link.to;
			if (closed.has(to)) {
				continue;
			}
			Vector2 entry = (link.left + link.right) * 0.5f;
			double cost = g[cur] + cp.distance_to(entry);
			if (to == gi) {
				cost += entry.distance_to(p_goal);
			}
			if (!g.has(to) || cost < g[to]) {
				g[to] = cost;
				pos[to] = entry;
				parent[to] = cur;
				parent_link[to] = link;
				if (!open.has(to)) {
					open.push_back(to);
				}
			}
		}
	}
	if (!found) {
		return path;
	}
	LocalVector<Link> chain;
	int n2 = gi;
	while (n2 != si) {
		chain.push_back(parent_link[n2]);
		n2 = parent[n2];
	}
	Vector<Vector2> lefts;
	Vector<Vector2> rights;
	lefts.push_back(p_start);
	rights.push_back(p_start);
	for (int i = (int)chain.size() - 1; i >= 0; i--) {
		lefts.push_back(chain[i].left);
		rights.push_back(chain[i].right);
	}
	lefts.push_back(p_goal);
	rights.push_back(p_goal);
	return NavMeshFunnel::funnel(lefts, rights, 10000);
}

PackedVector2Array NavMeshStitching::funnel(const Array &p_portals) {
	Vector<Vector2> lefts;
	Vector<Vector2> rights;
	for (int i = 0; i < p_portals.size(); i++) {
		Array pr = p_portals[i];
		ERR_FAIL_COND_V(pr.size() < 2, PackedVector2Array());
		lefts.push_back(pr[0]);
		rights.push_back(pr[1]);
	}
	return NavMeshFunnel::funnel(lefts, rights, 10000);
}

void NavMeshStitching::_bind_methods() {
	ClassDB::bind_static_method("NavMeshStitching", D_METHOD("stitch", "tile_a", "tile_b", "tolerance"), &NavMeshStitching::stitch);
	ClassDB::bind_static_method("NavMeshStitching", D_METHOD("build_graph", "tiles", "tolerance"), &NavMeshStitching::build_graph);
	ClassDB::bind_static_method("NavMeshStitching", D_METHOD("find_path", "graph", "start", "goal"), &NavMeshStitching::find_path);
	ClassDB::bind_static_method("NavMeshStitching", D_METHOD("funnel", "portals"), &NavMeshStitching::funnel);
}
