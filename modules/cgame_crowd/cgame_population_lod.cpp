/**************************************************************************/
/*  cgame_population_lod.cpp                                              */
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

#include "cgame_population_lod.h"

#include "core/object/class_db.h"

static const Vector2i NEIGHBOUR_OFFSETS[8] = {
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
};

CgamePopulationLOD::CgamePopulationLOD() {
	kind_weights.insert("noise", 1.0);
	kind_weights.insert("corpse", 0.6);
	kind_weights.insert("loot", 0.5);
	kind_weights.insert("night", 0.3);
	setup(1, 1, 64.0, 0);
}

void CgamePopulationLOD::setup(int p_cols, int p_rows, real_t p_cell_size, int64_t p_seed, const Vector2 &p_origin) {
	// Bounded so cols * rows cannot overflow an int.
	cols = CLAMP(p_cols, 1, 16384);
	rows = CLAMP(p_rows, 1, 16384);
	cell_size = MAX((real_t)1.0, p_cell_size);
	origin = p_origin;
	rng.seed((uint64_t)p_seed);
	herds.clear();
	attractors.clear();
	blocked.clear();
	decay.clear();
	spawners.clear();
	players = PackedVector2Array();
	next_id = 1;
	time = 0.0;
	concrete_count = 0;
	stats_data = Stats();
	attr.clear();
	attr.resize((uint32_t)cols * (uint32_t)rows);
	for (uint32_t i = 0; i < attr.size(); i++) {
		attr[i] = 0.0;
	}
	attr_dirty = true;
}

// --- Grid -----------------------------------------------------------------------

int CgamePopulationLOD::region_of(const Vector2 &p_pos) const {
	const Vector2 local = (p_pos - origin) / cell_size;
	if (!Math::is_finite(local.x) || !Math::is_finite(local.y)) {
		return 0;
	}
	const int cx = (int)CLAMP(Math::floor(local.x), (real_t)0.0, (real_t)(cols - 1));
	const int cy = (int)CLAMP(Math::floor(local.y), (real_t)0.0, (real_t)(rows - 1));
	return cy * cols + cx;
}

Vector2i CgamePopulationLOD::region_cell(int p_region) const {
	return Vector2i(p_region % cols, p_region / cols);
}

Vector2 CgamePopulationLOD::region_center(int p_region) const {
	const Vector2i c = region_cell(p_region);
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell_size;
}

void CgamePopulationLOD::set_blocked(int p_region, bool p_blocked) {
	ERR_FAIL_COND(!_valid_region(p_region));
	if (p_blocked) {
		blocked.insert(p_region);
	} else {
		blocked.erase(p_region);
	}
}

// --- Attractors, hazards, spawners ----------------------------------------------

void CgamePopulationLOD::set_kind_weight(const String &p_kind, real_t p_weight) {
	kind_weights[p_kind] = p_weight;
	attr_dirty = true;
}

real_t CgamePopulationLOD::get_kind_weight(const String &p_kind) const {
	const RBMap<String, real_t>::Element *e = kind_weights.find(p_kind);
	return e ? e->get() : 1.0;
}

void CgamePopulationLOD::add_attractor(const String &p_kind, const Vector2 &p_pos, real_t p_strength, real_t p_radius, real_t p_ttl) {
	Attractor a;
	a.kind = p_kind;
	a.pos = p_pos;
	a.strength = p_strength;
	a.radius = MAX((real_t)1.0, p_radius);
	a.ttl = p_ttl;
	attractors.push_back(a);
	attr_dirty = true;
}

