/**************************************************************************/
/*  test_line_builder.cpp                                                 */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,       */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY    */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_line_builder)

#include "scene/2d/line_builder.h"

namespace TestLineBuilder {

TEST_CASE("[LineBuilder] Two-point mesh has minimal geometry") {
	LineBuilder builder;
	builder.points.push_back(Vector2(0, 0));
	builder.points.push_back(Vector2(100, 0));
	builder.width = 2;
	builder.build();

	CHECK(builder.vertices.size() == 4);
	CHECK(builder.indices.size() == 6);
	CHECK(builder.colors.size() == 1);
	CHECK(builder.uvs.is_empty());
}

TEST_CASE("[LineBuilder] Long sharp-joined polyline maintains index bounds") {
	LineBuilder builder;
	builder.width = 1;
	for (int i = 0; i < 512; ++i) {
		builder.points.push_back(Vector2(i * 10, (i & 1) ? 1 : 0));
	}
	builder.build();

	REQUIRE_FALSE(builder.indices.is_empty());
	CHECK(builder.vertices.size() >= 512 * 2);
	CHECK(builder.indices.size() >= 511 * 6);
	CHECK(builder.colors.size() == 1);
	for (int index : builder.indices) {
		CHECK(index >= 0);
		CHECK(index < builder.vertices.size());
	}
}

TEST_CASE("[LineBuilder] Textured round caps and joints preserve attribute alignment") {
	LineBuilder builder;
	builder.width = 4;
	builder.texture_mode = Line2D::LINE_TEXTURE_STRETCH;
	builder.begin_cap_mode = Line2D::LINE_CAP_ROUND;
	builder.end_cap_mode = Line2D::LINE_CAP_ROUND;
	builder.joint_mode = Line2D::LINE_JOINT_ROUND;
	builder.round_precision = 8;
	builder.points.push_back(Vector2(0, 0));
	builder.points.push_back(Vector2(40, 0));
	builder.points.push_back(Vector2(40, 40));
	builder.build();

	REQUIRE_FALSE(builder.indices.is_empty());
	CHECK(builder.vertices.size() > 6);
	CHECK(builder.uvs.size() == builder.vertices.size());
	CHECK(builder.indices.size() % 3 == 0);
	for (int index : builder.indices) {
		CHECK(index >= 0);
		CHECK(index < builder.vertices.size());
	}
}

TEST_CASE("[LineBuilder] Closed polyline preserves valid triangle indices") {
	LineBuilder builder;
	builder.closed = true;
	builder.points.push_back(Vector2(0, 0));
	builder.points.push_back(Vector2(40, 0));
	builder.points.push_back(Vector2(40, 40));
	builder.points.push_back(Vector2(0, 40));
	builder.build();

	REQUIRE_FALSE(builder.indices.is_empty());
	CHECK(builder.indices.size() % 3 == 0);
	for (int index : builder.indices) {
		CHECK(index >= 0);
		CHECK(index < builder.vertices.size());
	}
}

} // namespace TestLineBuilder
