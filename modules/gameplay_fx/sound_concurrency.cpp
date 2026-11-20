/**************************************************************************/
/*  sound_concurrency.cpp                                               */
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
#include "sound_concurrency.h"

#include "core/math/math_funcs.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include "scene/3d/node_3d.h"

// ---------------------------------------------------------------------------
// SoundConcurrency
// ---------------------------------------------------------------------------

void SoundConcurrency::set_max_count(int p_max_count) {
	max_count = MAX(0, p_max_count);
	emit_changed();
}

void SoundConcurrency::set_resolution_rule(ResolutionRule p_rule) {
	resolution_rule = p_rule;
	emit_changed();
}

void SoundConcurrency::set_volume_scale(float p_scale) {
	volume_scale = CLAMP(p_scale, 0.0f, 1.0f);
	emit_changed();
}

void SoundConcurrency::set_retrigger_interval(float p_seconds) {
	retrigger_interval = MAX(0.0f, p_seconds);
	emit_changed();
}

int SoundConcurrency::pick_victim(const Voice *p_voices, int p_count, ResolutionRule p_rule, float p_new_distance, float p_new_volume) {
	if (p_voices == nullptr || p_count <= 0) {
		return VICTIM_REJECT_NEW;
	}

	switch (p_rule) {
		case RESOLUTION_PREVENT_NEW: {
			return VICTIM_REJECT_NEW;
		}
		case RESOLUTION_STOP_OLDEST: {
			int best = 0;
			for (int i = 1; i < p_count; i++) {
				if (p_voices[i].start_msec < p_voices[best].start_msec) {
					best = i;
				}
			}
			return best;
		}
		case RESOLUTION_STOP_FARTHEST: {
			int best = 0;
			for (int i = 1; i < p_count; i++) {
				if (p_voices[i].distance > p_voices[best].distance) {
					best = i;
				}
			}
			// The new sound is even farther away (or equally far): it loses.
			if (p_new_distance >= p_voices[best].distance) {
				return VICTIM_REJECT_NEW;
			}
			return best;
		}
		case RESOLUTION_STOP_QUIETEST: {
			int best = 0;
			for (int i = 1; i < p_count; i++) {
				if (p_voices[i].volume < p_voices[best].volume) {
					best = i;
				}
			}
			// The new sound is even quieter (or equally quiet): it loses.
			if (p_new_volume <= p_voices[best].volume) {
				return VICTIM_REJECT_NEW;
			}
			return best;
		}
	}
	return VICTIM_REJECT_NEW;
}

float SoundConcurrency::volume_scale_for(int p_active_count, float p_scale_per_voice) {
	if (p_active_count <= 0) {
		return 1.0f;
	}
	const float scale = CLAMP(p_scale_per_voice, 0.0f, 1.0f);
	return Math::pow(scale, (float)p_active_count);
}

int SoundConcurrency::pick_victim_arrays(const PackedInt64Array &p_start_msec, const PackedFloat32Array &p_distances, const PackedFloat32Array &p_volumes, ResolutionRule p_rule, float p_new_distance, float p_new_volume) {
	const int count = MIN(p_start_msec.size(), MIN(p_distances.size(), p_volumes.size()));
	LocalVector<Voice> voices;
	voices.resize(count);
	for (int i = 0; i < count; i++) {
		voices[i].start_msec = (uint64_t)p_start_msec[i];
		voices[i].distance = p_distances[i];
		voices[i].volume = p_volumes[i];
	}
	return pick_victim(voices.ptr(), count, p_rule, p_new_distance, p_new_volume);
}