// One moving noise/night source per player. Event pulses created through
// add_attractor() remain independent, as in the script fallback.
void CgamePopulationLOD::set_source_attractor(const String &p_kind, int p_source_id, const Vector2 &p_pos, real_t p_strength, real_t p_radius, real_t p_ttl) {
	if (!p_pos.is_finite() || !Math::is_finite(p_strength) || !Math::is_finite(p_radius) || !Math::is_finite(p_ttl) || p_radius <= 0.0 || p_ttl <= 0.0) {
		return;
	}
	const real_t radius = MAX((real_t)1.0, p_radius);
	for (uint32_t i = 0; i < attractors.size(); i++) {
		Attractor &a = attractors[i];
		if (!a.sourced || a.source_id != p_source_id || a.kind != p_kind) {
			continue;
		}
		if (a.pos != p_pos || a.strength != p_strength || a.radius != radius) {
			a.pos = p_pos;
			a.strength = p_strength;
			a.radius = radius;
			attr_dirty = true;
		}
		a.ttl = p_ttl;
		return;
	}
	Attractor a;
	a.kind = p_kind;
	a.pos = p_pos;
	a.strength = p_strength;
	a.radius = radius;
	a.ttl = p_ttl;
	a.source_id = p_source_id;
	a.sourced = true;
	attractors.push_back(a);
	attr_dirty = true;
}

void CgamePopulationLOD::clear_attractors() {
	attractors.clear();
	attr_dirty = true;
}

void CgamePopulationLOD::set_decay(int p_region, real_t p_rate) {
	ERR_FAIL_COND(!_valid_region(p_region));
	if (p_rate <= 0.0) {
		decay.erase(p_region);
	} else {
		decay[p_region] = p_rate;
	}
}

void CgamePopulationLOD::add_spawner(int p_region, const String &p_type, real_t p_rate, int p_cap) {
	ERR_FAIL_COND(!_valid_region(p_region));
	Spawner s;
	s.region = p_region;
	s.type = p_type;
	s.rate = p_rate;
	s.cap = p_cap;
	spawners.push_back(s);
}

real_t CgamePopulationLOD::attraction(int p_region) {
	ERR_FAIL_COND_V(!_valid_region(p_region), 0.0);
	_refresh_attraction();
	return attr[p_region];
}

void CgamePopulationLOD::_refresh_attraction() {
	if (!attr_dirty) {
		return;
	}
	attr_dirty = false;
	for (uint32_t r = 0; r < attr.size(); r++) {
		attr[r] = 0.0;
	}
	for (uint32_t k = 0; k < attractors.size(); k++) {
		const Attractor &a = attractors[k];
		const real_t w = get_kind_weight(a.kind);
		if (a.kind == "night" && !night) {
			continue;
		}
		// Only grid cells whose centres can intersect this signal need
		// evaluation. Rows retain the original ascending region order.
		const real_t min_x = (a.pos.x - a.radius - origin.x) / cell_size - 0.5;
		const real_t max_x = (a.pos.x + a.radius - origin.x) / cell_size - 0.5;
		const real_t min_y = (a.pos.y - a.radius - origin.y) / cell_size - 0.5;
		const real_t max_y = (a.pos.y + a.radius - origin.y) / cell_size - 0.5;
		if (!Math::is_finite(min_x) || !Math::is_finite(max_x) || !Math::is_finite(min_y) || !Math::is_finite(max_y)) {
			continue;
		}
		// Clamp before converting to int: a large but finite external
		// position must never overflow to another occupied region.
		const int low_x = (int)CLAMP(Math::floor(min_x), (real_t)0.0, (real_t)cols);
		const int high_x = (int)CLAMP(Math::ceil(max_x), (real_t)-1.0, (real_t)(cols - 1));
		const int low_y = (int)CLAMP(Math::floor(min_y), (real_t)0.0, (real_t)rows);
		const int high_y = (int)CLAMP(Math::ceil(max_y), (real_t)-1.0, (real_t)(rows - 1));
		for (int cy = low_y; cy <= high_y; cy++) {
			for (int cx = low_x; cx <= high_x; cx++) {
				const int r = cy * cols + cx;
				const real_t d = region_center(r).distance_to(a.pos);
				if (d < a.radius) {
					attr[r] += a.strength * w * (1.0 - d / a.radius);
				}
			}
		}
	}
}

// --- Herd management ------------------------------------------------------------

