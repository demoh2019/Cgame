/**************************************************************************/
/*  cgame_hierarchical_pathfinder.cpp                                     */
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

#include "cgame_hierarchical_pathfinder.h"

#include "cgame_navigation_util.h"

#include "core/object/class_db.h"
#include "core/templates/hash_set.h"

static const Vector2i CGAME_HPA_DIRS[4] = { Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1) };

void CgameHierarchicalPathfinder::Heap::push(double p_key, int p_val) {
	HeapItem item;
	item.key = p_key;
	item.val = p_val;
	items.push_back(item);
	int i = (int)items.size() - 1;
	while (i > 0) {
		int parent = (i - 1) >> 1;
		if (items[parent].key <= items[i].key) {
			break;
		}
		SWAP(items[parent], items[i]);
		i = parent;
	}
}

int CgameHierarchicalPathfinder::Heap::pop() {
	int top = items[0].val;
	int last = (int)items.size() - 1;
	items[0] = items[last];
	items.resize(last);
	int i = 0;
	while (true) {
		int l = i * 2 + 1;
		int r = l + 1;
		int m = i;
		if (l < last && items[l].key < items[m].key) {
			m = l;
		}
		if (r < last && items[r].key < items[m].key) {
			m = r;
		}
		if (m == i) {
			break;
		}
		SWAP(items[i], items[m]);
		i = m;
	}
	return top;
}

bool CgameHierarchicalPathfinder::_cell_in_bounds(const Vector2i &p_cell) const {
	return p_cell.x >= 0 && p_cell.y >= 0 && p_cell.x < width && p_cell.y < height;
}

bool CgameHierarchicalPathfinder::_is_walkable(const Vector2i &p_cell) const {
	if (!_cell_in_bounds(p_cell)) {
		return false;
	}
	return grid[p_cell.y * width + p_cell.x] != 0;
}

Vector2i CgameHierarchicalPathfinder::_cluster_of(const Vector2i &p_cell) const {
	return Vector2i(p_cell.x / cluster_size, p_cell.y / cluster_size);
}

int CgameHierarchicalPathfinder::_cidx(const Vector2i &p_cluster) const {
	return p_cluster.y * cw + p_cluster.x;
}

Rect2i CgameHierarchicalPathfinder::_cluster_rect(const Vector2i &p_cluster) const {
	Vector2i pos = p_cluster * cluster_size;
	return Rect2i(pos, Vector2i(MIN(cluster_size, width - pos.x), MIN(cluster_size, height - pos.y)));
}

int CgameHierarchicalPathfinder::_add_node(const Vector2i &p_cell) {
	HashMap<Vector2i, int>::Iterator existing = node_at.find(p_cell);
	if (existing) {
		return existing->value;
	}
	int id = (int)n_cell.size();
	Vector2i c = _cluster_of(p_cell);
	n_cell.push_back(p_cell);
	n_cluster.push_back(_cidx(c));
	n_alive.push_back(1);
	adj.push_back(HashMap<int, int>());
	node_at[p_cell] = id;
	cluster_nodes[_cidx(c)].push_back(id);
	return id;
}

void CgameHierarchicalPathfinder::_remove_node(int p_id) {
	if (n_alive[p_id] == 0) {
		return;
	}
	for (const KeyValue<int, int> &kv : adj[p_id]) {
		adj[kv.key].erase(p_id);
	}
	adj[p_id].clear();
	n_alive[p_id] = 0;
	node_at.erase(n_cell[p_id]);
	Vector<int> &list = cluster_nodes[n_cluster[p_id]];
	list.erase(p_id);
}

bool CgameHierarchicalPathfinder::_has_inter_edge(int p_id) const {
	for (const KeyValue<int, int> &kv : adj[p_id]) {
		if (n_cluster[kv.key] != n_cluster[p_id]) {
			return true;
		}
	}
	return false;
}

