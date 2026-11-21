/**************************************************************************/
/*  ai_stimulus_history_2d.cpp                                                 */
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

#include "ai_stimulus_history_2d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

Dictionary AIStimulusHistory2D::make_snapshot(const Stimulus &p_event) {
	Dictionary snapshot;
	snapshot["sense"] = int(p_event.sense);
	snapshot["source_id"] = p_event.source_id;
	snapshot["position"] = p_event.position;
	snapshot["strength"] = p_event.strength;
	snapshot["ttl_seconds"] = p_event.ttl;
	snapshot["remaining_seconds"] = p_event.remaining;
	snapshot["age_seconds"] = MAX(real_t(0.0), p_event.ttl - p_event.remaining);
	snapshot["score"] = p_event.strength * (p_event.remaining / p_event.ttl);
	return snapshot;
}

void AIStimulusHistory2D::set_capacity(int p_capacity) {
	ERR_FAIL_COND_MSG(p_capacity < 1 || p_capacity > 64, "Stimulus history capacity must be between 1 and 64.");
	capacity = p_capacity;
	while (events.size() > capacity) {
		events.remove_at(0);
	}
}

bool AIStimulusHistory2D::record_stimulus(int p_sense, const Vector2 &p_position, real_t p_strength, real_t p_ttl_seconds, int64_t p_source_id) {
	ERR_FAIL_COND_V_MSG(p_sense < SIGHT || p_sense > DAMAGE, false, "Stimulus sense is invalid.");
	ERR_FAIL_COND_V_MSG(!p_position.is_finite(), false, "Stimulus position must be finite.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_strength) || p_strength <= 0.0 || p_strength > 1.0, false, "Stimulus strength must be in (0,1].");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_ttl_seconds) || p_ttl_seconds <= 0.0 || p_ttl_seconds > 60.0, false, "Stimulus duration must be in (0,60].");
	ERR_FAIL_COND_V_MSG(p_source_id < -1, false, "Stimulus source ID must be -1 or nonnegative.");

	// Repeated confirmed signals refresh a known source's memory instead of
	// displacing other survivors with duplicates on every server AI tick.
	if (p_source_id >= 0) {
		for (int i = events.size() - 1; i >= 0; --i) {
			if (events[i].sense == p_sense && events[i].source_id == p_source_id) {
				events.remove_at(i);
				break;
			}
		}
	}
	if (events.size() >= capacity) {
		events.remove_at(0);
	}
	Stimulus stimulus;
	stimulus.sense = Sense(p_sense);
	stimulus.source_id = p_source_id;
	stimulus.position = p_position;
	stimulus.strength = p_strength;
	stimulus.ttl = p_ttl_seconds;
	stimulus.remaining = p_ttl_seconds;
	events.push_back(stimulus);
	return true;
}

void AIStimulusHistory2D::advance_time(real_t p_delta) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_delta) || p_delta < 0.0, "Stimulus delta must be finite and nonnegative.");
	for (int i = events.size() - 1; i >= 0; --i) {
		const real_t remaining = events[i].remaining - p_delta;
		if (remaining <= 0.0) {
			events.remove_at(i);
		} else {
			events.write[i].remaining = remaining;
		}
	}
}

Dictionary AIStimulusHistory2D::get_best(int p_sense) const {
	if (p_sense < SIGHT || p_sense > DAMAGE) {
		return Dictionary();
	}
	const Stimulus *best = nullptr;
	real_t best_score = real_t(-1.0);
	for (int i = 0; i < events.size(); ++i) {
		const Stimulus &candidate = events[i];
		if (candidate.sense != p_sense) {
			continue;
		}
		const real_t score = candidate.strength * (candidate.remaining / candidate.ttl);
		// The tie-breaker is independent of insertion/dictionary order.
		// Prefer a lower stable source ID, then lexicographic 2D location.
		const bool preferred_tie = best != nullptr && score == best_score &&
				(candidate.source_id < best->source_id ||
						(candidate.source_id == best->source_id &&
								(candidate.position.x < best->position.x ||
										(candidate.position.x == best->position.x && candidate.position.y < best->position.y))));
		if (score > best_score || preferred_tie) {
			best = &candidate;
			best_score = score;
		}
	}
	return best != nullptr ? make_snapshot(*best) : Dictionary();
}