int CgamePopulationLOD::_add_herd_internal(int p_region, const RBMap<String, int> &p_composition, const Vector2 &p_heading) {
	const int id = next_id++;
	Herd h;
	h.id = id;
	h.region = p_region;
	int total = 0;
	for (const KeyValue<String, int> &kv : p_composition) {
		if (kv.value > 0) {
			h.comp.insert(kv.key, kv.value);
			total += kv.value;
		}
	}
	h.count = total;
	h.heading = p_heading.length_squared() > 0.0 ? p_heading.normalized() : Vector2(1, 0);
	h.state = STATE_IDLE;
	h.pos = region_center(p_region);
	h.from = p_region;
	h.to = p_region;
	h.t = 0.0;
	h.travel = 1.0;
	h.timer = _randf_range(0.0, dwell_time);
	h.decay_acc = 0.0;
	herds.insert(id, h);
	return id;
}

int CgamePopulationLOD::add_herd(int p_region, const Dictionary &p_composition, const Vector2 &p_heading) {
	ERR_FAIL_COND_V_MSG(!_valid_region(p_region), -1, "CgamePopulationLOD: region out of range.");
	RBMap<String, int> comp;
	const Array keys = p_composition.keys();
	for (int k = 0; k < keys.size(); k++) {
		const Variant &value = p_composition[keys[k]];
		ERR_FAIL_COND_V_MSG(value.get_type() != Variant::INT && value.get_type() != Variant::FLOAT, -1, "CgamePopulationLOD: composition counts must be numbers.");
		const int n = (int)(int64_t)value;
		if (n > 0) {
			comp[String(keys[k])] += n;
		}
	}
	return _add_herd_internal(p_region, comp, p_heading);
}

PackedInt32Array CgamePopulationLOD::herd_ids() const {
	PackedInt32Array out;
	for (const KeyValue<int, Herd> &kv : herds) {
		out.push_back(kv.key);
	}
	return out;
}

Dictionary CgamePopulationLOD::get_herd(int p_id) const {
	Dictionary d;
	const RBMap<int, Herd>::Element *e = herds.find(p_id);
	if (!e) {
		return d;
	}
	const Herd &h = e->get();
	Dictionary comp;
	for (const KeyValue<String, int> &kv : h.comp) {
		comp[kv.key] = kv.value;
	}
	d["id"] = h.id;
	d["region"] = h.region;
	d["count"] = h.count;
	d["comp"] = comp;
	d["heading"] = h.heading;
	d["state"] = h.state == STATE_MOVING ? String("moving") : String("idle");
	d["pos"] = h.pos;
	d["from"] = h.from;
	d["to"] = h.to;
	d["t"] = h.t;
	d["travel"] = h.travel;
	d["timer"] = h.timer;
	return d;
}

int CgamePopulationLOD::herd_region_count(int p_region) const {
	int n = 0;
	for (const KeyValue<int, Herd> &kv : herds) {
		if (kv.value.region == p_region) {
			n += kv.value.count;
		}
	}
	return n;
}

int CgamePopulationLOD::abstract_count() const {
	int n = 0;
	for (const KeyValue<int, Herd> &kv : herds) {
		n += kv.value.count;
	}
	return n;
}

int CgamePopulationLOD::composition_total(const String &p_type) const {
	int n = 0;
	for (const KeyValue<int, Herd> &kv : herds) {
		const RBMap<String, int>::Element *e = kv.value.comp.find(p_type);
		if (e) {
			n += e->get();
		}
	}
	return n;
}

Dictionary CgamePopulationLOD::stats() const {
	Dictionary s;
	s["migrations"] = stats_data.migrations;
	s["merges"] = stats_data.merges;
	s["splits"] = stats_data.splits;
	s["promotions"] = stats_data.promotions;
	s["demotions"] = stats_data.demotions;
	s["spawned"] = stats_data.spawned;
	s["decayed"] = stats_data.decayed;
	s["promote_denied"] = stats_data.promote_denied;
	s["herds"] = (int)herds.size();
	const int abs_count = abstract_count();
	s["abstract"] = abs_count;
	s["concrete"] = concrete_count;
	s["total"] = abs_count + concrete_count;
	s["budget_left"] = MAX(0, max_concrete_agents - concrete_count);
	return s;
}

// --- Simulation -----------------------------------------------------------------

void CgamePopulationLOD::tick(real_t p_dt, const PackedVector2Array &p_player_positions) {
	players = p_player_positions;
	time += p_dt;
	_age_attractors(p_dt);
	_refresh_attraction();
	for (KeyValue<int, Herd> &kv : herds) {
		_step_herd(kv.value, p_dt);
	}
	_merge_pass();
	_split_pass();
	_rules_pass(p_dt);
}

