/**************************************************************************/
/*  cgame_smart_objects.cpp                                               */
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

#include "cgame_smart_objects.h"

#include "core/math/random_number_generator.h"

#include <algorithm>
#include <vector>

String CgameSmartObjects::_key(const String &p_id, int p_slot_index) {
	return vformat("%s#%d", p_id, p_slot_index);
}

bool CgameSmartObjects::_has_all(const Array &p_required, const Array &p_a, const Array &p_b) {
	for (int i = 0; i < p_required.size(); i++) {
		if (!p_a.has(p_required[i]) && !p_b.has(p_required[i])) {
			return false;
		}
	}
	return true;
}

void CgameSmartObjects::register_behavior(const String &p_behavior, const Array &p_steps) {
	Vector<Step> steps;
	for (int i = 0; i < p_steps.size(); i++) {
		const Dictionary s = p_steps[i];
		Step step;
		step.anim = String(s.get("anim", ""));
		step.duration = double(s.get("duration", 0.0));
		step.effect = String(s.get("effect", ""));
		steps.push_back(step);
	}
	behaviors[p_behavior] = steps;
}

bool CgameSmartObjects::register_object(const Dictionary &p_object) {
	if (!p_object.has("id") || !p_object.has("position")) {
		return false;
	}
	if (Variant(p_object["position"]).get_type() != Variant::VECTOR3) {
		return false;
	}
	Dictionary copy = p_object.duplicate(true);
	if (!copy.has("tags")) {
		copy["tags"] = Array();
	}
	if (!copy.has("slots")) {
		copy["slots"] = Array();
	}
	SmartObject obj;
	obj.id = String(copy["id"]);
	obj.position = copy["position"];
	obj.tags = copy["tags"];
	const Array slot_defs = copy["slots"];
	for (int i = 0; i < slot_defs.size(); i++) {
		const Dictionary sd = slot_defs[i];
		Slot slot;
		slot.offset = sd.get("offset", Vector3());
		slot.behavior = String(sd.get("behavior", ""));
		slot.tags = sd.get("tags", Array());
		obj.slots.push_back(slot);
	}
	obj.raw = copy;
	objects[obj.id] = obj;
	return true;
}

void CgameSmartObjects::unregister_object(const String &p_id) {
	const HashMap<String, SmartObject>::Iterator it = objects.find(p_id);
	if (!it) {
		return;
	}
	const int slot_count = it->value.slots.size();
	for (int i = 0; i < slot_count; i++) {
		const HashMap<String, int>::Iterator c = slot_claim.find(_key(p_id, i));
		if (c) {
			release(c->value);
		}
	}
	objects.erase(p_id);
}

bool CgameSmartObjects::has_object(const String &p_id) const {
	return objects.has(p_id);
}

int CgameSmartObjects::object_count() const {
	return objects.size();
}

Dictionary CgameSmartObjects::get_object(const String &p_id) const {
	const HashMap<String, SmartObject>::ConstIterator it = objects.find(p_id);
	return it ? it->value.raw.duplicate(true) : Dictionary();
}

Vector3 CgameSmartObjects::slot_position(const Dictionary &p_object, int p_slot_index) const {
	const Array slot_defs = p_object.get("slots", Array());
	ERR_FAIL_INDEX_V(p_slot_index, slot_defs.size(), Vector3());
	const Dictionary slot = slot_defs[p_slot_index];
	const Vector3 base = p_object.get("position", Vector3());
	const Vector3 off = slot.get("offset", Vector3());
	return base + off;
}

bool CgameSmartObjects::is_slot_free(const String &p_id, int p_slot_index) const {
	return !slot_claim.has(_key(p_id, p_slot_index));
}

namespace {
struct FoundSlot {
	String object;
	int slot;
	Vector3 position;
	double distance;
	double score;
};
} // namespace

