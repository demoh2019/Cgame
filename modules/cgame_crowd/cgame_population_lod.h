/**************************************************************************/
/*  cgame_population_lod.h                                                */
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

#pragma once

#include "core/math/random_pcg.h"
#include "core/math/vector2.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "core/templates/local_vector.h"
#include "core/templates/rb_map.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// Simulation LOD for large populations outside the players' active zone.
//
// Far from every player the crowd is not simulated agent by agent. It lives as abstract
// "herds" on a coarse region grid. Herds migrate along the gradient of attractors plus a
// seeded random wander, merge when they meet, split when they grow too big and decay or
// respawn by simple rules. promote() turns a region's herds into concrete spawn specs
// (conserving counts, bounded by an agent budget) and demote() folds agents back.
//
// Design references (concepts only): Mass Entity simulation/representation LOD and
// abstract-herd-on-a-graph talks. Original implementation.
//
// Deterministic: one seeded PCG, herds visited in ascending id order, no wall-clock input.
class CgamePopulationLOD : public RefCounted {
	GDCLASS(CgamePopulationLOD, RefCounted);

	enum HerdState {
		STATE_IDLE,
		STATE_MOVING,
	};

	struct Herd {
		int id = 0;
		int region = 0;
		int count = 0;
		RBMap<String, int> comp;
		Vector2 heading = Vector2(1, 0);
		HerdState state = STATE_IDLE;
		Vector2 pos;
		int from = 0;
		int to = 0;
		real_t t = 0.0;
		real_t travel = 1.0;
		real_t timer = 0.0;
		real_t decay_acc = 0.0;
	};

	struct Attractor {
		String kind;
		Vector2 pos;
		real_t strength = 0.0;
		real_t radius = 1.0;
		real_t ttl = -1.0;
		int source_id = 0;
		bool sourced = false; // Reusable per-player signal, not a one-off event.
	};

	struct Spawner {
		int region = 0;
		String type;
		real_t rate = 0.0;
		int cap = 0;
		real_t acc = 0.0;
	};

	struct Stats {
		int migrations = 0;
		int merges = 0;
		int splits = 0;
		int promotions = 0;
		int demotions = 0;
		int spawned = 0;
		int decayed = 0;
		int promote_denied = 0;
	};

	int cols = 0;
	int rows = 0;
	real_t cell_size = 64.0;
	Vector2 origin;

	RBMap<int, Herd> herds; // Ordered by id.
	RBMap<String, real_t> kind_weights;
	LocalVector<Attractor> attractors;
	LocalVector<real_t> attr;
	bool attr_dirty = true;
	HashSet<int> blocked;
	HashMap<int, real_t> decay;
	LocalVector<Spawner> spawners;
	PackedVector2Array players;
	Stats stats_data;
	RandomPCG rng;
	int next_id = 1;
	real_t time = 0.0;

	int max_herd_size = 40;
	real_t herd_speed = 8.0;
	real_t night_speed_mult = 1.5;
	real_t dwell_time = 4.0;
	real_t randomness = 0.6;
	real_t momentum = 0.25;
	real_t promote_radius = 120.0;
	int max_concrete_agents = 128;
	bool night = false;
	int concrete_count = 0;

	Herd *_herd_ptr(int p_id) {
		RBMap<int, Herd>::Element *e = herds.find(p_id);
		return e ? &e->get() : nullptr;
	}
	real_t _randf_range(real_t p_from, real_t p_to) { return rng.random((float)p_from, (float)p_to); }
	bool _valid_region(int p_region) const { return p_region >= 0 && p_region < cols * rows; }