void CgameHierarchicalPathfinder::_link_pair(Vector2i p_a, Vector2i p_b) {
	if (p_b.x < p_a.x || p_b.y < p_a.y) {
		SWAP(p_a, p_b);
	}
	Rect2i ra = _cluster_rect(p_a);
	bool horizontal = p_b.x > p_a.x;
	Vector<Vector2i> from_cells;
	Vector<Vector2i> to_cells;
	if (horizontal) {
		for (int y = ra.position.y; y < ra.position.y + ra.size.y; y++) {
			from_cells.push_back(Vector2i(ra.position.x + ra.size.x - 1, y));
			to_cells.push_back(Vector2i(ra.position.x + ra.size.x, y));
		}
	} else {
		for (int x = ra.position.x; x < ra.position.x + ra.size.x; x++) {
			from_cells.push_back(Vector2i(x, ra.position.y + ra.size.y - 1));
			to_cells.push_back(Vector2i(x, ra.position.y + ra.size.y));
		}
	}
	int run_start = -1;
	for (int i = 0; i < from_cells.size() + 1; i++) {
		bool open = i < from_cells.size() && _is_walkable(from_cells[i]) && _is_walkable(to_cells[i]);
		if (open && run_start < 0) {
			run_start = i;
		} else if (!open && run_start >= 0) {
			int run_end = i - 1;
			Vector<int> picks;
			if (run_end - run_start + 1 > LONG_RUN) {
				picks.push_back(run_start);
				picks.push_back(run_end);
			} else {
				picks.push_back((run_start + run_end) >> 1);
			}
			for (int p : picks) {
				int na = _add_node(from_cells[p]);
				int nb = _add_node(to_cells[p]);
				adj[na][nb] = 1;
				adj[nb][na] = 1;
			}
			run_start = -1;
		}
	}
}

HashMap<int, int> CgameHierarchicalPathfinder::_flood(const Vector2i &p_from, const Rect2i &p_rect) const {
	HashMap<int, int> dist;
	LocalVector<int> queue;
	int start_key = p_from.y * width + p_from.x;
	queue.push_back(start_key);
	dist[start_key] = 0;
	uint32_t head = 0;
	while (head < queue.size()) {
		int cur = queue[head++];
		Vector2i cell(cur % width, cur / width);
		int d = dist[cur];
		for (const Vector2i &dir : CGAME_HPA_DIRS) {
			Vector2i n = cell + dir;
			if (!p_rect.has_point(n) || !_is_walkable(n)) {
				continue;
			}
			int ni = n.y * width + n.x;
			if (dist.has(ni)) {
				continue;
			}
			dist[ni] = d + 1;
			queue.push_back(ni);
		}
	}
	return dist;
}

void CgameHierarchicalPathfinder::_build_intra(const Vector2i &p_cluster) {
	Vector<int> ids = cluster_nodes[_cidx(p_cluster)];
	Rect2i rect = _cluster_rect(p_cluster);
	for (int id : ids) {
		HashMap<int, int> keep;
		for (const KeyValue<int, int> &kv : adj[id]) {
			if (n_cluster[kv.key] != n_cluster[id]) {
				keep[kv.key] = kv.value;
			}
		}
		adj[id] = keep;
	}
	for (int id : ids) {
		HashMap<int, int> dist = _flood(n_cell[id], rect);
		for (int other : ids) {
			if (other == id) {
				continue;
			}
			int key = n_cell[other].y * width + n_cell[other].x;
			HashMap<int, int>::ConstIterator it = dist.find(key);
			if (it) {
				adj[id][other] = it->value;
			}
		}
	}
}

