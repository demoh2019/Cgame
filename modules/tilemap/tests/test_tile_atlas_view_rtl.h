/**************************************************************************/
/*  test_tile_atlas_view_rtl.h                                            */
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

#if defined(TOOLS_ENABLED)

#include "core/math/math_funcs.h"
#include "modules/tilemap/editor/tile_atlas_view.h"
#include "tests/test_macros.h"

namespace TestTileAtlasViewRTL {

TEST_CASE("[TileAtlasView][RTL] LTR pan preserves horizontal and vertical movement") {
	const Vector2 samples[] = {
		Vector2(), Vector2(1, 0), Vector2(0, 1),
		Vector2(20, -15), Vector2(-99, 200), Vector2(0.5, 1.25),
	};
	for (const Vector2 &sample : samples) {
		CHECK_EQ(TileAtlasView::layout_pan_delta(sample, false), sample);
	}
}

TEST_CASE("[TileAtlasView][RTL] RTL pan mirrors only horizontal movement") {
	const Vector2 samples[] = {
		Vector2(), Vector2(1, 0), Vector2(0, 1),
		Vector2(20, -15), Vector2(-99, 200), Vector2(0.5, 1.25),
	};
	for (const Vector2 &sample : samples) {
		const Vector2 result = TileAtlasView::layout_pan_delta(sample, true);
		CHECK_EQ(result.x, -sample.x);
		CHECK_EQ(result.y, sample.y);
	}
}

TEST_CASE("[TileAtlasView][RTL] Flipping pan twice restores original movement") {
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			const Vector2 sample(x * 17, y * 19);
			CHECK_EQ(TileAtlasView::layout_pan_delta(TileAtlasView::layout_pan_delta(sample, true), true), sample);
		}
	}
}

TEST_CASE("[TileAtlasView][RTL] LTR zoom origin uses the viewport center") {
	const Vector2 view_size(400, 300);
	CHECK_EQ(TileAtlasView::layout_zoom_origin(Vector2(200, 150), view_size, false), Vector2());
	CHECK_EQ(TileAtlasView::layout_zoom_origin(Vector2(), view_size, false), Vector2(-200, -150));
	CHECK_EQ(TileAtlasView::layout_zoom_origin(Vector2(400, 300), view_size, false), Vector2(200, 150));
	CHECK_EQ(TileAtlasView::layout_zoom_origin(Vector2(100, 50), view_size, false), Vector2(-100, -100));
}

TEST_CASE("[TileAtlasView][RTL] RTL zoom origin mirrors around the viewport center") {
	const Vector2 view_size(400, 300);
	CHECK_EQ(TileAtlasView::layout_zoom_origin(Vector2(200, 150), view_size, true), Vector2());
	CHECK_EQ(TileAtlasView::layout_zoom_origin(Vector2(), view_size, true), Vector2(200, -150));
	CHECK_EQ(TileAtlasView::layout_zoom_origin(Vector2(400, 300), view_size, true), Vector2(-200, 150));
	CHECK_EQ(TileAtlasView::layout_zoom_origin(Vector2(100, 50), view_size, true), Vector2(100, -100));
}

TEST_CASE("[TileAtlasView][RTL] Symmetric zoom positions are mirrored") {
	const Vector2 view_size(800, 600);
	for (int x = 0; x <= 800; x += 80) {
		for (int y = 0; y <= 600; y += 100) {
			const Vector2 mouse(x, y);
			const Vector2 ltr = TileAtlasView::layout_zoom_origin(mouse, view_size, false);
			const Vector2 rtl = TileAtlasView::layout_zoom_origin(mouse, view_size, true);
			CHECK_EQ(rtl.x, -ltr.x);
			CHECK_EQ(rtl.y, ltr.y);
		}
	}
}

TEST_CASE("[TileAtlasView][RTL] LTR tile control offsets do not change with zoom") {
	const float widths[] = { 0.0f, 16.0f, 32.0f, 128.0f, 256.0f };
	const float zooms[] = { 0.25f, 0.5f, 1.0f, 2.0f, 4.0f };
	for (float width : widths) {
		for (float zoom : zooms) {
			const Vector2 offsets = TileAtlasView::layout_content_offsets(width, zoom, false);
			CHECK_EQ(offsets.x, 0.0f);
			CHECK_EQ(offsets.y, width);
		}
	}
}

TEST_CASE("[TileAtlasView][RTL] RTL tile control offsets retain unscaled width") {
	const float widths[] = { 0.0f, 16.0f, 32.0f, 128.0f, 256.0f };
	const float zooms[] = { 0.25f, 0.5f, 1.0f, 2.0f, 4.0f };
	for (float width : widths) {
		for (float zoom : zooms) {
			const Vector2 offsets = TileAtlasView::layout_content_offsets(width, zoom, true);
			INFO("width=", width, " zoom=", zoom);
			CHECK_EQ(offsets.x, width * (zoom - 1.0f));
			CHECK_EQ(offsets.y, width * zoom);
			CHECK(Math::is_equal_approx(offsets.y - offsets.x, width));
		}
	}
}

TEST_CASE("[TileAtlasView][RTL] Zoom 1 gives identical offsets in both directions") {
	for (int width = 0; width <= 512; width += 16) {
		const Vector2 left_to_right = TileAtlasView::layout_content_offsets(width, 1.0f, false);
		const Vector2 right_to_left = TileAtlasView::layout_content_offsets(width, 1.0f, true);
		CHECK_EQ(left_to_right, right_to_left);
		CHECK_EQ(left_to_right, Vector2(0, width));
	}
}

TEST_CASE("[TileAtlasView][RTL] Base and alternative tile regions use their own widths") {
	for (float zoom : { 0.5f, 1.0f, 2.0f, 3.0f }) {
		const Vector2 base = TileAtlasView::layout_content_offsets(128.0f, zoom, true);
		const Vector2 alternative = TileAtlasView::layout_content_offsets(64.0f, zoom, true);
		CHECK(Math::is_equal_approx(base.y - base.x, 128.0f));
		CHECK(Math::is_equal_approx(alternative.y - alternative.x, 64.0f));
		CHECK_EQ(base.y, alternative.y * 2.0f);
	}
}

TEST_CASE("[TileAtlasView][RTL] Zero pan and centered zoom remain zero") {
	const Vector2 view_sizes[] = { Vector2(), Vector2(1, 1), Vector2(640, 480), Vector2(1920, 1080) };
	for (const Vector2 &view_size : view_sizes) {
		for (bool rtl : { false, true }) {
			CHECK_EQ(TileAtlasView::layout_pan_delta(Vector2(), rtl), Vector2());
			CHECK_EQ(TileAtlasView::layout_zoom_origin(view_size / 2.0f, view_size, rtl), Vector2());
		}
	}
}

} // namespace TestTileAtlasViewRTL

#endif // TOOLS_ENABLED
