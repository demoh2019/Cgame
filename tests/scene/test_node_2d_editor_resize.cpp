/**************************************************************************/
/*  test_node_2d_editor_resize.cpp                                        */
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
/* CLAIM, DAMAGES OR OTHER LIABILITY, ARISING FROM, OUT OF OR IN CONNECTION */
/* WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.         */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_node_2d_editor_resize)

#ifdef DEBUG_ENABLED

#include "scene/2d/node_2d.h"

namespace TestNode2DEditorResize {

class RectNode2D : public Node2D {
	GDCLASS(RectNode2D, Node2D);

protected:
	static void _bind_methods() {}

public:
	virtual bool _edit_use_rect() const override { return true; }
	virtual Rect2 _edit_get_rect() const override { return Rect2(0, 0, 100, 100); }
};

TEST_CASE("[Node2DEditorResize] Default minimum editor size is zero") {
	RectNode2D *node = memnew(RectNode2D);
	CHECK_EQ(node->_edit_get_minimum_size(), Size2());
	memdelete(node);
}

TEST_CASE("[Node2DEditorResize] Resize to zero width and height keeps positive finite scale") {
	RectNode2D *node = memnew(RectNode2D);
	node->_edit_set_rect(Rect2(Vector2(), Vector2()));
	const Vector2 scale = node->get_scale();
	CHECK(scale.is_finite());
	CHECK_EQ(scale, Vector2(CMP_EPSILON, CMP_EPSILON));
	memdelete(node);
}

TEST_CASE("[Node2DEditorResize] Resize to zero width preserves positive vertical scale") {
	RectNode2D *node = memnew(RectNode2D);
	node->_edit_set_rect(Rect2(Vector2(), Vector2(0, 150)));
	const Vector2 scale = node->get_scale();
	CHECK_EQ(scale.x, CMP_EPSILON);
	CHECK(Math::is_equal_approx(scale.y, (real_t)1.5));
	CHECK(scale.is_finite());
	memdelete(node);
}

TEST_CASE("[Node2DEditorResize] Resize to zero height preserves positive horizontal scale") {
	RectNode2D *node = memnew(RectNode2D);
	node->_edit_set_rect(Rect2(Vector2(), Vector2(250, 0)));
	const Vector2 scale = node->get_scale();
	CHECK(Math::is_equal_approx(scale.x, (real_t)2.5));
	CHECK_EQ(scale.y, CMP_EPSILON);
	CHECK(scale.is_finite());
	memdelete(node);
}

TEST_CASE("[Node2DEditorResize] Ordinary resize still applies ratio on each axis") {
	RectNode2D *node = memnew(RectNode2D);
	node->set_scale(Vector2(2, 3));
	node->_edit_set_rect(Rect2(Vector2(10, 20), Vector2(150, 50)));
	CHECK(node->get_scale().is_equal_approx(Vector2(3, 1.5)));
	CHECK(node->get_scale().is_finite());
	memdelete(node);
}

TEST_CASE("[Node2DEditorResize] Near-zero width clamps instead of creating a denormal scale") {
	RectNode2D *node = memnew(RectNode2D);
	node->_edit_set_rect(Rect2(Vector2(), Vector2(CMP_EPSILON / 10, 100)));
	CHECK_EQ(node->get_scale().x, CMP_EPSILON);
	CHECK(Math::is_equal_approx(node->get_scale().y, 1));
	memdelete(node);
}

TEST_CASE("[Node2DEditorResize] Repeated zero-size operations remain finite") {
	RectNode2D *node = memnew(RectNode2D);
	for (int i = 0; i < 16; i++) {
		node->_edit_set_rect(Rect2(Vector2(i * 4, i * 2), Vector2()));
		CHECK(node->get_scale().is_finite());
		CHECK(node->get_scale().x > 0);
		CHECK(node->get_scale().y > 0);
	}
	memdelete(node);
}

TEST_CASE("[Node2DEditorResize] Zero in either axis with varied initial scales stays nonzero") {
	const Vector2 initial_scales[] = {
		Vector2(1, 1), Vector2(2, 4), Vector2(0.5, 0.75),
		Vector2(-1, 1), Vector2(1, -1),
	};
	for (const Vector2 &initial : initial_scales) {
		for (int axis = 0; axis < 2; axis++) {
			RectNode2D *node = memnew(RectNode2D);
			node->set_scale(initial);
			const Vector2 edit_size = axis == 0 ? Vector2(0, 50) : Vector2(50, 0);
			node->_edit_set_rect(Rect2(Vector2(), edit_size));
			const Vector2 scale = node->get_scale();
			CHECK(scale.is_finite());
			if (axis == 0) {
				CHECK_EQ(scale.x, CMP_EPSILON);
			} else {
				CHECK_EQ(scale.y, CMP_EPSILON);
			}
			memdelete(node);
		}
	}
}

} // namespace TestNode2DEditorResize

#endif // DEBUG_ENABLED
