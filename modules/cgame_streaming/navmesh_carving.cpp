/**************************************************************************/
/*  navmesh_carving.cpp                                                   */
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

#include "navmesh_carving.h"

#include "navmesh_funnel.h"

#include "core/math/geometry_2d.h"
#include "core/object/class_db.h"

void NavMeshCarving::set_agent_radius(real_t p_radius) {
	agent_radius = MAX(p_radius, (real_t)0.0);
}

real_t NavMeshCarving::get_agent_radius() const {
	return agent_radius;
}

real_t NavMeshCarving::get_tile_size() const {
	return tile_size;
}

Rect2 NavMeshCarving::get_bounds() const {
	return bounds;
}

int NavMeshCarving::get_version() const {
	return version;
}

int NavMeshCarving::get_tiles_rebuilt_total() const {
	return tiles_rebuilt_total;
}

PackedVector2Array NavMeshCarving::_rect_poly(const Rect2 &p_rect) {
	PackedVector2Array poly;
	poly.push_back(p_rect.position);
	poly.push_back(Vector2(p_rect.position.x + p_rect.size.x, p_rect.position.y));
	poly.push_back(p_rect.position + p_rect.size);
	poly.push_back(Vector2(p_rect.position.x, p_rect.position.y + p_rect.size.y));
	return poly;
}

Rect2 NavMeshCarving::_bounds_of(const PackedVector2Array &p_poly) {
	Vector2 lo = p_poly[0];
	Vector2 hi = p_poly[0];
	for (const Vector2 &p : p_poly) {
		lo = Vector2(MIN(lo.x, p.x), MIN(lo.y, p.y));
		hi = Vector2(MAX(hi.x, p.x), MAX(hi.y, p.y));
	}
	return Rect2(lo, hi - lo);
}

real_t NavMeshCarving::_area(const PackedVector2Array &p_poly) {
	real_t s = 0.0;
	int n = p_poly.size();
	for (int i = 0; i < n; i++) {
		s += p_poly[i].cross(p_poly[(i + 1) % n]);
	}
	return Math::abs(s) * 0.5f;
}

real_t NavMeshCarving::polygon_area(const PackedVector2Array &p_poly) {
	return p_poly.is_empty() ? 0.0f : _area(p_poly);
}

Vector2 NavMeshCarving::_centroid(const PackedVector2Array &p_poly) {
	Vector2 c;
	for (const Vector2 &p : p_poly) {
		c += p;
	}
	return c / (real_t)p_poly.size();
}

bool NavMeshCarving::is_convex(const PackedVector2Array &p_poly) {
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
		if (Math::abs(cr) < 1.0e-6f) {
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

Rect2 NavMeshCarving::_tile_rect(const Vector2i &p_tile) const {
	return Rect2(bounds.position + Vector2(p_tile) * tile_size, Vector2(tile_size, tile_size));
}

void NavMeshCarving::_clear_nodes() {
	tile_nodes.clear();
	nodes.clear();
	dirty.clear();
	dirty_set.clear();
	events.clear();
}

void NavMeshCarving::setup(const Rect2 &p_bounds, real_t p_tile_size, real_t p_agent_radius) {
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
			Vector<PackedVector2Array> polys;
			polys.push_back(_rect_poly(_tile_rect(t)));
			base[t] = polys;
		}
	}
	_rebuild_all();
}