void SoundConcurrency::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_max_count", "max_count"), &SoundConcurrency::set_max_count);
	ClassDB::bind_method(D_METHOD("get_max_count"), &SoundConcurrency::get_max_count);
	ClassDB::bind_method(D_METHOD("set_resolution_rule", "rule"), &SoundConcurrency::set_resolution_rule);
	ClassDB::bind_method(D_METHOD("get_resolution_rule"), &SoundConcurrency::get_resolution_rule);
	ClassDB::bind_method(D_METHOD("set_volume_scale", "scale"), &SoundConcurrency::set_volume_scale);
	ClassDB::bind_method(D_METHOD("get_volume_scale"), &SoundConcurrency::get_volume_scale);
	ClassDB::bind_method(D_METHOD("set_retrigger_interval", "seconds"), &SoundConcurrency::set_retrigger_interval);
	ClassDB::bind_method(D_METHOD("get_retrigger_interval"), &SoundConcurrency::get_retrigger_interval);

	ClassDB::bind_static_method("SoundConcurrency", D_METHOD("pick_victim", "start_msec", "distances", "volumes", "rule", "new_distance", "new_volume"), &SoundConcurrency::pick_victim_arrays);
	ClassDB::bind_static_method("SoundConcurrency", D_METHOD("volume_scale_for", "active_count", "scale_per_voice"), &SoundConcurrency::volume_scale_for);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_count", PROPERTY_HINT_RANGE, "0,128,1,or_greater"), "set_max_count", "get_max_count");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "resolution_rule", PROPERTY_HINT_ENUM, "Stop Oldest,Stop Farthest,Stop Quietest,Prevent New"), "set_resolution_rule", "get_resolution_rule");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "volume_scale", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_volume_scale", "get_volume_scale");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "retrigger_interval", PROPERTY_HINT_RANGE, "0,5,0.001,or_greater,suffix:s"), "set_retrigger_interval", "get_retrigger_interval");

	BIND_ENUM_CONSTANT(RESOLUTION_STOP_OLDEST);
	BIND_ENUM_CONSTANT(RESOLUTION_STOP_FARTHEST);
	BIND_ENUM_CONSTANT(RESOLUTION_STOP_QUIETEST);
	BIND_ENUM_CONSTANT(RESOLUTION_PREVENT_NEW);
}

// ---------------------------------------------------------------------------
// SoundConcurrencyManager
// ---------------------------------------------------------------------------

SoundConcurrencyManager::SoundConcurrencyManager() {
	default_concurrency.instantiate();
	default_concurrency->set_max_count(8);
}

void SoundConcurrencyManager::set_default_concurrency(const Ref<SoundConcurrency> &p_concurrency) {
	default_concurrency = p_concurrency;
	if (default_concurrency.is_null()) {
		default_concurrency.instantiate();
		default_concurrency->set_max_count(8);
	}
}

void SoundConcurrencyManager::set_group_config(const StringName &p_group, const Ref<SoundConcurrency> &p_concurrency) {
	if (p_concurrency.is_null()) {
		configs.erase(p_group);
		return;
	}
	configs[p_group] = p_concurrency;
}

Ref<SoundConcurrency> SoundConcurrencyManager::get_group_config(const StringName &p_group) const {
	HashMap<StringName, Ref<SoundConcurrency>>::ConstIterator E = configs.find(p_group);
	if (E) {
		return E->value;
	}
	return default_concurrency;
}

bool SoundConcurrencyManager::has_group_config(const StringName &p_group) const {
	return configs.has(p_group);
}

void SoundConcurrencyManager::remove_group_config(const StringName &p_group) {
	configs.erase(p_group);
}

void SoundConcurrencyManager::clear_group_configs() {
	configs.clear();
}

void SoundConcurrencyManager::_stop_player(Node *p_player) {
	if (p_player) {
		p_player->call(SNAME("stop"));
		emit_signal(SNAME("voice_stopped"), p_player);
	}
}

void SoundConcurrencyManager::_restore_volume(const Entry &p_entry, Node *p_player) {
	if (p_player) {
		p_player->set(SNAME("volume_db"), p_entry.base_volume_db);
	}
}

