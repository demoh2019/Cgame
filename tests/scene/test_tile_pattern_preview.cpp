/**************************************************************************/
/*  test_tile_pattern_preview.cpp                                         */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_tile_pattern_preview)

#include "modules/modules_enabled.gen.h"

#if defined(TOOLS_ENABLED) && defined(MODULE_TILEMAP_ENABLED)

#include "modules/tilemap/editor/tiles_editor_plugin.h"
#include "modules/tilemap/tile_map_layer.h"
#include "modules/tilemap/tile_set.h"

namespace TestTilePatternPreview {

TEST_CASE("[SceneTree][TilePatternPreview] Pattern with invalid cells creates an empty tile map") {
	Ref<TileSet> tile_set;
	tile_set.instantiate();
	Ref<TileMapPattern> pattern;
	pattern.instantiate();

	pattern->set_cell(Vector2i(0, 0), TileSet::INVALID_SOURCE,
			TileSetSource::INVALID_ATLAS_COORDS, TileSetSource::INVALID_TILE_ALTERNATIVE);
	CHECK_FALSE(pattern->is_empty());
	TileMapLayer *layer = memnew(TileMapLayer);
	layer->set_tile_set(tile_set);
	layer->set_pattern(Vector2i(), pattern);

	// This was the crash scenario: a nonempty source pattern, but no cells
	// in the materialized tile map; preview must not dereference begin().
	CHECK(layer->get_tile_map_layer_data().is_empty());
	memdelete(layer);
}

TEST_CASE("[TilePatternPreview] Empty preview uses finite neutral scale") {
	const Vector2 scale = TilesEditorUtils::calculate_preview_scale(Vector2(64, 64), Rect2());
	CHECK_EQ(scale, Vector2(1, 1));
	CHECK(scale.is_finite());
}

TEST_CASE("[TilePatternPreview] Degenerate content bounds do not divide by zero") {
	const Rect2 zero_bounds(Vector2(10, 20), Vector2(0, 0));
	for (float size : { 16.0f, 64.0f, 256.0f }) {
		const Vector2 scale = TilesEditorUtils::calculate_preview_scale(Vector2(size, size), zero_bounds);
		CHECK_EQ(scale, Vector2(1, 1));
		CHECK(scale.is_finite());
	}
}

TEST_CASE("[TilePatternPreview] Wide content fits the thumbnail") {
	const Vector2 scale = TilesEditorUtils::calculate_preview_scale(Vector2(100, 100),
			Rect2(Vector2(15, 25), Vector2(200, 50)));
	CHECK(scale.is_equal_approx(Vector2(0.5f, 0.5f)));
	CHECK(scale.is_finite());
}

TEST_CASE("[TilePatternPreview] Tall content fits the thumbnail") {
	const Vector2 scale = TilesEditorUtils::calculate_preview_scale(Vector2(120, 120),
			Rect2(Vector2(-25, -20), Vector2(60, 300)));
	CHECK(scale.is_equal_approx(Vector2(0.4f, 0.4f)));
	CHECK(scale.is_finite());
}

TEST_CASE("[TilePatternPreview] Non-square preview maintains per-axis size") {
	const Vector2 scale = TilesEditorUtils::calculate_preview_scale(Vector2(256, 128),
			Rect2(Vector2(), Vector2(64, 32)));
	CHECK(scale.is_equal_approx(Vector2(4, 2)));
	CHECK(scale.is_finite());
}

TEST_CASE("[TilePatternPreview] Sub-epsilon bounds use a neutral scale") {
	const Vector2 scale = TilesEditorUtils::calculate_preview_scale(Vector2(64, 64),
			Rect2(Vector2(), Vector2(CMP_EPSILON * (real_t)0.25, CMP_EPSILON * (real_t)0.5)));
	CHECK_EQ(scale, Vector2(1, 1));
	CHECK(scale.is_finite());
}

TEST_CASE("[TilePatternPreview] Scale stays finite for assorted valid extents") {
	const float extents[] = { 1.0f, 2.0f, 4.0f, 8.0f, 16.0f, 64.0f, 128.0f, 1024.0f };
	for (float extent : extents) {
		for (float thumbnail : { 32.0f, 64.0f, 256.0f }) {
			const Vector2 scale = TilesEditorUtils::calculate_preview_scale(
					Vector2(thumbnail, thumbnail), Rect2(Vector2(), Vector2(extent, extent)));
			INFO("Content extent: ", extent, ", thumbnail: ", thumbnail);
			CHECK(scale.is_finite());
			CHECK(scale.x > 0);
			CHECK(scale.y > 0);
			CHECK(Math::is_equal_approx(scale.x, thumbnail / extent));
			CHECK(Math::is_equal_approx(scale.y, thumbnail / extent));
		}
	}
}

} // namespace TestTilePatternPreview

#endif // TOOLS_ENABLED && MODULE_TILEMAP_ENABLED
