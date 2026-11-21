/**************************************************************************/
/*  cgame_procedural_buildings.cpp                                        */
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

#include "cgame_procedural_buildings.h"

#include "core/object/class_db.h"

#include "core/math/math_funcs.h"
#include "core/math/random_number_generator.h"
#include "core/templates/hash_map.h"

void CgameProceduralBuildings::_split(const Rect2i &p_rect, RandomNumberGenerator &p_rng, Vector<Rect2i> &r_out) {
	const bool can_x = p_rect.size.x >= 2 * MIN_ROOM;
	const bool can_y = p_rect.size.y >= 2 * MIN_ROOM;
	if (!can_x && !can_y) {
		r_out.push_back(p_rect);
		return;
	}
	if (p_rect.size.x * p_rect.size.y <= 40 && p_rng.randf() < 0.5) {
		r_out.push_back(p_rect);
		return;
	}
	bool split_x;
	if (can_x && can_y) {
		if ((double)p_rect.size.x > (double)p_rect.size.y * 1.25) {
			split_x = true;
		} else if ((double)p_rect.size.y > (double)p_rect.size.x * 1.25) {
			split_x = false;
		} else {
			split_x = p_rng.randf() < 0.5;
		}
	} else {
		split_x = can_x;
	}
	if (split_x) {
		const int cut = p_rng.randi_range(MIN_ROOM, p_rect.size.x - MIN_ROOM);
		_split(Rect2i(p_rect.position, Vector2i(cut, p_rect.size.y)), p_rng, r_out);
		_split(Rect2i(p_rect.position + Vector2i(cut, 0), Vector2i(p_rect.size.x - cut, p_rect.size.y)), p_rng, r_out);
	} else {
		const int cut = p_rng.randi_range(MIN_ROOM, p_rect.size.y - MIN_ROOM);
		_split(Rect2i(p_rect.position, Vector2i(p_rect.size.x, cut)), p_rng, r_out);
		_split(Rect2i(p_rect.position + Vector2i(0, cut), Vector2i(p_rect.size.x, p_rect.size.y - cut)), p_rng, r_out);
	}
}

int CgameProceduralBuildings::_find(const Vector<int> &p_parent, int p_i) {
	int r = p_i;
	while (p_parent[r] != r) {
		r = p_parent[r];
	}
	return r;
}

Vector<CgameProceduralBuildings::Door> CgameProceduralBuildings::_doors_for_floor(int p_floor, const Vector<Room> &p_rooms, RandomNumberGenerator &p_rng) {
	struct Candidate {
		Vector2i ca;
		Vector2i cb;
		int i = 0;
		int j = 0;
	};
	Vector<Candidate> cand;
	for (int i = 0; i < p_rooms.size(); i++) {
		for (int j = i + 1; j < p_rooms.size(); j++) {
			const Rect2i a = p_rooms[i].rect;
			const Rect2i b = p_rooms[j].rect;
			const Vector2i a_end = a.get_end();
			const Vector2i b_end = b.get_end();
			bool has_door = false;
			Candidate door;
			if (a_end.x == b.position.x || b_end.x == a.position.x) {
				const int lo = MAX(a.position.y, b.position.y);
				const int hi = MIN(a_end.y, b_end.y);
				if (hi > lo) {
					const int y = p_rng.randi_range(lo, hi - 1);
					if (a_end.x == b.position.x) {
						door.ca = Vector2i(a_end.x - 1, y);
						door.cb = Vector2i(b.position.x, y);
					} else {
						door.ca = Vector2i(a.position.x, y);
						door.cb = Vector2i(b_end.x - 1, y);
					}
					has_door = true;
				}
			}
			if (!has_door && (a_end.y == b.position.y || b_end.y == a.position.y)) {
				const int lo2 = MAX(a.position.x, b.position.x);
				const int hi2 = MIN(a_end.x, b_end.x);
				if (hi2 > lo2) {
					const int x = p_rng.randi_range(lo2, hi2 - 1);
					if (a_end.y == b.position.y) {
						door.ca = Vector2i(x, a_end.y - 1);
						door.cb = Vector2i(x, b.position.y);
					} else {
						door.ca = Vector2i(x, a.position.y);
						door.cb = Vector2i(x, b_end.y - 1);
					}
					has_door = true;
				}
			}
			if (has_door) {
				door.i = i;
				door.j = j;
				cand.push_back(door);
			}
		}
	}
	for (int i = cand.size() - 1; i > 0; i--) {
		const int k = p_rng.randi_range(0, i);
		SWAP(cand.write[i], cand.write[k]);
	}
	Vector<int> parent;
	parent.resize(p_rooms.size());
	for (int i = 0; i < p_rooms.size(); i++) {
		parent.write[i] = i;
	}
	Vector<Door> out;
	for (const Candidate &c : cand) {
		const int ra = _find(parent, c.i);
		const int rb = _find(parent, c.j);
		bool take = false;
		if (ra != rb) {
			parent.write[ra] = rb;
			take = true;
		} else if (p_rng.randf() < LOOP_CHANCE) {
			take = true;
		}
		if (take) {
			Door d;
			d.floor = p_floor;
			d.a = p_rooms[c.i].id;
			d.b = p_rooms[c.j].id;
			d.cell_a = c.ca;
			d.cell_b = c.cb;
			out.push_back(d);
		}
	}
	return out;
}

