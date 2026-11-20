/**************************************************************************/
/*  animation_lod_controller.h                                            */
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

#include "core/object/object_id.h"
#include "core/templates/vector.h"
#include "scene/animation/animation_mixer.h"
#include "scene/main/node.h"

/**
 * Animation update-rate optimization (Unreal URO / Unity Culling Mode).
 * Registered AnimationMixer nodes are switched to manual callback mode and advanced
 * at a distance-dependent rate with accumulated delta, so animation time stays correct.
 */
class AnimationLODController : public Node {
	GDCLASS(AnimationLODController, Node);

	struct Entry {
		ObjectID mixer_id;
		AnimationMixer::AnimationCallbackModeProcess original_mode = AnimationMixer::ANIMATION_CALLBACK_MODE_PROCESS_IDLE;
		double accumulated = 0.0;
		uint32_t phase = 0; // Stagger offset so mixers do not all tick on the same frame.
		bool modifiers_culled = false;
		bool high_priority = false; // Preserve key combat telegraphs on a bounded visible subset.
		bool manage_modifiers = true; // Only the base mixer owns shared skeleton IK culling.
		Vector<ObjectID> disabled_modifiers;
	};

	Vector<Entry> entries;
	bool enabled = true;
	real_t near_distance = 15.0;
	real_t mid_distance = 35.0;
	real_t far_distance = 70.0;
	real_t modifier_cull_distance = 40.0; // <= 0 disables modifier culling.
	bool cull_offscreen = true;
	double max_accumulated_delta = 0.5;
	uint32_t frame_counter = 0;
	uint32_t next_phase = 0;
	int max_priority_mixers = 8; // Extra full-rate animation slots, never unlimited.

	void _update(double p_delta);
	void _restore_entry(Entry &r_entry);
	void _set_modifiers_culled(Entry &r_entry, AnimationMixer *p_mixer, bool p_culled);

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	// 1 = every frame, 2 = every 2nd, 4 = every 4th, 0 = paused (offscreen or beyond far_distance).
	static int update_interval(real_t p_distance, bool p_visible, real_t p_near, real_t p_mid, real_t p_far);

	// Stable, finite-only nearest-first selection for a bounded number of
	// combat-critical mixer updates. Gameplay never uses this visual ranking.
	// Public to native tests; not exported as a script API.
	static Vector<int> select_nearest_priority_indices(const Vector<real_t> &p_distances, int p_budget);

	void register_mixer(AnimationMixer *p_mixer, bool p_manage_modifiers = true);
	void unregister_mixer(AnimationMixer *p_mixer);
	void clear_mixers();
	void set_mixer_high_priority(AnimationMixer *p_mixer, bool p_priority);
	bool is_mixer_high_priority(AnimationMixer *p_mixer) const;
	void set_max_priority_mixers(int p_count) { max_priority_mixers = CLAMP(p_count, 0, 32); }
	int get_max_priority_mixers() const { return max_priority_mixers; }
	int get_mixer_count() const { return entries.size(); }

	void set_enabled(bool p_enabled);
	bool is_enabled() const { return enabled; }
	void set_near_distance(real_t p_distance) { near_distance = p_distance; }
	real_t get_near_distance() const { return near_distance; }
	void set_mid_distance(real_t p_distance) { mid_distance = p_distance; }
	real_t get_mid_distance() const { return mid_distance; }
	void set_far_distance(real_t p_distance) { far_distance = p_distance; }
	real_t get_far_distance() const { return far_distance; }
	void set_modifier_cull_distance(real_t p_distance) { modifier_cull_distance = p_distance; }
	real_t get_modifier_cull_distance() const { return modifier_cull_distance; }
	void set_cull_offscreen(bool p_cull) { cull_offscreen = p_cull; }
	bool is_cull_offscreen() const { return cull_offscreen; }
	void set_max_accumulated_delta(double p_seconds) { max_accumulated_delta = MAX(p_seconds, 0.0); }
	double get_max_accumulated_delta() const { return max_accumulated_delta; }
};
