/**************************************************************************/
/*  cgame_dynamic_carver.cpp                                              */
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

#include "cgame_dynamic_carver.h"

#include "cgame_navigation_util.h"

#include "core/math/geometry_2d.h"
#include "core/object/class_db.h"

Vector<Vector2> CgameDynamicCarver::_rect_poly(const Rect2 &p_rect) {
	Vector<Vector2> out;
	Vector2 end = p_rect.position + p_rect.size;
	out.push_back(p_rect.position);
	out.push_back(Vector2(end.x, p_rect.position.y));
	out.push_back(end);
	out.push_back(Vector2(p_rect.position.x, end.y));
	return out;
}

Rect2 CgameDynamicCarver::_bounds_of(const Vector<Vector2> &p_poly) {
	Vector2 lo = p_poly[0];
	Vector2 hi = p_poly[0];
	for (const Vector2 &p : p_poly) {
		lo = Vector2(MIN(lo.x, p.x), MIN(lo.y, p.y));
		hi = Vector2(MAX(hi.x, p.x), MAX(hi.y, p.y));
	}
	return Rect2(lo, hi - lo);
}

real_t CgameDynamicCarver::_area(const Vector<Vector2> &p_poly) {
	real_t s = 0.0;
	int n = p_poly.size();
	for (int i = 0; i < n; i++) {
		s += p_poly[i].cross(p_poly[(i + 1) % n]);
	}
	return Math::abs(s) * 0.5;
}

Vector2 CgameDynamicCarver::_centroid(const Vector<Vector2> &p_poly) {
	Vector2 c;
	for (const Vector2 &p : p_poly) {
		c += p;
	}
	return c / real_t(p_poly.size());
}

real_t CgameDynamicCarver::_tri2(const Vector2 &p_a, const Vector2 &p_b, const Vector2 &p_c) {
	real_t ax = p_b.x - p_a.x;
	real_t ay = p_b.y - p_a.y;
	real_t bx = p_c.x - p_a.x;
	real_t by = p_c.y - p_a.y;
	return bx * ay - ax * by;
}

bool CgameDynamicCarver::is_convex(const PackedVector2Array &p_poly) {
	int n = p_poly.size();
	if (n < 3) {
		return false;
	}
	real_t sign_seen = 0.0;
	for (int i = 0; i < n; i++) {
		Vector2 a = p_poly[i];
		Vector2 b = p_poly[(i + 1) % n];
		Vector2 c = p_poly[(i + 2) % n];
		real_t cr = (b - a).cross(c - b);
		if (Math::abs(cr) < 1.0e-6) {
			continue;
		}
		if (sign_seen == 0.0) {
			sign_seen = SIGN(cr);
		} else if (SIGN(cr) != sign_seen) {
			return false;
		}
	}
	return true;
}

void CgameDynamicCarver::_clear_nodes() {
	tile_nodes.clear();
	node_poly.clear();
	node_rect.clear();
	node_tile.clear();
	links.clear();
	dirty.clear();
	dirty_set.clear();
	events.clear();
}

Rect2 CgameDynamicCarver::_tile_rect(const Vector2i &p_tile) const {
	return Rect2(bounds.position + Vector2(p_tile) * tile_size, Vector2(tile_size, tile_size));
}

Vector2i CgameDynamicCarver::tile_of(const Vector2 &p_point) const {
	return Vector2i(Math::floor((p_point.x - bounds.position.x) / tile_size), Math::floor((p_point.y - bounds.position.y) / tile_size));
}

void CgameDynamicCarver::setup(const Rect2 &p_bounds, real_t p_tile_size, real_t p_agent_radius) {
	bounds = p_bounds;
	tile_size = MAX(p_tile_size, (real_t)1.0);
	agent_radius = MAX(p_agent_radius, (real_t)0.0);
	tiles_x = MAX(1, (int)Math::ceil(bounds.size.x / tile_size));
	tiles_y = MAX(1, (int)Math::ceil(bounds.size.y / tile_size));
	_clear_nodes();
	base.clear();
	for (int ty = 0; ty < tiles_y; ty++) {
		for (int tx = 0; tx < tiles_x; tx++) {
			Vector2i t(tx, ty);
			Vector<Vector<Vector2>> polys;
			polys.push_back(_rect_poly(_tile_rect(t)));
			base[t] = polys;
		}
	}
	_rebuild_all();
}