void CgameHierarchicalPathfinder::_build_graph() {
	cw = (width + cluster_size - 1) / cluster_size;
	ch = (height + cluster_size - 1) / cluster_size;
	n_cell.clear();
	n_cluster.clear();
	n_alive.clear();
	adj.clear();
	node_at.clear();
	route_cache.clear();
	cache_hits = 0;
	cluster_nodes.clear();
	cluster_nodes.resize(MAX(0, cw * ch));
	for (int cy = 0; cy < ch; cy++) {
		for (int cx = 0; cx < cw; cx++) {
			if (cx + 1 < cw) {
				_link_pair(Vector2i(cx, cy), Vector2i(cx + 1, cy));
			}
			if (cy + 1 < ch) {
				_link_pair(Vector2i(cx, cy), Vector2i(cx, cy + 1));
			}
		}
	}
	for (int cy = 0; cy < ch; cy++) {
		for (int cx = 0; cx < cw; cx++) {
			_build_intra(Vector2i(cx, cy));
		}
	}
}

void CgameHierarchicalPathfinder::build(int p_width, int p_height, int p_cluster_size, const Callable &p_walkable) {
	ERR_FAIL_COND_MSG(p_width <= 0 || p_height <= 0, "Grid size must be positive.");
	ERR_FAIL_COND_MSG(!p_walkable.is_valid(), "Walkable callable is invalid.");
	width = p_width;
	height = p_height;
	cluster_size = MAX(2, p_cluster_size);
	walkable_callable = p_walkable;
	grid.resize(width * height);
	for (int y = 0; y < height; y++) {
		for (int x = 0; x < width; x++) {
			Variant vx = x;
			Variant vy = y;
			const Variant *args[2] = { &vx, &vy };
			Variant ret;
			Callable::CallError ce;
			walkable_callable.callp(args, 2, ret, ce);
			grid.write[y * width + x] = (ce.error == Callable::CallError::CALL_OK && bool(ret)) ? 1 : 0;
		}
	}
	_build_graph();
}

void CgameHierarchicalPathfinder::build_from_grid(int p_width, int p_height, int p_cluster_size, const PackedByteArray &p_cells) {
	ERR_FAIL_COND_MSG(p_width <= 0 || p_height <= 0, "Grid size must be positive.");
	ERR_FAIL_COND_MSG(p_cells.size() < (int64_t)p_width * p_height, "Cell array is smaller than width * height.");
	width = p_width;
	height = p_height;
	cluster_size = MAX(2, p_cluster_size);
	walkable_callable = Callable();
	grid.resize(width * height);
	for (int i = 0; i < width * height; i++) {
		grid.write[i] = p_cells[i] != 0 ? 1 : 0;
	}
	_build_graph();
}

HashMap<int, int> CgameHierarchicalPathfinder::_reach(const Vector2i &p_cell, const Vector2i &p_cluster) const {
	HashMap<int, int> dist = _flood(p_cell, _cluster_rect(p_cluster));
	HashMap<int, int> out;
	for (int id : cluster_nodes[_cidx(p_cluster)]) {
		int key = n_cell[id].y * width + n_cell[id].x;
		HashMap<int, int>::ConstIterator it = dist.find(key);
		if (it) {
			out[id] = it->value;
		}
	}
	return out;
}

bool CgameHierarchicalPathfinder::_route_ok(const Vector<int> &p_route, const HashMap<int, int> &p_start_edges, const HashMap<int, int> &p_goal_costs) const {
	if (p_route.is_empty() || !p_start_edges.has(p_route[0]) || !p_goal_costs.has(p_route[p_route.size() - 1])) {
		return false;
	}
	for (int i = 0; i < p_route.size(); i++) {
		if (n_alive[p_route[i]] == 0) {
			return false;
		}
		if (i > 0 && !adj[p_route[i - 1]].has(p_route[i])) {
			return false;
		}
	}
	return true;
}

int CgameHierarchicalPathfinder::_manhattan(const Vector2i &p_a, const Vector2i &p_b) {
	return Math::abs(p_a.x - p_b.x) + Math::abs(p_a.y - p_b.y);
}

