/**************************************************************************/
/*  physics_softbody_shape_matching.h                                     */
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

#include "core/math/quaternion.h"
#include "core/math/vector3.h"

// Horn's least-squares best-fit proper rotation of a point cloud.
// Each added vector is centered around its cloud's centroid.
// A 4x4 symmetric Jacobi eigensolve avoids the reflection/negative-eigenvalue
// failure of naive quaternion power iteration. No allocation per iteration.
struct PhysicsSoftBodyShapeMatchingCovariance {
	double m[3][3] = {};

	_FORCE_INLINE_ void add(const Vector3 &p_rest, const Vector3 &p_current) {
		const double r[3] = { double(p_rest.x), double(p_rest.y), double(p_rest.z) };
		const double c[3] = { double(p_current.x), double(p_current.y), double(p_current.z) };
		for (int i = 0; i < 3; ++i) {
			for (int j = 0; j < 3; ++j) {
				m[i][j] += r[i] * c[j];
			}
		}
	}

	_FORCE_INLINE_ bool solve_rotation(Quaternion &r_rotation) const {
		const double xx = m[0][0], xy = m[0][1], xz = m[0][2];
		const double yx = m[1][0], yy = m[1][1], yz = m[1][2];
		const double zx = m[2][0], zy = m[2][1], zz = m[2][2];
		const double h[4][4] = {
			{ xx + yy + zz, yz - zy, zx - xz, xy - yx },
			{ yz - zy, xx - yy - zz, xy + yx, zx + xz },
			{ zx - xz, xy + yx, -xx + yy - zz, yz + zy },
			{ xy - yx, zx + xz, yz + zy, -xx - yy + zz }
		};
		double scale = 0.0;
		for (int i = 0; i < 4; ++i) {
			for (int j = 0; j < 4; ++j) {
				if (!Math::is_finite(h[i][j])) {
					return false;
				}
				scale = MAX(scale, Math::abs(h[i][j]));
			}
		}
		if (!(scale > 0.0)) {
			return false;
		}

		double a[4][4];
		double v[4][4] = {};
		for (int i = 0; i < 4; ++i) {
			for (int j = 0; j < 4; ++j) {
				a[i][j] = h[i][j] / scale;
			}
			v[i][i] = 1.0;
		}
		for (int sweep = 0; sweep < 16; ++sweep) {
			bool changed = false;
			for (int p = 0; p < 3; ++p) {
				for (int q = p + 1; q < 4; ++q) {
					const double apq = a[p][q];
					if (Math::abs(apq) <= 1e-15) {
						continue;
					}
					changed = true;
					const double tau = (a[q][q] - a[p][p]) / (2.0 * apq);
					const double t = (tau >= 0.0 ? 1.0 : -1.0) /
							(Math::abs(tau) + Math::sqrt(1.0 + tau * tau));
					const double c = 1.0 / Math::sqrt(1.0 + t * t);
					const double s = t * c;
					a[p][p] -= t * apq;
					a[q][q] += t * apq;
					a[p][q] = a[q][p] = 0.0;
					for (int k = 0; k < 4; ++k) {
						if (k != p && k != q) {
							const double akp = a[k][p], akq = a[k][q];
							a[k][p] = a[p][k] = c * akp - s * akq;
							a[k][q] = a[q][k] = s * akp + c * akq;
						}
						const double vkp = v[k][p], vkq = v[k][q];
						v[k][p] = c * vkp - s * vkq;
						v[k][q] = s * vkp + c * vkq;
					}
				}
			}
			if (!changed) {
				break;
			}
		}
		int best = 0;
		for (int i = 1; i < 4; ++i) {
			if (a[i][i] > a[best][best]) {
				best = i;
			}
		}
		const Quaternion rotation = Quaternion(real_t(v[1][best]), real_t(v[2][best]),
				real_t(v[3][best]), real_t(v[0][best]));
		const real_t norm2 = rotation.length_squared();
		if (!(norm2 > real_t(0.0)) || !Math::is_finite(norm2)) {
			return false;
		}
		r_rotation = rotation.normalized();
		return true;
	}
};

// Atomic position projection; pinned particles and bad targets are ignored.
_FORCE_INLINE_ bool physics_softbody_shape_matching_project(
		Vector3 &r_position, const Vector3 &p_rest_offset,
		const Vector3 &p_current_center, const Quaternion &p_rotation,
		real_t p_strength, real_t p_inv_mass) {
	if (!(p_strength > real_t(0.0)) || p_strength > real_t(1.0) ||
			!(p_inv_mass > real_t(0.0)) || !Math::is_finite(p_strength) ||
			!Math::is_finite(p_inv_mass) || !r_position.is_finite() ||
			!p_rest_offset.is_finite() || !p_current_center.is_finite()) {
		return false;
	}
	const Vector3 target = p_current_center + p_rotation.xform(p_rest_offset);
	if (!target.is_finite()) {
		return false;
	}
	const Vector3 proposed = r_position + (target - r_position) * p_strength;
	if (!proposed.is_finite()) {
		return false;
	}
	r_position = proposed;
	return true;
}
