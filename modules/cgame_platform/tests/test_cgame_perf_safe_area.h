/**************************************************************************/
/*  test_cgame_perf_safe_area.h                                           */
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

#include "../cgame_perf_stats.h"
#include "../cgame_safe_area.h"

#include "scene/gui/margin_container.h"
#include "tests/test_macros.h"

namespace TestCgamePerfSafeArea {

static Ref<CgamePerfStats> make_stats(int p_capacity) {
	Ref<CgamePerfStats> s;
	s.instantiate();
	s->set_capacity(p_capacity);
	return s;
}

static int inset_sum(const Dictionary &p_insets) {
	return (int)p_insets["left"] + (int)p_insets["top"] + (int)p_insets["right"] + (int)p_insets["bottom"];
}

TEST_CASE("[CgamePerfStats] Ring buffer keeps the newest samples") {
	Ref<CgamePerfStats> st = make_stats(5);
	for (int i = 0; i < 8; i++) {
		st->push("a", (double)i);
	}
	const PackedFloat32Array s = st->series("a");
	CHECK(s.size() == 5); // The ring never exceeds its capacity.
	CHECK(s[0] == 3.0f); // The oldest kept sample.
	CHECK(s[4] == 7.0f); // The newest sample is last.
	CHECK(st->series("missing").size() == 0);
	st->push("a", Math::NaN);
	st->push("a", Math::INF);
	CHECK(st->count("a") == 5); // Non-finite values are ignored.
	CHECK(st->series("a", 2).size() == 2);
	CHECK(st->total_pushed("a") == 8);
	CHECK(st->has_series("a"));
	CHECK_FALSE(st->has_series("b"));
	CHECK(st->names().size() == 1);
	CHECK(st->last("a") == doctest::Approx(7.0));
	CHECK(st->last("missing") == doctest::Approx(0.0));
	st->clear();
	CHECK(st->count("a") == 0);
}

TEST_CASE("[CgamePerfStats] Percentiles") {
	Ref<CgamePerfStats> p = make_stats(200);
	for (int i = 0; i < 101; i++) {
		p->push("x", (double)i);
	}
	CHECK(p->percentile("x", 50.0) == doctest::Approx(50.0));
	CHECK(p->percentile("x", 95.0) == doctest::Approx(95.0));
	CHECK(p->percentile("x", 99.0) == doctest::Approx(99.0));
	CHECK(p->percentile("x", 0.0) == doctest::Approx(0.0));
	CHECK(p->percentile("x", 100.0) == doctest::Approx(100.0));
	CHECK(p->percentile("x", 50.0, 11) == doctest::Approx(95.0)); // Median of the last 11 samples.
	CHECK(p->percentile("none", 50.0) == doctest::Approx(0.0));
	CHECK(p->average("x") == doctest::Approx(50.0));
	CHECK(p->max_value("x") == doctest::Approx(100.0));

	const Dictionary sum = p->summary("x", 0);
	CHECK((int)sum["samples"] == 101);
	CHECK((double)sum["p95"] == doctest::Approx(95.0));
	CHECK((double)sum["last"] == doctest::Approx(100.0));
}

TEST_CASE("[CgamePerfStats] Percentiles interpolate between samples") {
	Ref<CgamePerfStats> p = make_stats(10);
	p->push("y", 10.0);
	p->push("y", 20.0);
	CHECK(p->percentile("y", 50.0) == doctest::Approx(15.0));
	CHECK(p->percentile("y", 25.0) == doctest::Approx(12.5));
	CHECK(p->percentile("y", 150.0) == doctest::Approx(20.0)); // Clamped to the 0..100 range.
}

TEST_CASE("[CgameSafeArea] Insets from the display safe rectangle") {
	const Dictionary full = CgameSafeArea::insets(Vector2i(1280, 800), Rect2i(0, 0, 1280, 800));
	CHECK(inset_sum(full) == 0);

	const Dictionary notch = CgameSafeArea::insets(Vector2i(2400, 1080), Rect2i(90, 0, 2220, 1060));
	CHECK((int)notch["left"] == 90);
	CHECK((int)notch["right"] == 90);
	CHECK((int)notch["top"] == 0);
	CHECK((int)notch["bottom"] == 20); // Home indicator.

	const Dictionary outside = CgameSafeArea::insets(Vector2i(800, 600), Rect2i(-50, -50, 2000, 2000));
	CHECK((int)outside["left"] == 0); // A safe area larger than the window gives no inset.
	CHECK(inset_sum(outside) == 0);
	CHECK((int)CgameSafeArea::insets(Vector2i(), Rect2i())["top"] == 0); // Degenerate input is safe.
}

TEST_CASE("[CgameSafeArea] Display rectangle is converted to window and canvas space") {
	// The window sits at (100, 50); the screen-space safe rectangle starts at (190, 50).
	const Dictionary raw = CgameSafeArea::from_display(Vector2i(100, 50), Vector2i(2400, 1080), Rect2i(190, 50, 2220, 1060), Vector2(2400, 1080));
	CHECK((int)raw["left"] == 90);
	CHECK((int)raw["bottom"] == 20);
	// A 2:1 canvas halves the window pixels.
	const Dictionary scaled = CgameSafeArea::from_display(Vector2i(100, 50), Vector2i(2400, 1080), Rect2i(190, 50, 2220, 1060), Vector2(1200, 540));
	CHECK((int)scaled["left"] == 45);
	CHECK((int)scaled["right"] == 45);
	CHECK((int)scaled["bottom"] == 10);
}

TEST_CASE("[SceneTree][CgameSafeArea] Margins grow by the inset") {
	const Dictionary notch = CgameSafeArea::insets(Vector2i(2400, 1080), Rect2i(90, 0, 2220, 1060));
	MarginContainer *margin = memnew(MarginContainer);
	CgameSafeArea::apply(margin, notch);
	CHECK(margin->get_theme_constant("margin_left") == 104); // Base margin plus the inset.
	CHECK(margin->get_theme_constant("margin_top") == CgameSafeArea::BASE_MARGIN);
	CgameSafeArea::apply(margin, notch, 0);
	CHECK(margin->get_theme_constant("margin_right") == 90);
	CgameSafeArea::apply(nullptr, notch); // Must not crash.
	memdelete(margin);
}

} // namespace TestCgamePerfSafeArea
