/**************************************************************************/
/*  audio_mix_snapshot_controller.cpp                                      */
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "audio_mix_snapshot_controller.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

int AudioMixSnapshotController::_find(const StringName &p_source) const {
	for (int i = 0; i < mixes.size(); ++i) {
		if (mixes[i].source == p_source) {
			return i;
		}
	}
	return -1;
}

bool AudioMixSnapshotController::_valid_name(const StringName &p_name) {
	const String name = p_name;
	return !name.is_empty() && name.length() <= 128;
}

bool AudioMixSnapshotController::activate_mix(const StringName &p_source,
		const Dictionary &p_bus_offsets_db, double p_fade_seconds) {
	if (!_valid_name(p_source) || p_bus_offsets_db.is_empty() ||
			p_bus_offsets_db.size() > MAX_BUSES_PER_MIX ||
			!Math::is_finite(p_fade_seconds) || p_fade_seconds < 0.0 ||
			p_fade_seconds > MAX_FADE_SECONDS) {
		return false;
	}

	Vector<BusStage> stages;
	for (const Variant &key : p_bus_offsets_db) {
		if (key.get_type() != Variant::STRING && key.get_type() != Variant::STRING_NAME) {
			return false;
		}
		const StringName bus = key;
		if (!_valid_name(bus)) {
			return false;
		}
		// String and StringName keys may identify the same bus. Reject
		// duplicates after normalizing to avoid silently double-counting.
		for (const BusStage &existing : stages) {
			if (existing.bus == bus) {
				return false;
			}
		}
		const Variant raw = p_bus_offsets_db[key];
		if (raw.get_type() != Variant::FLOAT && raw.get_type() != Variant::INT) {
			return false;
		}
		const double db = double(raw);
		if (!Math::is_finite(db) || db > 0.0 || db < -MAX_ABS_STAGE_DB) {
			return false;
		}
		BusStage stage;
		stage.bus = bus;
		stage.offset_db = db;
		stages.push_back(stage);
	}

	const int index = _find(p_source);
	if (index >= 0) {
		Mix &mix = mixes.write[index];
		mix.stages = stages;
		mix.target = 1.0;
		mix.fade_seconds = p_fade_seconds;
		if (p_fade_seconds == 0.0) {
			mix.weight = 1.0;
		}
		return true;
	}
	if (mixes.size() >= MAX_MIXES) {
		return false;
	}

	Mix mix;
	mix.source = p_source;
	mix.stages = stages;
	mix.target = 1.0;
	mix.fade_seconds = p_fade_seconds;
	mix.weight = p_fade_seconds == 0.0 ? 1.0 : 0.0;
	mixes.push_back(mix);
	return true;
}

bool AudioMixSnapshotController::deactivate_mix(const StringName &p_source, double p_fade_seconds) {
	if (!Math::is_finite(p_fade_seconds) || p_fade_seconds < 0.0 ||
			p_fade_seconds > MAX_FADE_SECONDS) {
		return false;
	}
	const int index = _find(p_source);
	if (index < 0) {
		return false;
	}
	if (p_fade_seconds == 0.0) {
		mixes.remove_at(index);
		return true;
	}
	Mix &mix = mixes.write[index];
	mix.target = 0.0;
	mix.fade_seconds = p_fade_seconds;
	return true;
}

void AudioMixSnapshotController::tick(double p_delta) {
	if (!Math::is_finite(p_delta) || p_delta <= 0.0) {
		return;
	}
	for (int i = mixes.size() - 1; i >= 0; --i) {
		Mix &mix = mixes.write[i];
		if (mix.fade_seconds == 0.0) {
			mix.weight = mix.target;
		} else {
			const double step = p_delta / mix.fade_seconds;
			mix.weight = mix.target > mix.weight ?
				MIN(mix.target, mix.weight + step) :
				MAX(mix.target, mix.weight - step);
		}
		if (mix.target == 0.0 && mix.weight <= 0.0) {
			mixes.remove_at(i);
		}
	}
}

double AudioMixSnapshotController::get_bus_offset_db(const StringName &p_bus) const {
	if (!_valid_name(p_bus)) {
		return 0.0;
	}
	double offset = 0.0;
	for (const Mix &mix : mixes) {
		for (const BusStage &stage : mix.stages) {
			if (stage.bus == p_bus) {
				offset += stage.offset_db * mix.weight;
			}
		}
	}
	return MAX(MIN_BUS_GAIN_DB, offset);
}

double AudioMixSnapshotController::get_mix_weight(const StringName &p_source) const {
	const int index = _find(p_source);
	return index >= 0 ? mixes[index].weight : 0.0;
}

void AudioMixSnapshotController::clear() {
	mixes.clear();
}

void AudioMixSnapshotController::_bind_methods() {
	ClassDB::bind_method(D_METHOD("activate_mix", "source", "bus_offsets_db", "fade_seconds"),
			&AudioMixSnapshotController::activate_mix, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("deactivate_mix", "source", "fade_seconds"),
			&AudioMixSnapshotController::deactivate_mix, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("tick", "delta"), &AudioMixSnapshotController::tick);
	ClassDB::bind_method(D_METHOD("clear"), &AudioMixSnapshotController::clear);
	ClassDB::bind_method(D_METHOD("get_bus_offset_db", "bus"), &AudioMixSnapshotController::get_bus_offset_db);
	ClassDB::bind_method(D_METHOD("get_mix_weight", "source"), &AudioMixSnapshotController::get_mix_weight);
	ClassDB::bind_method(D_METHOD("has_mix", "source"), &AudioMixSnapshotController::has_mix);
	ClassDB::bind_method(D_METHOD("get_mix_count"), &AudioMixSnapshotController::get_mix_count);
}
