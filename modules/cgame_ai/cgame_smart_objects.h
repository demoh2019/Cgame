/**************************************************************************/
/*  cgame_smart_objects.h                                                 */
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

#include "cgame_ai_common.h"

#include "core/math/rect2.h"
#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/templates/rb_map.h"

// Smart Object registry: slots, exclusive claims with timeouts, query scoring,
// placement scoring / automatic placement and per-behavior interaction steps.
// Positions are world Vector3; 2D areas (Rect2) map x -> world x, y -> world z.
class CgameSmartObjects : public RefCounted {
	GDCLASS(CgameSmartObjects, RefCounted);

	struct Slot {
		Vector3 offset;
		String behavior;
		Array tags;
	};

	struct SmartObject {
		String id;
		Vector3 position;
		Array tags;
		Vector<Slot> slots;
		Dictionary raw;
	};

	struct Step {
		String anim;
		double duration = 0.0;
		String effect;
	};

	struct Claim {
		String object;
		int slot = 0;
		Variant user;
		double timeout = 0.0;
		double left = 0.0;
		int step = -1;
		double t = 0.0;
		bool interacting = false;
	};

	Callable on_effect;
	bool release_on_complete = true;
	double default_claim_timeout = 10.0;

	HashMap<String, SmartObject> objects;
	HashMap<String, Vector<Step>> behaviors;
	RBMap<int, Claim> claims;
	HashMap<String, int> slot_claim;
	int next_handle = 1;

	static String _key(const String &p_id, int p_slot_index);
	static bool _has_all(const Array &p_required, const Array &p_a, const Array &p_b);
	Vector<Step> _steps_of(const Claim &p_claim) const;
	void _begin_step(Claim &r_claim, int p_index);
	Vector<Vector3> _all_positions(const Array &p_extra) const;

protected:
	static void _bind_methods();

public:
	void set_on_effect(const Callable &p_callable) { on_effect = p_callable; }
	Callable get_on_effect() const { return on_effect; }
	void set_release_on_complete(bool p_enabled) { release_on_complete = p_enabled; }
	bool get_release_on_complete() const { return release_on_complete; }
	void set_default_claim_timeout(double p_timeout) { default_claim_timeout = p_timeout; }
	double get_default_claim_timeout() const { return default_claim_timeout; }

	void register_behavior(const String &p_behavior, const Array &p_steps);
	bool register_object(const Dictionary &p_object);
	void unregister_object(const String &p_id);
	bool has_object(const String &p_id) const;
	int object_count() const;
	Dictionary get_object(const String &p_id) const;
	Vector3 slot_position(const Dictionary &p_object, int p_slot_index) const;
	bool is_slot_free(const String &p_id, int p_slot_index) const;
	Array find(const Dictionary &p_query) const;

	int claim(const String &p_object_id, int p_slot_index, const Variant &p_user, double p_timeout = -1.0);
	bool release(int p_handle);
	bool is_claimed(int p_handle) const;
	Variant claim_user(int p_handle) const;
	void touch(int p_handle);
	bool start_interaction(int p_handle);
	Dictionary interaction_state(int p_handle) const;
	Array advance(double p_dt);

	double placement_score(const Vector3 &p_candidate_pos, const Callable &p_nav_reachable, double p_density, const Array &p_placed = Array(), double p_min_spacing = 0.0) const;
	Array auto_place(const Rect2 &p_area, int p_count, const Dictionary &p_rules, int64_t p_rng_seed) const;
};
