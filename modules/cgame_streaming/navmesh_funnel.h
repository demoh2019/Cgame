/**************************************************************************/
/*  navmesh_funnel.h                                                      */
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
#include "core/templates/vector.h"

// "Simple stupid funnel" string pulling shared by NavMeshStitching and NavMeshCarving.
// Portal i is (lefts[i], rights[i]); index 0 is (start, start) and the last is (goal, goal).
namespace NavMeshFunnel {

_FORCE_INLINE_ float tri2(const Vector2 &p_a, const Vector2 &p_b, const Vector2 &p_c) {
	float ax = p_b.x - p_a.x;
	float ay = p_b.y - p_a.y;
	float bx = p_c.x - p_a.x;
	float by = p_c.y - p_a.y;
	return bx * ay - ax * by;
}

inline Vector<Vector2> funnel(const Vector<Vector2> &p_left, const Vector<Vector2> &p_right, int p_guard_limit) {
	Vector<Vector2> out;
	int n = p_left.size();
	if (n == 0) {
		return out;
	}
	Vector2 apex = p_left[0];
	Vector2 lft = p_left[0];
	Vector2 rgt = p_right[0];
	int apex_i = 0;
	int left_i = 0;
	int right_i = 0;
	out.push_back(apex);
	int i = 1;
	int guard = 0;
	while (i < n && guard < p_guard_limit) {
		guard++;
		Vector2 nl = p_left[i];
		Vector2 nr = p_right[i];
		if (tri2(apex, rgt, nr) <= 0.0f) {
			if (apex.is_equal_approx(rgt) || tri2(apex, lft, nr) > 0.0f) {
				rgt = nr;
				right_i = i;
			} else {
				out.push_back(lft);
				apex = lft;
				apex_i = left_i;
				lft = apex;
				rgt = apex;
				left_i = apex_i;
				right_i = apex_i;
				i = apex_i + 1;
				continue;
			}
		}
		if (tri2(apex, lft, nl) >= 0.0f) {
			if (apex.is_equal_approx(lft) || tri2(apex, rgt, nl) < 0.0f) {
				lft = nl;
				left_i = i;
			} else {
				out.push_back(rgt);
				apex = rgt;
				apex_i = right_i;
				lft = apex;
				rgt = apex;
				left_i = apex_i;
				right_i = apex_i;
				i = apex_i + 1;
				continue;
			}
		}
		i++;
	}
	Vector2 goal = p_left[n - 1];
	if (out.is_empty() || !out[out.size() - 1].is_equal_approx(goal)) {
		out.push_back(goal);
	}
	return out;
}

} //namespace NavMeshFunnel