void CgameDynamicCarver::set_walkable(const Array &p_polys) {
	_clear_nodes();
	for (int ty = 0; ty < tiles_y; ty++) {
		for (int tx = 0; tx < tiles_x; tx++) {
			Vector2i t(tx, ty);
			Vector<Vector2> rect_poly = _rect_poly(_tile_rect(t));
			Vector<Vector<Vector2>> out;
			for (int i = 0; i < p_polys.size(); i++) {
				Vector<Vector2> poly = p_polys[i];
				Vector<Vector<Vector2>> res = Geometry2D::intersect_polygons(poly, rect_poly);
				for (const Vector<Vector2> &r : res) {
					if (!Geometry2D::is_polygon_clockwise(r) && _area(r) > EPS) {
						out.push_back(r);
					}
				}
			}
			base[t] = out;
		}
	}
	_rebuild_all();
}

Vector<Vector<Vector2>> CgameDynamicCarver::_make_carvers(const Variant &p_shape, Obstacle &r_obstacle) const {
	Vector<Vector<Vector2>> out;
	if (p_shape.get_type() == Variant::DICTIONARY) {
		Dictionary d = p_shape;
		Vector2 center = d.get("center", Vector2());
		real_t raw_radius = d.get("radius", 1.0);
		real_t radius = raw_radius + agent_radius;
		int segs = MAX((int)d.get("segments", 12), 6);
		real_t rr = radius / Math::cos(Math::PI / real_t(segs)); // Circumscribed so the polygon covers the circle.
		Vector<Vector2> poly;
		Vector<Vector2> outline;
		for (int i = 0; i < segs; i++) {
			real_t ang = Math::TAU * real_t(i) / real_t(segs);
			poly.push_back(center + Vector2(Math::cos(ang), Math::sin(ang)) * rr);
			outline.push_back(center + Vector2(Math::cos(ang), Math::sin(ang)) * raw_radius);
		}
		out.push_back(poly);
		r_obstacle.outline = outline;
		r_obstacle.is_circle = true;
		r_obstacle.circle_center = center;
		r_obstacle.circle_radius = raw_radius;
	} else if (p_shape.get_type() == Variant::PACKED_VECTOR2_ARRAY) {
		Vector<Vector2> src = p_shape;
		if (src.size() < 3) {
			return out;
		}
		r_obstacle.outline = src;
		if (agent_radius > 0.0) {
			Vector<Vector<Vector2>> grown = Geometry2D::offset_polygon(src, agent_radius, Geometry2D::JOIN_MITER);
			for (const Vector<Vector2> &g : grown) {
				if (!Geometry2D::is_polygon_clockwise(g)) {
					out.push_back(g);
				}
			}
		} else {
			out.push_back(src);
		}
	}
	return out;
}

void CgameDynamicCarver::_mark_rect_dirty(const Rect2 &p_rect) {
	Vector2i lo = tile_of(p_rect.position - Vector2(EPS, EPS));
	Vector2i hi = tile_of(p_rect.position + p_rect.size + Vector2(EPS, EPS));
	for (int ty = MAX(lo.y, 0); ty <= MIN(hi.y, tiles_y - 1); ty++) {
		for (int tx = MAX(lo.x, 0); tx <= MIN(hi.x, tiles_x - 1); tx++) {
			Vector2i t(tx, ty);
			if (!dirty_set.has(t)) {
				dirty_set.insert(t);
				dirty.push_back(t);
			}
		}
	}
}

