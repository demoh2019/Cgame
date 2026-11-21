/**************************************************************************/
/*  cgame_off_mesh_link_generator.cpp                                     */
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

#include "cgame_off_mesh_link_generator.h"

#include "cgame_navigation_util.h"

#include "core/object/class_db.h"

static const Vector2i CGAME_LINK_DIRS[2] = { Vector2i(1, 0), Vector2i(0, 1) };

bool CgameOffMeshLinkGenerator::_in(const Vector2i &p_cell) const {
	return p_cell.x >= 0 && p_cell.y >= 0 && p_cell.x < grid_width && p_cell.y < grid_height;
}

bool CgameOffMeshLinkGenerator::_is_walkable(const Vector2i &p_cell) const {
	return _in(p_cell) && walkable_cells[p_cell.y * grid_width + p_cell.x] != 0;
}

float CgameOffMeshLinkGenerator::_height_at(const Vector2i &p_cell) const {
	return heights[p_cell.y * grid_width + p_cell.x];
}

void CgameOffMeshLinkGenerator::_step_link(Vector<Link> &r_links, const Vector2i &p_a, const Vector2i &p_b, float p_dh, float p_max_drop, float p_max_jump_up, float p_walk_step) const {
	float rise = Math::abs(p_dh);
	if (rise <= p_walk_step) {
		return;
	}
	Vector2i upper = p_dh < 0.0f ? p_a : p_b;
	Vector2i lower = p_dh < 0.0f ? p_b : p_a;
	Link link;
	if (rise <= p_max_jump_up) {
		link.from = lower;
		link.to = upper;
		link.kind = "jump";
		link.bidirectional = true;
		r_links.push_back(link);
	} else if (rise <= p_max_drop) {
		link.from = upper;
		link.to = lower;
		link.kind = "drop";
		link.bidirectional = false;
		r_links.push_back(link);
	}
}

void CgameOffMeshLinkGenerator::_gap_link(Vector<Link> &r_links, const Vector2i &p_a, const Vector2i &p_dir, float p_h0, float p_max_jump_up, int p_max_gap) const {
	if (!_in(p_a + p_dir)) {
		return;
	}
	for (int span = 1; span <= p_max_gap; span++) {
		Vector2i cell = p_a + p_dir * (span + 1);
		if (!_in(cell)) {
			return;
		}
		if (!_is_walkable(cell)) {
			continue;
		}
		float dh = Math::abs(_height_at(cell) - p_h0);
		if (dh <= p_max_jump_up) {
			Link link;
			link.from = p_a;
			link.to = cell;
			link.kind = "gap";
			link.bidirectional = true;
			r_links.push_back(link);
		}
		return;
	}
}

Vector<CgameOffMeshLinkGenerator::Link> CgameOffMeshLinkGenerator::_generate(float p_max_drop, float p_max_jump_up, int p_max_gap, float p_walk_step) const {
	Vector<Link> links;
	for (int y = 0; y < grid_height; y++) {
		for (int x = 0; x < grid_width; x++) {
			Vector2i here(x, y);
			if (!_is_walkable(here)) {
				continue;
			}
			float h0 = _height_at(here);
			for (const Vector2i &dir : CGAME_LINK_DIRS) {
				Vector2i n = here + dir;
				if (_is_walkable(n)) {
					_step_link(links, here, n, _height_at(n) - h0, p_max_drop, p_max_jump_up, p_walk_step);
				} else {
					_gap_link(links, here, dir, h0, p_max_jump_up, p_max_gap);
				}
			}
		}
	}
	return links;
}

Array CgameOffMeshLinkGenerator::_links_to_array(const Vector<Link> &p_links) {
	Array out;
	for (const Link &l : p_links) {
		Dictionary d;
		d["from"] = l.from;
		d["to"] = l.to;
		d["kind"] = l.kind;
		d["bidirectional"] = l.bidirectional;
		out.push_back(d);
	}
	return out;
}

Vector<CgameOffMeshLinkGenerator::Link> CgameOffMeshLinkGenerator::_array_to_links(const Array &p_links) {
	Vector<Link> out;
	for (int i = 0; i < p_links.size(); i++) {
		Dictionary d = p_links[i];
		Link l;
		l.from = d.get("from", Vector2i());
		l.to = d.get("to", Vector2i());
		l.kind = d.get("kind", String());
		l.bidirectional = d.get("bidirectional", false);
		out.push_back(l);
	}
	return out;
}

Array CgameOffMeshLinkGenerator::generate_from_arrays(int p_width, int p_height, const PackedFloat32Array &p_heights, const PackedByteArray &p_walkable, float p_max_drop, float p_max_jump_up, int p_max_gap, float p_walk_step) {
	ERR_FAIL_COND_V_MSG(p_width <= 0 || p_height <= 0, Array(), "Grid size must be positive.");
	int64_t count = (int64_t)p_width * p_height;
	ERR_FAIL_COND_V_MSG(p_heights.size() < count || p_walkable.size() < count, Array(), "Height/walkable arrays are smaller than width * height.");
	grid_width = p_width;
	grid_height = p_height;
	heights.resize(count);
	walkable_cells.resize(count);
	for (int64_t i = 0; i < count; i++) {
		heights.write[i] = p_heights[i];
		walkable_cells.write[i] = p_walkable[i] != 0 ? 1 : 0;
	}
	last_links = _generate(p_max_drop, p_max_jump_up, p_max_gap, p_walk_step);
	return _links_to_array(last_links);
}

