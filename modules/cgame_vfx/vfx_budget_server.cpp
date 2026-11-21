/**************************************************************************/
/*  vfx_budget_server.cpp                                                 */
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

#include "vfx_budget_server.h"

#include "core/math/math_funcs.h"

VFXBudgetServer *VFXBudgetServer::singleton = nullptr;

double VFXBudgetServer::_tier_scale(Tier p_tier) {
	static const double scale[TIER_MAX] = { 0.4, 1.0, 1.75, 3.0 };
	return scale[CLAMP((int)p_tier, 0, (int)TIER_MAX - 1)];
}

double VFXBudgetServer::_tier_max_distance(Tier p_tier) {
	static const double distance[TIER_MAX] = { 40.0, 70.0, 110.0, 160.0 };
	return distance[CLAMP((int)p_tier, 0, (int)TIER_MAX - 1)];
}

VFXBudgetServer::VFXBudgetServer() {
	if (singleton == nullptr) {
		singleton = this;
	}
	set_category_limits("combat", 24, 2400);
	set_category_limits("ambient", 16, 1600);
	set_category_limits("weather", 6, 3000);
	set_category_limits("environment", 12, 2000);
	set_category_limits("ui", 8, 400);
}

VFXBudgetServer::~VFXBudgetServer() {
	if (singleton == this) {
		singleton = nullptr;
	}
}

void VFXBudgetServer::set_tier(Tier p_tier) {
	tier = (Tier)CLAMP((int)p_tier, 0, (int)TIER_MAX - 1);
}

void VFXBudgetServer::set_category_limits(const String &p_category, int p_max_effects, int p_max_particles) {
	CategoryLimits limits;
	limits.max_effects = MAX(p_max_effects, 1);
	limits.max_particles = MAX(p_max_particles, 1);
	categories[p_category] = limits;
}

VFXBudgetServer::CategoryLimits VFXBudgetServer::_limits(const String &p_category) const {
	const HashMap<String, CategoryLimits>::ConstIterator it = categories.find(p_category);
	return it ? it->value : CategoryLimits();
}

int VFXBudgetServer::get_max_effects(const String &p_category) const {
	return MAX(1, (int)Math::round((double)_limits(p_category).max_effects * _tier_scale(tier)));
}

int VFXBudgetServer::get_max_particles(const String &p_category) const {
	return MAX(1, (int)Math::round((double)_limits(p_category).max_particles * _tier_scale(tier)));
}

int VFXBudgetServer::get_max_total_particles() const {
	return (int)Math::round((double)global_particle_base * _tier_scale(tier));
}

double VFXBudgetServer::get_max_distance() const {
	return _tier_max_distance(tier);
}

double VFXBudgetServer::value_of(double p_priority, const Vector3 &p_position, const Vector3 &p_camera_position) const {
	return p_priority / (1.0 + (double)p_position.distance_to(p_camera_position) * distance_falloff);
}

bool VFXBudgetServer::_plan_evictions(const String &p_category, int p_cost, double p_value, LocalVector<int> &r_victims) const {
	r_victims.clear();
	const HashMap<String, int>::ConstIterator ce = category_effects.find(p_category);
	const HashMap<String, int>::ConstIterator cp = category_particles.find(p_category);
	int effects = (ce ? ce->value : 0) + 1;
	int cat_particles = (cp ? cp->value : 0) + p_cost;
	int total = particles_total + p_cost;
	const int cap_e = get_max_effects(p_category);
	const int cap_p = get_max_particles(p_category);
	const int cap_t = get_max_total_particles();
	if (effects <= cap_e && cat_particles <= cap_p && total <= cap_t) {
		return true;
	}
	// Candidates are strictly lower value than the request, cheapest value first (stable).
	LocalVector<int> candidates;
	for (const KeyValue<int, Live> &kv : live) {
		if (kv.value.value < p_value) {
			candidates.push_back(kv.key);
		}
	}
	for (uint32_t i = 1; i < candidates.size(); i++) {
		const int id = candidates[i];
		const double v = live[id].value;
		int j = (int)i - 1;
		while (j >= 0 && live[candidates[j]].value > v) {
			candidates[j + 1] = candidates[j];
			j--;
		}
		candidates[j + 1] = id;
	}
	for (const int id : candidates) {
		const Live &e = live[id];
		const bool same = e.category == p_category;
		const bool over_cat = effects > cap_e || cat_particles > cap_p;
		const bool over_total = total > cap_t;
		if (!(same && over_cat) && !over_total) {
			continue;
		}
		r_victims.push_back(id);
		total -= e.cost;
		if (same) {
			effects -= 1;
			cat_particles -= e.cost;
		}
		if (effects <= cap_e && cat_particles <= cap_p && total <= cap_t) {
			return true;
		}
	}
	return false;
}

int VFXBudgetServer::request_id(const String &p_category, int p_cost, double p_priority, const Vector3 &p_position, const Vector3 &p_camera_position) {
	last_id = 0;
	const int cost = MAX(0, p_cost);
	if ((double)p_position.distance_to(p_camera_position) > get_max_distance() || cost > get_max_particles(p_category) || cost > get_max_total_particles()) {
		stat_rejected++;
		return 0;
	}
	const double value = value_of(p_priority, p_position, p_camera_position);
	LocalVector<int> victims;
	if (!_plan_evictions(p_category, cost, value, victims)) {
		stat_rejected++;
		return 0;
	}
	for (const int vid : victims) {
		const String vcat = live[vid].category;
		_remove(vid);
		stat_evicted++;
		emit_signal(SNAME("evicted"), vid, vcat);
	}
	const int id = next_id++;
	Live entry;
	entry.category = p_category;
	entry.cost = cost;
	entry.priority = p_priority;
	entry.value = value;
	live[id] = entry;
	category_effects[p_category] += 1;
	category_particles[p_category] += cost;
	particles_total += cost;
	stat_accepted++;
	last_id = id;
	return id;
}