void CgameDynamicCarver::add_obstacle(const Variant &p_id, const Variant &p_shape) {
	if (id_to_slot.has(p_id)) {
		remove_obstacle(p_id);
	}
	Obstacle ob;
	ob.carvers = _make_carvers(p_shape, ob);
	if (ob.carvers.is_empty()) {
		return;
	}
	bool first = true;
	for (const Vector<Vector2> &cv : ob.carvers) {
		Rect2 b = _bounds_of(cv);
		ob.rect = first ? b : ob.rect.merge(b);
		first = false;
	}
	_create_server_obstacle(ob);
	Rect2 rect = ob.rect;
	int slot = next_slot++;
	id_to_slot[p_id] = slot;
	obstacles[slot] = ob;
	_mark_rect_dirty(rect);
}

bool CgameDynamicCarver::remove_obstacle(const Variant &p_id) {
	if (!id_to_slot.has(p_id)) {
		return false;
	}
	int slot = id_to_slot[p_id];
	id_to_slot.erase(p_id);
	HashMap<int, Obstacle>::Iterator it = obstacles.find(slot);
	if (!it) {
		return false;
	}
	Rect2 rect = it->value.rect;
	_free_server_obstacle(it->value);
	obstacles.remove(it);
	_mark_rect_dirty(rect);
	return true;
}

bool CgameDynamicCarver::on_destroyed(const Variant &p_id) {
	return remove_obstacle(p_id);
}

bool CgameDynamicCarver::has_obstacle(const Variant &p_id) const {
	return id_to_slot.has(p_id);
}

int CgameDynamicCarver::update(int p_max_tiles_per_call) {
	int done = 0;
	while (!dirty.is_empty() && (p_max_tiles_per_call <= 0 || done < p_max_tiles_per_call)) {
		Vector2i t = dirty[0];
		dirty.remove_at(0);
		dirty_set.erase(t);
		_rebuild_tile(t);
		events.push_back(t);
		if (rebake_callable.is_valid()) {
			Variant vt = t;
			Variant vr = _tile_rect(t);
			const Variant *args[2] = { &vt, &vr };
			Variant ret;
			Callable::CallError ce;
			rebake_callable.callp(args, 2, ret, ce);
		}
		done++;
	}
	if (done > 0) {
		version++;
	}
	return done;
}

TypedArray<Vector2i> CgameDynamicCarver::consume_changed_tiles() {
	TypedArray<Vector2i> out;
	for (const Vector2i &t : events) {
		out.push_back(t);
	}
	events.clear();
	return out;
}

int CgameDynamicCarver::tile_version(const Vector2i &p_tile) const {
	HashMap<Vector2i, int>::ConstIterator it = tile_versions.find(p_tile);
	return it ? it->value : 0;
}

TypedArray<PackedVector2Array> CgameDynamicCarver::polygons_in_tile(const Vector2i &p_tile) const {
	TypedArray<PackedVector2Array> out;
	HashMap<Vector2i, Vector<int>>::ConstIterator it = tile_nodes.find(p_tile);
	if (!it) {
		return out;
	}
	for (int n : it->value) {
		out.push_back(node_poly[n]);
	}
	return out;
}

bool CgameDynamicCarver::is_walkable(const Vector2 &p_point) const {
	return _node_at(p_point) != 0;
}

void CgameDynamicCarver::_rebuild_all() {
	for (int ty = 0; ty < tiles_y; ty++) {
		for (int tx = 0; tx < tiles_x; tx++) {
			_rebuild_tile(Vector2i(tx, ty));
		}
	}
	tiles_rebuilt_total = 0;
	tile_versions.clear();
}

