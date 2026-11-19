/**************************************************************************/
/*  physics_manifold_reduction_3d.h                                       */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/vector3.h"

// Optional Box2D/Jolt-style reduction of five candidate contact points to
// four. Preserve the deepest penetration; among similar-normal manifolds,
// maximize the projected contact patch's coverage (sum of squared triangle
// areas) rather than clustering all points around the deepest corner.
//
// Return 0..3 for the old point to replace, or -1 to ignore the new point.
// Fixed-size stack data and O(1) work; this helper allocates no memory.
struct GodotPhysicsManifoldReduction3D {
	static constexpr int MAX_CONTACTS = 4;

	static real_t _projected_area_score(const Vector3 p_points[MAX_CONTACTS + 1], int p_omit, const Vector3 &p_normal) {
		int retained[MAX_CONTACTS];
		int n = 0;
		for (int i = 0; i <= MAX_CONTACTS; i++) {
			if (i != p_omit) {
				retained[n++] = i;
			}
		}

		real_t area_score = 0.0;
		for (int i = 0; i < MAX_CONTACTS - 2; i++) {
			for (int j = i + 1; j < MAX_CONTACTS - 1; j++) {
				for (int k = j + 1; k < MAX_CONTACTS; k++) {
					const Vector3 edge_a = p_points[retained[j]] - p_points[retained[i]];
					const Vector3 edge_b = p_points[retained[k]] - p_points[retained[i]];
					const real_t twice_area = edge_a.cross(edge_b).dot(p_normal);
					area_score += twice_area * twice_area;
				}
			}
		}
		return area_score;
	}

	static int choose_replacement(const Vector3 p_points[MAX_CONTACTS + 1], const real_t p_depths[MAX_CONTACTS + 1], const Vector3 p_normals[MAX_CONTACTS + 1]) {
		int deepest = 0;
		for (int i = 1; i <= MAX_CONTACTS; i++) {
			if (p_depths[i] > p_depths[deepest]) {
				deepest = i;
			}
		}

		// Contacts on different faces cannot be evaluated as one planar
		// patch. Retain the legacy depth-first choice in that case.
		for (int i = 0; i <= MAX_CONTACTS; i++) {
			if (p_normals[i].dot(p_normals[deepest]) < real_t(0.98)) {
				int replacement = -1;
				real_t min_depth = p_depths[MAX_CONTACTS];
				for (int j = 0; j < MAX_CONTACTS; j++) {
					if (p_depths[j] < min_depth) {
						replacement = j;
						min_depth = p_depths[j];
					}
				}
				return replacement;
			}
		}

		// Keep the deepest point even if the candidate area is smaller.
		// When the new point isn't deepest, the existing four contacts
		// form a stable baseline. A 1% hysteresis prevents tiny changes
		// in the surface patch from constantly reshuffling old impulses.
		int best_omit = deepest == MAX_CONTACTS ? 0 : MAX_CONTACTS;
		real_t best_score = _projected_area_score(p_points, best_omit, p_normals[deepest]);
		for (int omitted = 0; omitted < MAX_CONTACTS; omitted++) {
			if (omitted == deepest || omitted == best_omit) {
				continue;
			}
			const real_t score = _projected_area_score(p_points, omitted, p_normals[deepest]);
			if (score > best_score * real_t(1.01)) {
				best_score = score;
				best_omit = omitted;
			}
		}
		return best_omit == MAX_CONTACTS ? -1 : best_omit;
	}
};