Vector<int> CgameHierarchicalPathfinder::_abstract(const Vector2i &p_goal, const HashMap<int, int> &p_start_edges, const HashMap<int, int> &p_goal_costs) const {
	HashMap<int, int> g;
	HashMap<int, int> came;
	HashSet<int> closed;
	Heap heap;
	for (const KeyValue<int, int> &kv : p_start_edges) {
		g[kv.key] = kv.value;
		came[kv.key] = -1;
		heap.push(kv.value + _manhattan(n_cell[kv.key], p_goal), kv.key);
	}
	while (!heap.is_empty()) {
		int cur = heap.pop();
		if (cur == -2) {
			break;
		}
		if (closed.has(cur)) {
			continue;
		}
		closed.insert(cur);
		int gc = g[cur];
		HashMap<int, int>::ConstIterator gi = p_goal_costs.find(cur);
		if (gi) {
			int total = gc + gi->value;
			int best = g.has(-2) ? g[-2] : FAR;
			if (total < best) {
				g[-2] = total;
				came[-2] = cur;
				heap.push(total, -2);
			}
		}
		for (const KeyValue<int, int> &kv : adj[cur]) {
			int to = kv.key;
			int ng = gc + kv.value;
			int old = g.has(to) ? g[to] : FAR;
			if (ng < old) {
				g[to] = ng;
				came[to] = cur;
				heap.push(ng + _manhattan(n_cell[to], p_goal), to);
			}
		}
	}
	Vector<int> route;
	if (!came.has(-2)) {
		return route;
	}
	int n = came[-2];
	while (n != -1) {
		route.push_back(n);
		n = came[n];
	}
	route.reverse();
	return route;
}

bool CgameHierarchicalPathfinder::_astar(const Vector2i &p_start, const Vector2i &p_goal, const Rect2i &p_rect, Vector<Vector2i> &r_out) const {
	r_out.clear();
	HashMap<int, int> g;
	HashMap<int, int> came;
	HashSet<int> closed;
	Heap heap;
	int si = p_start.y * width + p_start.x;
	int gi = p_goal.y * width + p_goal.x;
	g[si] = 0;
	heap.push(_manhattan(p_start, p_goal), si);
	while (!heap.is_empty()) {
		int cur = heap.pop();
		if (cur == gi) {
			Vector<Vector2i> rev;
			int n = gi;
			while (n != si) {
				rev.push_back(Vector2i(n % width, n / width));
				n = came[n];
			}
			rev.push_back(p_start);
			rev.reverse();
			r_out = rev;
			return true;
		}
		if (closed.has(cur)) {
			continue;
		}
		closed.insert(cur);
		Vector2i cell(cur % width, cur / width);
		int cg = g[cur];
		for (const Vector2i &dir : CGAME_HPA_DIRS) {
			Vector2i nb = cell + dir;
			if (!p_rect.has_point(nb) || !_is_walkable(nb)) {
				continue;
			}
			int ni = nb.y * width + nb.x;
			int old = g.has(ni) ? g[ni] : FAR;
			if (cg + 1 < old) {
				g[ni] = cg + 1;
				came[ni] = cur;
				heap.push(cg + 1 + _manhattan(nb, p_goal), ni);
			}
		}
	}
	return false;
}

bool CgameHierarchicalPathfinder::_append_segment(Vector<Vector2i> &r_path, const Vector<Vector2i> &p_seg) {
	if (p_seg.is_empty()) {
		return false;
	}
	for (int i = 0; i < p_seg.size(); i++) {
		if (i == 0 && !r_path.is_empty() && r_path[r_path.size() - 1] == p_seg[0]) {
			continue;
		}
		r_path.push_back(p_seg[i]);
	}
	return true;
}

