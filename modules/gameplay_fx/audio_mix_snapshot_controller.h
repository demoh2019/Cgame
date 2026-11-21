/**************************************************************************/
/*  audio_mix_snapshot_controller.h                                        */
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#pragma once

#include "core/object/ref_counted.h"
#include "core/string/string_name.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"

// Source-keyed, parallel bus-mix profiles with bounded fades. Like Unreal's
// Control Bus Mixes, a profile can affect multiple buses while other profiles
// affect the same buses. This object is purely a control model: no DSP and
// no calls to AudioServer. User volume and transient ducking remain separate.
class AudioMixSnapshotController : public RefCounted {
	GDCLASS(AudioMixSnapshotController, RefCounted);

public:
	static constexpr int MAX_MIXES = 16;
	static constexpr int MAX_BUSES_PER_MIX = 8;
	static constexpr double MAX_ABS_STAGE_DB = 30.0;
	static constexpr double MAX_FADE_SECONDS = 15.0;
	static constexpr double MIN_BUS_GAIN_DB = -60.0;

private:
	struct BusStage {
		StringName bus;
		double offset_db = 0.0;
	};
	struct Mix {
		StringName source;
		Vector<BusStage> stages;
		double weight = 0.0;
		double target = 1.0;
		double fade_seconds = 1.0;
	};
	Vector<Mix> mixes;
	int _find(const StringName &p_source) const;
	static bool _valid_name(const StringName &p_name);

protected:
	static void _bind_methods();

public:
	// Validates the whole profile before replacing or inserting anything.
	bool activate_mix(const StringName &p_source, const Dictionary &p_bus_offsets_db, double p_fade_seconds = 1.0);
	// Starts a reversible fade-out; a second activation continues from the
	// current weight instead of popping to zero or allocating a duplicate.
	bool deactivate_mix(const StringName &p_source, double p_fade_seconds = 1.0);
	void tick(double p_delta);
	void clear();

	// Sum of independently faded negative dB offsets, hard-limited to -60dB.
	double get_bus_offset_db(const StringName &p_bus) const;
	double get_mix_weight(const StringName &p_source) const;
	bool has_mix(const StringName &p_source) const { return _find(p_source) >= 0; }
	int get_mix_count() const { return mixes.size(); }
};
