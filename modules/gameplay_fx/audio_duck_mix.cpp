/**************************************************************************/
/*  audio_duck_mix.cpp                                                     */
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "audio_duck_mix.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

int AudioDuckMix::_find_source(const StringName &p_source) const {
	for (int i = 0; i < sources.size(); ++i) {
		if (sources[i].name == p_source) {
			return i;
		}
	}
	return -1;
}

bool AudioDuckMix::trigger(const StringName &p_source, double p_depth_db, double p_hold_seconds) {
	const String source = p_source;
	if (source.is_empty() || source.length() > 128 ||
			!Math::is_finite(p_depth_db) || p_depth_db >= 0.0 || p_depth_db < -MAX_DEPTH_DB ||
			!Math::is_finite(p_hold_seconds) || p_hold_seconds <= 0.0 || p_hold_seconds > MAX_HOLD_SECONDS) {
		return false;
	}
	const int index = _find_source(p_source);
	if (index >= 0) {
		Source &entry = sources.write[index];
		entry.depth_db = MIN(entry.depth_db, p_depth_db);
		entry.remaining = p_hold_seconds;
		return true;
	}
	if (sources.size() >= MAX_SOURCES) {
		return false;
	}
	Source entry;
	entry.name = p_source;
	entry.depth_db = p_depth_db;
	entry.remaining = p_hold_seconds;
	sources.push_back(entry);
	return true;
}

bool AudioDuckMix::release_source(const StringName &p_source) {
	const int index = _find_source(p_source);
	if (index < 0) {
		return false;
	}
	sources.remove_at(index);
	return true;
}

double AudioDuckMix::get_remaining(const StringName &p_source) const {
	const int index = _find_source(p_source);
	return index < 0 ? 0.0 : sources[index].remaining;
}

double AudioDuckMix::get_target_db() const {
	double target = 0.0;
	for (const Source &entry : sources) {
		target = MIN(target, entry.depth_db);
	}
	return target;
}

double AudioDuckMix::tick(double p_delta) {
	if (!Math::is_finite(p_delta) || p_delta <= 0.0) {
		return current_db;
	}
	for (int i = sources.size() - 1; i >= 0; --i) {
		if (sources[i].remaining <= p_delta) {
			sources.remove_at(i);
		} else {
			sources.write[i].remaining -= p_delta;
		}
	}
	const double target = get_target_db();
	const double step = (target < current_db ? attack_rate : release_rate) * p_delta;
	if (target < current_db) {
		current_db = MAX(target, current_db - step);
	} else {
		current_db = MIN(target, current_db + step);
	}
	return current_db;
}

void AudioDuckMix::clear() {
	sources.clear();
	current_db = 0.0;
}

bool AudioDuckMix::set_rates(double p_attack_db_per_second, double p_release_db_per_second) {
	if (!Math::is_finite(p_attack_db_per_second) ||
			!Math::is_finite(p_release_db_per_second) ||
			p_attack_db_per_second <= 0.0 || p_attack_db_per_second > MAX_RATE_DB_PER_SECOND ||
			p_release_db_per_second <= 0.0 || p_release_db_per_second > MAX_RATE_DB_PER_SECOND) {
		return false;
	}
	attack_rate = p_attack_db_per_second;
	release_rate = p_release_db_per_second;
	return true;
}

void AudioDuckMix::_bind_methods() {
	ClassDB::bind_method(D_METHOD("trigger", "source", "depth_db", "hold_seconds"),
			&AudioDuckMix::trigger, DEFVAL(1.2));
	ClassDB::bind_method(D_METHOD("release_source", "source"), &AudioDuckMix::release_source);
	ClassDB::bind_method(D_METHOD("tick", "delta"), &AudioDuckMix::tick);
	ClassDB::bind_method(D_METHOD("clear"), &AudioDuckMix::clear);
	ClassDB::bind_method(D_METHOD("set_rates", "attack_db_per_second", "release_db_per_second"),
			&AudioDuckMix::set_rates);
	ClassDB::bind_method(D_METHOD("get_current_db"), &AudioDuckMix::get_current_db);
	ClassDB::bind_method(D_METHOD("get_target_db"), &AudioDuckMix::get_target_db);
	ClassDB::bind_method(D_METHOD("get_remaining", "source"), &AudioDuckMix::get_remaining);
	ClassDB::bind_method(D_METHOD("get_source_count"), &AudioDuckMix::get_source_count);
	ClassDB::bind_method(D_METHOD("has_source", "source"), &AudioDuckMix::has_source);
}