CgameProceduralBuildings::Entrance CgameProceduralBuildings::_entrance(const Vector<Room> &p_rooms, const Vector2i &p_footprint, RandomNumberGenerator &p_rng) {
	Vector<int> choices;
	for (int i = 0; i < p_rooms.size(); i++) {
		if (p_rooms[i].rect.get_end().y == p_footprint.y) {
			choices.push_back(i);
		}
	}
	Entrance e;
	ERR_FAIL_COND_V_MSG(choices.is_empty(), e, "CgameProceduralBuildings: no room touches the south wall.");
	const Room &pick = p_rooms[choices[p_rng.randi_range(0, choices.size() - 1)]];
	const int x = p_rng.randi_range(pick.rect.position.x, pick.rect.get_end().x - 1);
	e.valid = true;
	e.room = pick.id;
	e.cell = Vector2i(x, p_footprint.y - 1);
	e.normal = Vector2i(0, 1);
	return e;
}

void CgameProceduralBuildings::_windows_for_floor(int p_floor, const Vector<Room> &p_rooms, const Vector2i &p_footprint, const Entrance &p_entrance, Array &r_out) {
	for (const Room &rm : p_rooms) {
		const Rect2i r = rm.rect;
		const Vector2i end = r.get_end();
		struct Spot {
			Vector2i cell;
			Vector2i normal;
		};
		Vector<Spot> spots;
		if (r.position.y == 0) {
			for (int x = r.position.x + 1; x < end.x - 1; x += 2) {
				spots.push_back({ Vector2i(x, 0), Vector2i(0, -1) });
			}
		}
		if (end.y == p_footprint.y) {
			for (int x = r.position.x + 1; x < end.x - 1; x += 2) {
				spots.push_back({ Vector2i(x, p_footprint.y - 1), Vector2i(0, 1) });
			}
		}
		if (r.position.x == 0) {
			for (int y = r.position.y + 1; y < end.y - 1; y += 2) {
				spots.push_back({ Vector2i(0, y), Vector2i(-1, 0) });
			}
		}
		if (end.x == p_footprint.x) {
			for (int y = r.position.y + 1; y < end.y - 1; y += 2) {
				spots.push_back({ Vector2i(p_footprint.x - 1, y), Vector2i(1, 0) });
			}
		}
		for (const Spot &s : spots) {
			if (p_floor == 0 && p_entrance.valid && p_entrance.cell == s.cell) {
				continue;
			}
			Dictionary w;
			w["floor"] = p_floor;
			w["room"] = rm.id;
			w["cell"] = s.cell;
			w["normal"] = s.normal;
			r_out.push_back(w);
		}
	}
}

