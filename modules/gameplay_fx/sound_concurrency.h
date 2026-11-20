/**************************************************************************/
/*  sound_concurrency.h                                                 */
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

#include "core/io/resource.h"
#include "core/object/object.h"
#include "core/string/string_name.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"

/**
 * Unreal-style "Sound Concurrency" settings for one group of sounds.
 * Also hosts the pure (node-free) victim selection logic so it can be unit tested.
 */
class SoundConcurrency : public Resource {
	GDCLASS(SoundConcurrency, Resource);

public:
	enum ResolutionRule {
		RESOLUTION_STOP_OLDEST,
		RESOLUTION_STOP_FARTHEST,
		RESOLUTION_STOP_QUIETEST,
		RESOLUTION_PREVENT_NEW,
	};

	// Snapshot of one currently playing voice, used by pick_victim().
	struct Voice {
		uint64_t start_msec = 0;
		float distance = 0.0f;
		float volume = 1.0f; // Linear.
	};

	// Returned by pick_victim() when the new sound must not be played.
	static constexpr int VICTIM_REJECT_NEW = -1;

private:
	int max_count = 4;
	ResolutionRule resolution_rule = RESOLUTION_STOP_OLDEST;
	float volume_scale = 1.0f;
	float retrigger_interval = 0.0f;

protected:
	static void _bind_methods();

public:
	void set_max_count(int p_max_count);
	int get_max_count() const { return max_count; }

	void set_resolution_rule(ResolutionRule p_rule);
	ResolutionRule get_resolution_rule() const { return resolution_rule; }

	void set_volume_scale(float p_scale);
	float get_volume_scale() const { return volume_scale; }

	void set_retrigger_interval(float p_seconds);
	float get_retrigger_interval() const { return retrigger_interval; }

	// Pure logic. Returns the index of the voice to stop to make room for a new
	// sound, or VICTIM_REJECT_NEW when the new sound should not be played.
	static int pick_victim(const Voice *p_voices, int p_count, ResolutionRule p_rule, float p_new_distance, float p_new_volume);
	// Linear gain for a new voice when p_active_count voices are already playing.
	static float volume_scale_for(int p_active_count, float p_scale_per_voice);

	// Script-friendly wrapper around pick_victim() (parallel arrays, one entry per voice).
	static int pick_victim_arrays(const PackedInt64Array &p_start_msec, const PackedFloat32Array &p_distances, const PackedFloat32Array &p_volumes, ResolutionRule p_rule, float p_new_distance, float p_new_volume);
};

VARIANT_ENUM_CAST(SoundConcurrency::ResolutionRule);

/**
 * Tracks AudioStreamPlayer / AudioStreamPlayer3D voices per concurrency group and
 * resolves overflow according to the group's SoundConcurrency rule.
 */
class SoundConcurrencyManager : public Node {
	GDCLASS(SoundConcurrencyManager, Node);

	struct Entry {
		ObjectID player;
		uint64_t start_msec = 0;
		float base_volume_db = 0.0f;
		float volume = 1.0f; // Linear, after scaling.
		float distance = 0.0f;
	};

	HashMap<StringName, Ref<SoundConcurrency>> configs;
	HashMap<StringName, LocalVector<Entry>> active;
	HashMap<StringName, uint64_t> last_trigger_msec;
	Ref<SoundConcurrency> default_concurrency;

	void _on_player_finished(uint64_t p_player_id);
	void _stop_player(Node *p_player);
	void _restore_volume(const Entry &p_entry, Node *p_player);
	bool _release_entry_of(ObjectID p_id, bool p_stop);
	void _prune(LocalVector<Entry> &r_entries, uint64_t p_now);

protected:
	static void _bind_methods();

public:
	void set_default_concurrency(const Ref<SoundConcurrency> &p_concurrency);
	Ref<SoundConcurrency> get_default_concurrency() const { return default_concurrency; }

	void set_group_config(const StringName &p_group, const Ref<SoundConcurrency> &p_concurrency);
	Ref<SoundConcurrency> get_group_config(const StringName &p_group) const;
	bool has_group_config(const StringName &p_group) const;
	void remove_group_config(const StringName &p_group);
	void clear_group_configs();

	// Returns true when the caller may start p_player now. Victims are stopped
	// automatically. The player's volume_db is scaled and restored on release.
	bool request_play(const StringName &p_group, Node *p_player, const Vector3 &p_position, const Vector3 &p_listener);
	void release_player(Node *p_player);
	int get_active_count(const StringName &p_group) const;
	void stop_group(const StringName &p_group);
	void stop_all();

	SoundConcurrencyManager();
};
