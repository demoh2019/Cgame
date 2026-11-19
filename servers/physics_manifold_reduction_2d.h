/**************************************************************************/
/*  physics_manifold_reduction_2d.h                                       */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/vector2.h"

// Reduce three candidate contact points to two while retaining the deepest
// contact and maximizing the tangent-space span of a same-normal manifold.
// The input order is [old contact 0, old contact 1, new candidate].
// Return 0 or 1 to replace that old contact, or -1 to discard the candidate.
// This is a constant-time, allocation-free alternative to depth-only pruning.
struct GodotPhysicsManifoldReduction2D {
	static constexpr int MAX_CONTACTS = 2;

	static int choose_replacement(const Vector2 p_points[MAX_CONTACTS + 1], const real_t p_depths[MAX_CONTACTS + 1], const Vector2 p_normals[MAX_CONTACTS + 1]) {
		int deepest = 0;
		for (int i = 1; i <= MAX_CONTACTS; i++) {
			if (p_depths[i] > p_depths[deepest]) {
				deepest = i;
			}
		}

		// Contacts on different faces do not form a common line segment.
		// Keep the legacy depth-first choice for mixed-normal candidates.
		for (int i = 0; i <= MAX_CONTACTS; i++) {
			if (p_normals[i].dot(p_normals[deepest]) < real_t(0.98)) {
				int replacement = -1;
				real_t minimum_depth = p_depths[MAX_CONTACTS];
				for (int j = 0; j < MAX_CONTACTS; j++) {
					if (p_depths[j] < minimum_depth) {
						minimum_depth = p_depths[j];
						replacement = j;
					}
				}
				return replacement;
			}
		}

		// The squared cross product measures span along the manifold tangent.
		// Use the deepest contact's normal so the score does not change sign
		// when the tangent direction is reversed.
		const Vector2 &normal = p_normals[deepest];
		auto span_score = [&](int p_omit) -> real_t {
			const int first = (p_omit == 0) ? 1 : 0;
			const int second = (p_omit == 2) ? 1 : 2;
			const real_t tangent_span = normal.cross(p_points[second] - p_points[first]);
			return tangent_span * tangent_span;
		};

		// Prefer the previous manifold if the new point is not deepest.
		// The 1% hysteresis avoids repeated swaps for insignificant changes.
		int best_omit = (deepest == MAX_CONTACTS) ? 0 : MAX_CONTACTS;
		real_t best_score = span_score(best_omit);
		for (int omit = 0; omit < MAX_CONTACTS; omit++) {
			if (omit == deepest || omit == best_omit) {
				continue;
			}
			const real_t score = span_score(omit);
			if (score > best_score * real_t(1.01)) {
				best_score = score;
				best_omit = omit;
			}
		}
		return best_omit == MAX_CONTACTS ? -1 : best_omit;
	}
};