void CgameDynamicCarver::_rebuild_tile(const Vector2i &p_tile) {
	_remove_tile_nodes(p_tile);
	Vector<Vector<Vector2>> polys = base[p_tile];
	Rect2 rect = _tile_rect(p_tile).grow(EPS);
	for (const KeyValue<int, Obstacle> &kv : obstacles) {
		const Obstacle &ob = kv.value;
		if (!ob.rect.intersects(rect)) {
			continue;
		}
		for (const Vector<Vector2> &cv : ob.carvers) {
			polys = _subtract(polys, cv);
		}
		if (polys.is_empty()) {
			break;
		}
	}
	Vector<int> ids;
	for (const Vector<Vector2> &p : polys) {
		Vector<Vector<Vector2>> pieces;
		if (is_convex(p)) {
			pieces.push_back(p);
		} else {
			pieces = Geometry2D::decompose_polygon_in_convex(p);
		}
		for (const Vector<Vector2> &piece : pieces) {
			if (piece.size() < 3 || _area(piece) < EPS) {
				continue;
			}
			int nid = next_node++;
			node_poly[nid] = piece;
			node_rect[nid] = _bounds_of(piece);
			node_tile[nid] = p_tile;
			links[nid] = Vector<Link>();
			ids.push_back(nid);
		}
	}
	tile_nodes[p_tile] = ids;
	tile_versions[p_tile] = tile_version(p_tile) + 1;
	tiles_rebuilt_total++;
	// Re-link the new nodes against this tile and its 8 neighbours.
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			Vector2i nt = p_tile + Vector2i(dx, dy);
			HashMap<Vector2i, Vector<int>>::Iterator nit = tile_nodes.find(nt);
			if (!nit) {
				continue;
			}
			Vector<int> others = nit->value;
			for (int a : ids) {
				for (int b : others) {
					if (nt != p_tile || a < b) {
						_try_link(a, b);
					}
				}
			}
		}
	}
}

void CgameDynamicCarver::_remove_tile_nodes(const Vector2i &p_tile) {
	HashMap<Vector2i, Vector<int>>::Iterator it = tile_nodes.find(p_tile);
	if (!it) {
		return;
	}
	for (int n : it->value) {
		HashMap<int, Vector<Link>>::Iterator lit = links.find(n);
		if (lit) {
			for (const Link &lk : lit->value) {
				HashMap<int, Vector<Link>>::Iterator back = links.find(lk.to);
				if (!back) {
					continue;
				}
				for (int i = back->value.size() - 1; i >= 0; i--) {
					if (back->value[i].to == n) {
						back->value.remove_at(i);
					}
				}
			}
			links.remove(lit);
		}
		node_poly.erase(n);
		node_rect.erase(n);
		node_tile.erase(n);
	}
	it->value = Vector<int>();
}

void CgameDynamicCarver::_try_link(int p_a, int p_b) {
	Rect2 ra = node_rect[p_a];
	Rect2 rb = node_rect[p_b];
	if (!ra.grow(EPS * 4.0).intersects(rb)) {
		return;
	}
	const Vector<Vector2> &pa = node_poly[p_a];
	const Vector<Vector2> &pb = node_poly[p_b];
	for (int i = 0; i < pa.size(); i++) {
		Vector2 a0 = pa[i];
		Vector2 a1 = pa[(i + 1) % pa.size()];
		real_t seg_len = a0.distance_to(a1);
		if (seg_len < EPS) {
			continue;
		}
		Vector2 d = (a1 - a0) / seg_len;
		for (int j = 0; j < pb.size(); j++) {
			Vector2 b0 = pb[j];
			Vector2 b1 = pb[(j + 1) % pb.size()];
			if (Math::abs(d.cross(b0 - a0)) > EPS || Math::abs(d.cross(b1 - a0)) > EPS) {
				continue;
			}
			real_t tb0 = d.dot(b0 - a0);
			real_t tb1 = d.dot(b1 - a0);
			real_t lo = MAX((real_t)0.0, MIN(tb0, tb1));
			real_t hi = MIN(seg_len, MAX(tb0, tb1));
			if (hi - lo > 0.01) {
				Link ab;
				ab.to = p_b;
				ab.a = a0 + d * lo;
				ab.b = a0 + d * hi;
				Link ba = ab;
				ba.to = p_a;
				links[p_a].push_back(ab);
				links[p_b].push_back(ba);
				return;
			}
		}
	}
}

const CgameDynamicCarver::Link *CgameDynamicCarver::_link_between(int p_a, int p_b) const {
	HashMap<int, Vector<Link>>::ConstIterator it = links.find(p_a);
	if (!it) {
		return nullptr;
	}
	for (const Link &lk : it->value) {
		if (lk.to == p_b) {
			return &lk;
		}
	}
	return nullptr;
}