void CgamePopulationLOD::_age_attractors(real_t p_dt) {
	for (int i = (int)attractors.size() - 1; i >= 0; i--) {
		real_t ttl = attractors[i].ttl;
		if (ttl >= 0.0) {
			ttl -= p_dt;
			if (ttl <= 0.0) {
				attractors.remove_at(i);
				attr_dirty = true;
			} else {
				attractors[i].ttl = ttl;
			}
		}
	}
}

void CgamePopulationLOD::_step_herd(Herd &r_herd, real_t p_dt) {
	if (r_herd.state == STATE_MOVING) {
		r_herd.t += p_dt / MAX((real_t)0.001, r_herd.travel);
		const Vector2 from_c = region_center(r_herd.from);
		const Vector2 to_c = region_center(r_herd.to);
		r_herd.pos = from_c.lerp(to_c, MIN(r_herd.t, (real_t)1.0));
		if (r_herd.t >= 0.5) {
			r_herd.region = r_herd.to;
		}
		if (r_herd.t >= 1.0) {
			r_herd.state = STATE_IDLE;
			r_herd.region = r_herd.to;
			r_herd.pos = to_c;
			r_herd.timer = dwell_time * _randf_range(0.5, 1.5);
		}
		return;
	}
	r_herd.timer -= p_dt;
	if (r_herd.timer > 0.0) {
		return;
	}
	const int next = _choose_next(r_herd);
	if (next < 0) {
		r_herd.timer = dwell_time * _randf_range(0.5, 1.5);
		return;
	}
	const int cur = r_herd.region;
	const Vector2 dir = region_center(next) - region_center(cur);
	const real_t dist = dir.length();
	const real_t speed = herd_speed * (night ? night_speed_mult : 1.0);
	r_herd.heading = dir / MAX((real_t)0.001, dist);
	r_herd.from = cur;
	r_herd.to = next;
	r_herd.t = 0.0;
	r_herd.travel = dist / MAX((real_t)0.001, speed);
	r_herd.state = STATE_MOVING;
	stats_data.migrations++;
}

int CgamePopulationLOD::_choose_next(const Herd &p_herd) {
	const int cur = p_herd.region;
	const Vector2i cc = region_cell(cur);
	const real_t cur_attr = attr[cur];
	int best = -1;
	real_t best_score = -Math::INF;
	real_t best_neighbour_attr = -Math::INF;
	for (int k = 0; k < 8; k++) {
		const Vector2i off = NEIGHBOUR_OFFSETS[k];
		const Vector2i n = cc + off;
		if (n.x < 0 || n.y < 0 || n.x >= cols || n.y >= rows) {
			continue;
		}
		const int r = n.y * cols + n.x;
		if (blocked.has(r)) {
			continue;
		}
		best_neighbour_attr = MAX(best_neighbour_attr, attr[r]);
		const Vector2 dir = Vector2(off).normalized();
		real_t score = (attr[r] - cur_attr) * 2.0;
		score += dir.dot(p_herd.heading) * momentum;
		score += _randf_range(-1.0, 1.0) * randomness * (night ? 0.5 : 1.0);
		if (score > best_score) {
			best_score = score;
			best = r;
		}
	}
	// Sitting on the best attractor spot: stay until it fades.
	if (best >= 0 && cur_attr > 0.0 && cur_attr >= best_neighbour_attr) {
		return -1;
	}
	return best;
}

void CgamePopulationLOD::_merge_pass() {
	RBMap<int, LocalVector<int>> by_region;
	for (const KeyValue<int, Herd> &kv : herds) {
		by_region[kv.value.region].push_back(kv.key);
	}
	const real_t merge_dist = cell_size * 0.5;
	for (const KeyValue<int, LocalVector<int>> &rv : by_region) {
		const LocalVector<int> &list = rv.value;
		for (uint32_t i = 0; i < list.size(); i++) {
			Herd *a = _herd_ptr(list[i]);
			if (!a) {
				continue;
			}
			for (uint32_t j = i + 1; j < list.size(); j++) {
				Herd *b = _herd_ptr(list[j]);
				if (!b) {
					continue;
				}
				if (a->count + b->count <= max_herd_size && a->pos.distance_to(b->pos) <= merge_dist) {
					_absorb(*a, *b);
					herds.erase(list[j]);
					stats_data.merges++;
				}
			}
		}
	}
}