Array CgameSmartObjects::find(const Dictionary &p_query) const {
	const Vector3 pos = p_query.get("position", Vector3());
	const double radius = double(p_query.get("radius", 50.0));
	const Array required = p_query.get("required_tags", Array());
	const Array preferred = p_query.get("preferred_tags", Array());
	const String behavior = String(p_query.get("behavior", ""));
	const bool include_claimed = bool(p_query.get("include_claimed", false));
	std::vector<FoundSlot> found;
	for (const KeyValue<String, SmartObject> &kv : objects) {
		const SmartObject &obj = kv.value;
		for (int i = 0; i < obj.slots.size(); i++) {
			const Slot &slot = obj.slots[i];
			if (!behavior.is_empty() && slot.behavior != behavior) {
				continue;
			}
			if (!include_claimed && !is_slot_free(obj.id, i)) {
				continue;
			}
			if (!_has_all(required, obj.tags, slot.tags)) {
				continue;
			}
			const Vector3 p = obj.position + slot.offset;
			const double d = pos.distance_to(p);
			if (d > radius) {
				continue;
			}
			const double closeness = 1.0 - d / MAX(radius, 0.0001);
			double bonus = 0.0;
			if (!preferred.is_empty()) {
				int hit = 0;
				for (int t = 0; t < preferred.size(); t++) {
					if (obj.tags.has(preferred[t]) || slot.tags.has(preferred[t])) {
						hit++;
					}
				}
				bonus = double(hit) / double(preferred.size());
			}
			found.push_back({ obj.id, i, p, d, closeness + bonus });
		}
	}
	std::stable_sort(found.begin(), found.end(), [](const FoundSlot &a, const FoundSlot &b) {
		if (!Math::is_equal_approx(a.score, b.score)) {
			return a.score > b.score;
		}
		if (a.object != b.object) {
			return a.object < b.object;
		}
		return a.slot < b.slot;
	});
	Array results;
	for (const FoundSlot &f : found) {
		Dictionary d;
		d["object"] = f.object;
		d["slot"] = f.slot;
		d["position"] = f.position;
		d["distance"] = f.distance;
		d["score"] = f.score;
		results.push_back(d);
	}
	return results;
}

int CgameSmartObjects::claim(const String &p_object_id, int p_slot_index, const Variant &p_user, double p_timeout) {
	const HashMap<String, SmartObject>::ConstIterator it = objects.find(p_object_id);
	if (!it) {
		return 0;
	}
	if (p_slot_index < 0 || p_slot_index >= it->value.slots.size()) {
		return 0;
	}
	const String key = _key(p_object_id, p_slot_index);
	if (slot_claim.has(key)) {
		return 0;
	}
	const int handle = next_handle;
	next_handle++;
	const double t = p_timeout < 0.0 ? default_claim_timeout : p_timeout;
	Claim c;
	c.object = p_object_id;
	c.slot = p_slot_index;
	c.user = p_user;
	c.timeout = t;
	c.left = t;
	claims[handle] = c;
	slot_claim[key] = handle;
	return handle;
}

bool CgameSmartObjects::release(int p_handle) {
	RBMap<int, Claim>::Element *e = claims.find(p_handle);
	if (!e) {
		return false;
	}
	slot_claim.erase(_key(e->get().object, e->get().slot));
	claims.erase(e);
	return true;
}

bool CgameSmartObjects::is_claimed(int p_handle) const {
	return claims.has(p_handle);
}

Variant CgameSmartObjects::claim_user(int p_handle) const {
	const RBMap<int, Claim>::Element *e = claims.find(p_handle);
	return e ? e->get().user : Variant();
}

// Resets the idle timeout of a claim (user is still on its way).
void CgameSmartObjects::touch(int p_handle) {
	RBMap<int, Claim>::Element *e = claims.find(p_handle);
	if (e) {
		e->get().left = e->get().timeout;
	}
}

Vector<CgameSmartObjects::Step> CgameSmartObjects::_steps_of(const Claim &p_claim) const {
	const HashMap<String, SmartObject>::ConstIterator obj = objects.find(p_claim.object);
	if (!obj || p_claim.slot < 0 || p_claim.slot >= obj->value.slots.size()) {
		return Vector<Step>();
	}
	const HashMap<String, Vector<Step>>::ConstIterator steps = behaviors.find(obj->value.slots[p_claim.slot].behavior);
	return steps ? steps->value : Vector<Step>();
}

void CgameSmartObjects::_begin_step(Claim &r_claim, int p_index) {
	r_claim.step = p_index;
	r_claim.t = 0.0;
	const Vector<Step> steps = _steps_of(r_claim);
	if (p_index < 0 || p_index >= steps.size()) {
		return;
	}
	const String effect = steps[p_index].effect;
	if (!effect.is_empty() && on_effect.is_valid()) {
		on_effect.call(effect, r_claim.user, r_claim.object);
	}
}

