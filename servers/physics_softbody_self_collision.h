/**************************************************************************/
/*  physics_softbody_self_collision.h                                     */
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

// Closest point on a non-degenerate triangle with barycentric coordinates.
// Implements Ericson's Voronoi-region triangle classification, with no
// allocations, so cloth vertices can query triangle faces in the hot path.
_FORCE_INLINE_ bool physics_softbody_closest_triangle_point(
		const Vector3 &p_point, const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c,
		Vector3 &r_closest, Vector3 &r_barycentric) {
	if (!p_point.is_finite() || !p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite()) {
		return false;
	}
	const Vector3 ab = p_b - p_a;
	const Vector3 ac = p_c - p_a;
	const real_t area_sq = ab.cross(ac).length_squared();
	if (!(area_sq > CMP_EPSILON * CMP_EPSILON) || !Math::is_finite(area_sq)) {
		return false;
	}
	const Vector3 ap = p_point - p_a;
	const real_t d1 = ab.dot(ap);
	const real_t d2 = ac.dot(ap);
	Vector3 bary;
	if (d1 <= 0.0 && d2 <= 0.0) {
		bary = Vector3(1, 0, 0);
	} else {
		const Vector3 bp = p_point - p_b;
		const real_t d3 = ab.dot(bp);
		const real_t d4 = ac.dot(bp);
		if (d3 >= 0.0 && d4 <= d3) {
			bary = Vector3(0, 1, 0);
		} else {
			const real_t vc = d1 * d4 - d3 * d2;
			if (vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0) {
				const real_t v = d1 / (d1 - d3);
				bary = Vector3(1.0 - v, v, 0);
			} else {
				const Vector3 cp = p_point - p_c;
				const real_t d5 = ab.dot(cp);
				const real_t d6 = ac.dot(cp);
				if (d6 >= 0.0 && d5 <= d6) {
					bary = Vector3(0, 0, 1);
				} else {
					const real_t vb = d5 * d2 - d1 * d6;
					if (vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0) {
						const real_t w = d2 / (d2 - d6);
						bary = Vector3(1.0 - w, 0, w);
					} else {
						const real_t va = d3 * d6 - d5 * d4;
						if (va <= 0.0 && (d4 - d3) >= 0.0 && (d5 - d6) >= 0.0) {
							const real_t w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
							bary = Vector3(0, 1.0 - w, w);
						} else {
							const real_t denominator = va + vb + vc;
							if (!(denominator > 0.0) || !Math::is_finite(denominator)) {
								return false;
							}
							const real_t v = vb / denominator;
							const real_t w = vc / denominator;
							bary = Vector3(1.0 - v - w, v, w);
						}
					}
				}
			}
		}
	}
	const Vector3 closest = p_a * bary.x + p_b * bary.y + p_c * bary.z;
	if (!closest.is_finite() || !bary.is_finite()) {
		return false;
	}
	r_closest = closest;
	r_barycentric = bary;
	return true;
}