Vector<Vector2i> CgameHierarchicalPathfinder::_refine(const Vector2i &p_start, const Vector2i &p_goal, const Vector<int> &p_route) const {
	Vector<Vector2i> path;
	Vector<Vector2i> seg;
	Vector2i first = n_cell[p_route[0]];
	if (!_astar(p_start, first, _cluster_rect(_cluster_of(p_start)), seg) || !_append_segment(path, seg)) {
		return Vector<Vector2i>();
	}
	for (int i = 1; i < p_route.size(); i++) {
		int a = p_route[i - 1];
		int b = p_route[i];
		seg.clear();
		if (n_cluster[a] == n_cluster[b]) {
			Rect2i rect = _cluster_rect(_cluster_of(n_cell[a]));
			if (!_astar(n_cell[a], n_cell[b], rect, seg)) {
				return Vector<Vector2i>();
			}
		} else {
			seg.push_back(n_cell[a]);
			seg.push_back(n_cell[b]);
		}
		if (!_append_segment(path, seg)) {
			return Vector<Vector2i>();
		}
	}
	Vector2i last = n_cell[p_route[p_route.size() - 1]];
	if (!_astar(last, p_goal, _cluster_rect(_cluster_of(p_goal)), seg) || !_append_segment(path, seg)) {
		return Vector<Vector2i>();
	}
	return path;
}

Vector<Vector2i> CgameHierarchicalPathfinder::_find_cells(const Vector2i &p_start, const Vector2i &p_goal) {
	Vector<Vector2i> empty;
	if (width <= 0 || !_is_walkable(p_start) || !_is_walkable(p_goal)) {
		return empty;
	}
	if (p_start == p_goal) {
		Vector<Vector2i> single;
		single.push_back(p_start);
		return single;
	}
	Vector2i sc = _cluster_of(p_start);
	Vector2i gc = _cluster_of(p_goal);
	if (sc == gc) {
		Vector<Vector2i> direct;
		if (_astar(p_start, p_goal, _cluster_rect(sc), direct)) {
			return direct;
		}
	}
	HashMap<int, int> start_edges = _reach(p_start, sc);
	HashMap<int, int> goal_costs = _reach(p_goal, gc);
	if (start_edges.is_empty() || goal_costs.is_empty()) {
		return empty;
	}
	Vector2i key(_cidx(sc), _cidx(gc));
	Vector<int> route;
	HashMap<Vector2i, Vector<int>>::Iterator cached = route_cache.find(key);
	if (cached && _route_ok(cached->value, start_edges, goal_costs)) {
		route = cached->value;
		cache_hits++;
	}
	if (route.is_empty()) {
		route = _abstract(p_goal, start_edges, goal_costs);
		if (route.is_empty()) {
			return empty;
		}
		route_cache[key] = route;
	}
	return _refine(p_start, p_goal, route);
}

PackedVector2Array CgameHierarchicalPathfinder::find_path(const Vector2i &p_start, const Vector2i &p_goal) {
	Vector<Vector2i> cells = _find_cells(p_start, p_goal);
	PackedVector2Array out;
	out.resize(cells.size());
	for (int i = 0; i < cells.size(); i++) {
		out.write[i] = Vector2(cells[i]);
	}
	return out;
}

Vector<Vector2i> CgameHierarchicalPathfinder::find_path_cells(const Vector2i &p_start, const Vector2i &p_goal) {
	return _find_cells(p_start, p_goal);
}

void CgameHierarchicalPathfinder::set_cell_walkable(const Vector2i &p_cell, bool p_walkable) {
	ERR_FAIL_COND(!_cell_in_bounds(p_cell));
	grid.write[p_cell.y * width + p_cell.x] = p_walkable ? 1 : 0;
	// Rebuild just the cluster; avoid re-querying the callable when one is set.
	Callable saved = walkable_callable;
	walkable_callable = Callable();
	invalidate_cluster(p_cell);
	walkable_callable = saved;
}