bool CgameSmartObjects::start_interaction(int p_handle) {
	RBMap<int, Claim>::Element *e = claims.find(p_handle);
	if (!e) {
		return false;
	}
	Claim c = e->get();
	if (_steps_of(c).is_empty()) {
		return false;
	}
	c.interacting = true;
	c.step = -1;
	c.t = 0.0;
	_begin_step(c, 0);
	e = claims.find(p_handle);
	if (e) {
		e->get() = c;
	}
	return true;
}

// Returns {step, anim, t, duration} or {} when not interacting.
Dictionary CgameSmartObjects::interaction_state(int p_handle) const {
	const RBMap<int, Claim>::Element *e = claims.find(p_handle);
	if (!e || !e->get().interacting) {
		return Dictionary();
	}
	const Claim &c = e->get();
	const Vector<Step> steps = _steps_of(c);
	ERR_FAIL_INDEX_V(c.step, steps.size(), Dictionary());
	Dictionary d;
	d["step"] = c.step;
	d["anim"] = steps[c.step].anim;
	d["t"] = c.t;
	d["duration"] = steps[c.step].duration;
	return d;
}

// Advances interactions and claim timeouts. Returns handles of interactions finished this call.
Array CgameSmartObjects::advance(double p_dt) {
	Array finished;
	Vector<int> expired;
	Vector<int> handles;
	for (const KeyValue<int, Claim> &kv : claims) {
		handles.push_back(kv.key);
	}
	for (int h = 0; h < handles.size(); h++) {
		const int handle = handles[h];
		RBMap<int, Claim>::Element *e = claims.find(handle);
		if (!e) {
			continue;
		}
		Claim c = e->get();
		if (c.interacting) {
			double left = p_dt;
			while (left > 0.0 && c.interacting) {
				const Vector<Step> steps = _steps_of(c);
				const int step_i = c.step;
				if (step_i < 0 || step_i >= steps.size()) {
					c.interacting = false;
					break;
				}
				const double dur = MAX(steps[step_i].duration, 0.0);
				const double remaining = dur - c.t;
				if (left < remaining) {
					c.t = c.t + left;
					left = 0.0;
				} else {
					left -= remaining;
					if (step_i + 1 < steps.size()) {
						_begin_step(c, step_i + 1);
					} else {
						c.interacting = false;
						finished.push_back(handle);
					}
				}
			}
		} else if (c.timeout > 0.0) {
			c.left = c.left - p_dt;
			if (c.left <= 0.0) {
				expired.push_back(handle);
			}
		}
		e = claims.find(handle);
		if (e) {
			e->get() = c;
		}
	}
	for (int i = 0; i < expired.size(); i++) {
		release(expired[i]);
	}
	if (release_on_complete) {
		for (int i = 0; i < finished.size(); i++) {
			release(int(finished[i]));
		}
	}
	return finished;
}

Vector<Vector3> CgameSmartObjects::_all_positions(const Array &p_extra) const {
	Vector<Vector3> out;
	for (int i = 0; i < p_extra.size(); i++) {
		if (Variant(p_extra[i]).get_type() == Variant::VECTOR3) {
			out.push_back(p_extra[i]);
		}
	}
	for (const KeyValue<String, SmartObject> &kv : objects) {
		out.push_back(kv.value.position);
	}
	return out;
}

// Score in [0, 1] for putting a new object at the candidate position. 0 when
// unreachable or closer than min_spacing to an existing / placed position.
double CgameSmartObjects::placement_score(const Vector3 &p_candidate_pos, const Callable &p_nav_reachable, double p_density, const Array &p_placed, double p_min_spacing) const {
	if (p_nav_reachable.is_valid() && !bool(p_nav_reachable.call(p_candidate_pos))) {
		return 0.0;
	}
	int near = 0;
	const double ring = MAX(p_min_spacing, 0.001) * 2.5;
	const Vector<Vector3> all = _all_positions(p_placed);
	for (int i = 0; i < all.size(); i++) {
		const double d = p_candidate_pos.distance_to(all[i]);
		if (d < p_min_spacing) {
			return 0.0;
		}
		if (d < ring) {
			near++;
		}
	}
	const double tolerated = MAX(p_density, 1.0);
	return CLAMP(1.0 - double(near) / (tolerated * 2.0), 0.05, 1.0);
}