// Removes the entry belonging to p_id from every group. Optionally stops the player.
bool SoundConcurrencyManager::_release_entry_of(ObjectID p_id, bool p_stop) {
	bool found = false;
	for (KeyValue<StringName, LocalVector<Entry>> &kv : active) {
		LocalVector<Entry> &entries = kv.value;
		for (uint32_t i = 0; i < entries.size(); i++) {
			if (entries[i].player != p_id) {
				continue;
			}
			Node *player = ObjectDB::get_instance<Node>(p_id);
			if (p_stop) {
				_stop_player(player);
			}
			_restore_volume(entries[i], player);
			entries.remove_at(i);
			found = true;
			break;
		}
	}
	return found;
}

void SoundConcurrencyManager::_on_player_finished(uint64_t p_player_id) {
	_release_entry_of(ObjectID(p_player_id), false);
}

void SoundConcurrencyManager::_prune(LocalVector<Entry> &r_entries, uint64_t p_now) {
	// Players that were freed, or that stopped without emitting "finished", are dropped.
	// A short grace period covers the gap between request_play() and the caller's play().
	for (uint32_t i = 0; i < r_entries.size();) {
		Node *player = ObjectDB::get_instance<Node>(r_entries[i].player);
		bool dead = player == nullptr;
		if (!dead && p_now - r_entries[i].start_msec > 100) {
			dead = !(bool)player->call(SNAME("is_playing"));
		}
		if (dead) {
			if (player) {
				_restore_volume(r_entries[i], player);
			}
			r_entries.remove_at(i);
		} else {
			i++;
		}
	}
}

bool SoundConcurrencyManager::request_play(const StringName &p_group, Node *p_player, const Vector3 &p_position, const Vector3 &p_listener) {
	ERR_FAIL_NULL_V(p_player, false);
	ERR_FAIL_COND_V_MSG(!p_player->has_signal(SNAME("finished")) || !p_player->has_method(SNAME("stop")) || !p_player->has_method(SNAME("is_playing")), false, "SoundConcurrencyManager: player must be an AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D.");

	const uint64_t now = OS::get_singleton()->get_ticks_msec();
	Ref<SoundConcurrency> config = get_group_config(p_group);

	// A pooled player being retriggered releases its previous slot first (without stopping it).
	_release_entry_of(p_player->get_instance_id(), false);

	LocalVector<Entry> &entries = active[p_group];
	_prune(entries, now);

	const float interval_msec = config->get_retrigger_interval() * 1000.0f;
	if (interval_msec > 0.0f) {
		HashMap<StringName, uint64_t>::Iterator last = last_trigger_msec.find(p_group);
		if (last && (float)(now - last->value) < interval_msec) {
			return false;
		}
	}

	const float base_db = (float)p_player->get(SNAME("volume_db"));
	const float new_distance = p_position.distance_to(p_listener);
	const float new_volume = Math::db_to_linear(base_db);

	const int max_count = config->get_max_count();
	if (max_count > 0) {
		int guard = (int)entries.size() + 1;
		while ((int)entries.size() >= max_count && guard-- > 0) {
			LocalVector<SoundConcurrency::Voice> voices;
			voices.resize(entries.size());
			for (uint32_t i = 0; i < entries.size(); i++) {
				voices[i].start_msec = entries[i].start_msec;
				voices[i].volume = entries[i].volume;
				voices[i].distance = entries[i].distance;
				Node3D *existing = ObjectDB::get_instance<Node3D>(entries[i].player);
				if (existing && existing->is_inside_tree()) {
					voices[i].distance = existing->get_global_position().distance_to(p_listener);
				}
			}
			const int victim = SoundConcurrency::pick_victim(voices.ptr(), (int)voices.size(), config->get_resolution_rule(), new_distance, new_volume);
			if (victim < 0 || victim >= (int)entries.size()) {
				return false;
			}
			Node *victim_player = ObjectDB::get_instance<Node>(entries[victim].player);
			_stop_player(victim_player);
			_restore_volume(entries[victim], victim_player);
			entries.remove_at(victim);
		}
		if ((int)entries.size() >= max_count) {
			return false;
		}
	}

	const float scale = SoundConcurrency::volume_scale_for((int)entries.size(), config->get_volume_scale());
	if (scale < 1.0f) {
		p_player->set(SNAME("volume_db"), base_db + Math::linear_to_db(MAX(scale, 0.0001f)));
	}

	Entry entry;
	entry.player = p_player->get_instance_id();
	entry.start_msec = now;
	entry.base_volume_db = base_db;
	entry.volume = new_volume * scale;
	entry.distance = new_distance;
	entries.push_back(entry);
	last_trigger_msec[p_group] = now;

	Callable on_finished = callable_mp(this, &SoundConcurrencyManager::_on_player_finished).bind((uint64_t)p_player->get_instance_id());
	if (!p_player->is_connected(SNAME("finished"), on_finished)) {
		p_player->connect(SNAME("finished"), on_finished);
	}
	return true;
}