void CgameHierarchicalPathfinder::invalidate_cluster(const Vector2i &p_cell) {
	if (!_cell_in_bounds(p_cell)) {
		return;
	}
	Vector2i c = _cluster_of(p_cell);
	Rect2i rect = _cluster_rect(c);
	if (walkable_callable.is_valid()) {
		for (int y = rect.position.y; y < rect.position.y + rect.size.y; y++) {
			for (int x = rect.position.x; x < rect.position.x + rect.size.x; x++) {
				Variant vx = x;
				Variant vy = y;
				const Variant *args[2] = { &vx, &vy };
				Variant ret;
				Callable::CallError ce;
				walkable_callable.callp(args, 2, ret, ce);
				grid.write[y * width + x] = (ce.error == Callable::CallError::CALL_OK && bool(ret)) ? 1 : 0;
			}
		}
	}
	route_cache.clear();
	Vector<Vector2i> neighbors;
	for (const Vector2i &d : CGAME_HPA_DIRS) {
		Vector2i n = c + d;
		if (n.x >= 0 && n.y >= 0 && n.x < cw && n.y < ch) {
			neighbors.push_back(n);
		}
	}
	Vector<int> own = cluster_nodes[_cidx(c)];
	for (int id : own) {
		_remove_node(id);
	}
	for (const Vector2i &n : neighbors) {
		Vector<int> ours = cluster_nodes[_cidx(n)];
		for (int id : ours) {
			if (!_has_inter_edge(id)) {
				_remove_node(id);
			}
		}
	}
	for (const Vector2i &n : neighbors) {
		_link_pair(c, n);
	}
	_build_intra(c);
	for (const Vector2i &n : neighbors) {
		_build_intra(n);
	}
}

bool CgameHierarchicalPathfinder::is_cell_walkable(const Vector2i &p_cell) const {
	return _is_walkable(p_cell);
}

int CgameHierarchicalPathfinder::node_count() const {
	int total = 0;
	for (uint32_t i = 0; i < n_alive.size(); i++) {
		total += n_alive[i];
	}
	return total;
}

void CgameHierarchicalPathfinder::set_world_mapping(const Vector2 &p_origin_xz, real_t p_cell_size) {
	ERR_FAIL_COND_MSG(p_cell_size <= 0.0, "Cell size must be positive.");
	world_origin = p_origin_xz;
	world_cell_size = p_cell_size;
}

Vector2i CgameHierarchicalPathfinder::world_to_cell(const Vector3 &p_world) const {
	return Vector2i(Math::floor((p_world.x - world_origin.x) / world_cell_size), Math::floor((p_world.z - world_origin.y) / world_cell_size));
}

Vector3 CgameHierarchicalPathfinder::cell_to_world(const Vector2i &p_cell, real_t p_y) const {
	return Vector3(world_origin.x + (p_cell.x + 0.5) * world_cell_size, p_y, world_origin.y + (p_cell.y + 0.5) * world_cell_size);
}

Vector<Vector3> CgameHierarchicalPathfinder::plan_waypoints(const Vector3 &p_from, const Vector3 &p_to, real_t p_region_size) {
	Vector<Vector3> waypoints;
	real_t region = MAX(p_region_size, world_cell_size);
	waypoints.push_back(p_from);
	Vector2i a = world_to_cell(p_from);
	Vector2i b = world_to_cell(p_to);
	if (width > 0 && _cell_in_bounds(a) && _cell_in_bounds(b)) {
		Vector<Vector2i> cells = _find_cells(a, b);
		if (cells.is_empty()) {
			return Vector<Vector3>(); // Unreachable at the coarse level.
		}
		auto region_of = [&](const Vector2i &p_cell) {
			Vector3 w = cell_to_world(p_cell);
			return Vector2i(Math::floor((w.x - world_origin.x) / region), Math::floor((w.z - world_origin.y) / region));
		};
		Vector2i current_region = region_of(cells[0]);
		for (int i = 1; i < cells.size() - 1; i++) {
			Vector2i r = region_of(cells[i]);
			if (r != current_region) {
				current_region = r;
				real_t t = real_t(i) / real_t(cells.size() - 1);
				waypoints.push_back(cell_to_world(cells[i], Math::lerp(p_from.y, p_to.y, t)));
			}
		}
	} else {
		real_t dist = Vector2(p_from.x, p_from.z).distance_to(Vector2(p_to.x, p_to.z));
		int steps = (int)Math::ceil(dist / region);
		for (int i = 1; i < steps; i++) {
			waypoints.push_back(p_from.lerp(p_to, real_t(i) / real_t(steps)));
		}
	}
	waypoints.push_back(p_to);
	return waypoints;
}