Array AIStimulusHistory2D::get_recent(int p_limit) const {
	ERR_FAIL_COND_V_MSG(p_limit < 0 || p_limit > 64, Array(), "Stimulus history query limit must be between 0 and 64.");
	Array results;
	for (int i = events.size() - 1; i >= 0 && results.size() < p_limit; --i) {
		results.push_back(make_snapshot(events[i]));
	}
	return results;
}

Array AIStimulusHistory2D::get_ranked(int p_sense, int p_limit) const {
	Array result;
	ERR_FAIL_COND_V_MSG(p_sense < SIGHT || p_sense > DAMAGE, result, "Unknown stimulus sense.");
	ERR_FAIL_COND_V_MSG(p_limit < 0 || p_limit > 64, result, "Ranked stimulus limit must be between 0 and 64.");
	if (p_limit == 0) {
		return result;
	}
	// A per-agent history has at most 64 entries. Use a bounded sorted
	// top-K of indices instead of allocating mutable snapshots for all events.
	Vector<int> best;
	for (int i = 0; i < events.size(); i++) {
		const Stimulus &candidate = events[i];
		if (candidate.sense != p_sense) {
			continue;
		}
		const real_t candidate_score = candidate.strength * (candidate.remaining / candidate.ttl);
		int insert_at = 0;
		while (insert_at < best.size()) {
			const Stimulus &previous = events[best[insert_at]];
			const real_t previous_score = previous.strength * (previous.remaining / previous.ttl);
			const bool preferred = candidate_score > previous_score ||
					(candidate_score == previous_score &&
						(candidate.source_id < previous.source_id ||
							(candidate.source_id == previous.source_id &&
								(candidate.position.x < previous.position.x ||
									(candidate.position.x == previous.position.x &&
										candidate.position.y < previous.position.y)))));
			if (preferred) {
				break;
			}
			insert_at++;
		}
		if (insert_at >= p_limit) {
			continue;
		}
		best.insert(insert_at, i);
		if (best.size() > p_limit) {
			best.resize(p_limit);
		}
	}
	for (int i = 0; i < best.size(); i++) {
		result.push_back(make_snapshot(events[best[i]]));
	}
	return result;
}

void AIStimulusHistory2D::reset() {
	events.clear();
}

void AIStimulusHistory2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_capacity", "capacity"), &AIStimulusHistory2D::set_capacity);
	ClassDB::bind_method(D_METHOD("get_capacity"), &AIStimulusHistory2D::get_capacity);
	ClassDB::bind_method(D_METHOD("record_stimulus", "sense", "position", "strength", "ttl_seconds", "source_id"), &AIStimulusHistory2D::record_stimulus, DEFVAL(int64_t(-1)));
	ClassDB::bind_method(D_METHOD("advance_time", "delta"), &AIStimulusHistory2D::advance_time);
	ClassDB::bind_method(D_METHOD("get_event_count"), &AIStimulusHistory2D::get_event_count);
	ClassDB::bind_method(D_METHOD("get_best", "sense"), &AIStimulusHistory2D::get_best);
	ClassDB::bind_method(D_METHOD("get_recent", "limit"), &AIStimulusHistory2D::get_recent, DEFVAL(8));
	ClassDB::bind_method(D_METHOD("get_ranked", "sense", "limit"), &AIStimulusHistory2D::get_ranked, DEFVAL(8));
	ClassDB::bind_method(D_METHOD("reset"), &AIStimulusHistory2D::reset);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "capacity", PROPERTY_HINT_RANGE, "1,64,1"), "set_capacity", "get_capacity");
	BIND_ENUM_CONSTANT(SIGHT);
	BIND_ENUM_CONSTANT(SOUND);
	BIND_ENUM_CONSTANT(DAMAGE);
}