int CgameDynamicCarver::_node_at(const Vector2 &p_point) const {
	HashMap<Vector2i, Vector<int>>::ConstIterator it = tile_nodes.find(tile_of(p_point));
	if (!it) {
		return 0;
	}
	for (int n : it->value) {
		const Rect2 &r = node_rect[n];
		if (r.grow(EPS).has_point(p_point) && _inside(node_poly[n], p_point)) {
			return n;
		}
	}
	return 0;
}

bool CgameDynamicCarver::_inside(const Vector<Vector2> &p_poly, const Vector2 &p_point) {
	if (Geometry2D::is_point_in_polygon(p_point, p_poly)) {
		return true;
	}
	// Boundary counts as walkable.
	for (int i = 0; i < p_poly.size(); i++) {
		Vector2 a = p_poly[i];
		Vector2 b = p_poly[(i + 1) % p_poly.size()];
		if (Geometry2D::get_closest_point_to_segment(p_point, a, b).distance_to(p_point) < EPS) {
			return true;
		}
	}
	return false;
}

Vector<Vector<Vector2>> CgameDynamicCarver::_subtract(const Vector<Vector<Vector2>> &p_polys, const Vector<Vector2> &p_carver) const {
	Vector<Vector<Vector2>> out;
	Rect2 cr = _bounds_of(p_carver);
	for (const Vector<Vector2> &p : p_polys) {
		if (!_bounds_of(p).grow(EPS).intersects(cr)) {
			out.push_back(p);
		} else {
			_clip_into(p, p_carver, cr, out, 0);
		}
	}
	return out;
}

void CgameDynamicCarver::_clip_into(const Vector<Vector2> &p_poly, const Vector<Vector2> &p_carver, const Rect2 &p_carver_rect, Vector<Vector<Vector2>> &r_out, int p_depth) const {
	Vector<Vector<Vector2>> res = Geometry2D::clip_polygons(p_poly, p_carver);
	bool has_hole = false;
	for (const Vector<Vector2> &r : res) {
		if (Geometry2D::is_polygon_clockwise(r)) {
			has_hole = true;
		}
	}
	if (!has_hole || p_depth >= 3) {
		for (const Vector<Vector2> &r : res) {
			if (!Geometry2D::is_polygon_clockwise(r) && _area(r) > EPS) {
				r_out.push_back(r);
			}
		}
		return;
	}
	// Hole: cut the polygon in two through the carver's centre so neither half contains it entirely.
	Rect2 pb = _bounds_of(p_poly).grow(1.0);
	Vector2 c = p_carver_rect.get_center();
	Vector2 pb_end = pb.position + pb.size;
	Vector<Vector<Vector2>> halves;
	if (p_depth % 2 == 0) {
		halves.push_back(_rect_poly(Rect2(pb.position, Vector2(c.x - pb.position.x, pb.size.y))));
		halves.push_back(_rect_poly(Rect2(Vector2(c.x, pb.position.y), Vector2(pb_end.x - c.x, pb.size.y))));
	} else {
		halves.push_back(_rect_poly(Rect2(pb.position, Vector2(pb.size.x, c.y - pb.position.y))));
		halves.push_back(_rect_poly(Rect2(Vector2(pb.position.x, c.y), Vector2(pb.size.x, pb_end.y - c.y))));
	}
	for (const Vector<Vector2> &h : halves) {
		Vector<Vector<Vector2>> parts = Geometry2D::intersect_polygons(p_poly, h);
		for (const Vector<Vector2> &part : parts) {
			if (!Geometry2D::is_polygon_clockwise(part) && _area(part) > EPS) {
				_clip_into(part, p_carver, p_carver_rect, r_out, p_depth + 1);
			}
		}
	}
}