void CgamePopulationLOD::_absorb(Herd &r_a, const Herd &p_b) {
	for (const KeyValue<String, int> &kv : p_b.comp) {
		r_a.comp[kv.key] += kv.value;
	}
	const int ca = r_a.count;
	const int cb = p_b.count;
	const int total = ca + cb;
	if (total > 0) {
		r_a.pos = (r_a.pos * (real_t)ca + p_b.pos * (real_t)cb) / (real_t)total;
		const Vector2 h = r_a.heading * (real_t)ca + p_b.heading * (real_t)cb;
		if (h.length_squared() > 0.0001) {
			r_a.heading = h.normalized();
		}
	}
	r_a.count = total;
	// The merged herd stays idle whenever the absorbed part was still moving.
	if (p_b.state == STATE_MOVING && r_a.state != STATE_MOVING) {
		r_a.state = STATE_IDLE;
		r_a.timer = 0.0;
	}
}

void CgamePopulationLOD::_split_pass() {
	const PackedInt32Array ids = herd_ids();
	for (int k = 0; k < ids.size(); k++) {
		Herd *h = _herd_ptr(ids[k]);
		if (!h) {
			continue;
		}
		const int count = h->count;
		if (count <= max_herd_size || h->state == STATE_MOVING) {
			continue;
		}
		RBMap<String, int> moved;
		int moved_total = 0;
		for (KeyValue<String, int> &kv : h->comp) {
			const int half = kv.value / 2;
			if (half > 0) {
				moved[kv.key] = half;
				kv.value -= half;
				moved_total += half;
			}
		}
		if (moved_total <= 0) {
			continue;
		}
		h->count = count - moved_total;
		const Vector2 heading = h->heading.rotated(_randf_range(0.8, 2.4));
		const int nid = _add_herd_internal(h->region, moved, heading);
		Herd *nh = _herd_ptr(nid);
		nh->pos = h->pos;
		nh->timer = 0.0;
		h->timer = 0.0;
		stats_data.splits++;
	}
}

void CgamePopulationLOD::_rules_pass(real_t p_dt) {
	// Decay.
	for (KeyValue<int, Herd> &kv : herds) {
		Herd &h = kv.value;
		const HashMap<int, real_t>::Iterator d = decay.find(h.region);
		if (!d) {
			continue;
		}
		real_t acc = h.decay_acc + d->value * p_dt;
		const int lose = (int)Math::floor(acc);
		acc -= (real_t)lose;
		h.decay_acc = acc;
		if (lose > 0) {
			_remove_from_herd(h, lose);
		}
	}
	LocalVector<int> empty;
	for (const KeyValue<int, Herd> &kv : herds) {
		if (kv.value.count <= 0) {
			empty.push_back(kv.key);
		}
	}
	for (uint32_t k = 0; k < empty.size(); k++) {
		herds.erase(empty[k]);
	}
	// Populate each region's total once after decay. Multiple nests share
	// current capacity instead of rescanning the full herd map per nest.
	RBMap<int, int> region_totals;
	if (!spawners.is_empty()) {
		for (const KeyValue<int, Herd> &kv : herds) {
			region_totals[kv.value.region] += kv.value.count;
		}
	}
	// Respawn order and RNG state remain unchanged.
	for (uint32_t k = 0; k < spawners.size(); k++) {
		Spawner &s = spawners[k];
		s.acc += s.rate * p_dt;
		int add = (int)Math::floor(s.acc);
		s.acc -= (real_t)add;
		if (add <= 0) {
			continue;
		}
		const RBMap<int, int>::Element *existing = region_totals.find(s.region);
		const int room = s.cap - (existing ? existing->get() : 0);
		add = MIN(add, room);
		if (add <= 0) {
			s.acc = 0.0;
			continue;
		}
		_add_to_region(s.region, s.type, add);
		region_totals[s.region] += add;
		stats_data.spawned += add;
	}
}