Dictionary CgameProceduralBuildings::building(int64_t p_seed, const Vector2i &p_footprint, int p_floors) {
	const Vector2i fp(MAX(p_footprint.x, MIN_ROOM), MAX(p_footprint.y, MIN_ROOM));
	const int nfloors = MAX(p_floors, 1);
	Vector<Room> rooms;
	Array doors;
	Array windows;
	Array stairs;
	Entrance entrance;
	Vector<Vector<Room>> floor_rooms;
	for (int f = 0; f < nfloors; f++) {
		Ref<RandomNumberGenerator> rng;
		rng.instantiate();
		rng->set_seed((uint64_t)(p_seed + (int64_t)f * 7919));
		Vector<Rect2i> rects;
		_split(Rect2i(Vector2i(), fp), *rng.ptr(), rects);
		Vector<Room> this_floor;
		for (const Rect2i &r : rects) {
			Room room;
			room.id = rooms.size();
			room.floor = f;
			room.rect = r;
			rooms.push_back(room);
			this_floor.push_back(room);
		}
		floor_rooms.push_back(this_floor);
		for (const Door &d : _doors_for_floor(f, this_floor, *rng.ptr())) {
			Dictionary dd;
			dd["floor"] = d.floor;
			dd["a"] = d.a;
			dd["b"] = d.b;
			dd["cell_a"] = d.cell_a;
			dd["cell_b"] = d.cell_b;
			doors.push_back(dd);
		}
		if (f == 0) {
			entrance = _entrance(this_floor, fp, *rng.ptr());
		}
		_windows_for_floor(f, this_floor, fp, entrance, windows);
	}
	for (int f = 0; f < nfloors - 1; f++) {
		const Vector<Room> &lower = floor_rooms[f];
		const Vector<Room> &upper = floor_rooms[f + 1];
		const Room *best = &lower[0];
		for (const Room &rm : lower) {
			if (rm.rect.get_area() > best->rect.get_area()) {
				best = &rm;
			}
		}
		const Vector2i cell = best->rect.get_center();
		int up_id = -1;
		for (const Room &rm : upper) {
			if (rm.rect.has_point(cell)) {
				up_id = rm.id;
				break;
			}
		}
		Dictionary s;
		s["from_floor"] = f;
		s["to_floor"] = f + 1;
		s["cell"] = cell;
		s["room_from"] = best->id;
		s["room_to"] = up_id;
		stairs.push_back(s);
	}
	Array room_array;
	for (const Room &rm : rooms) {
		Dictionary d;
		d["id"] = rm.id;
		d["floor"] = rm.floor;
		d["rect"] = rm.rect;
		room_array.push_back(d);
	}
	Dictionary entrance_dict;
	if (entrance.valid) {
		entrance_dict["room"] = entrance.room;
		entrance_dict["cell"] = entrance.cell;
		entrance_dict["normal"] = entrance.normal;
	}
	Dictionary result;
	result["footprint"] = fp;
	result["floors"] = nfloors;
	result["rooms"] = room_array;
	result["doors"] = doors;
	result["stairs"] = stairs;
	result["windows"] = windows;
	result["entrance"] = entrance_dict;
	return result;
}

bool CgameProceduralBuildings::_too_close(const Vector2 &p_cand, const Vector<Vector2> &p_pts, const HashMap<Vector2i, int> &p_grid, double p_cell, double p_d) {
	const int gx = (int)Math::floor(p_cand.x / p_cell);
	const int gy = (int)Math::floor(p_cand.y / p_cell);
	for (int dy = -2; dy <= 2; dy++) {
		for (int dx = -2; dx <= 2; dx++) {
			const HashMap<Vector2i, int>::ConstIterator it = p_grid.find(Vector2i(gx + dx, gy + dy));
			if (it) {
				if ((double)p_pts[it->value].distance_to(p_cand) < p_d) {
					return true;
				}
			}
		}
	}
	return false;
}