void SoundConcurrencyManager::release_player(Node *p_player) {
	ERR_FAIL_NULL(p_player);
	_release_entry_of(p_player->get_instance_id(), true);
}

int SoundConcurrencyManager::get_active_count(const StringName &p_group) const {
	HashMap<StringName, LocalVector<Entry>>::ConstIterator E = active.find(p_group);
	if (!E) {
		return 0;
	}
	int count = 0;
	for (uint32_t i = 0; i < E->value.size(); i++) {
		if (ObjectDB::get_instance<Node>(E->value[i].player) != nullptr) {
			count++;
		}
	}
	return count;
}

void SoundConcurrencyManager::stop_group(const StringName &p_group) {
	HashMap<StringName, LocalVector<Entry>>::Iterator E = active.find(p_group);
	if (!E) {
		return;
	}
	LocalVector<Entry> entries;
	entries = E->value;
	E->value.clear();
	for (uint32_t i = 0; i < entries.size(); i++) {
		Node *player = ObjectDB::get_instance<Node>(entries[i].player);
		_stop_player(player);
		_restore_volume(entries[i], player);
	}
}

void SoundConcurrencyManager::stop_all() {
	LocalVector<StringName> groups;
	for (const KeyValue<StringName, LocalVector<Entry>> &kv : active) {
		groups.push_back(kv.key);
	}
	for (const StringName &group : groups) {
		stop_group(group);
	}
}

void SoundConcurrencyManager::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_default_concurrency", "concurrency"), &SoundConcurrencyManager::set_default_concurrency);
	ClassDB::bind_method(D_METHOD("get_default_concurrency"), &SoundConcurrencyManager::get_default_concurrency);

	ClassDB::bind_method(D_METHOD("set_group_config", "group", "concurrency"), &SoundConcurrencyManager::set_group_config);
	ClassDB::bind_method(D_METHOD("get_group_config", "group"), &SoundConcurrencyManager::get_group_config);
	ClassDB::bind_method(D_METHOD("has_group_config", "group"), &SoundConcurrencyManager::has_group_config);
	ClassDB::bind_method(D_METHOD("remove_group_config", "group"), &SoundConcurrencyManager::remove_group_config);
	ClassDB::bind_method(D_METHOD("clear_group_configs"), &SoundConcurrencyManager::clear_group_configs);

	ClassDB::bind_method(D_METHOD("request_play", "group", "player", "position", "listener"), &SoundConcurrencyManager::request_play);
	ClassDB::bind_method(D_METHOD("release_player", "player"), &SoundConcurrencyManager::release_player);
	ClassDB::bind_method(D_METHOD("get_active_count", "group"), &SoundConcurrencyManager::get_active_count);
	ClassDB::bind_method(D_METHOD("stop_group", "group"), &SoundConcurrencyManager::stop_group);
	ClassDB::bind_method(D_METHOD("stop_all"), &SoundConcurrencyManager::stop_all);

	ClassDB::bind_method(D_METHOD("_on_player_finished", "player_id"), &SoundConcurrencyManager::_on_player_finished);

	ADD_SIGNAL(MethodInfo("voice_stopped", PropertyInfo(Variant::OBJECT, "player", PROPERTY_HINT_NODE_TYPE, "Node")));

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "default_concurrency", PROPERTY_HINT_RESOURCE_TYPE, "SoundConcurrency"), "set_default_concurrency", "get_default_concurrency");
}