void CgamePopulationLOD::_remove_from_herd(Herd &r_herd, int p_amount) {
	int left = p_amount;
	LocalVector<String> emptied;
	for (KeyValue<String, int> &kv : r_herd.comp) {
		if (left <= 0) {
			break;
		}
		const int take = MIN(kv.value, left);
		kv.value -= take;
		left -= take;
		if (kv.value <= 0) {
			emptied.push_back(kv.key);
		}
	}
	for (uint32_t k = 0; k < emptied.size(); k++) {
		r_herd.comp.erase(emptied[k]);
	}
	const int removed = p_amount - left;
	r_herd.count -= removed;
	stats_data.decayed += removed;
}

void CgamePopulationLOD::_add_to_region(int p_region, const String &p_type, int p_amount) {
	for (KeyValue<int, Herd> &kv : herds) {
		Herd &h = kv.value;
		if (h.region == p_region && h.state != STATE_MOVING && h.count + p_amount <= max_herd_size) {
			h.comp[p_type] += p_amount;
			h.count += p_amount;
			return;
		}
	}
	RBMap<String, int> comp;
	comp[p_type] = p_amount;
	_add_herd_internal(p_region, comp, Vector2(1, 0));
}

// --- Promotion / demotion -------------------------------------------------------

bool CgamePopulationLOD::_near_player(const Vector2 &p_pos, const PackedVector2Array &p_positions) const {
	const real_t reach = promote_radius + cell_size * 0.5;
	for (int i = 0; i < p_positions.size(); i++) {
		if (p_positions[i].distance_to(p_pos) <= reach) {
			return true;
		}
	}
	return false;
}

PackedInt32Array CgamePopulationLOD::regions_near(const PackedVector2Array &p_positions) const {
	PackedInt32Array out;
	for (int r = 0; r < region_count(); r++) {
		if (_near_player(region_center(r), p_positions) && herd_region_count(r) > 0) {
			out.push_back(r);
		}
	}
	return out;
}

Array CgamePopulationLOD::promote(int p_region, const PackedVector2Array &p_player_positions) {
	Array out;
	const PackedVector2Array &active = p_player_positions.size() > 0 ? p_player_positions : players;
	if (!_valid_region(p_region) || !_near_player(region_center(p_region), active)) {
		return out;
	}
	int budget = max_concrete_agents - concrete_count;
	if (budget <= 0) {
		stats_data.promote_denied++;
		return out;
	}
	const real_t spread = cell_size * 0.35;
	const PackedInt32Array ids = herd_ids();
	for (int k = 0; k < ids.size(); k++) {
		if (budget <= 0) {
			break;
		}
		Herd *h = _herd_ptr(ids[k]);
		if (!h || h->region != p_region) {
			continue;
		}
		const Vector2 heading = h->heading;
		const Vector2 center = h->pos;
		Vector<String> types;
		for (const KeyValue<String, int> &kv : h->comp) {
			types.push_back(kv.key);
		}
		for (int t = 0; t < types.size(); t++) {
			const int c = h->comp[types[t]];
			const int take = MIN(c, budget);
			for (int n = 0; n < take; n++) {
				const real_t ox = _randf_range(-spread, spread);
				const real_t oy = _randf_range(-spread, spread);
				Dictionary spec;
				spec["type"] = types[t];
				spec["position"] = center + Vector2(ox, oy);
				spec["heading"] = heading;
				out.push_back(spec);
			}
			if (c - take <= 0) {
				h->comp.erase(types[t]);
			} else {
				h->comp[types[t]] = c - take;
			}
			budget -= take;
			h->count -= take;
			if (budget <= 0) {
				break;
			}
		}
		if (h->count <= 0) {
			herds.erase(ids[k]);
		}
	}
	concrete_count += out.size();
	if (out.size() > 0) {
		stats_data.promotions += out.size();
	}
	return out;
}