Vector<Vector3> CgameHierarchicalPathfinder::plan_on_map(const RID &p_map, const Vector3 &p_from, const Vector3 &p_to, real_t p_region_size, uint32_t p_navigation_layers) {
	Vector<Vector3> result;
	if (!CgameNavigationUtil::is_server_functional() || !p_map.is_valid()) {
		return result;
	}
	NavigationServer3D *server = NavigationServer3D::get_singleton();
	Vector<Vector3> waypoints = plan_waypoints(p_from, p_to, p_region_size);
	if (waypoints.is_empty()) {
		return result;
	}
	// Snap intermediate waypoints onto the navmesh; the end points are kept for the server to handle.
	for (int i = 1; i < waypoints.size() - 1; i++) {
		waypoints.write[i] = server->map_get_closest_point(p_map, waypoints[i]);
	}
	for (int i = 0; i + 1 < waypoints.size(); i++) {
		Vector<Vector3> seg = server->map_get_path(p_map, waypoints[i], waypoints[i + 1], true, p_navigation_layers);
		if (seg.is_empty()) {
			return Vector<Vector3>();
		}
		for (int k = 0; k < seg.size(); k++) {
			if (k == 0 && !result.is_empty() && result[result.size() - 1].is_equal_approx(seg[0])) {
				continue;
			}
			result.push_back(seg[k]);
		}
	}
	return result;
}

void CgameHierarchicalPathfinder::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build", "width", "height", "cluster_size", "walkable"), &CgameHierarchicalPathfinder::build);
	ClassDB::bind_method(D_METHOD("build_from_grid", "width", "height", "cluster_size", "cells"), &CgameHierarchicalPathfinder::build_from_grid);
	ClassDB::bind_method(D_METHOD("find_path", "start", "goal"), &CgameHierarchicalPathfinder::find_path);
	ClassDB::bind_method(D_METHOD("set_cell_walkable", "cell", "walkable"), &CgameHierarchicalPathfinder::set_cell_walkable);
	ClassDB::bind_method(D_METHOD("invalidate_cluster", "cell"), &CgameHierarchicalPathfinder::invalidate_cluster);
	ClassDB::bind_method(D_METHOD("is_cell_walkable", "cell"), &CgameHierarchicalPathfinder::is_cell_walkable);
	ClassDB::bind_method(D_METHOD("node_count"), &CgameHierarchicalPathfinder::node_count);
	ClassDB::bind_method(D_METHOD("get_cache_hits"), &CgameHierarchicalPathfinder::get_cache_hits);
	ClassDB::bind_method(D_METHOD("get_width"), &CgameHierarchicalPathfinder::get_width);
	ClassDB::bind_method(D_METHOD("get_height"), &CgameHierarchicalPathfinder::get_height);
	ClassDB::bind_method(D_METHOD("get_cluster_size"), &CgameHierarchicalPathfinder::get_cluster_size);
	ClassDB::bind_method(D_METHOD("set_world_mapping", "origin_xz", "cell_size"), &CgameHierarchicalPathfinder::set_world_mapping);
	ClassDB::bind_method(D_METHOD("world_to_cell", "world"), &CgameHierarchicalPathfinder::world_to_cell);
	ClassDB::bind_method(D_METHOD("cell_to_world", "cell", "y"), &CgameHierarchicalPathfinder::cell_to_world, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("plan_waypoints", "from", "to", "region_size"), &CgameHierarchicalPathfinder::plan_waypoints);
	ClassDB::bind_method(D_METHOD("plan_on_map", "map", "from", "to", "region_size", "navigation_layers"), &CgameHierarchicalPathfinder::plan_on_map, DEFVAL(1));
}