Array CgameOffMeshLinkGenerator::generate(int p_width, int p_height, const Callable &p_height_at, const Callable &p_walkable, float p_max_drop, float p_max_jump_up, int p_max_gap, float p_walk_step) {
	ERR_FAIL_COND_V_MSG(p_width <= 0 || p_height <= 0, Array(), "Grid size must be positive.");
	ERR_FAIL_COND_V_MSG(!p_height_at.is_valid() || !p_walkable.is_valid(), Array(), "Callables must be valid.");
	PackedFloat32Array hs;
	PackedByteArray ws;
	hs.resize(p_width * p_height);
	ws.resize(p_width * p_height);
	for (int y = 0; y < p_height; y++) {
		for (int x = 0; x < p_width; x++) {
			Variant vx = x;
			Variant vy = y;
			const Variant *args[2] = { &vx, &vy };
			Variant ret;
			Callable::CallError ce;
			p_walkable.callp(args, 2, ret, ce);
			bool walk = ce.error == Callable::CallError::CALL_OK && bool(ret);
			ws.write[y * p_width + x] = walk ? 1 : 0;
			float h = 0.0f;
			if (walk) {
				p_height_at.callp(args, 2, ret, ce);
				h = ce.error == Callable::CallError::CALL_OK ? float(ret) : 0.0f;
			}
			hs.write[y * p_width + x] = h;
		}
	}
	return generate_from_arrays(p_width, p_height, hs, ws, p_max_drop, p_max_jump_up, p_max_gap, p_walk_step);
}

Dictionary CgameOffMeshLinkGenerator::link_world_positions(const Dictionary &p_link, const Vector2 &p_origin_xz, real_t p_cell_size) const {
	Vector2i from = p_link.get("from", Vector2i());
	Vector2i to = p_link.get("to", Vector2i());
	Dictionary out;
	auto world = [&](const Vector2i &p_cell) {
		real_t y = _in(p_cell) ? real_t(_height_at(p_cell)) : real_t(0.0);
		return Vector3(p_origin_xz.x + (p_cell.x + 0.5) * p_cell_size, y, p_origin_xz.y + (p_cell.y + 0.5) * p_cell_size);
	};
	out["start"] = world(from);
	out["end"] = world(to);
	return out;
}

int CgameOffMeshLinkGenerator::create_links_on_map(const RID &p_map, const Vector2 &p_origin_xz, real_t p_cell_size, const Array &p_links, uint32_t p_navigation_layers, real_t p_enter_cost, real_t p_travel_cost) {
	if (!CgameNavigationUtil::is_server_functional() || !p_map.is_valid()) {
		return 0;
	}
	NavigationServer3D *server = NavigationServer3D::get_singleton();
	Vector<Link> links = p_links.is_empty() ? last_links : _array_to_links(p_links);
	int created = 0;
	for (const Link &l : links) {
		Dictionary d;
		d["from"] = l.from;
		d["to"] = l.to;
		Dictionary pos = link_world_positions(d, p_origin_xz, p_cell_size);
		RID link = server->link_create();
		server->link_set_map(link, p_map);
		server->link_set_enabled(link, true);
		server->link_set_bidirectional(link, l.bidirectional);
		server->link_set_navigation_layers(link, p_navigation_layers);
		server->link_set_start_position(link, pos["start"]);
		server->link_set_end_position(link, pos["end"]);
		server->link_set_enter_cost(link, p_enter_cost);
		server->link_set_travel_cost(link, p_travel_cost);
		server_links.push_back(link);
		created++;
	}
	return created;
}

void CgameOffMeshLinkGenerator::clear_map_links() {
	if (CgameNavigationUtil::is_server_functional()) {
		NavigationServer3D *server = NavigationServer3D::get_singleton();
		for (const RID &link : server_links) {
			server->free_rid(link);
		}
	}
	server_links.clear();
}

CgameOffMeshLinkGenerator::~CgameOffMeshLinkGenerator() {
	clear_map_links();
}

void CgameOffMeshLinkGenerator::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate", "width", "height", "height_at", "walkable", "max_drop", "max_jump_up", "max_gap", "walk_step"), &CgameOffMeshLinkGenerator::generate, DEFVAL(3.0), DEFVAL(1.2), DEFVAL(2), DEFVAL(0.5));
	ClassDB::bind_method(D_METHOD("generate_from_arrays", "width", "height", "heights", "walkable", "max_drop", "max_jump_up", "max_gap", "walk_step"), &CgameOffMeshLinkGenerator::generate_from_arrays, DEFVAL(3.0), DEFVAL(1.2), DEFVAL(2), DEFVAL(0.5));
	ClassDB::bind_method(D_METHOD("link_world_positions", "link", "origin_xz", "cell_size"), &CgameOffMeshLinkGenerator::link_world_positions);
	ClassDB::bind_method(D_METHOD("create_links_on_map", "map", "origin_xz", "cell_size", "links", "navigation_layers", "enter_cost", "travel_cost"), &CgameOffMeshLinkGenerator::create_links_on_map, DEFVAL(Array()), DEFVAL(1), DEFVAL(0.0), DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("clear_map_links"), &CgameOffMeshLinkGenerator::clear_map_links);
	ClassDB::bind_method(D_METHOD("get_map_link_count"), &CgameOffMeshLinkGenerator::get_map_link_count);
	ClassDB::bind_method(D_METHOD("get_last_links"), &CgameOffMeshLinkGenerator::get_last_links);
}