Array CgameProceduralBuildings::settlement(int64_t p_seed, const Vector2 &p_center, double p_radius, int p_count) {
	Ref<RandomNumberGenerator> rng_ref;
	rng_ref.instantiate();
	RandomNumberGenerator &rng = *rng_ref.ptr();
	rng.set_seed((uint64_t)p_seed);
	Array out;
	if (p_radius <= 0.0) {
		return out;
	}
	const double d = MAX(MIN_LOT_SPACING, p_radius * Math::sqrt(2.0 / (double)MAX(p_count, 1)));
	const double plaza_r = d * 0.6;
	{
		Dictionary plaza;
		plaza["kind"] = "plaza";
		plaza["center"] = p_center;
		plaza["radius"] = plaza_r;
		out.push_back(plaza);
	}
	if (p_count <= 0) {
		return out;
	}
	const double min_r = plaza_r + 0.5 * d;
	const double max_r = p_radius - 0.5 * d;
	if (max_r <= min_r) {
		return out;
	}
	const double cell = d / Math::sqrt(2.0);
	HashMap<Vector2i, int> grid;
	Vector<Vector2> pts;
	Vector<int> active;
	{
		// The reference script retries up to 200 times but always accepts the first draw.
		const double ang = (double)rng.randf() * Math::TAU;
		const double rr = Math::sqrt((double)rng.randf_range((real_t)(min_r * min_r), (real_t)(max_r * max_r)));
		const Vector2 first = Vector2((real_t)Math::cos(ang), (real_t)Math::sin(ang)) * (real_t)rr;
		pts.push_back(first);
		active.push_back(0);
		grid[Vector2i((int)Math::floor(first.x / cell), (int)Math::floor(first.y / cell))] = 0;
	}
	while (!active.is_empty() && pts.size() < p_count) {
		const int ai = rng.randi_range(0, active.size() - 1);
		const Vector2 base = pts[active[ai]];
		bool found = false;
		for (int k = 0; k < BRIDSON_TRIES; k++) {
			const double ang2 = (double)rng.randf() * Math::TAU;
			const double dist = d * (1.0 + (double)rng.randf());
			const Vector2 cand = base + Vector2((real_t)Math::cos(ang2), (real_t)Math::sin(ang2)) * (real_t)dist;
			const double cl = cand.length();
			if (cl < min_r || cl > max_r) {
				continue;
			}
			if (_too_close(cand, pts, grid, cell, d)) {
				continue;
			}
			grid[Vector2i((int)Math::floor(cand.x / cell), (int)Math::floor(cand.y / cell))] = pts.size();
			active.push_back(pts.size());
			pts.push_back(cand);
			found = true;
			break;
		}
		if (!found) {
			active.remove_at(ai);
		}
	}
	const int max_side = MAX(MIN_LOT, (int)(0.7 * d));
	for (const Vector2 &off : pts) {
		const int fx = rng.randi_range(MIN_LOT, max_side);
		const int fy = rng.randi_range(MIN_LOT, max_side);
		const Vector2 size((real_t)fx, (real_t)fy);
		const Vector2 pos = p_center + off;
		Dictionary lot;
		lot["kind"] = "lot";
		lot["center"] = pos;
		lot["rect"] = Rect2(pos - size * 0.5f, size);
		lot["footprint"] = Vector2i(fx, fy);
		lot["floors"] = rng.randi_range(1, 3);
		lot["seed"] = (int64_t)rng.randi();
		out.push_back(lot);
		if (out.size() > p_count) {
			break;
		}
	}
	return out;
}

void CgameProceduralBuildings::_bind_methods() {
	ClassDB::bind_static_method("CgameProceduralBuildings", D_METHOD("building", "seed", "footprint", "floors"), &CgameProceduralBuildings::building);
	ClassDB::bind_static_method("CgameProceduralBuildings", D_METHOD("settlement", "seed", "center", "radius", "count"), &CgameProceduralBuildings::settlement);
}
