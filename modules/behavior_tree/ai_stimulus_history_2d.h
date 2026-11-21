/**************************************************************************/
/*  ai_stimulus_history_2d.h                                                 */
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

#include "core/math/vector2.h"
#include "core/object/ref_counted.h"
#include "core/templates/vector.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

/**
 * Bounded, source-aware event memory for already-authorized AI perceptions.
 * The game owns visibility, occlusion, affiliation, wind and safe-zone rules.
 * This never creates a sensor event or selects a combat target on its own.
 */
class AIStimulusHistory2D : public RefCounted {
	GDCLASS(AIStimulusHistory2D, RefCounted);

public:
	enum Sense {
		SIGHT,
		SOUND,
		DAMAGE,
	};

private:
	struct Stimulus {
		Sense sense = SIGHT;
		int64_t source_id = -1;
		Vector2 position;
		real_t strength = 1.0;
		real_t ttl = 1.0;
		real_t remaining = 1.0;
	};

	int capacity = 16;
	Vector<Stimulus> events; // Oldest to newest; stable bounded storage.

	static Dictionary make_snapshot(const Stimulus &p_event);

protected:
	static void _bind_methods();

public:
	void set_capacity(int p_capacity);
	int get_capacity() const { return capacity; }

	// Updates the existing (sense, source_id) event for identified sources;
	// anonymous source_id -1 is not deduplicated. Valid strength is (0,1],
	// TTL (0,60]. Invalid events are rejected with no mutation.
	bool record_stimulus(int p_sense, const Vector2 &p_position, real_t p_strength, real_t p_ttl_seconds, int64_t p_source_id = -1);
	void advance_time(real_t p_delta);
	int get_event_count() const { return events.size(); }
	// Highest decayed strength in the selected sense; ties are deterministic.
	Dictionary get_best(int p_sense) const;
	// Newest events first. A detached Array of plain-data Dictionaries.
	Array get_recent(int p_limit = 8) const;
	// Highest decayed confidence first; stable source-id/position ties.
	// Results are detached snapshots, not mutable views into agent memory.
	Array get_ranked(int p_sense, int p_limit = 8) const;
	void reset();
};

VARIANT_ENUM_CAST(AIStimulusHistory2D::Sense);
