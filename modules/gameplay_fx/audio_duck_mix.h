/**************************************************************************/
/*  audio_duck_mix.h                                                       */
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#pragma once

#include "core/object/ref_counted.h"
#include "core/string/string_name.h"
#include "core/templates/vector.h"

// Stateless from the audio server's perspective: this object only computes
// a mix value in dB. It never changes AudioServer buses or persists user gain.
// Reusable for music, ambience, dialogue and sound-effect mix destinations.
class AudioDuckMix : public RefCounted {
	GDCLASS(AudioDuckMix, RefCounted);

public:
	static constexpr int MAX_SOURCES = 32;
	static constexpr double MAX_DEPTH_DB = 60.0;
	static constexpr double MAX_HOLD_SECONDS = 30.0;
	static constexpr double MAX_RATE_DB_PER_SECOND = 120.0;

private:
	struct Source {
		StringName name;
		double depth_db = 0.0;
		double remaining = 0.0;
	};
	Vector<Source> sources;
	double current_db = 0.0;
	double attack_rate = 40.0;
	double release_rate = 4.0;

	int _find_source(const StringName &p_source) const;

protected:
	static void _bind_methods();

public:
	// Source triggers do not stack unboundedly. Re-trigger retains the deeper
	// dip for that source while resetting its independent hold duration.
	bool trigger(const StringName &p_source, double p_depth_db, double p_hold_seconds = 1.2);
	bool release_source(const StringName &p_source);
	// Advances source lifetimes then approaches deepest live source by bounded
	// rates. Invalid deltas leave both the timers and current dB unchanged.
	double tick(double p_delta);
	void clear(); // Immediately restore 0 dB and remove all sources.
	bool set_rates(double p_attack_db_per_second, double p_release_db_per_second);

	double get_current_db() const { return current_db; }
	double get_target_db() const;
	double get_remaining(const StringName &p_source) const;
	int get_source_count() const { return sources.size(); }
	bool has_source(const StringName &p_source) const { return _find_source(p_source) >= 0; }
};