PackedVector2Array CgameDynamicCarver::find_path(const Vector2 &p_from, const Vector2 &p_to) const {
	int sn = _node_at(p_from);
	int en = _node_at(p_to);
	if (sn == 0 || en == 0) {
		return PackedVector2Array();
	}
	if (sn == en) {
		PackedVector2Array direct;
		direct.push_back(p_from);
		direct.push_back(p_to);
		return direct;
	}
	HashMap<int, real_t> g;
	HashMap<int, Vector2> pos;
	HashMap<int, int> came;
	Vector<int> open;
	HashSet<int> closed;
	g[sn] = 0.0;
	pos[sn] = p_from;
	open.push_back(sn);
	bool found = false;
	while (!open.is_empty()) {
		int bi = 0;
		real_t bf = Math::INF;
		for (int i = 0; i < open.size(); i++) {
			int n = open[i];
			real_t f = g[n] + pos[n].distance_to(p_to);
			if (f < bf) {
				bf = f;
				bi = i;
			}
		}
		int cur = open[bi];
		open.remove_at(bi);
		if (cur == en) {
			found = true;
			break;
		}
		closed.insert(cur);
		Vector2 cur_pos = pos[cur];
		HashMap<int, Vector<Link>>::ConstIterator lit = links.find(cur);
		if (!lit) {
			continue;
		}
		for (const Link &lk : lit->value) {
			int nb = lk.to;
			if (closed.has(nb)) {
				continue;
			}
			Vector2 mid = (lk.a + lk.b) * 0.5;
			real_t ng = g[cur] + cur_pos.distance_to(mid);
			if (!g.has(nb) || ng < g[nb]) {
				g[nb] = ng;
				pos[nb] = mid;
				came[nb] = cur;
				if (!open.has(nb)) {
					open.push_back(nb);
				}
			}
		}
	}
	if (!found) {
		return PackedVector2Array();
	}
	Vector<int> corridor;
	corridor.push_back(en);
	int walk = en;
	while (came.has(walk)) {
		walk = came[walk];
		corridor.insert(0, walk);
	}
	Vector<Vector2> lefts;
	Vector<Vector2> rights;
	for (int i = 0; i + 1 < corridor.size(); i++) {
		int from_n = corridor[i];
		int to_n = corridor[i + 1];
		const Link *link = _link_between(from_n, to_n);
		if (!link) {
			return PackedVector2Array();
		}
		Vector2 c = _centroid(node_poly[from_n]);
		if ((link->a - c).cross(link->b - c) < 0.0) {
			lefts.push_back(link->a);
			rights.push_back(link->b);
		} else {
			lefts.push_back(link->b);
			rights.push_back(link->a);
		}
	}
	return _funnel(p_from, p_to, lefts, rights);
}

// "Simple stupid funnel" string pulling (Mikko Mononen, zlib), adapted to 2D y-down.
Vector<Vector2> CgameDynamicCarver::_funnel(const Vector2 &p_start, const Vector2 &p_goal, const Vector<Vector2> &p_lefts, const Vector<Vector2> &p_rights) {
	Vector<Vector2> pl;
	pl.push_back(p_start);
	pl.append_array(p_lefts);
	pl.push_back(p_goal);
	Vector<Vector2> pr;
	pr.push_back(p_start);
	pr.append_array(p_rights);
	pr.push_back(p_goal);
	Vector<Vector2> out;
	out.push_back(p_start);
	Vector2 apex = p_start;
	Vector2 lft = p_start;
	Vector2 rgt = p_start;
	int apex_i = 0;
	int left_i = 0;
	int right_i = 0;
	int i = 1;
	int n = pl.size();
	int guard = 0;
	while (i < n && guard < n * n + 16) {
		guard++;
		Vector2 l = pl[i];
		Vector2 r = pr[i];
		if (_tri2(apex, rgt, r) <= 0.0) {
			if (apex.is_equal_approx(rgt) || _tri2(apex, lft, r) > 0.0) {
				rgt = r;
				right_i = i;
			} else {
				out.push_back(lft);
				apex = lft;
				apex_i = left_i;
				lft = apex;
				rgt = apex;
				left_i = apex_i;
				right_i = apex_i;
				i = apex_i + 1;
				continue;
			}
		}
		if (_tri2(apex, lft, l) >= 0.0) {
			if (apex.is_equal_approx(lft) || _tri2(apex, rgt, l) < 0.0) {
				lft = l;
				left_i = i;
			} else {
				out.push_back(rgt);
				apex = rgt;
				apex_i = right_i;
				lft = apex;
				rgt = apex;
				left_i = apex_i;
				right_i = apex_i;
				i = apex_i + 1;
				continue;
			}
		}
		i++;
	}
	if (!out[out.size() - 1].is_equal_approx(p_goal)) {
		out.push_back(p_goal);
	}
	return out;
}