	void _refresh_attraction();
	void _age_attractors(real_t p_dt);
	void _step_herd(Herd &r_herd, real_t p_dt);
	int _choose_next(const Herd &p_herd);
	void _merge_pass();
	void _absorb(Herd &r_a, const Herd &p_b);
	void _split_pass();
	void _rules_pass(real_t p_dt);
	void _remove_from_herd(Herd &r_herd, int p_amount);
	void _add_to_region(int p_region, const String &p_type, int p_amount);
	bool _near_player(const Vector2 &p_pos, const PackedVector2Array &p_positions) const;
	int _add_herd_internal(int p_region, const RBMap<String, int> &p_composition, const Vector2 &p_heading);

protected:
	static void _bind_methods();

public:
	void setup(int p_cols, int p_rows, real_t p_cell_size, int64_t p_seed, const Vector2 &p_origin = Vector2());

	// Grid.
	int get_cols() const { return cols; }
	int get_rows() const { return rows; }
	real_t get_cell_size() const { return cell_size; }
	Vector2 get_origin() const { return origin; }
	int region_count() const { return cols * rows; }
	int region_of(const Vector2 &p_pos) const;
	Vector2i region_cell(int p_region) const;
	Vector2 region_center(int p_region) const;
	void set_blocked(int p_region, bool p_blocked);
	bool is_blocked(int p_region) const { return blocked.has(p_region); }

	// Attractors, hazards, spawners.
	void set_kind_weight(const String &p_kind, real_t p_weight);
	real_t get_kind_weight(const String &p_kind) const;
	void add_attractor(const String &p_kind, const Vector2 &p_pos, real_t p_strength, real_t p_radius, real_t p_ttl = -1.0);
	void set_source_attractor(const String &p_kind, int p_source_id, const Vector2 &p_pos, real_t p_strength, real_t p_radius, real_t p_ttl);
	int active_attractor_count() const { return (int)attractors.size(); }
	void clear_attractors();
	void set_night(bool p_night) {
		if (night != p_night) {
			night = p_night;
			attr_dirty = true;
		}
	}
	bool is_night() const { return night; }
	void set_decay(int p_region, real_t p_rate);
	void add_spawner(int p_region, const String &p_type, real_t p_rate, int p_cap);
	real_t attraction(int p_region);

	// Herds.
	int add_herd(int p_region, const Dictionary &p_composition, const Vector2 &p_heading = Vector2(1, 0));
	PackedInt32Array herd_ids() const;
	bool has_herd(int p_id) const { return herds.has(p_id); }
	Dictionary get_herd(int p_id) const;
	int herd_count() const { return (int)herds.size(); }
	int herd_region_count(int p_region) const;
	int abstract_count() const;
	int total_population() const { return abstract_count() + concrete_count; }
	int composition_total(const String &p_type) const;
	Dictionary stats() const;

	// Simulation.
	void tick(real_t p_dt, const PackedVector2Array &p_player_positions = PackedVector2Array());

	// Promotion / demotion.
	PackedInt32Array regions_near(const PackedVector2Array &p_positions) const;
	Array promote(int p_region, const PackedVector2Array &p_player_positions = PackedVector2Array());
	void demote(const Array &p_agents, int p_region);

	// Tunables.
	void set_max_herd_size(int p_value) { max_herd_size = MAX(1, p_value); }
	int get_max_herd_size() const { return max_herd_size; }
	void set_herd_speed(real_t p_value) { herd_speed = p_value; }
	real_t get_herd_speed() const { return herd_speed; }
	void set_night_speed_mult(real_t p_value) { night_speed_mult = p_value; }
	real_t get_night_speed_mult() const { return night_speed_mult; }
	void set_dwell_time(real_t p_value) { dwell_time = p_value; }
	real_t get_dwell_time() const { return dwell_time; }
	void set_randomness(real_t p_value) { randomness = p_value; }
	real_t get_randomness() const { return randomness; }
	void set_momentum(real_t p_value) { momentum = p_value; }
	real_t get_momentum() const { return momentum; }
	void set_promote_radius(real_t p_value) { promote_radius = p_value; }
	real_t get_promote_radius() const { return promote_radius; }
	void set_max_concrete_agents(int p_value) { max_concrete_agents = MAX(0, p_value); }
	int get_max_concrete_agents() const { return max_concrete_agents; }
	int get_concrete_count() const { return concrete_count; }

	CgamePopulationLOD();
};
