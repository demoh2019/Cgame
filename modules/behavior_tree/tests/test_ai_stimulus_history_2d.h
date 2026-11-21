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
	CHECK(entry["sense"] ==Variant( Variant(int(AIStimulusHistory2D::SIGHT))));
	CHECK(entry["source_id"] == Variant(41));
	CHECK(entry["position"] == Variant(Vector2(6, 2)));
	CHECK(entry["strength"] == Variant(real_t(1.0)));
	CHECK(entry["age_seconds"] == Variant(real_t(0.0)));
	CHECK(entry["remaining_seconds"] == Variant(real_t(6.0)));
	CHECK(history->get_best(AIStimulusHistory2D::SOUND).is_empty());
	history->advance_time(1.5);
	entry = history->get_best(AIStimulusHistory2D::SIGHT);
	CHECK(entry["age_seconds"] == Variant(real_t(1.5)));
	CHECK(entry["remaining_seconds"] == Variant(real_t(4.5)));
}

TEST_CASE("[AIStimulusHistory2D] Identified sources update instead of duplicating") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(12, 0), 0.4, 3.0, 7));
	history->advance_time(1.0);
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(5, 0), 0.8, 3.0, 7));
	CHECK(history->get_event_count() == 1);
	Dictionary entry = history->get_best(AIStimulusHistory2D::SOUND);
	CHECK(entry["position"] == Variant(Vector2(5, 0)));
	CHECK(entry["remaining_seconds"] == Variant(real_t(3.0)));
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
	CHECK(newest["position"] == Variant(Vector2(2, 0)));
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
	CHECK(newest["source_id"] == Variant(4));
	CHECK(oldest["source_id"] == Variant(2));
	history->set_capacity(1);
	CHECK(history->get_event_count() == 1);
	recent = history->get_recent();
	newest = recent[0];
	CHECK(newest["source_id"] == Variant(4));
}

TEST_CASE("[AIStimulusHistory2D] Expiring one source does not erase another") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(3, 0), 1.0, 1.0, 1));
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(9, 0), 0.2, 3.0, 2));
	history->advance_time(1.1);
	CHECK(history->get_event_count() == 1);
	Dictionary best = history->get_best(AIStimulusHistory2D::SOUND);
	CHECK(best["source_id"] == Variant(2));
	CHECK(best["position"] == Variant(Vector2(9, 0)));
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
	CHECK(best["source_id"] == Variant(2)); // 0.6 > 0.95 * 0.5.
	CHECK(best["score"] == Variant(real_t(0.6)));
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
	CHECK(a->get_best(AIStimulusHistory2D::SIGHT)["source_id"] == Variant(3));
	CHECK(b->get_best(AIStimulusHistory2D::SIGHT)["source_id"] == Variant(3));
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
	CHECK(history->get_best(AIStimulusHistory2D::DAMAGE)["position"] == Variant(Vector2(5, 1)));
	CHECK(history->get_best(AIStimulusHistory2D::DAMAGE)["source_id"] == Variant(23));
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

TEST_CASE("[AIStimulusHistory2D] Radius query filters before ranking and includes the boundary") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(30, 0), 1.0, 5.0, 10));
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(3, 4), 0.4, 5.0, 11));
	CHECK(history->get_best(AIStimulusHistory2D::SOUND)["source_id"] == Variant(10));
	Dictionary nearby = history->get_best_in_radius(AIStimulusHistory2D::SOUND, Vector2(), 5.0);
	CHECK(nearby["source_id"] == Variant(11));
	CHECK(nearby["position"] == Variant(Vector2(3, 4)));
	CHECK(history->get_best_in_radius(AIStimulusHistory2D::SOUND, Vector2(), 4.99).is_empty());
	CHECK(history->get_best_in_radius(AIStimulusHistory2D::SIGHT, Vector2(), 5.0).is_empty());
	CHECK(history->get_event_count() == 2);
	nearby["source_id"] = 888;
	CHECK(history->get_best_in_radius(AIStimulusHistory2D::SOUND, Vector2(), 5.0)["source_id"] == Variant(11));
	history->advance_time(5.0);
	CHECK(history->get_best_in_radius(AIStimulusHistory2D::SOUND, Vector2(), 5.0).is_empty());
}