bool CgameDynamicCarver::path_affected(const PackedVector2Array &p_path, const TypedArray<Vector2i> &p_changed) const {
	if (p_changed.is_empty()) {
		return false;
	}
	for (int i = 0; i + 1 < p_path.size(); i++) {
		Vector2 a = p_path[i];
		Vector2 b = p_path[i + 1];
		int steps = MAX(1, (int)Math::ceil(a.distance_to(b) / (tile_size * 0.5)));
		for (int s = 0; s <= steps; s++) {
			Vector2i t = tile_of(a.lerp(b, real_t(s) / real_t(steps)));
			if (p_changed.has(t)) {
				return true;
			}
		}
	}
	return false;
}

// ---------------------------------------------------------------- engine integration

void CgameDynamicCarver::_create_server_obstacle(Obstacle &r_obstacle) {
	if (!server_map.is_valid() || !CgameNavigationUtil::is_server_functional()) {
		return;
	}
	NavigationServer3D *server = NavigationServer3D::get_singleton();
	RID ob = server->obstacle_create();
	server->obstacle_set_map(ob, server_map);
	server->obstacle_set_height(ob, server_height);
	server->obstacle_set_avoidance_enabled(ob, true);
	if (r_obstacle.is_circle) {
		server->obstacle_set_radius(ob, r_obstacle.circle_radius + agent_radius);
		server->obstacle_set_position(ob, Vector3(r_obstacle.circle_center.x, server_y, r_obstacle.circle_center.y));
	} else {
		Vector<Vector3> verts;
		for (const Vector2 &v : r_obstacle.outline) {
			verts.push_back(Vector3(v.x, 0.0, v.y));
		}
		server->obstacle_set_position(ob, Vector3(0.0, server_y, 0.0));
		server->obstacle_set_vertices(ob, verts);
	}
	r_obstacle.server_obstacle = ob;
}

void CgameDynamicCarver::_free_server_obstacle(Obstacle &r_obstacle) {
	if (r_obstacle.server_obstacle.is_valid() && CgameNavigationUtil::is_server_functional()) {
		NavigationServer3D::get_singleton()->free_rid(r_obstacle.server_obstacle);
	}
	r_obstacle.server_obstacle = RID();
}

void CgameDynamicCarver::_release_server_obstacles() {
	for (KeyValue<int, Obstacle> &kv : obstacles) {
		_free_server_obstacle(kv.value);
	}
}

void CgameDynamicCarver::set_server_map(const RID &p_map, real_t p_y, real_t p_height) {
	_release_server_obstacles();
	server_map = p_map;
	server_y = p_y;
	server_height = p_height;
	if (!server_map.is_valid()) {
		return;
	}
	for (KeyValue<int, Obstacle> &kv : obstacles) {
		_create_server_obstacle(kv.value);
	}
}

int CgameDynamicCarver::get_server_obstacle_count() const {
	int count = 0;
	for (const KeyValue<int, Obstacle> &kv : obstacles) {
		if (kv.value.server_obstacle.is_valid()) {
			count++;
		}
	}
	return count;
}

int CgameDynamicCarver::export_obstructions(const Ref<NavigationMeshSourceGeometryData3D> &p_source, real_t p_elevation, real_t p_height, const Rect2 &p_rect) const {
	ERR_FAIL_COND_V(p_source.is_null(), 0);
	bool filter = p_rect.has_area();
	int added = 0;
	for (const KeyValue<int, Obstacle> &kv : obstacles) {
		const Obstacle &ob = kv.value;
		if (filter && !ob.rect.intersects(p_rect)) {
			continue;
		}
		for (const Vector<Vector2> &cv : ob.carvers) {
			Vector<Vector3> verts;
			for (const Vector2 &v : cv) {
				verts.push_back(Vector3(v.x, p_elevation, v.y));
			}
			p_source->add_projected_obstruction(verts, p_elevation, p_height, true);
			added++;
		}
	}
	return added;
}

