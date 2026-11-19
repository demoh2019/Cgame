/**************************************************************************/
/*  physics_softbody_shape_matching.h                                     */
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

// One GLOBAL, equal-material-particle-weight corotational shape-matching
// cluster (Muller et al., "Meshless Deformations Based on Shape Matching").
//
// Nodes provide .s (source/rest position), .x (predicted position) and .im
// (inverse mass). Pinned nodes participate in fitting the reference pose,
// but NEVER move. All non-pinned nodes have the same material weight in
// GodotSoftBody3D; this is a PBD shape-memory projection, NOT volumetric FEM
// or an XPBD strain-energy constraint. Runtime cost is O(nodes) with fixed
// 4x4 symmetric eigensolve, no allocations and no stored rest-shape buffer.
//
// Return false on invalid input BEFORE changing any position. All proposed
// corrections are prevalidated and only then committed.
template <typename NodeContainer>
_FORCE_INLINE_ bool physics_softbody_project_shape_matching(NodeContainer &r_nodes, real_t p_fraction) {
	const uint32_t count = r_nodes.size();
	if (count < 4 || !(p_fraction > 0.0) || p_fraction > 1.0 ||
			!Math::is_finite(p_fraction)) {
		return false;
	}

	double rest_sum[3] = {};
	double current_sum[3] = {};
	uint32_t mobile_count = 0;
	for (uint32_t i = 0; i < count; ++i) {
		const auto &node = r_nodes[i];
		if (!node.s.is_finite() || !node.x.is_finite() ||
				!Math::is_finite(node.im) || node.im < 0.0) {
			return false;
		}
		if (node.im > 0.0) {
			++mobile_count;
		}
		rest_sum[0] += double(node.s.x);
		rest_sum[1] += double(node.s.y);
		rest_sum[2] += double(node.s.z);
		current_sum[0] += double(node.x.x);
		current_sum[1] += double(node.x.y);
		current_sum[2] += double(node.x.z);
	}
	if (mobile_count == 0) {
		return false;
	}
	const double inverse_count = 1.0 / double(count);
	double rest_center[3], current_center[3];
	for (int i = 0; i < 3; ++i) {
		rest_center[i] = rest_sum[i] * inverse_count;
		current_center[i] = current_sum[i] * inverse_count;
		if (!Math::is_finite(rest_center[i]) || !Math::is_finite(current_center[i])) {
			return false;
		}
	}

	// H = sum_i (x_i - x_center) * (s_i - s_center)^T.
	// Horn's quaternion 4x4 matrix is built for a rotation mapping s to x.
	// Double intermediates and centered coordinates limit loss of precision
	// for translated game worlds and very long/very small meshes.
	double h[3][3] = {};
	double rest_variance = 0.0;
	for (uint32_t i = 0; i < count; ++i) {
		const auto &node = r_nodes[i];
		const double s[3] = {
			double(node.s.x) - rest_center[0],
			double(node.s.y) - rest_center[1],
			double(node.s.z) - rest_center[2],
		};
		const double x[3] = {
			double(node.x.x) - current_center[0],
			double(node.x.y) - current_center[1],
			double(node.x.z) - current_center[2],
		};
		for (int row = 0; row < 3; ++row) {
			rest_variance += s[row] * s[row];
			for (int col = 0; col < 3; ++col) {
				h[row][col] += x[row] * s[col];
			}
		}
	}
	if (!(rest_variance > 0.0) || !Math::is_finite(rest_variance)) {
		return false;
	}
	double h_scale = 0.0;
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			if (!Math::is_finite(h[row][col])) {
				return false;
			}
			h_scale = MAX(h_scale, Math::abs(h[row][col]));
		}
	}
	// A completely collapsed present shape has no unique orientation.
	// A deterministic identity orientation restores the rest shape.
	if (h_scale > 0.0) {
		for (int row = 0; row < 3; ++row) {
			for (int col = 0; col < 3; ++col) {
				h[row][col] /= h_scale;
			}
		}
	}

	const double trace = h[0][0] + h[1][1] + h[2][2];
	double k[4][4] = {};
	k[0][0] = trace;
	k[0][1] = h[2][1] - h[1][2];
	k[0][2] = h[0][2] - h[2][0];
	k[0][3] = h[1][0] - h[0][1];
	k[1][1] = h[0][0] - h[1][1] - h[2][2];
	k[1][2] = h[0][1] + h[1][0];
	k[1][3] = h[0][2] + h[2][0];
	k[2][2] = -h[0][0] + h[1][1] - h[2][2];
	k[2][3] = h[1][2] + h[2][1];
	k[3][3] = -h[0][0] - h[1][1] + h[2][2];
	for (int row = 0; row < 4; ++row) {
		for (int col = 0; col < row; ++col) {
			k[row][col] = k[col][row];
		}
	}

	// Symmetric Jacobi eigendecomposition; 4x4 is tiny and fixed size.
	// The largest eigenvector of Horn's K is a unit quaternion, hence a
	// proper rotation with determinant +1 (no mirrored shape goals).
	double eigenvectors[4][4] = {};
	for (int i = 0; i < 4; ++i) {
		eigenvectors[i][i] = 1.0;
	}
	for (int iteration = 0; iteration < 48; ++iteration) {
		int p = 0, q = 1;
		double biggest = 0.0;
		for (int row = 0; row < 4; ++row) {
			for (int col = row + 1; col < 4; ++col) {
				const double off_diagonal = Math::abs(k[row][col]);
				if (off_diagonal > biggest) {
					biggest = off_diagonal;
					p = row;
					q = col;
				}
			}
		}
		if (biggest < 1e-13) {
			break;
		}
		const double app = k[p][p];
		const double aqq = k[q][q];
		const double apq = k[p][q];
		const double tau = (aqq - app) / (2.0 * apq);
		const double tangent = (tau >= 0.0 ? 1.0 : -1.0) /
				(Math::abs(tau) + Math::sqrt(1.0 + tau * tau));
		const double cosine = 1.0 / Math::sqrt(1.0 + tangent * tangent);
		const double sine = tangent * cosine;
		if (!Math::is_finite(cosine) || !Math::is_finite(sine)) {
			return false;
		}
		for (int index = 0; index < 4; ++index) {
			if (index != p && index != q) {
				const double ap = k[index][p];
				const double aq = k[index][q];
				k[index][p] = k[p][index] = cosine * ap - sine * aq;
				k[index][q] = k[q][index] = sine * ap + cosine * aq;
			}
			const double vp = eigenvectors[index][p];
			const double vq = eigenvectors[index][q];
			eigenvectors[index][p] = cosine * vp - sine * vq;
			eigenvectors[index][q] = sine * vp + cosine * vq;
		}
		k[p][p] = app - tangent * apq;
		k[q][q] = aqq + tangent * apq;
		k[p][q] = k[q][p] = 0.0;
	}
	int best = 0;
	for (int i = 1; i < 4; ++i) {
		if (k[i][i] > k[best][best]) {
			best = i;
		}
	}
	double quaternion[4];
	double qnorm_sq = 0.0;
	for (int i = 0; i < 4; ++i) {
		quaternion[i] = eigenvectors[i][best];
		qnorm_sq += quaternion[i] * quaternion[i];
	}
	if (!(qnorm_sq > 0.0) || !Math::is_finite(qnorm_sq)) {
		return false;
	}
	const double inv_qnorm = 1.0 / Math::sqrt(qnorm_sq);
	for (double &component : quaternion) {
		component *= inv_qnorm;
	}
	const double w = quaternion[0];
	const double x = quaternion[1];
	const double y = quaternion[2];
	const double z = quaternion[3];
	const double rotation[3][3] = {
		{ 1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - w * z), 2.0 * (x * z + w * y) },
		{ 2.0 * (x * y + w * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - w * x) },
		{ 2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y) },
	};

	// The same projection is computed twice: validate all proposed
	// positions first, then commit. Avoid heap scratch, partial updates
	// on non-finite values, and any change to exact pinned vertices.
	const auto projected = [&](const auto &p_node) -> Vector3 {
		const double s[3] = {
			double(p_node.s.x) - rest_center[0],
			double(p_node.s.y) - rest_center[1],
			double(p_node.s.z) - rest_center[2],
		};
		double result[3];
		for (int row = 0; row < 3; ++row) {
			double goal = current_center[row];
			for (int col = 0; col < 3; ++col) {
				goal += rotation[row][col] * s[col];
			}
			const double actual = row == 0 ? double(p_node.x.x) :
					row == 1 ? double(p_node.x.y) : double(p_node.x.z);
			result[row] = actual + double(p_fraction) * (goal - actual);
		}
		return Vector3(real_t(result[0]), real_t(result[1]), real_t(result[2]));
	};
	for (uint32_t i = 0; i < count; ++i) {
		if (r_nodes[i].im > 0.0 && !projected(r_nodes[i]).is_finite()) {
			return false;
		}
	}
	for (uint32_t i = 0; i < count; ++i) {
		if (r_nodes[i].im > 0.0) {
			r_nodes[i].x = projected(r_nodes[i]);
		}
	}
	return true;
}