// Discrete, two-sided, mass-weighted vertex/face self-contact. A previously
// outside vertex that tunnels completely through the surface is not caught;
// continuous collision detection is a separate feature.
//
// p_alpha_tilde is nonnegative compliance / dt^2. Unlike persistent XPBD
// joints, collision contacts are transient, resolved once per physics step.
_FORCE_INLINE_ bool physics_softbody_project_self_contact(
		Vector3 &r_point, Vector3 &r_a, Vector3 &r_b, Vector3 &r_c,
		real_t p_inv_mass_point, real_t p_inv_mass_a, real_t p_inv_mass_b, real_t p_inv_mass_c,
		real_t p_thickness, real_t p_alpha_tilde, const Vector3 &p_previous_point) {
	if (!(p_thickness > 0.0) || !Math::is_finite(p_thickness) ||
			!Math::is_finite(p_alpha_tilde) || p_alpha_tilde < 0.0 ||
			!Math::is_finite(p_inv_mass_point) || !Math::is_finite(p_inv_mass_a) ||
			!Math::is_finite(p_inv_mass_b) || !Math::is_finite(p_inv_mass_c) ||
			p_inv_mass_point < 0.0 || p_inv_mass_a < 0.0 ||
			p_inv_mass_b < 0.0 || p_inv_mass_c < 0.0) {
		return false;
	}
	Vector3 closest, bary;
	if (!physics_softbody_closest_triangle_point(r_point, r_a, r_b, r_c, closest, bary)) {
		return false;
	}
	const Vector3 offset = r_point - closest;
	const real_t dist_sq = offset.length_squared();
	if (!Math::is_finite(dist_sq) || dist_sq >= p_thickness * p_thickness) {
		return false;
	}
	Vector3 normal;
	const real_t distance = Math::sqrt(dist_sq);
	if (distance > CMP_EPSILON) {
		normal = offset / distance;
	} else {
		// At zero distance the separating direction is ambiguous. Prefer
		// the side the vertex occupied before prediction; use winding if
		// that point was exactly coplanar as well.
		const Vector3 face_normal = (r_b - r_a).cross(r_c - r_a).normalized();
		normal = (p_previous_point - closest).dot(face_normal) < 0.0 ? -face_normal : face_normal;
	}
	const real_t weighted_mass = p_inv_mass_point +
			p_inv_mass_a * bary.x * bary.x +
			p_inv_mass_b * bary.y * bary.y +
			p_inv_mass_c * bary.z * bary.z;
	const double denominator = double(weighted_mass) + double(p_alpha_tilde);
	if (!(weighted_mass > 0.0) || !(denominator > 0.0) || !Math::is_finite(denominator)) {
		return false;
	}
	const double projection = (double(p_thickness) - double(distance)) / denominator;
	if (!Math::is_finite(projection)) {
		return false;
	}
	const Vector3 next_point = r_point + normal * real_t(projection * p_inv_mass_point);
	const Vector3 next_a = r_a - normal * real_t(projection * p_inv_mass_a * bary.x);
	const Vector3 next_b = r_b - normal * real_t(projection * p_inv_mass_b * bary.y);
	const Vector3 next_c = r_c - normal * real_t(projection * p_inv_mass_c * bary.z);
	if (!next_point.is_finite() || !next_a.is_finite() || !next_b.is_finite() || !next_c.is_finite()) {
		return false;
	}
	r_point = next_point;
	r_a = next_a;
	r_b = next_b;
	r_c = next_c;
	return true;
}


// Closest pair of points on two finite segments (Ericson). Used for
// edge-edge cloth self-contacts that vertex-face tests cannot detect,
// e.g. two crossed thin edges with all endpoints far apart.
// Return false for degenerate segments or any non-finite result.
_FORCE_INLINE_ bool physics_softbody_closest_segment_points(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c, const Vector3 &p_d,
		Vector3 &r_on_ab, Vector3 &r_on_cd, real_t &r_s, real_t &r_t) {
	if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() || !p_d.is_finite()) {
		return false;
	}
	const Vector3 d1 = p_b - p_a;
	const Vector3 d2 = p_d - p_c;
	const Vector3 r = p_a - p_c;
	const real_t a = d1.length_squared();
	const real_t e = d2.length_squared();
	if (!(a > CMP_EPSILON * CMP_EPSILON) || !(e > CMP_EPSILON * CMP_EPSILON) ||
			!Math::is_finite(a) || !Math::is_finite(e)) {
		return false;
	}
	const real_t b = d1.dot(d2);
	const real_t c = d1.dot(r);
	const real_t f = d2.dot(r);
	const double determinant = double(a) * double(e) - double(b) * double(b);
	real_t s;
	if (determinant > double(CMP_EPSILON) * double(CMP_EPSILON) * double(a) * double(e)) {
		s = CLAMP(real_t((double(b) * double(f) - double(c) * double(e)) / determinant), real_t(0.0), real_t(1.0));
	} else {
		// Parallel lines: pick an endpoint and project onto the other.
		s = 0.0;
	}
	real_t t = real_t((double(b) * double(s) + double(f)) / double(e));
	if (t < 0.0) {
		t = 0.0;
		s = CLAMP(-c / a, real_t(0.0), real_t(1.0));
	} else if (t > 1.0) {
		t = 1.0;
		s = CLAMP((b - c) / a, real_t(0.0), real_t(1.0));
	}
	if (!Math::is_finite(s) || !Math::is_finite(t)) {
		return false;
	}
	const Vector3 on_ab = p_a + d1 * s;
	const Vector3 on_cd = p_c + d2 * t;
	if (!on_ab.is_finite() || !on_cd.is_finite()) {
		return false;
	}
	r_s = s;
	r_t = t;
	r_on_ab = on_ab;
	r_on_cd = on_cd;
	return true;
}