TEST_CASE("[AIStimulusHistory2D] Radius query validates inputs and keeps deterministic ties") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(2, 0), 0.7, 5.0, 8));
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(1, 0), 0.7, 5.0, 4));
	CHECK(history->get_best_in_radius(AIStimulusHistory2D::SOUND, Vector2(), 2.0)["source_id"] == Variant(4));
	CHECK(history->get_best_in_radius(AIStimulusHistory2D::SOUND, Vector2(1, 0), 0.0)["source_id"] == Variant(4));
	ERR_PRINT_OFF;
	CHECK(history->get_best_in_radius(AIStimulusHistory2D::SOUND, Vector2(), -1.0).is_empty());
	CHECK(history->get_best_in_radius(AIStimulusHistory2D::SOUND, Vector2(), Math::INF).is_empty());
	CHECK(history->get_best_in_radius(AIStimulusHistory2D::SOUND, Vector2(Math::NaN, 0), 10.0).is_empty());
	CHECK(history->get_best_in_radius(-1, Vector2(), 5.0).is_empty());
	ERR_PRINT_ON;
	CHECK(history->get_event_count() == 2);
}

TEST_CASE("[AIStimulusHistory2D] Repeated newest-source refresh preserves unrelated ages") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(1, 0), 0.3, 4.0, 1));
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(2, 0), 0.7, 4.0, 2));
	history->advance_time(1.0);
	for (int i = 0; i < 20; i++) {
		REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(2 + i, 0), 0.7, 4.0, 2));
	}
	CHECK(history->get_event_count() == 2);
	const Array recent = history->get_recent(2);
	const Dictionary newest = recent[0];
	const Dictionary older = recent[1];
	CHECK(newest["source_id"] == Variant(2));
	CHECK(newest["position"] == Variant(Vector2(21, 0)));
	CHECK(newest["remaining_seconds"] == Variant(real_t(4.0)));
	CHECK(older["source_id"] == Variant(1));
	CHECK(older["remaining_seconds"] == Variant(real_t(3.0)));
}

TEST_CASE("[AIStimulusHistory2D] Selective forget preserves other identities and ages") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(1, 0), 1.0, 5.0, 41));
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(2, 0), 0.9, 5.0, 41));
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(3, 0), 0.5, 5.0, 42));
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(4, 0), 0.4, 5.0)); // Anonymous.
	history->advance_time(1.25);
	CHECK(history->forget_source(41, AIStimulusHistory2D::SOUND) == 1);
	CHECK(history->get_event_count() == 3);
	CHECK(history->get_best(AIStimulusHistory2D::SIGHT)["source_id"] == Variant(41));
	const Array kept = history->get_recent(3);
	const Dictionary anonymous = kept[0];
	const Dictionary survivor = kept[1];
	const Dictionary sight = kept[2];
	CHECK(anonymous["source_id"] == Variant(-1));
	CHECK(survivor["source_id"] == Variant(42));
	CHECK(sight["source_id"] == Variant(41));
	CHECK(survivor["remaining_seconds"] == Variant(real_t(3.75)));
	CHECK(history->forget_source(41) == 1);
	CHECK(history->forget_source(41) == 0);
	CHECK(history->get_event_count() == 2);
	CHECK(history->get_best(AIStimulusHistory2D::SIGHT).is_empty());
	CHECK(history->get_best(AIStimulusHistory2D::SOUND)["source_id"] == Variant(42));
}

TEST_CASE("[AIStimulusHistory2D] Invalid source forget is atomic and does not remove anonymous events") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::DAMAGE, Vector2(7, 1), 0.7, 6.0, 7));
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(5, 1), 0.9, 6.0));
	CHECK(history->forget_source(-1) == 0);
	CHECK(history->forget_source(-2, AIStimulusHistory2D::SOUND) == 0);
	CHECK(history->forget_source(7, -2) == 0);
	CHECK(history->forget_source(7, 3) == 0);
	CHECK(history->forget_source(999) == 0);
	CHECK(history->get_event_count() == 2);
	CHECK(history->forget_source(7, AIStimulusHistory2D::DAMAGE) == 1);
	CHECK(history->get_best(AIStimulusHistory2D::DAMAGE).is_empty());
	CHECK(history->get_event_count() == 1);
	CHECK(history->get_recent(1).size() == 1);
}