CgameDynamicCarver::~CgameDynamicCarver() {
	_release_server_obstacles();
}

void CgameDynamicCarver::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "bounds", "tile_size", "agent_radius"), &CgameDynamicCarver::setup);
	ClassDB::bind_method(D_METHOD("set_walkable", "polygons"), &CgameDynamicCarver::set_walkable);
	ClassDB::bind_method(D_METHOD("add_obstacle", "id", "shape"), &CgameDynamicCarver::add_obstacle);
	ClassDB::bind_method(D_METHOD("remove_obstacle", "id"), &CgameDynamicCarver::remove_obstacle);
	ClassDB::bind_method(D_METHOD("on_destroyed", "id"), &CgameDynamicCarver::on_destroyed);
	ClassDB::bind_method(D_METHOD("has_obstacle", "id"), &CgameDynamicCarver::has_obstacle);
	ClassDB::bind_method(D_METHOD("get_obstacle_count"), &CgameDynamicCarver::get_obstacle_count);
	ClassDB::bind_method(D_METHOD("pending_tiles"), &CgameDynamicCarver::pending_tiles);
	ClassDB::bind_method(D_METHOD("update", "max_tiles_per_call"), &CgameDynamicCarver::update, DEFVAL(4));
	ClassDB::bind_method(D_METHOD("consume_changed_tiles"), &CgameDynamicCarver::consume_changed_tiles);
	ClassDB::bind_method(D_METHOD("tile_version", "tile"), &CgameDynamicCarver::tile_version);
	ClassDB::bind_method(D_METHOD("tile_count"), &CgameDynamicCarver::tile_count);
	ClassDB::bind_method(D_METHOD("tile_of", "point"), &CgameDynamicCarver::tile_of);
	ClassDB::bind_method(D_METHOD("polygons_in_tile", "tile"), &CgameDynamicCarver::polygons_in_tile);
	ClassDB::bind_method(D_METHOD("is_walkable", "point"), &CgameDynamicCarver::is_walkable);
	ClassDB::bind_static_method("CgameDynamicCarver", D_METHOD("is_convex", "polygon"), &CgameDynamicCarver::is_convex);
	ClassDB::bind_method(D_METHOD("find_path", "from", "to"), &CgameDynamicCarver::find_path);
	ClassDB::bind_method(D_METHOD("path_affected", "path", "changed"), &CgameDynamicCarver::path_affected);
	ClassDB::bind_method(D_METHOD("get_version"), &CgameDynamicCarver::get_version);
	ClassDB::bind_method(D_METHOD("get_tiles_rebuilt_total"), &CgameDynamicCarver::get_tiles_rebuilt_total);
	ClassDB::bind_method(D_METHOD("get_tile_size"), &CgameDynamicCarver::get_tile_size);
	ClassDB::bind_method(D_METHOD("get_agent_radius"), &CgameDynamicCarver::get_agent_radius);
	ClassDB::bind_method(D_METHOD("get_bounds"), &CgameDynamicCarver::get_bounds);
	ClassDB::bind_method(D_METHOD("set_server_map", "map", "y", "height"), &CgameDynamicCarver::set_server_map, DEFVAL(0.0), DEFVAL(2.0));
	ClassDB::bind_method(D_METHOD("get_server_map"), &CgameDynamicCarver::get_server_map);
	ClassDB::bind_method(D_METHOD("get_server_obstacle_count"), &CgameDynamicCarver::get_server_obstacle_count);
	ClassDB::bind_method(D_METHOD("export_obstructions", "source_geometry", "elevation", "height", "rect"), &CgameDynamicCarver::export_obstructions, DEFVAL(Rect2()));
	ClassDB::bind_method(D_METHOD("set_rebake_callable", "callable"), &CgameDynamicCarver::set_rebake_callable);
	ClassDB::bind_method(D_METHOD("get_rebake_callable"), &CgameDynamicCarver::get_rebake_callable);
}