// One-sided non-penetration correction for two cloth edges. Here "one-sided"
// describes the contact inequality (the edges cannot come closer than the
// thickness), not a preferred face normal: the edges may cross either way.
// Both endpoints of both edges move in opposite directions according to
// barycentric factors and inverse masses. No persistent collision lambda.
_FORCE_INLINE_ bool physics_softbody_project_edge_contact(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_mass_a, real_t p_inv_mass_b, real_t p_inv_mass_c, real_t p_inv_mass_d,
		real_t p_thickness, real_t p_alpha_tilde,
		const Vector3 &p_prev_a, const Vector3 &p_prev_b,
		const Vector3 &p_prev_c, const Vector3 &p_prev_d) {
	if (!(p_thickness > 0.0) || !Math::is_finite(p_thickness) ||
			!Math::is_finite(p_alpha_tilde) || p_alpha_tilde < 0.0 ||
			!Math::is_finite(p_inv_mass_a) || !Math::is_finite(p_inv_mass_b) ||
			!Math::is_finite(p_inv_mass_c) || !Math::is_finite(p_inv_mass_d) ||
			p_inv_mass_a < 0.0 || p_inv_mass_b < 0.0 ||
			p_inv_mass_c < 0.0 || p_inv_mass_d < 0.0) {
		return false;
	}
	Vector3 on_ab, on_cd;
	real_t s, t;
	if (!physics_softbody_closest_segment_points(r_a, r_b, r_c, r_d, on_ab, on_cd, s, t)) {
		return false;
	}
	const Vector3 separation = on_ab - on_cd;
	const real_t distance_sq = separation.length_squared();
	const real_t thickness_sq = p_thickness * p_thickness;
	if (!Math::is_finite(distance_sq) || !Math::is_finite(thickness_sq) ||
			distance_sq >= thickness_sq) {
		return false;
	}
	const real_t distance = Math::sqrt(distance_sq);
	Vector3 normal;
	if (distance > CMP_EPSILON) {
		normal = separation / distance;
	} else {
		// Intersecting segments have no unique separating side. A segment
		// cross product gives a stable normal for non-parallel edges.
		normal = (r_b - r_a).cross(r_d - r_c);
		const Vector3 previous_ab = p_prev_a.lerp(p_prev_b, s);
		const Vector3 previous_cd = p_prev_c.lerp(p_prev_d, t);
		const Vector3 old_separation = previous_ab - previous_cd;
		if (normal.length_squared() <= CMP_EPSILON * CMP_EPSILON) {
			normal = old_separation;
		}
		if (normal.length_squared() <= CMP_EPSILON * CMP_EPSILON) {
			// Deterministic perpendicular for parallel coincident edges.
			const Vector3 edge = r_b - r_a;
			normal = Math::abs(edge.x) < Math::abs(edge.y) ?
					edge.cross(Vector3(1, 0, 0)) : edge.cross(Vector3(0, 1, 0));
		}
		if (!normal.is_finite() || normal.length_squared() <= CMP_EPSILON * CMP_EPSILON) {
			return false;
		}
		normal.normalize();
		if (old_separation.dot(normal) < 0.0) {
			normal = -normal;
		}
	}
	const real_t u = 1.0 - s;
	const real_t v = 1.0 - t;
	const double weighted_mass =
			double(p_inv_mass_a) * double(u) * double(u) +
			double(p_inv_mass_b) * double(s) * double(s) +
			double(p_inv_mass_c) * double(v) * double(v) +
			double(p_inv_mass_d) * double(t) * double(t);
	const double denom = weighted_mass + double(p_alpha_tilde);
	if (!(weighted_mass > 0.0) || !Math::is_finite(denom) || !(denom > 0.0)) {
		return false;
	}
	const double correction = (double(p_thickness) - double(distance)) / denom;
	if (!Math::is_finite(correction)) {
		return false;
	}
	const Vector3 next_a = r_a + normal * real_t(correction * p_inv_mass_a * u);
	const Vector3 next_b = r_b + normal * real_t(correction * p_inv_mass_b * s);
	const Vector3 next_c = r_c - normal * real_t(correction * p_inv_mass_c * v);
	const Vector3 next_d = r_d - normal * real_t(correction * p_inv_mass_d * t);
	if (!next_a.is_finite() || !next_b.is_finite() || !next_c.is_finite() || !next_d.is_finite()) {
		return false;
	}
	r_a = next_a;
	r_b = next_b;
	r_c = next_c;
	r_d = next_d;
	return true;
}
