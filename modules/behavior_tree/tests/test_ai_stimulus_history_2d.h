/**************************************************************************/
/*  test_ai_stimulus_history_2d.h                                                  */
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

#include "../ai_stimulus_history_2d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestAIStimulusHistory2D {

TEST_CASE("[AIStimulusHistory2D] Starts empty with a bounded capacity") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	CHECK(history->get_capacity() == 16);
	CHECK(history->get_event_count() == 0);
	CHECK(history->get_best(AIStimulusHistory2D::SIGHT).is_empty());
	CHECK(history->get_recent().is_empty());
}

TEST_CASE("[AIStimulusHistory2D] Keeps source identity, position, category and age") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(6, 2), 1.0, 6.0, 41));
	Dictionary entry = history->get_best(AIStimulusHistory2D::SIGHT);
	CHECK(entry["sense"] == AIStimulusHistory2D::SIGHT);
	CHECK(entry["source_id"] == 41);
	CHECK(entry["position"] == Vector2(6, 2));
	CHECK(entry["strength"] == real_t(1.0));
	CHECK(entry["age_seconds"] == real_t(0.0));
	CHECK(entry["remaining_seconds"] == real_t(6.0));
	CHECK(history->get_best(AIStimulusHistory2D::SOUND).is_empty());
	history->advance_time(1.5);
	entry = history->get_best(AIStimulusHistory2D::SIGHT);
	CHECK(entry["age_seconds"] == real_t(1.5));
	CHECK(entry["remaining_seconds"] == real_t(4.5));
}

TEST_CASE("[AIStimulusHistory2D] Identified sources update instead of duplicating") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(12, 0), 0.4, 3.0, 7));
	history->advance_time(1.0);
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(5, 0), 0.8, 3.0, 7));
	CHECK(history->get_event_count() == 1);
	Dictionary entry = history->get_best(AIStimulusHistory2D::SOUND);
	CHECK(entry["position"] == Vector2(5, 0));
	CHECK(entry["remaining_seconds"] == real_t(3.0));
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(5, 0), 1.0, 6.0, 7));
	CHECK(history->get_event_count() == 2); // Same ID, different senses.
}

TEST_CASE("[AIStimulusHistory2D] Anonymous events remain distinct") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	CHECK(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(1, 0), 1.0, 3.0));
	CHECK(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(2, 0), 1.0, 3.0));
	CHECK(history->get_event_count() == 2);
	Array recent = history->get_recent();
	Dictionary newest = recent[0];
	CHECK(newest["position"] == Vector2(2, 0));
}

TEST_CASE("[AIStimulusHistory2D] Bounded history evicts oldest and shrinks safely") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	history->set_capacity(3);
	for (int i = 0; i < 5; ++i) {
		CHECK(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(i, 0), 1.0, 5.0, i));
	}
	CHECK(history->get_event_count() == 3);
	Array recent = history->get_recent();
	Dictionary newest = recent[0];
	Dictionary oldest = recent[2];
	CHECK(newest["source_id"] == 4);
	CHECK(oldest["source_id"] == 2);
	history->set_capacity(1);
	CHECK(history->get_event_count() == 1);
	recent = history->get_recent();
	newest = recent[0];
	CHECK(newest["source_id"] == 4);
}

TEST_CASE("[AIStimulusHistory2D] Expiring one source does not erase another") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(3, 0), 1.0, 1.0, 1));
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(9, 0), 0.2, 3.0, 2));
	history->advance_time(1.1);
	CHECK(history->get_event_count() == 1);
	Dictionary best = history->get_best(AIStimulusHistory2D::SOUND);
	CHECK(best["source_id"] == 2);
	CHECK(best["position"] == Vector2(9, 0));
	history->advance_time(2.0);
	CHECK(history->get_event_count() == 0);
}

TEST_CASE("[AIStimulusHistory2D] Ranking decays strength with remaining memory") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(3, 0), 0.95, 2.0, 1));
	history->advance_time(1.0);
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(9, 0), 0.6, 3.0, 2));
	Dictionary best = history->get_best(AIStimulusHistory2D::SOUND);
	CHECK(best["source_id"] == 2); // 0.6 > 0.95 * 0.5.
	CHECK(best["score"] == real_t(0.6));
}

TEST_CASE("[AIStimulusHistory2D] Equal-score tie is independent of insertion order") {
	Ref<AIStimulusHistory2D> a;
	a.instantiate();
	Ref<AIStimulusHistory2D> b;
	b.instantiate();
	CHECK(a->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(8, 0), 1.0, 5.0, 7));
	CHECK(a->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(4, 0), 1.0, 5.0, 3));
	CHECK(b->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(4, 0), 1.0, 5.0, 3));
	CHECK(b->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(8, 0), 1.0, 5.0, 7));
	CHECK(a->get_best(AIStimulusHistory2D::SIGHT)["source_id"] == 3);
	CHECK(b->get_best(AIStimulusHistory2D::SIGHT)["source_id"] == 3);
}

TEST_CASE("[AIStimulusHistory2D] Query snapshots cannot mutate live memory") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::DAMAGE, Vector2(5, 1), 0.4, 6.0, 23));
	Dictionary best = history->get_best(AIStimulusHistory2D::DAMAGE);
	best["position"] = Vector2(100, 100);
	Array recent = history->get_recent();
	Dictionary entry = recent[0];
	entry["source_id"] = 999;
	CHECK(history->get_best(AIStimulusHistory2D::DAMAGE)["position"] == Vector2(5, 1));
	CHECK(history->get_best(AIStimulusHistory2D::DAMAGE)["source_id"] == 23);
	CHECK(history->get_event_count() == 1);
}

TEST_CASE("[AIStimulusHistory2D] Invalid events and limits fail closed") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	ERR_PRINT_OFF;
	CHECK_FALSE(history->record_stimulus(-1, Vector2(), 1.0, 1.0));
	CHECK_FALSE(history->record_stimulus(3, Vector2(), 1.0, 1.0));
	CHECK_FALSE(history->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(Math::NaN, 0), 1.0, 1.0));
	CHECK_FALSE(history->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(), 0.0, 1.0));
	CHECK_FALSE(history->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(), 1.1, 1.0));
	CHECK_FALSE(history->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(), 1.0, 0.0));
	CHECK_FALSE(history->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(), 1.0, 61.0));
	CHECK_FALSE(history->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(), 1.0, 2.0, -2));
	history->set_capacity(0);
	history->set_capacity(65);
	history->advance_time(-1.0);
	CHECK(history->get_recent(-1).is_empty());
	ERR_PRINT_ON;
	CHECK(history->get_capacity() == 16);
	CHECK(history->get_event_count() == 0);
}

TEST_CASE("[AIStimulusHistory2D] Reset and per-listener isolation") {
	Ref<AIStimulusHistory2D> one;
	one.instantiate();
	Ref<AIStimulusHistory2D> other;
	other.instantiate();
	CHECK(one->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(7, 0), 1.0, 2.0, 1));
	CHECK(other->get_event_count() == 0);
	one->reset();
	CHECK(one->get_event_count() == 0);
	CHECK(one->get_capacity() == 16);
}

} // namespace TestAIStimulusHistory2D