// Deterministic automatic placement. rules: {min_spacing, density, nav_reachable: Callable,
// candidates: int (samples per object)}. Returns up to `count` positions (Vector3, y = 0).
Array CgameSmartObjects::auto_place(const Rect2 &p_area, int p_count, const Dictionary &p_rules, int64_t p_rng_seed) const {
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed(p_rng_seed);
	const double spacing = double(p_rules.get("min_spacing", 1.0));
	const double density = double(p_rules.get("density", 2.0));
	const Callable nav = p_rules.get("nav_reachable", Callable());
	const int samples = int(p_rules.get("candidates", 16));
	const Vector2 area_end = p_area.position + p_area.size;
	Array placed;
	for (int n = 0; n < p_count; n++) {
		Vector3 best;
		double best_score = 0.0;
		for (int s = 0; s < samples; s++) {
			const real_t cx = rng->randf_range(p_area.position.x, area_end.x);
			const real_t cz = rng->randf_range(p_area.position.y, area_end.y);
			const Vector3 cand = Vector3(cx, 0.0, cz);
			const double sc = placement_score(cand, nav, density, placed, spacing);
			if (sc > best_score) {
				best_score = sc;
				best = cand;
			}
		}
		if (best_score > 0.0) {
			placed.push_back(best);
		}
	}
	return placed;
}

void CgameSmartObjects::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_on_effect", "callable"), &CgameSmartObjects::set_on_effect);
	ClassDB::bind_method(D_METHOD("get_on_effect"), &CgameSmartObjects::get_on_effect);
	ClassDB::bind_method(D_METHOD("set_release_on_complete", "enabled"), &CgameSmartObjects::set_release_on_complete);
	ClassDB::bind_method(D_METHOD("get_release_on_complete"), &CgameSmartObjects::get_release_on_complete);
	ClassDB::bind_method(D_METHOD("set_default_claim_timeout", "timeout"), &CgameSmartObjects::set_default_claim_timeout);
	ClassDB::bind_method(D_METHOD("get_default_claim_timeout"), &CgameSmartObjects::get_default_claim_timeout);

	ClassDB::bind_method(D_METHOD("register_behavior", "behavior", "steps"), &CgameSmartObjects::register_behavior);
	ClassDB::bind_method(D_METHOD("register_object", "object"), &CgameSmartObjects::register_object);
	ClassDB::bind_method(D_METHOD("unregister_object", "id"), &CgameSmartObjects::unregister_object);
	ClassDB::bind_method(D_METHOD("has_object", "id"), &CgameSmartObjects::has_object);
	ClassDB::bind_method(D_METHOD("object_count"), &CgameSmartObjects::object_count);
	ClassDB::bind_method(D_METHOD("get_object", "id"), &CgameSmartObjects::get_object);
	ClassDB::bind_method(D_METHOD("slot_position", "object", "slot_index"), &CgameSmartObjects::slot_position);
	ClassDB::bind_method(D_METHOD("is_slot_free", "id", "slot_index"), &CgameSmartObjects::is_slot_free);
	ClassDB::bind_method(D_METHOD("find", "query"), &CgameSmartObjects::find);

	ClassDB::bind_method(D_METHOD("claim", "object_id", "slot_index", "user", "timeout"), &CgameSmartObjects::claim, DEFVAL(-1.0));
	ClassDB::bind_method(D_METHOD("release", "handle"), &CgameSmartObjects::release);
	ClassDB::bind_method(D_METHOD("is_claimed", "handle"), &CgameSmartObjects::is_claimed);
	ClassDB::bind_method(D_METHOD("claim_user", "handle"), &CgameSmartObjects::claim_user);
	ClassDB::bind_method(D_METHOD("touch", "handle"), &CgameSmartObjects::touch);
	ClassDB::bind_method(D_METHOD("start_interaction", "handle"), &CgameSmartObjects::start_interaction);
	ClassDB::bind_method(D_METHOD("interaction_state", "handle"), &CgameSmartObjects::interaction_state);
	ClassDB::bind_method(D_METHOD("advance", "dt"), &CgameSmartObjects::advance);

	ClassDB::bind_method(D_METHOD("placement_score", "candidate_pos", "nav_reachable", "density", "placed", "min_spacing"), &CgameSmartObjects::placement_score, DEFVAL(Array()), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("auto_place", "area", "count", "rules", "rng_seed"), &CgameSmartObjects::auto_place);

	ADD_PROPERTY(PropertyInfo(Variant::CALLABLE, "on_effect", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "set_on_effect", "get_on_effect");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "release_on_complete", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "set_release_on_complete", "get_release_on_complete");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "default_claim_timeout", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "set_default_claim_timeout", "get_default_claim_timeout");
}