void NavMeshCarving::set_walkable(const Array &p_polys) {
	_clear_nodes();
	for (int ty = 0; ty < tiles_y; ty++) {
		for (int tx = 0; tx < tiles_x; tx++) {
			Vector2i t(tx, ty);
			PackedVector2Array rect_poly = _rect_poly(_tile_rect(t));
			Vector<PackedVector2Array> out;
			for (int i = 0; i < p_polys.size(); i++) {
				PackedVector2Array poly = p_polys[i];
				Vector<PackedVector2Array> res = Geometry2D::intersect_polygons(poly, rect_poly);
				for (const PackedVector2Array &r : res) {
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

LocalVector<PackedVector2Array> NavMeshCarving::_make_carvers(const Variant &p_shape) const {
	LocalVector<PackedVector2Array> out;
	if (p_shape.get_type() == Variant::DICTIONARY) {
		Dictionary d = p_shape;
		Vector2 center = d.get("center", Vector2());
		real_t radius = (real_t)(double)d.get("radius", 1.0) + agent_radius;
		int segs = MAX((int)d.get("segments", 12), 6);
		real_t rr = radius / Math::cos(Math::PI / (real_t)segs);
		PackedVector2Array poly;
		for (int i = 0; i < segs; i++) {
			real_t ang = Math::TAU * (real_t)i / (real_t)segs;
			poly.push_back(center + Vector2(Math::cos(ang), Math::sin(ang)) * rr);
		}
		out.push_back(poly);
	} else if (p_shape.get_type() == Variant::PACKED_VECTOR2_ARRAY || p_shape.get_type() == Variant::ARRAY) {
		PackedVector2Array src = p_shape;
		if (src.size() < 3) {
			return out;
		}
		if (agent_radius > 0.0) {
			Vector<PackedVector2Array> grown = Geometry2D::offset_polygon(src, agent_radius, Geometry2D::JOIN_MITER);
			for (const PackedVector2Array &g : grown) {
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

void NavMeshCarving::_mark_rect_dirty(const Rect2 &p_rect) {
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

void NavMeshCarving::add_obstacle(const Variant &p_id, const Variant &p_shape) {
	if (obstacles.has(p_id)) {
		remove_obstacle(p_id);
	}
	LocalVector<PackedVector2Array> carvers = _make_carvers(p_shape);
	if (carvers.is_empty()) {
		return;
	}
	Rect2 rect;
	bool first = true;
	for (const PackedVector2Array &cv : carvers) {
		Rect2 b = _bounds_of(cv);
		rect = first ? b : rect.merge(b);
		first = false;
	}
	Obstacle ob;
	ob.carvers = carvers;
	ob.rect = rect;
	obstacles[p_id] = ob;
	_mark_rect_dirty(rect);
}

bool NavMeshCarving::remove_obstacle(const Variant &p_id) {
	HashMap<Variant, Obstacle, HashMapHasherDefault, StringLikeVariantComparator>::Iterator it = obstacles.find(p_id);
	if (!it) {
		return false;
	}
	Rect2 rect = it->value.rect;
	obstacles.erase(p_id);
	_mark_rect_dirty(rect);
	return true;
}

bool NavMeshCarving::on_destroyed(const Variant &p_id) {
	return remove_obstacle(p_id);
}

bool NavMeshCarving::has_obstacle(const Variant &p_id) const {
	return obstacles.has(p_id);
}

int NavMeshCarving::pending_tiles() const {
	return dirty.size();
}

int NavMeshCarving::update(int p_max_tiles_per_call) {
	int done = 0;
	while (!dirty.is_empty() && (p_max_tiles_per_call <= 0 || done < p_max_tiles_per_call)) {
		Vector2i t = dirty[0];
		dirty.remove_at(0);
		dirty_set.erase(t);
		_rebuild_tile(t);
		events.push_back(t);
		done++;
	}
	if (done > 0) {
		version++;
	}
	return done;
}

TypedArray<Vector2i> NavMeshCarving::consume_changed_tiles() {
	TypedArray<Vector2i> out;
	for (const Vector2i &t : events) {
		out.push_back(t);
	}
	events.clear();
	return out;
}

int NavMeshCarving::tile_version(const Vector2i &p_tile) const {
	HashMap<Vector2i, int>::ConstIterator it = tile_versions.find(p_tile);
	return it ? it->value : 0;
}

Vector2i NavMeshCarving::tile_count() const {
	return Vector2i(tiles_x, tiles_y);
}

Vector2i NavMeshCarving::tile_of(const Vector2 &p_point) const {
	return Vector2i((int)Math::floor((p_point.x - bounds.position.x) / tile_size), (int)Math::floor((p_point.y - bounds.position.y) / tile_size));
}

TypedArray<PackedVector2Array> NavMeshCarving::polygons_in_tile(const Vector2i &p_tile) const {
	TypedArray<PackedVector2Array> out;
	HashMap<Vector2i, PackedInt32Array>::ConstIterator it = tile_nodes.find(p_tile);
	if (!it) {
		return out;
	}
	for (int n : it->value) {
		out.push_back(nodes[n].poly);
	}
	return out;
}

bool NavMeshCarving::is_walkable(const Vector2 &p_point) const {
	return _node_at(p_point) != 0;
}

void NavMeshCarving::_rebuild_all() {
	for (int ty = 0; ty < tiles_y; ty++) {
		for (int tx = 0; tx < tiles_x; tx++) {
			_rebuild_tile(Vector2i(tx, ty));
		}
	}
	tiles_rebuilt_total = 0;
	tile_versions.clear();
}

void NavMeshCarving::_rebuild_tile(const Vector2i &p_tile) {
	_remove_tile_nodes(p_tile);
	Vector<PackedVector2Array> polys = base[p_tile];
	Rect2 rect = _tile_rect(p_tile).grow(EPS);
	for (const KeyValue<Variant, Obstacle> &kv : obstacles) {
		const Obstacle &ob = kv.value;
		if (!ob.rect.intersects(rect)) {
			continue;
		}
		for (const PackedVector2Array &cv : ob.carvers) {
			polys = _subtract(polys, cv);
		}
		if (polys.is_empty()) {
			break;
		}
	}
	PackedInt32Array ids;
	for (const PackedVector2Array &p : polys) {
		Vector<PackedVector2Array> pieces;
		if (is_convex(p)) {
			pieces.push_back(p);
		} else {
			pieces = Geometry2D::decompose_polygon_in_convex(p);
		}
		for (const PackedVector2Array &piece : pieces) {
			if (piece.size() < 3 || _area(piece) < EPS) {
				continue;
			}
			int nid = next_node++;
			NavNode &nn = nodes[nid];
			nn.poly = piece;
			nn.rect = _bounds_of(piece);
			nn.tile = p_tile;
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
			HashMap<Vector2i, PackedInt32Array>::Iterator nit = tile_nodes.find(nt);
			if (!nit) {
				continue;
			}
			PackedInt32Array others = nit->value;
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

void NavMeshCarving::_remove_tile_nodes(const Vector2i &p_tile) {
	HashMap<Vector2i, PackedInt32Array>::Iterator it = tile_nodes.find(p_tile);
	if (!it) {
		return;
	}
	PackedInt32Array ids = it->value;
	for (int n : ids) {
		HashMap<int, NavNode>::Iterator nit = nodes.find(n);
		if (!nit) {
			continue;
		}
		for (const Link &link : nit->value.links) {
			HashMap<int, NavNode>::Iterator oit = nodes.find(link.to);
			if (!oit) {
				continue;
			}
			LocalVector<Link> &back = oit->value.links;
			for (int i = (int)back.size() - 1; i >= 0; i--) {
				if (back[i].to == n) {
					back.remove_at(i);
				}
			}
		}
		nodes.erase(n);
	}
	tile_nodes[p_tile] = PackedInt32Array();
}

void NavMeshCarving::_try_link(int p_a, int p_b) {
	NavNode &na = nodes[p_a];
	NavNode &nb = nodes[p_b];
	if (!na.rect.grow(EPS * 4.0f).intersects(nb.rect)) {
		return;
	}
	const PackedVector2Array &pa = na.poly;
	const PackedVector2Array &pb = nb.poly;
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
			if (hi - lo > 0.01f) {
				Vector2 la = a0 + d * lo;
				Vector2 lb = a0 + d * hi;
				Link l_ab;
				l_ab.to = p_b;
				l_ab.a = la;
				l_ab.b = lb;
				Link l_ba;
				l_ba.to = p_a;
				l_ba.a = la;
				l_ba.b = lb;
				na.links.push_back(l_ab);
				nb.links.push_back(l_ba);
				return;
			}
		}
	}
}

const NavMeshCarving::Link *NavMeshCarving::_link_between(int p_a, int p_b) const {
	HashMap<int, NavNode>::ConstIterator it = nodes.find(p_a);
	if (!it) {
		return nullptr;
	}
	for (const Link &l : it->value.links) {
		if (l.to == p_b) {
			return &l;
		}
	}
	return nullptr;
}

int NavMeshCarving::_node_at(const Vector2 &p_point) const {
	Vector2i t = tile_of(p_point);
	HashMap<Vector2i, PackedInt32Array>::ConstIterator it = tile_nodes.find(t);
	if (!it) {
		return 0;
	}
	for (int n : it->value) {
		const NavNode &nn = nodes[n];
		if (nn.rect.grow(EPS).has_point(p_point) && _inside(nn.poly, p_point)) {
			return n;
		}
	}
	return 0;
}

bool NavMeshCarving::_inside(const PackedVector2Array &p_poly, const Vector2 &p_point) {
	if (Geometry2D::is_point_in_polygon(p_point, p_poly)) {
		return true;
	}
	// Boundary counts as walkable.
	int n = p_poly.size();
	for (int i = 0; i < n; i++) {
		Vector2 a = p_poly[i];
		Vector2 b = p_poly[(i + 1) % n];
		if (Geometry2D::get_closest_point_to_segment(p_point, a, b).distance_to(p_point) < EPS) {
			return true;
		}
	}
	return false;
}

Vector<PackedVector2Array> NavMeshCarving::_subtract(const Vector<PackedVector2Array> &p_polys, const PackedVector2Array &p_carver) const {
	Vector<PackedVector2Array> out;
	Rect2 cr = _bounds_of(p_carver);
	for (const PackedVector2Array &p : p_polys) {
		if (!_bounds_of(p).grow(EPS).intersects(cr)) {
			out.push_back(p);
		} else {
			_clip_into(p, p_carver, cr, out, 0);
		}
	}
	return out;
}

void NavMeshCarving::_clip_into(const PackedVector2Array &p_poly, const PackedVector2Array &p_carver, const Rect2 &p_carver_rect, Vector<PackedVector2Array> &r_out, int p_depth) const {
	Vector<PackedVector2Array> res = Geometry2D::clip_polygons(p_poly, p_carver);
	bool has_hole = false;
	for (const PackedVector2Array &r : res) {
		if (Geometry2D::is_polygon_clockwise(r)) {
			has_hole = true;
		}
	}
	if (!has_hole || p_depth >= 3) {
		for (const PackedVector2Array &r : res) {
			if (!Geometry2D::is_polygon_clockwise(r) && _area(r) > EPS) {
				r_out.push_back(r);
			}
		}
		return;
	}
	// Hole: cut the polygon in two through the carver's centre so neither half contains it entirely.
	Rect2 pb = _bounds_of(p_poly).grow(1.0);
	Vector2 pb_end = pb.position + pb.size;
	Vector2 c = p_carver_rect.get_center();
	Vector<PackedVector2Array> halves;
	if (p_depth % 2 == 0) {
		halves.push_back(_rect_poly(Rect2(pb.position, Vector2(c.x - pb.position.x, pb.size.y))));
		halves.push_back(_rect_poly(Rect2(Vector2(c.x, pb.position.y), Vector2(pb_end.x - c.x, pb.size.y))));
	} else {
		halves.push_back(_rect_poly(Rect2(pb.position, Vector2(pb.size.x, c.y - pb.position.y))));
		halves.push_back(_rect_poly(Rect2(Vector2(pb.position.x, c.y), Vector2(pb.size.x, pb_end.y - c.y))));
	}
	for (const PackedVector2Array &h : halves) {
		Vector<PackedVector2Array> parts = Geometry2D::intersect_polygons(p_poly, h);
		for (const PackedVector2Array &part : parts) {
			if (!Geometry2D::is_polygon_clockwise(part) && _area(part) > EPS) {
				_clip_into(part, p_carver, p_carver_rect, r_out, p_depth + 1);
			}
		}
	}
}

PackedVector2Array NavMeshCarving::find_path(const Vector2 &p_from, const Vector2 &p_to) const {
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
	HashMap<int, double> g;
	HashMap<int, Vector2> pos;
	HashMap<int, int> came;
	HashSet<int> closed;
	LocalVector<int> open;
	g[sn] = 0.0;
	pos[sn] = p_from;
	open.push_back(sn);
	bool found = false;
	while (!open.is_empty()) {
		int bi = 0;
		double bf = Math::INF;
		for (uint32_t i = 0; i < open.size(); i++) {
			int n = open[i];
			double f = g[n] + pos[n].distance_to(p_to);
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
		for (const Link &link : nodes[cur].links) {
			int nb = link.to;
			if (closed.has(nb)) {
				continue;
			}
			Vector2 mid = (link.a + link.b) * 0.5f;
			double ng = g[cur] + cur_pos.distance_to(mid);
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
	LocalVector<int> corridor;
	corridor.push_back(en);
	int walk = en;
	while (came.has(walk)) {
		walk = came[walk];
		corridor.insert(0, walk);
	}
	Vector<Vector2> lefts;
	Vector<Vector2> rights;
	lefts.push_back(p_from);
	rights.push_back(p_from);
	for (uint32_t i = 0; i + 1 < corridor.size(); i++) {
		int from_n = corridor[i];
		int to_n = corridor[i + 1];
		const Link *link = _link_between(from_n, to_n);
		ERR_FAIL_NULL_V(link, PackedVector2Array());
		Vector2 c = _centroid(nodes[from_n].poly);
		if ((link->a - c).cross(link->b - c) < 0.0f) {
			lefts.push_back(link->a);
			rights.push_back(link->b);
		} else {
			lefts.push_back(link->b);
			rights.push_back(link->a);
		}
	}
	lefts.push_back(p_to);
	rights.push_back(p_to);
	int n = lefts.size();
	return NavMeshFunnel::funnel(lefts, rights, n * n + 16);
}

bool NavMeshCarving::path_affected(const PackedVector2Array &p_path, const TypedArray<Vector2i> &p_changed) const {
	if (p_changed.is_empty()) {
		return false;
	}
	HashSet<Vector2i> changed;
	for (int i = 0; i < p_changed.size(); i++) {
		changed.insert(p_changed[i]);
	}
	for (int i = 0; i + 1 < p_path.size(); i++) {
		Vector2 a = p_path[i];
		Vector2 b = p_path[i + 1];
		int steps = MAX(1, (int)Math::ceil(a.distance_to(b) / (tile_size * 0.5f)));
		for (int s = 0; s <= steps; s++) {
			if (changed.has(tile_of(a.lerp(b, (real_t)s / (real_t)steps)))) {
				return true;
			}
		}
	}
	return false;
}

void NavMeshCarving::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_agent_radius", "radius"), &NavMeshCarving::set_agent_radius);
	ClassDB::bind_method(D_METHOD("get_agent_radius"), &NavMeshCarving::get_agent_radius);
	ClassDB::bind_method(D_METHOD("get_tile_size"), &NavMeshCarving::get_tile_size);
	ClassDB::bind_method(D_METHOD("get_bounds"), &NavMeshCarving::get_bounds);
	ClassDB::bind_method(D_METHOD("get_version"), &NavMeshCarving::get_version);
	ClassDB::bind_method(D_METHOD("get_tiles_rebuilt_total"), &NavMeshCarving::get_tiles_rebuilt_total);

	ClassDB::bind_method(D_METHOD("setup", "bounds", "tile_size", "agent_radius"), &NavMeshCarving::setup);
	ClassDB::bind_method(D_METHOD("set_walkable", "polygons"), &NavMeshCarving::set_walkable);
	ClassDB::bind_method(D_METHOD("add_obstacle", "id", "shape"), &NavMeshCarving::add_obstacle);
	ClassDB::bind_method(D_METHOD("remove_obstacle", "id"), &NavMeshCarving::remove_obstacle);
	ClassDB::bind_method(D_METHOD("on_destroyed", "id"), &NavMeshCarving::on_destroyed);
	ClassDB::bind_method(D_METHOD("has_obstacle", "id"), &NavMeshCarving::has_obstacle);
	ClassDB::bind_method(D_METHOD("pending_tiles"), &NavMeshCarving::pending_tiles);
	ClassDB::bind_method(D_METHOD("update", "max_tiles_per_call"), &NavMeshCarving::update, DEFVAL(4));
	ClassDB::bind_method(D_METHOD("consume_changed_tiles"), &NavMeshCarving::consume_changed_tiles);
	ClassDB::bind_method(D_METHOD("tile_version", "tile"), &NavMeshCarving::tile_version);
	ClassDB::bind_method(D_METHOD("tile_count"), &NavMeshCarving::tile_count);
	ClassDB::bind_method(D_METHOD("tile_of", "point"), &NavMeshCarving::tile_of);
	ClassDB::bind_method(D_METHOD("polygons_in_tile", "tile"), &NavMeshCarving::polygons_in_tile);
	ClassDB::bind_method(D_METHOD("is_walkable", "point"), &NavMeshCarving::is_walkable);
	ClassDB::bind_method(D_METHOD("find_path", "from", "to"), &NavMeshCarving::find_path);
	ClassDB::bind_method(D_METHOD("path_affected", "path", "changed"), &NavMeshCarving::path_affected);
	ClassDB::bind_static_method("NavMeshCarving", D_METHOD("is_convex", "polygon"), &NavMeshCarving::is_convex);
	ClassDB::bind_static_method("NavMeshCarving", D_METHOD("polygon_area", "polygon"), &NavMeshCarving::polygon_area);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "agent_radius", PROPERTY_HINT_RANGE, "0,100,0.01,or_greater,suffix:m"), "set_agent_radius", "get_agent_radius");
}