TEST_CASE("[AIStimulusHistory2D] Actor-specific perception ignores stronger unrelated sources") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(12, 0), 1.0, 5.0, 77));
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(3, 4), 0.5, 5.0, 41));
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SIGHT, Vector2(6, 0), 0.9, 6.0, 41));
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(1, 0), 0.8, 5.0)); // Anonymous.
	CHECK(history->get_best(AIStimulusHistory2D::SOUND)["source_id"] == Variant(77));
	const Dictionary source = history->get_best_for_source(AIStimulusHistory2D::SOUND, 41);
	CHECK(source["source_id"] == Variant(41));
	CHECK(source["position"] == Variant(Vector2(3, 4)));
	CHECK(history->get_best_for_source(AIStimulusHistory2D::SIGHT, 41)["position"] == Variant(Vector2(6, 0)));
	CHECK(history->get_best_for_source(AIStimulusHistory2D::SOUND, 77)["position"] == Variant(Vector2(12, 0)));
	CHECK(history->get_best_for_source_in_radius(AIStimulusHistory2D::SOUND, 41, Vector2(), 5.0)["position"] == Variant(Vector2(3, 4)));
	CHECK(history->get_best_for_source_in_radius(AIStimulusHistory2D::SOUND, 41, Vector2(), 4.99).is_empty());
	CHECK(history->get_best_for_source_in_radius(AIStimulusHistory2D::SIGHT, 41, Vector2(), 5.0).is_empty());
	CHECK(history->get_best_for_source(AIStimulusHistory2D::SOUND, 42).is_empty());
	CHECK(history->get_event_count() == 4);
	Dictionary snapshot = history->get_best_for_source(AIStimulusHistory2D::SOUND, 41);
	snapshot["source_id"] = 900;
	CHECK(history->get_best_for_source(AIStimulusHistory2D::SOUND, 41)["source_id"] == Variant(41));
	history->advance_time(5.0);
	CHECK(history->get_best_for_source(AIStimulusHistory2D::SOUND, 41).is_empty());
	CHECK(history->get_best_for_source(AIStimulusHistory2D::SIGHT, 41)["source_id"] == Variant(41));
	CHECK(history->forget_source(41) == 1);
	CHECK(history->get_best_for_source(AIStimulusHistory2D::SIGHT, 41).is_empty());
}

TEST_CASE("[AIStimulusHistory2D] Actor query rejects anonymous, malformed and huge spatial requests") {
	Ref<AIStimulusHistory2D> history;
	history.instantiate();
	REQUIRE(history->record_stimulus(AIStimulusHistory2D::SOUND, Vector2(0, 0), 0.7, 5.0, 7));
	CHECK(history->get_best_for_source(AIStimulusHistory2D::SOUND, -1).is_empty());
	CHECK(history->get_best_for_source(AIStimulusHistory2D::SOUND, -2).is_empty());
	CHECK(history->get_best_for_source(-1, 7).is_empty());
	CHECK(history->get_best_for_source(3, 7).is_empty());
	CHECK(history->get_best_for_source_in_radius(AIStimulusHistory2D::SOUND, -1, Vector2(), 0.0).is_empty());
	CHECK(history->get_best_for_source_in_radius(AIStimulusHistory2D::SOUND, 7, Vector2(Math::NaN, 0), 1.0).is_empty());
	CHECK(history->get_best_for_source_in_radius(AIStimulusHistory2D::SOUND, 7, Vector2(), Math::INF).is_empty());
	CHECK(history->get_best_for_source_in_radius(AIStimulusHistory2D::SOUND, 7, Vector2(), -0.1).is_empty());
	CHECK(history->get_best_for_source_in_radius(AIStimulusHistory2D::SOUND, 7, Vector2(), 1000001.0).is_empty());
	CHECK(history->get_best_for_source_in_radius(AIStimulusHistory2D::SOUND, 7, Vector2(), 0.0)["source_id"] == Variant(7));
	CHECK(history->get_event_count() == 1);
}

} // namespace TestAIStimulusHistory2D