bool VFXBudgetServer::request(const String &p_category, int p_cost, double p_priority, const Vector3 &p_position, const Vector3 &p_camera_position) {
	return request_id(p_category, p_cost, p_priority, p_position, p_camera_position) > 0;
}

void VFXBudgetServer::_remove(int p_id) {
	const HashMap<int, Live>::Iterator it = live.find(p_id);
	if (!it) {
		return;
	}
	category_effects[it->value.category] -= 1;
	category_particles[it->value.category] -= it->value.cost;
	particles_total -= it->value.cost;
	live.remove(it);
}

void VFXBudgetServer::release(int p_id) {
	if (live.has(p_id)) {
		_remove(p_id);
		stat_released++;
	}
}

int VFXBudgetServer::get_active_effects(const String &p_category) const {
	if (p_category.is_empty()) {
		return (int)live.size();
	}
	const HashMap<String, int>::ConstIterator it = category_effects.find(p_category);
	return it ? it->value : 0;
}

int VFXBudgetServer::get_active_particles(const String &p_category) const {
	if (p_category.is_empty()) {
		return particles_total;
	}
	const HashMap<String, int>::ConstIterator it = category_particles.find(p_category);
	return it ? it->value : 0;
}

void VFXBudgetServer::clear() {
	live.clear();
	category_effects.clear();
	category_particles.clear();
	particles_total = 0;
}

void VFXBudgetServer::reset_stats() {
	stat_accepted = 0;
	stat_rejected = 0;
	stat_evicted = 0;
	stat_released = 0;
}

Dictionary VFXBudgetServer::get_stats() const {
	Dictionary out;
	out["accepted"] = stat_accepted;
	out["rejected"] = stat_rejected;
	out["evicted"] = stat_evicted;
	out["released"] = stat_released;
	out["active_effects"] = (int)live.size();
	out["active_particles"] = particles_total;
	out["tier"] = (int)tier;
	return out;
}

void VFXBudgetServer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_tier", "tier"), &VFXBudgetServer::set_tier);
	ClassDB::bind_method(D_METHOD("get_tier"), &VFXBudgetServer::get_tier);
	ClassDB::bind_method(D_METHOD("set_distance_falloff", "falloff"), &VFXBudgetServer::set_distance_falloff);
	ClassDB::bind_method(D_METHOD("get_distance_falloff"), &VFXBudgetServer::get_distance_falloff);
	ClassDB::bind_method(D_METHOD("set_global_particle_base", "base"), &VFXBudgetServer::set_global_particle_base);
	ClassDB::bind_method(D_METHOD("get_global_particle_base"), &VFXBudgetServer::get_global_particle_base);
	ClassDB::bind_method(D_METHOD("set_category_limits", "category", "max_effects", "max_particles"), &VFXBudgetServer::set_category_limits);
	ClassDB::bind_method(D_METHOD("has_category", "category"), &VFXBudgetServer::has_category);
	ClassDB::bind_method(D_METHOD("get_max_effects", "category"), &VFXBudgetServer::get_max_effects);
	ClassDB::bind_method(D_METHOD("get_max_particles", "category"), &VFXBudgetServer::get_max_particles);
	ClassDB::bind_method(D_METHOD("get_max_total_particles"), &VFXBudgetServer::get_max_total_particles);
	ClassDB::bind_method(D_METHOD("get_max_distance"), &VFXBudgetServer::get_max_distance);
	ClassDB::bind_method(D_METHOD("value_of", "priority", "position", "camera_position"), &VFXBudgetServer::value_of);
	ClassDB::bind_method(D_METHOD("request", "category", "cost", "priority", "position", "camera_position"), &VFXBudgetServer::request);
	ClassDB::bind_method(D_METHOD("request_id", "category", "cost", "priority", "position", "camera_position"), &VFXBudgetServer::request_id);
	ClassDB::bind_method(D_METHOD("get_last_id"), &VFXBudgetServer::get_last_id);
	ClassDB::bind_method(D_METHOD("release", "id"), &VFXBudgetServer::release);
	ClassDB::bind_method(D_METHOD("is_live", "id"), &VFXBudgetServer::is_live);
	ClassDB::bind_method(D_METHOD("get_active_effects", "category"), &VFXBudgetServer::get_active_effects, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("get_active_particles", "category"), &VFXBudgetServer::get_active_particles, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("clear"), &VFXBudgetServer::clear);
	ClassDB::bind_method(D_METHOD("get_stats"), &VFXBudgetServer::get_stats);
	ClassDB::bind_method(D_METHOD("reset_stats"), &VFXBudgetServer::reset_stats);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "tier", PROPERTY_HINT_ENUM, "Low,Medium,High,Ultra"), "set_tier", "get_tier");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "distance_falloff", PROPERTY_HINT_RANGE, "0,1,0.001,or_greater"), "set_distance_falloff", "get_distance_falloff");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "global_particle_base", PROPERTY_HINT_RANGE, "1,1000000,1,or_greater"), "set_global_particle_base", "get_global_particle_base");

	ADD_SIGNAL(MethodInfo("evicted", PropertyInfo(Variant::INT, "id"), PropertyInfo(Variant::STRING, "category")));

	BIND_ENUM_CONSTANT(TIER_LOW);
	BIND_ENUM_CONSTANT(TIER_MEDIUM);
	BIND_ENUM_CONSTANT(TIER_HIGH);
	BIND_ENUM_CONSTANT(TIER_ULTRA);
}
