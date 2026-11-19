/**************************************************************************/
/*  rope_geometry.cpp                                             */
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

#include "rope_geometry.h"

namespace RopeGeometry {

real_t polyline_length(const Vector<Vector3> &p_points) {
	real_t length = 0.0;
	for (int i = 1; i < p_points.size(); i++) {
		length += p_points[i].distance_to(p_points[i - 1]);
	}
	return length;
}

// Samples the sagging curve densely.
static void sample_curve(const Vector3 &p_start, const Vector3 &p_end, const Vector3 &p_sag_direction, real_t p_sag, int p_samples, Vector<Vector3> &r_points) {
	r_points.resize(p_samples + 1);
	Vector3 *out = r_points.ptrw();
	for (int i = 0; i <= p_samples; i++) {
		const real_t t = real_t(i) / real_t(p_samples);
		out[i] = p_start.lerp(p_end, t) + p_sag_direction * (real_t(4.0) * p_sag * t * (real_t(1.0) - t));
	}
}

bool layout_points(const Vector3 &p_start, const Vector3 &p_end, real_t p_length, int p_segments, const Vector3 &p_down, Vector<Vector3> &r_points) {
	r_points.clear();
	if (p_segments < 1 || !p_start.is_finite() || !p_end.is_finite() || !(p_length > 0.0) || !Math::is_finite(p_length)) {
		return false;
	}
	const real_t distance = p_start.distance_to(p_end);
	const real_t length = MAX(p_length, distance);

	Vector<Vector3> dense;
	const int samples = MAX(p_segments * 16, 256);
	if (length <= distance * real_t(1.00001) || distance < real_t(CMP_EPSILON)) {
		// Taut: a straight line. If both ends coincide the rope is folded straight down.
		const Vector3 end = distance < real_t(CMP_EPSILON) ? p_start + (p_down.is_zero_approx() ? Vector3(0, -1, 0) : p_down.normalized()) * length : p_end;
		sample_curve(p_start, end, Vector3(), 0.0, samples, dense);
	} else {
		// The sag direction is the "down" direction made perpendicular to the chord; if the chord is
		// (nearly) parallel to down, any perpendicular will do.
		const Vector3 chord = (p_end - p_start) / distance;
		Vector3 sag_direction = p_down - chord * p_down.dot(chord);
		if (sag_direction.length_squared() < real_t(1e-6)) {
			sag_direction = chord.cross(Math::abs(chord.y) < real_t(0.9) ? Vector3(0, 1, 0) : Vector3(1, 0, 0));
		}
		sag_direction.normalize();

		// The arc length grows monotonically with the sag: bisect for the sag that gives `length`.
		real_t low = 0.0;
		real_t high = length; // A sag this deep is always longer than the rope.
		for (int iteration = 0; iteration < 60; iteration++) {
			const real_t middle = (low + high) * real_t(0.5);
			sample_curve(p_start, p_end, sag_direction, middle, samples, dense);
			if (polyline_length(dense) < length) {
				low = middle;
			} else {
				high = middle;
			}
		}
		sample_curve(p_start, p_end, sag_direction, (low + high) * real_t(0.5), samples, dense);
	}

	// Resample by arc length into equal segments.
	const real_t total = polyline_length(dense);
	r_points.resize(p_segments + 1);
	Vector3 *out = r_points.ptrw();
	out[0] = dense[0];
	real_t walked = 0.0;
	int index = 1;
	for (int k = 1; k < p_segments; k++) {
		const real_t target = total * real_t(k) / real_t(p_segments);
		while (index < dense.size() - 1 && walked + dense[index].distance_to(dense[index - 1]) < target) {
			walked += dense[index].distance_to(dense[index - 1]);
			index++;
		}
		const real_t piece = dense[index].distance_to(dense[index - 1]);
		const real_t t = piece > 0.0 ? CLAMP((target - walked) / piece, real_t(0.0), real_t(1.0)) : real_t(0.0);
		out[k] = dense[index - 1].lerp(dense[index], t);
	}
	out[p_segments] = dense[dense.size() - 1];
	return true;
}

bool build_tube(const Vector<Vector3> &p_points, real_t p_radius, int p_radial, real_t p_uv_length, TubeMesh &r_mesh) {
	r_mesh = TubeMesh();
	const int count = p_points.size();
	if (count < 2 || p_radial < 3 || !(p_radius > 0.0) || !(p_uv_length > 0.0)) {
		return false;
	}
	// Tangents: average of the neighbouring segment directions.
	Vector<Vector3> tangents;
	tangents.resize(count);
	for (int i = 0; i < count; i++) {
		Vector3 before = i > 0 ? p_points[i] - p_points[i - 1] : Vector3();
		Vector3 after = i + 1 < count ? p_points[i + 1] - p_points[i] : Vector3();
		before = before.is_zero_approx() ? Vector3() : before.normalized();
		after = after.is_zero_approx() ? Vector3() : after.normalized();
		Vector3 tangent = before + after;
		if (tangent.is_zero_approx()) {
			tangent = after.is_zero_approx() ? before : after;
		}
		if (tangent.is_zero_approx()) {
			tangent = i > 0 ? tangents[i - 1] : Vector3(0, 1, 0);
		}
		tangents.write[i] = tangent.normalized();
	}

	const int ring = p_radial + 1; // The seam vertex is duplicated so u can wrap.
	r_mesh.vertices.resize(count * ring + 2);
	r_mesh.normals.resize(count * ring + 2);
	r_mesh.uvs.resize(count * ring + 2);
	Vector3 *vertex = r_mesh.vertices.ptrw();
	Vector3 *normal = r_mesh.normals.ptrw();
	Vector2 *uv = r_mesh.uvs.ptrw();

	// Parallel transport: carry the frame along the rope so the tube does not twist.
	const Vector3 first_tangent = tangents[0];
	Vector3 side = first_tangent.cross(Math::abs(first_tangent.y) < real_t(0.9) ? Vector3(0, 1, 0) : Vector3(1, 0, 0)).normalized();
	real_t distance = 0.0;
	for (int i = 0; i < count; i++) {
		if (i > 0) {
			distance += p_points[i].distance_to(p_points[i - 1]);
			// Re-orthogonalize the frame against the new tangent.
			side = (side - tangents[i] * side.dot(tangents[i]));
			if (side.length_squared() < real_t(1e-8)) {
				side = tangents[i].cross(Vector3(0, 1, 0));
				if (side.length_squared() < real_t(1e-8)) {
					side = tangents[i].cross(Vector3(1, 0, 0));
				}
			}
			side.normalize();
		}
		const Vector3 up = tangents[i].cross(side);
		for (int k = 0; k <= p_radial; k++) {
			const real_t angle = real_t(Math::TAU) * real_t(k) / real_t(p_radial);
			const Vector3 direction = side * Math::cos(angle) + up * Math::sin(angle);
			const int index = i * ring + k;
			vertex[index] = p_points[i] + direction * p_radius;
			normal[index] = direction;
			uv[index] = Vector2(real_t(k) / real_t(p_radial), distance / p_uv_length);
		}
	}
	// Cap centers.
	const int cap_start = count * ring;
	const int cap_end = cap_start + 1;
	vertex[cap_start] = p_points[0];
	normal[cap_start] = -tangents[0];
	uv[cap_start] = Vector2(0.5, 0);
	vertex[cap_end] = p_points[count - 1];
	normal[cap_end] = tangents[count - 1];
	uv[cap_end] = Vector2(0.5, distance / p_uv_length);

	PackedInt32Array &indices = r_mesh.indices;
	indices.resize((count - 1) * p_radial * 6 + 2 * p_radial * 3);
	int32_t *out = indices.ptrw();
	int n = 0;
	// Godot front faces are clockwise seen from outside.
	for (int i = 0; i + 1 < count; i++) {
		for (int k = 0; k < p_radial; k++) {
			const int a = i * ring + k;
			const int b = a + 1;
			const int c = a + ring;
			const int d = c + 1;
			out[n++] = a;
			out[n++] = c;
			out[n++] = b;
			out[n++] = b;
			out[n++] = c;
			out[n++] = d;
		}
	}
	for (int k = 0; k < p_radial; k++) {
		out[n++] = cap_start;
		out[n++] = k;
		out[n++] = k + 1;
	}
	const int last = (count - 1) * ring;
	for (int k = 0; k < p_radial; k++) {
		out[n++] = cap_end;
		out[n++] = last + k + 1;
		out[n++] = last + k;
	}
	return true;
}

} // namespace RopeGeometry
