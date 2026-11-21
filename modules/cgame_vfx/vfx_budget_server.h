/**************************************************************************/
/*  vfx_budget_server.h                                                   */
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

#pragma once

#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"

// Global VFX budget: per-category effect and particle caps scaled by quality tier, with
// priority/distance based admission and eviction of the lowest value live effects.
// Registered as the engine singleton "VFXBudgetServer".
class VFXBudgetServer : public Object {
	GDCLASS(VFXBudgetServer, Object);

public:
	enum Tier {
		TIER_LOW,
		TIER_MEDIUM,
		TIER_HIGH,
		TIER_ULTRA,
		TIER_MAX,
	};

private:
	struct CategoryLimits {
		int max_effects = 8;
		int max_particles = 800; // MEDIUM tier values; other tiers scale them.
	};

	struct Live {
		String category;
		int cost = 0;
		double priority = 0.0;
		double value = 0.0;
	};

	static VFXBudgetServer *singleton;

	Tier tier = TIER_MEDIUM;
	double distance_falloff = 0.05;
	int global_particle_base = 6000;
	int next_id = 1;
	int last_id = 0;
	HashMap<String, CategoryLimits> categories;
	HashMap<int, Live> live;
	HashMap<String, int> category_effects;
	HashMap<String, int> category_particles;
	int particles_total = 0;
	int stat_accepted = 0;
	int stat_rejected = 0;
	int stat_evicted = 0;
	int stat_released = 0;

	static double _tier_scale(Tier p_tier);
	static double _tier_max_distance(Tier p_tier);
	CategoryLimits _limits(const String &p_category) const;
	// Returns false when the request cannot fit; otherwise fills the ids to evict.
	bool _plan_evictions(const String &p_category, int p_cost, double p_value, LocalVector<int> &r_victims) const;
	void _remove(int p_id);

protected:
	static void _bind_methods();

public:
	static VFXBudgetServer *get_singleton() { return singleton; }

	void set_tier(Tier p_tier);
	Tier get_tier() const { return tier; }
	void set_distance_falloff(double p_falloff) { distance_falloff = MAX(p_falloff, 0.0); }
	double get_distance_falloff() const { return distance_falloff; }
	void set_global_particle_base(int p_base) { global_particle_base = MAX(p_base, 1); }
	int get_global_particle_base() const { return global_particle_base; }

	// Overrides (or adds) a category using MEDIUM tier numbers.
	void set_category_limits(const String &p_category, int p_max_effects, int p_max_particles);
	bool has_category(const String &p_category) const { return categories.has(p_category); }

	int get_max_effects(const String &p_category) const;
	int get_max_particles(const String &p_category) const;
	int get_max_total_particles() const;
	double get_max_distance() const;
	double value_of(double p_priority, const Vector3 &p_position, const Vector3 &p_camera_position) const;

	bool request(const String &p_category, int p_cost, double p_priority, const Vector3 &p_position, const Vector3 &p_camera_position);
	// Like request() but returns the admitted effect id (0 when rejected).
	int request_id(const String &p_category, int p_cost, double p_priority, const Vector3 &p_position, const Vector3 &p_camera_position);
	int get_last_id() const { return last_id; }
	void release(int p_id);
	bool is_live(int p_id) const { return live.has(p_id); }
	int get_active_effects(const String &p_category = "") const;
	int get_active_particles(const String &p_category = "") const;
	void clear();
	Dictionary get_stats() const;
	void reset_stats();

	VFXBudgetServer();
	~VFXBudgetServer();
};

VARIANT_ENUM_CAST(VFXBudgetServer::Tier);