void CgamePopulationLOD::demote(const Array &p_agents, int p_region) {
	if (p_agents.is_empty()) {
		return;
	}
	ERR_FAIL_COND_MSG(!_valid_region(p_region), "CgamePopulationLOD: region out of range.");
	RBMap<String, int> counts;
	int n = 0;
	for (int i = 0; i < p_agents.size(); i++) {
		const Variant &a = p_agents[i];
		String type = "unknown";
		if (a.get_type() == Variant::STRING || a.get_type() == Variant::STRING_NAME) {
			type = a;
		} else if (a.get_type() == Variant::DICTIONARY) {
			const Dictionary d = a;
			type = String(d.get("type", "unknown"));
		}
		counts[type]++;
		n++;
	}
	for (const KeyValue<String, int> &kv : counts) {
		_add_to_region(p_region, kv.key, kv.value);
	}
	concrete_count = MAX(0, concrete_count - n);
	stats_data.demotions += n;
}

void CgamePopulationLOD::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "cols", "rows", "cell_size", "seed", "origin"), &CgamePopulationLOD::setup, DEFVAL(Vector2()));

	ClassDB::bind_method(D_METHOD("get_cols"), &CgamePopulationLOD::get_cols);
	ClassDB::bind_method(D_METHOD("get_rows"), &CgamePopulationLOD::get_rows);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &CgamePopulationLOD::get_cell_size);
	ClassDB::bind_method(D_METHOD("get_origin"), &CgamePopulationLOD::get_origin);
	ClassDB::bind_method(D_METHOD("region_count"), &CgamePopulationLOD::region_count);
	ClassDB::bind_method(D_METHOD("region_of", "pos"), &CgamePopulationLOD::region_of);
	ClassDB::bind_method(D_METHOD("region_cell", "region"), &CgamePopulationLOD::region_cell);
	ClassDB::bind_method(D_METHOD("region_center", "region"), &CgamePopulationLOD::region_center);
	ClassDB::bind_method(D_METHOD("set_blocked", "region", "blocked"), &CgamePopulationLOD::set_blocked);
	ClassDB::bind_method(D_METHOD("is_blocked", "region"), &CgamePopulationLOD::is_blocked);

	ClassDB::bind_method(D_METHOD("set_kind_weight", "kind", "weight"), &CgamePopulationLOD::set_kind_weight);
	ClassDB::bind_method(D_METHOD("get_kind_weight", "kind"), &CgamePopulationLOD::get_kind_weight);
	ClassDB::bind_method(D_METHOD("add_attractor", "kind", "pos", "strength", "radius", "ttl"), &CgamePopulationLOD::add_attractor, DEFVAL(-1.0));
	ClassDB::bind_method(D_METHOD("set_source_attractor", "kind", "source_id", "pos", "strength", "radius", "ttl"), &CgamePopulationLOD::set_source_attractor);
	ClassDB::bind_method(D_METHOD("active_attractor_count"), &CgamePopulationLOD::active_attractor_count);
	ClassDB::bind_method(D_METHOD("clear_attractors"), &CgamePopulationLOD::clear_attractors);
	ClassDB::bind_method(D_METHOD("set_night", "night"), &CgamePopulationLOD::set_night);
	ClassDB::bind_method(D_METHOD("is_night"), &CgamePopulationLOD::is_night);
	ClassDB::bind_method(D_METHOD("set_decay", "region", "rate"), &CgamePopulationLOD::set_decay);
	ClassDB::bind_method(D_METHOD("add_spawner", "region", "type", "rate", "cap"), &CgamePopulationLOD::add_spawner);
	ClassDB::bind_method(D_METHOD("attraction", "region"), &CgamePopulationLOD::attraction);

	ClassDB::bind_method(D_METHOD("add_herd", "region", "composition", "heading"), &CgamePopulationLOD::add_herd, DEFVAL(Vector2(1, 0)));
	ClassDB::bind_method(D_METHOD("herd_ids"), &CgamePopulationLOD::herd_ids);
	ClassDB::bind_method(D_METHOD("has_herd", "id"), &CgamePopulationLOD::has_herd);
	ClassDB::bind_method(D_METHOD("get_herd", "id"), &CgamePopulationLOD::get_herd);
	ClassDB::bind_method(D_METHOD("herd_count"), &CgamePopulationLOD::herd_count);
	ClassDB::bind_method(D_METHOD("herd_region_count", "region"), &CgamePopulationLOD::herd_region_count);
	ClassDB::bind_method(D_METHOD("abstract_count"), &CgamePopulationLOD::abstract_count);
	ClassDB::bind_method(D_METHOD("total_population"), &CgamePopulationLOD::total_population);
	ClassDB::bind_method(D_METHOD("composition_total", "type"), &CgamePopulationLOD::composition_total);
	ClassDB::bind_method(D_METHOD("stats"), &CgamePopulationLOD::stats);

	ClassDB::bind_method(D_METHOD("tick", "dt", "player_positions"), &CgamePopulationLOD::tick, DEFVAL(PackedVector2Array()));

	ClassDB::bind_method(D_METHOD("regions_near", "positions"), &CgamePopulationLOD::regions_near);
	ClassDB::bind_method(D_METHOD("promote", "region", "player_positions"), &CgamePopulationLOD::promote, DEFVAL(PackedVector2Array()));
	ClassDB::bind_method(D_METHOD("demote", "agents", "region"), &CgamePopulationLOD::demote);

	ClassDB::bind_method(D_METHOD("set_max_herd_size", "value"), &CgamePopulationLOD::set_max_herd_size);
	ClassDB::bind_method(D_METHOD("get_max_herd_size"), &CgamePopulationLOD::get_max_herd_size);
	ClassDB::bind_method(D_METHOD("set_herd_speed", "value"), &CgamePopulationLOD::set_herd_speed);
	ClassDB::bind_method(D_METHOD("get_herd_speed"), &CgamePopulationLOD::get_herd_speed);
	ClassDB::bind_method(D_METHOD("set_night_speed_mult", "value"), &CgamePopulationLOD::set_night_speed_mult);
	ClassDB::bind_method(D_METHOD("get_night_speed_mult"), &CgamePopulationLOD::get_night_speed_mult);
	ClassDB::bind_method(D_METHOD("set_dwell_time", "value"), &CgamePopulationLOD::set_dwell_time);
	ClassDB::bind_method(D_METHOD("get_dwell_time"), &CgamePopulationLOD::get_dwell_time);
	ClassDB::bind_method(D_METHOD("set_randomness", "value"), &CgamePopulationLOD::set_randomness);
	ClassDB::bind_method(D_METHOD("get_randomness"), &CgamePopulationLOD::get_randomness);
	ClassDB::bind_method(D_METHOD("set_momentum", "value"), &CgamePopulationLOD::set_momentum);
	ClassDB::bind_method(D_METHOD("get_momentum"), &CgamePopulationLOD::get_momentum);
	ClassDB::bind_method(D_METHOD("set_promote_radius", "value"), &CgamePopulationLOD::set_promote_radius);
	ClassDB::bind_method(D_METHOD("get_promote_radius"), &CgamePopulationLOD::get_promote_radius);
	ClassDB::bind_method(D_METHOD("set_max_concrete_agents", "value"), &CgamePopulationLOD::set_max_concrete_agents);
	ClassDB::bind_method(D_METHOD("get_max_concrete_agents"), &CgamePopulationLOD::get_max_concrete_agents);
	ClassDB::bind_method(D_METHOD("get_concrete_count"), &CgamePopulationLOD::get_concrete_count);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_herd_size", PROPERTY_HINT_RANGE, "1,100000,1,or_greater"), "set_max_herd_size", "get_max_herd_size");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "herd_speed"), "set_herd_speed", "get_herd_speed");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "night_speed_mult"), "set_night_speed_mult", "get_night_speed_mult");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "dwell_time"), "set_dwell_time", "get_dwell_time");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "randomness"), "set_randomness", "get_randomness");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "momentum"), "set_momentum", "get_momentum");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "promote_radius"), "set_promote_radius", "get_promote_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_concrete_agents", PROPERTY_HINT_RANGE, "0,100000,1,or_greater"), "set_max_concrete_agents", "get_max_concrete_agents");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "night"), "set_night", "is_night");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "concrete_count", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_concrete_count");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "cols", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_cols");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "rows", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_rows");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_cell_size");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "origin", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_origin");
}
