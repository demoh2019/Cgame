/**************************************************************************/
/*  godot_shape_2d.cpp                                                    */
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

#include "godot_shape_2d.h"

#include "core/math/geometry_2d.h"
#include "core/templates/sort_array.h"
#include "core/variant/variant.h"

void GodotShape2D::configure(const Rect2 &p_aabb) {
	aabb = p_aabb;
	configured = true;
	for (const KeyValue<GodotShapeOwner2D *, int> &E : owners) {
		E.key->_shape_changed();
	}
}

Vector2 GodotShape2D::get_support(const Vector2 &p_normal) const {
	Vector2 res[2];
	int amnt;
	get_supports(p_normal, res, amnt);
	return res[0];
}

void GodotShape2D::add_owner(GodotShapeOwner2D *p_owner) {
	HashMap<GodotShapeOwner2D *, int>::Iterator E = owners.find(p_owner);
	if (E) {
		E->value++;
	} else {
		owners[p_owner] = 1;
	}
}

void GodotShape2D::remove_owner(GodotShapeOwner2D *p_owner) {
	HashMap<GodotShapeOwner2D *, int>::Iterator E = owners.find(p_owner);
	ERR_FAIL_COND(!E);
	E->value--;
	if (E->value == 0) {
		owners.remove(E);
	}
}

bool GodotShape2D::is_owner(GodotShapeOwner2D *p_owner) const {
	return owners.has(p_owner);
}

const HashMap<GodotShapeOwner2D *, int> &GodotShape2D::get_owners() const {
	return owners;
}

GodotShape2D::~GodotShape2D() {
	ERR_FAIL_COND(owners.size());
}

/*********************************************************/
/*********************************************************/
/*********************************************************/

void GodotWorldBoundaryShape2D::get_supports(const Vector2 &p_normal, Vector2 *r_supports, int &r_amount) const {
	r_amount = 0;
}

bool GodotWorldBoundaryShape2D::contains_point(const Vector2 &p_point) const {
	return normal.dot(p_point) < d;
}

bool GodotWorldBoundaryShape2D::intersect_segment(const Vector2 &p_begin, const Vector2 &p_end, Vector2 &r_point, Vector2 &r_normal) const {
	Vector2 segment = p_begin - p_end;
	real_t den = normal.dot(segment);

	//printf("den is %i\n",den);
	if (Math::abs(den) <= CMP_EPSILON) {
		return false;
	}

	real_t dist = (normal.dot(p_begin) - d) / den;
	//printf("dist is %i\n",dist);

	if (dist < -CMP_EPSILON || dist > (1.0 + CMP_EPSILON)) {
		return false;
	}

	r_point = p_begin + segment * -dist;
	r_normal = normal;

	return true;
}

real_t GodotWorldBoundaryShape2D::get_moment_of_inertia(real_t p_mass, const Size2 &p_scale) const {
	return 0;
}

void GodotWorldBoundaryShape2D::set_data(const Variant &p_data) {
	ERR_FAIL_COND(p_data.get_type() != Variant::ARRAY);
	Array arr = p_data;
	ERR_FAIL_COND(arr.size() != 2);
	normal = arr[0];
	d = arr[1];
	configure(Rect2(Vector2(-1e15, -1e15), Vector2(1e15 * 2, 1e15 * 2)));
}

Variant GodotWorldBoundaryShape2D::get_data() const {
	Array arr;
	arr.resize(2);
	arr[0] = normal;
	arr[1] = d;
	return arr;
}

/*********************************************************/
/*********************************************************/
/*********************************************************/

void GodotSeparationRayShape2D::get_supports(const Vector2 &p_normal, Vector2 *r_supports, int &r_amount) const {
	r_amount = 1;

	if (p_normal.y > 0) {
		*r_supports = Vector2(0, length);
	} else {
		*r_supports = Vector2();
	}
}

bool GodotSeparationRayShape2D::contains_point(const Vector2 &p_point) const {
	return false;
}

bool GodotSeparationRayShape2D::intersect_segment(const Vector2 &p_begin, const Vector2 &p_end, Vector2 &r_point, Vector2 &r_normal) const {
	return false; //rays can't be intersected
}

real_t GodotSeparationRayShape2D::get_moment_of_inertia(real_t p_mass, const Size2 &p_scale) const {
	return 0; //rays are mass-less
}

void GodotSeparationRayShape2D::set_data(const Variant &p_data) {
	Dictionary d = p_data;
	length = d["length"];
	slide_on_slope = d["slide_on_slope"];
	configure(Rect2(0, 0, 0.001, length));
}

Variant GodotSeparationRayShape2D::get_data() const {
	Dictionary d;
	d["length"] = length;
	d["slide_on_slope"] = slide_on_slope;
	return d;
}

/*********************************************************/
/*********************************************************/
/*********************************************************/

void GodotSegmentShape2D::get_supports(const Vector2 &p_normal, Vector2 *r_supports, int &r_amount) const {
	if (Math::abs(p_normal.dot(n)) > segment_is_valid_support_threshold) {
		r_supports[0] = a;
		r_supports[1] = b;
		r_amount = 2;
		return;
	}

	real_t dp = p_normal.dot(b - a);
	if (dp > 0) {
		*r_supports = b;
	} else {
		*r_supports = a;
	}
	r_amount = 1;
}

bool GodotSegmentShape2D::contains_point(const Vector2 &p_point) const {
	return false;
}

bool GodotSegmentShape2D::intersect_segment(const Vector2 &p_begin, const Vector2 &p_end, Vector2 &r_point, Vector2 &r_normal) const {
	if (!Geometry2D::segment_intersects_segment(p_begin, p_end, a, b, &r_point)) {
		return false;
	}

	if (n.dot(p_begin) > n.dot(a)) {
		r_normal = n;
	} else {
		r_normal = -n;
	}

	return true;
}

real_t GodotSegmentShape2D::get_moment_of_inertia(real_t p_mass, const Size2 &p_scale) const {
	return p_mass * ((a * p_scale).distance_squared_to(b * p_scale)) / 12;
}

void GodotSegmentShape2D::set_data(const Variant &p_data) {
	ERR_FAIL_COND(p_data.get_type() != Variant::RECT2);

	Rect2 r = p_data;
	a = r.position;
	b = r.size;
	n = (b - a).orthogonal();

	Rect2 aabb_new;
	aabb_new.position = a;
	aabb_new.expand_to(b);
	if (aabb_new.size.x == 0) {
		aabb_new.size.x = 0.001;
	}
	if (aabb_new.size.y == 0) {
		aabb_new.size.y = 0.001;
	}
	configure(aabb_new);
}

Variant GodotSegmentShape2D::get_data() const {
	Rect2 r;
	r.position = a;
	r.size = b;
	return r;
}

/*********************************************************/
/*********************************************************/
/*********************************************************/

void GodotCircleShape2D::get_supports(const Vector2 &p_normal, Vector2 *r_supports, int &r_amount) const {
	r_amount = 1;
	*r_supports = p_normal * radius;
}

bool GodotCircleShape2D::contains_point(const Vector2 &p_point) const {
	return p_point.length_squared() < radius * radius;
}

bool GodotCircleShape2D::intersect_segment(const Vector2 &p_begin, const Vector2 &p_end, Vector2 &r_point, Vector2 &r_normal) const {
	const Vector2 direction = p_end - p_begin;
	const double dx = double(direction.x);
	const double dy = double(direction.y);
	const double length_squared = dx * dx + dy * dy;
	if (length_squared == 0.0) {
		return false; // A zero-length ray cannot enter a circle.
	}

	const double bx = double(p_begin.x);
	const double by = double(p_begin.y);
	const double radius_squared = double(radius) * double(radius);
	if (bx * bx + by * by < radius_squared) {
		return false; // Preserve entry-only semantics for a ray starting inside.
	}

	const double projection = -(bx * dx + by * dy) / length_squared;
	if (projection < 0.0) {
		return false; // The ray points away from the circle.
	}

	// Use closest approach, not a difference of squared terms or roots.
	// Those suffer catastrophic cancellation when the ray is very long.
	const double closest_x = bx + dx * projection;
	const double closest_y = by + dy * projection;
	const double closest_dist_sq = closest_x * closest_x + closest_y * closest_y;
	if (closest_dist_sq > radius_squared) {
		return false;
	}

	const double fraction = projection - Math::sqrt((radius_squared - closest_dist_sq) / length_squared);
	if (fraction < 0.0 || fraction > 1.0 + CMP_EPSILON) {
		return false;
	}

	// Avoid rounding the fraction to real_t before computing a long-ray hit.
	r_point = Vector2(real_t(bx + dx * fraction), real_t(by + dy * fraction));
	r_normal = r_point.normalized();
	return true;
}

real_t GodotCircleShape2D::get_moment_of_inertia(real_t p_mass, const Size2 &p_scale) const {
	real_t a = radius * p_scale.x;
	real_t b = radius * p_scale.y;
	return p_mass * (a * a + b * b) / 4;
}

void GodotCircleShape2D::set_data(const Variant &p_data) {
	ERR_FAIL_COND(!p_data.is_num());
	radius = p_data;
	configure(Rect2(-radius, -radius, radius * 2, radius * 2));
}

Variant GodotCircleShape2D::get_data() const {
	return radius;
}

/*********************************************************/
/*********************************************************/
/*********************************************************/

void GodotRectangleShape2D::get_supports(const Vector2 &p_normal, Vector2 *r_supports, int &r_amount) const {
	for (int i = 0; i < 2; i++) {
		Vector2 ag;
		ag[i] = 1.0;
		real_t dp = ag.dot(p_normal);
		if (Math::abs(dp) <= segment_is_valid_support_threshold) {
			continue;
		}

		real_t sgn = dp > 0 ? 1.0 : -1.0;

		r_amount = 2;

		r_supports[0][i] = half_extents[i] * sgn;
		r_supports[0][i ^ 1] = half_extents[i ^ 1];

		r_supports[1][i] = half_extents[i] * sgn;
		r_supports[1][i ^ 1] = -half_extents[i ^ 1];

		return;
	}

	/* USE POINT */

	r_amount = 1;
	r_supports[0] = Vector2(
			(p_normal.x < 0) ? -half_extents.x : half_extents.x,
			(p_normal.y < 0) ? -half_extents.y : half_extents.y);
}

bool GodotRectangleShape2D::contains_point(const Vector2 &p_point) const {
	real_t x = p_point.x;
	real_t y = p_point.y;
	real_t edge_x = half_extents.x;
	real_t edge_y = half_extents.y;
	return (x >= -edge_x) && (x < edge_x) && (y >= -edge_y) && (y < edge_y);
}

bool GodotRectangleShape2D::intersect_segment(const Vector2 &p_begin, const Vector2 &p_end, Vector2 &r_point, Vector2 &r_normal) const {
	return get_aabb().intersects_segment(p_begin, p_end, &r_point, &r_normal);
}

real_t GodotRectangleShape2D::get_moment_of_inertia(real_t p_mass, const Size2 &p_scale) const {
	Vector2 he2 = half_extents * 2 * p_scale;
	return p_mass * he2.dot(he2) / 12.0;
}

void GodotRectangleShape2D::set_data(const Variant &p_data) {
	ERR_FAIL_COND(p_data.get_type() != Variant::VECTOR2);

	half_extents = p_data;
	configure(Rect2(-half_extents, half_extents * 2.0));
}

Variant GodotRectangleShape2D::get_data() const {
	return half_extents;
}

/*********************************************************/
/*********************************************************/
/*********************************************************/

void GodotCapsuleShape2D::get_supports(const Vector2 &p_normal, Vector2 *r_supports, int &r_amount) const {
	Vector2 n = p_normal;

	real_t h = height * 0.5 - radius; // half-height of the rectangle part

	if (h > 0 && Math::abs(n.x) > segment_is_valid_support_threshold) {
		// make it flat
		n.y = 0.0;
		n.x = SIGN(n.x) * radius;

		r_amount = 2;
		r_supports[0] = n;
		r_supports[0].y += h;
		r_supports[1] = n;
		r_supports[1].y -= h;
	} else {
		n *= radius;
		n.y += (n.y > 0) ? h : -h;
		r_amount = 1;
		*r_supports = n;
	}
}

bool GodotCapsuleShape2D::contains_point(const Vector2 &p_point) const {
	Vector2 p = p_point;
	p.y = Math::abs(p.y);
	p.y -= height * 0.5 - radius;
	if (p.y < 0) {
		p.y = 0;
	}

	return p.length_squared() < radius * radius;
}

bool GodotCapsuleShape2D::intersect_segment(const Vector2 &p_begin, const Vector2 &p_end, Vector2 &r_point, Vector2 &r_normal) const {
	const Vector2 direction = p_end - p_begin;
	const real_t direction_length_squared = direction.length_squared();
	if (direction_length_squared == 0.0) {
		return false;
	}

	const Vector2 n = direction / Math::sqrt(direction_length_squared);
	real_t d = real_t(Math::INF);
	bool collided = false;

	// Check both end caps. The ray direction and its squared length do
	// not change when translated into either cap's local coordinates.
	for (int i = 0; i < 2; i++) {
		Vector2 begin = p_begin;
		const real_t ofs = (i == 0) ? -height * 0.5 + radius : height * 0.5 - radius;
		begin.y += ofs;

		const real_t half_b = begin.dot(direction);
		const real_t c = begin.length_squared() - radius * radius;
		if (c > 0.0 && half_b >= 0.0) {
			continue;
		}
		const real_t discriminant = half_b * half_b - direction_length_squared * c;
		if (discriminant < 0.0) {
			continue;
		}

		const real_t fraction = (-half_b - Math::sqrt(discriminant)) / direction_length_squared;
		if (fraction < 0.0 || fraction > 1.0 + CMP_EPSILON) {
			continue;
		}

		const Vector2 point = begin + direction * fraction;
		const Vector2 pointf(point.x, point.y - ofs);
		const real_t pd = n.dot(pointf);
		if (pd < d) {
			r_point = pointf;
			r_normal = point.normalized();
			d = pd;
			collided = true;
		}
	}

	Vector2 rpos, rnorm;
	if (Rect2(Point2(-radius, -height * 0.5 + radius), Size2(radius * 2.0, height - radius * 2)).intersects_segment(p_begin, p_end, &rpos, &rnorm)) {
		const real_t pd = n.dot(rpos);
		if (pd < d) {
			r_point = rpos;
			r_normal = rnorm;
			collided = true;
		}
	}

	return collided;
}

Vector2 GodotCapsuleShape2D::_get_second_moments() const {
	const double r = double(radius);
	const double straight_height = double(height) - 2.0 * r;
	const double cap_area = Math_PI * r * r;
	const double rect_area = 2.0 * r * straight_height;
	const double total_area = cap_area + rect_area;

	// Exact second moments of a vertical capsule about its centroid.
	// Combine the central rectangle with two semicircular end caps using
	// the parallel-axis theorem, including the semicircle centroid shift.
	const double second_x = (rect_area * r * r / 3.0 + cap_area * r * r / 4.0) / total_area;
	const double second_y = (rect_area * straight_height * straight_height / 12.0 +
			cap_area * (r * r / 4.0 + straight_height * straight_height / 4.0) +
			4.0 * straight_height * r * r * r / 3.0) / total_area;
	return Vector2(real_t(second_x), real_t(second_y));
}

real_t GodotCapsuleShape2D::get_moment_of_inertia(real_t p_mass, const Size2 &p_scale) const {
	if (radius <= 0.0 || height < 2.0 * radius) {
		// Preserve the previous bounded estimate for temporarily invalid shape data.
		const Vector2 bounds = Vector2(radius * 2.0, height) * p_scale;
		return p_mass * bounds.length_squared() / 12.0;
	}
	const Vector2 moments = _get_second_moments();
	return p_mass * (moments.x * p_scale.x * p_scale.x + moments.y * p_scale.y * p_scale.y);
}

real_t GodotCapsuleShape2D::get_moment_of_inertia_transformed(real_t p_mass, const Transform2D &p_transform) const {
	if (radius <= 0.0 || height < 2.0 * radius) {
		return get_moment_of_inertia(p_mass, p_transform.get_scale());
	}
	const Vector2 moments = _get_second_moments();
	return p_mass * (moments.x * p_transform.columns[0].length_squared() +
			moments.y * p_transform.columns[1].length_squared());
}

void GodotCapsuleShape2D::set_data(const Variant &p_data) {
	ERR_FAIL_COND(p_data.get_type() != Variant::ARRAY && p_data.get_type() != Variant::VECTOR2);

	if (p_data.get_type() == Variant::ARRAY) {
		Array arr = p_data;
		ERR_FAIL_COND(arr.size() != 2);
		height = arr[0];
		radius = arr[1];
	} else {
		Point2 p = p_data;
		radius = p.x;
		height = p.y;
	}

	Point2 he(radius, height * 0.5);
	configure(Rect2(-he, he * 2));
}

Variant GodotCapsuleShape2D::get_data() const {
	// Match set_data(Vector2) and PhysicsServer2D's (radius, height) convention.
	return Point2(radius, height);
}

/*********************************************************/
/*********************************************************/
/*********************************************************/

void GodotConvexPolygonShape2D::get_supports(const Vector2 &p_normal, Vector2 *r_supports, int &r_amount) const {
	r_amount = 0;
	ERR_FAIL_COND_MSG(point_count <= 0, "Convex polygon shape support not found.");

	// Initialize from a real vertex instead of a finite coordinate sentinel.
	// This remains correct even when every projection is below -1e10.
	int support_idx = 0;
	real_t best_projection = p_normal.dot(points[0].pos);
	for (int i = 0; i < point_count; i++) {
		const real_t projection = p_normal.dot(points[i].pos);
		if (projection > best_projection) {
			support_idx = i;
			best_projection = projection;
		}

		// A supporting edge produces a two-point contact manifold.
		if (points[i].normal.dot(p_normal) > segment_is_valid_support_threshold) {
			r_amount = 2;
			r_supports[0] = points[i].pos;
			r_supports[1] = points[(i + 1) % point_count].pos;
			return;
		}
	}
	r_amount = 1;
	r_supports[0] = points[support_idx].pos;
}

bool GodotConvexPolygonShape2D::contains_point(const Vector2 &p_point) const {
	if (valid_mass_properties && normals_generated_from_vertices) {
		// Normals generated from vertex edges have a known winding.
		// An exterior point can be rejected at its first separating edge.
		for (int i = 0; i < point_count; i++) {
			const real_t separation = points[i].normal.dot(p_point - points[i].pos);
			if (mass_clockwise ? (separation < 0.0) : (separation > 0.0)) {
				return false;
			}
		}
		return true;
	}

	// Preserve the sign-independent fallback for user-provided normals
	// and zero-area polygons, whose winding cannot be trusted.
	bool has_positive = false;
	bool has_negative = false;

	for (int i = 0; i < point_count; i++) {
		// A convex point is outside when two edges disagree on its side.
		// Zero-distance edges are neutral, so boundary hits work with
		// either vertex winding.
		const real_t d = points[i].normal.dot(p_point - points[i].pos);
		if (d > 0.0) {
			has_positive = true;
		} else if (d < 0.0) {
			has_negative = true;
		}
		if (has_positive && has_negative) {
			return false;
		}
	}

	return point_count > 0;
}

bool GodotConvexPolygonShape2D::intersect_segment(const Vector2 &p_begin, const Vector2 &p_end, Vector2 &r_point, Vector2 &r_normal) const {
	if (p_begin == p_end) {
		return false;
	}

	if (valid_mass_properties) {
		// Convex ray cast by clipping the segment against every edge half-plane.
		// This avoids one generic segment/segment intersection per polygon edge.
		// Keep the calculation in double precision to preserve the first hit
		// when the ray is very long or the polygon is far from the origin.
		const double dx = double(p_end.x) - double(p_begin.x);
		const double dy = double(p_end.y) - double(p_begin.y);
		double enter_fraction = 0.0;
		double exit_fraction = 1.0;
		int enter_edge = -1;
		int exit_edge = -1;

		for (int i = 0; i < point_count; i++) {
			const Vector2 &a = points[i].pos;
			const Vector2 &b = points[(i + 1) % point_count].pos;
			const double edge_x = double(b.x) - double(a.x);
			const double edge_y = double(b.y) - double(a.y);
			// Vector2::orthogonal() is outward for counter-clockwise polygons.
			const double outward_x = mass_clockwise ? -edge_y : edge_y;
			const double outward_y = mass_clockwise ? edge_x : -edge_x;
			const double distance = outward_x * (double(p_begin.x) - double(a.x)) +
					outward_y * (double(p_begin.y) - double(a.y));
			const double velocity = outward_x * dx + outward_y * dy;

			if (velocity == 0.0) {
				if (distance > 0.0) {
					return false;
				}
				continue;
			}

			const double fraction = -distance / velocity;
			if (velocity < 0.0) {
				if (fraction >= enter_fraction) {
					enter_fraction = fraction;
					enter_edge = i;
				}
			} else if (fraction <= exit_fraction) {
				exit_fraction = fraction;
				exit_edge = i;
			}
			if (enter_fraction > exit_fraction) {
				return false;
			}
		}

		// Prefer the first entering boundary. If the ray begins inside,
		// preserve the previous behavior by returning its first exit.
		const int hit_edge = enter_edge >= 0 ? enter_edge : exit_edge;
		const double fraction = enter_edge >= 0 ? enter_fraction : exit_fraction;
		if (hit_edge < 0 || fraction < 0.0 || fraction > 1.0) {
			return false;
		}
		r_point = Vector2(real_t(double(p_begin.x) + dx * fraction),
				real_t(double(p_begin.y) + dy * fraction));
		r_normal = points[hit_edge].normal;
		return true;
	}

	// Preserve the segment-based behavior for zero-area/degenerate polygons.
	const Vector2 direction = (p_end - p_begin).normalized();
	real_t closest_distance = 0.0;
	bool intersects = false;
	for (int i = 0; i < point_count; i++) {
		Vector2 hit;
		if (!Geometry2D::segment_intersects_segment(p_begin, p_end, points[i].pos, points[(i + 1) % point_count].pos, &hit)) {
			continue;
		}
		const real_t distance = direction.dot(hit);
		if (!intersects || distance < closest_distance) {
			closest_distance = distance;
			r_point = hit;
			r_normal = points[i].normal;
			intersects = true;
		}
	}
	return intersects;
}

real_t GodotConvexPolygonShape2D::get_moment_of_inertia(real_t p_mass, const Size2 &p_scale) const {
	ERR_FAIL_COND_V_MSG(point_count == 0, 0, "Convex polygon shape has no points.");
	if (valid_mass_properties) {
		// Exact (for uniform density) principal second moments around the polygon centroid.
		return p_mass * (mass_variance_x * p_scale.x * p_scale.x + mass_variance_y * p_scale.y * p_scale.y);
	}

	// Preserve the former behavior for degenerate/zero-area polygons.
	Rect2 aabb_new;
	aabb_new.position = points[0].pos * p_scale;
	for (int i = 1; i < point_count; i++) {
		aabb_new.expand_to(points[i].pos * p_scale);
	}
	return p_mass * aabb_new.size.dot(aabb_new.size) / 12.0;
}

real_t GodotConvexPolygonShape2D::get_moment_of_inertia_transformed(real_t p_mass, const Transform2D &p_transform) const {
	if (!valid_mass_properties) {
		return get_moment_of_inertia(p_mass, p_transform.get_scale());
	}

	// A linear map M transforms covariance C into M * C * M^T.
	// In 2D, angular inertia about the center is mass * trace(M * C * M^T).
	const Vector2 &basis_x = p_transform.columns[0];
	const Vector2 &basis_y = p_transform.columns[1];
	const real_t inertia_per_mass = mass_variance_x * basis_x.length_squared() +
			mass_variance_y * basis_y.length_squared() +
			real_t(2.0) * mass_covariance_xy * basis_x.dot(basis_y);
	return p_mass * MAX(inertia_per_mass, real_t(0.0));
}

void GodotConvexPolygonShape2D::set_data(const Variant &p_data) {
#ifdef REAL_T_IS_DOUBLE
	ERR_FAIL_COND(p_data.get_type() != Variant::PACKED_VECTOR2_ARRAY && p_data.get_type() != Variant::PACKED_FLOAT64_ARRAY);
#else
	ERR_FAIL_COND(p_data.get_type() != Variant::PACKED_VECTOR2_ARRAY && p_data.get_type() != Variant::PACKED_FLOAT32_ARRAY);
#endif

	if (points) {
		memdelete_arr(points);
	}
	points = nullptr;
	point_count = 0;
	mass_centroid = Vector2();
	mass_variance_x = 0.0;
	mass_variance_y = 0.0;
	mass_covariance_xy = 0.0;
	mass_area = 0.0;
	valid_mass_properties = false;
	mass_clockwise = false;
	normals_generated_from_vertices = false;

	if (p_data.get_type() == Variant::PACKED_VECTOR2_ARRAY) {
		Vector<Vector2> arr = p_data;
		ERR_FAIL_COND(arr.is_empty());
		point_count = arr.size();
		points = memnew_arr(Point, point_count);
		normals_generated_from_vertices = true;
		const Vector2 *r = arr.ptr();

		for (int i = 0; i < point_count; i++) {
			points[i].pos = r[i];
		}

		for (int i = 0; i < point_count; i++) {
			Vector2 p = points[i].pos;
			Vector2 pn = points[(i + 1) % point_count].pos;
			points[i].normal = (pn - p).orthogonal().normalized();
		}
	} else {
		Vector<real_t> dvr = p_data;
		point_count = dvr.size() / 4;
		ERR_FAIL_COND(point_count == 0);

		points = memnew_arr(Point, point_count);
		const real_t *r = dvr.ptr();

		for (int i = 0; i < point_count; i++) {
			int idx = i << 2;
			points[i].pos.x = r[idx + 0];
			points[i].pos.y = r[idx + 1];
			points[i].normal.x = r[idx + 2];
			points[i].normal.y = r[idx + 3];
		}
	}

	ERR_FAIL_COND(point_count == 0);
	Rect2 aabb_new;
	aabb_new.position = points[0].pos;
	for (int i = 1; i < point_count; i++) {
		aabb_new.expand_to(points[i].pos);
	}

	// Cache polygon centroid and second moments once when vertices change.
	// Using a vertex as reference reduces cancellation for distant polygons.
	// The signed ratios also work for either winding direction.
	if (point_count >= 3) {
		const Vector2 reference = points[0].pos;
		double twice_area = 0.0;
		double first_x = 0.0;
		double first_y = 0.0;
		double second_x = 0.0;
		double second_y = 0.0;
		double mixed_xy = 0.0;
		for (int i = 0; i < point_count; i++) {
			const Vector2 &a = points[i].pos;
			const Vector2 &b = points[(i + 1) % point_count].pos;
			const double ax = double(a.x) - double(reference.x);
			const double ay = double(a.y) - double(reference.y);
			const double bx = double(b.x) - double(reference.x);
			const double by = double(b.y) - double(reference.y);
			const double cross = ax * by - ay * bx;
			twice_area += cross;
			first_x += (ax + bx) * cross;
			first_y += (ay + by) * cross;
			second_x += (ax * ax + ax * bx + bx * bx) * cross;
			second_y += (ay * ay + ay * by + by * by) * cross;
			mixed_xy += (2.0 * ax * ay + ax * by + bx * ay + 2.0 * bx * by) * cross;
		}

		// An absolute threshold incorrectly rejects physically valid tiny shapes.
		// Use the local AABB area as a scale reference instead.
		const double area_scale = double(aabb_new.size.x) * double(aabb_new.size.y);
		if (Math::abs(twice_area) > 1.0e-12 * area_scale) {
			mass_clockwise = twice_area < 0.0;
			const double cx = first_x / (3.0 * twice_area);
			const double cy = first_y / (3.0 * twice_area);
			const double vx = second_x / (6.0 * twice_area) - cx * cx;
			const double vy = second_y / (6.0 * twice_area) - cy * cy;
			const double cxy = mixed_xy / (12.0 * twice_area) - cx * cy;
			mass_centroid = reference + Vector2(real_t(cx), real_t(cy));
			mass_variance_x = MAX(real_t(0.0), real_t(vx));
			mass_variance_y = MAX(real_t(0.0), real_t(vy));
			mass_covariance_xy = real_t(cxy);
			mass_area = real_t(0.5 * Math::abs(twice_area));
			valid_mass_properties = true;
		}
	}

	configure(aabb_new);
}

Variant GodotConvexPolygonShape2D::get_data() const {
	Vector<Vector2> dvr;

	dvr.resize(point_count);

	for (int i = 0; i < point_count; i++) {
		dvr.set(i, points[i].pos);
	}

	return dvr;
}

GodotConvexPolygonShape2D::~GodotConvexPolygonShape2D() {
	if (points) {
		memdelete_arr(points);
	}
}

//////////////////////////////////////////////////

void GodotConcavePolygonShape2D::get_supports(const Vector2 &p_normal, Vector2 *r_supports, int &r_amount) const {
	r_amount = 0;
	ERR_FAIL_COND(points.is_empty());

	// Use the first actual point instead of a fixed projection floor.
	int idx = 0;
	real_t best_projection = p_normal.dot(points[0]);
	for (int i = 1; i < points.size(); i++) {
		const real_t projection = p_normal.dot(points[i]);
		if (projection > best_projection) {
			best_projection = projection;
			idx = i;
		}
	}
	r_amount = 1;
	*r_supports = points[idx];
}

bool GodotConcavePolygonShape2D::contains_point(const Vector2 &p_point) const {
	return false; //sorry
}

bool GodotConcavePolygonShape2D::intersect_segment(const Vector2 &p_begin, const Vector2 &p_end, Vector2 &r_point, Vector2 &r_normal) const {
	if (segments.is_empty() || points.is_empty() || bvh.is_empty()) {
		return false;
	}

	uint32_t *stack = (uint32_t *)alloca(sizeof(int) * bvh_depth);

	enum {
		TEST_AABB_BIT = 0,
		VISIT_LEFT_BIT = 1,
		VISIT_RIGHT_BIT = 2,
		VISIT_DONE_BIT = 3,
		VISIT_RIGHT_FIRST_BIT = 4,
		VISIT_LEFT_SECOND_BIT = 5,
		VISITED_BIT_SHIFT = 29,
		NODE_IDX_MASK = (1 << VISITED_BIT_SHIFT) - 1,
		VISITED_BIT_MASK = ~NODE_IDX_MASK,

	};

	const Vector2 ray = p_end - p_begin;
	if (ray.length_squared() == 0.0) {
		return false;
	}
	const Vector2 n = ray.normalized();
	real_t d = 0.0;
	bool inters = false;

	/*
	for(int i=0;i<bvh_depth;i++)
		stack[i]=0;
	*/

	int level = 0;

	const Segment *segmentptr = &segments[0];
	const Vector2 *pointptr = &points[0];
	const BVH *bvhptr = &bvh[0];

	stack[0] = 0;
	while (true) {
		uint32_t node = stack[level] & NODE_IDX_MASK;
		const BVH &bvh2 = bvhptr[node];
		bool done = false;

		switch (stack[level] >> VISITED_BIT_SHIFT) {
			case TEST_AABB_BIT: {
				// Once a hit is known, skip nodes whose earliest possible point
				// along the ray is farther away than that hit (closest-hit pruning).
				bool valid = true;
				if (inters) {
					const Vector2 aabb_min = bvh2.aabb.position;
					const Vector2 aabb_max = bvh2.aabb.get_end();
					const real_t earliest = MIN(n.x * (aabb_min.x - p_begin.x), n.x * (aabb_max.x - p_begin.x)) +
							MIN(n.y * (aabb_min.y - p_begin.y), n.y * (aabb_max.y - p_begin.y));
					valid = earliest <= d;
				}
				if (valid) {
					valid = bvh2.aabb.intersects_segment(p_begin, p_end);
				}
				if (!valid) {
					stack[level] = (VISIT_DONE_BIT << VISITED_BIT_SHIFT) | node;

				} else {
					if (bvh2.left < 0) {
						const Segment &s = segmentptr[bvh2.right];
						Vector2 a = pointptr[s.points[0]];
						Vector2 b = pointptr[s.points[1]];

						Vector2 res;

						if (Geometry2D::segment_intersects_segment(p_begin, p_end, a, b, &res)) {
							const real_t nd = n.dot(res - p_begin);
							if (!inters || nd < d) {
								d = nd;
								r_point = res;
								r_normal = (b - a).orthogonal().normalized();
								inters = true;
							}
						}

						stack[level] = (VISIT_DONE_BIT << VISITED_BIT_SHIFT) | node;

					} else {
						// Visit the child whose AABB center is closer along the ray.
						// This improves the chance of finding a near hit before exploring
						// distant nodes, making the existing closest-hit pruning effective.
						const BVH &left = bvhptr[bvh2.left];
						const BVH &right = bvhptr[bvh2.right];
						const Vector2 center_delta = (left.aabb.position + left.aabb.size * real_t(0.5)) -
								(right.aabb.position + right.aabb.size * real_t(0.5));
						stack[level] = ((n.dot(center_delta) <= 0.0 ? VISIT_LEFT_BIT : VISIT_RIGHT_FIRST_BIT) << VISITED_BIT_SHIFT) | node;
					}
				}
			}
				continue;
			case VISIT_LEFT_BIT: {
				stack[level] = (VISIT_RIGHT_BIT << VISITED_BIT_SHIFT) | node;
				stack[level + 1] = bvh2.left | TEST_AABB_BIT;
				level++;
			}
				continue;
			case VISIT_RIGHT_BIT: {
				stack[level] = (VISIT_DONE_BIT << VISITED_BIT_SHIFT) | node;
				stack[level + 1] = bvh2.right | TEST_AABB_BIT;
				level++;
			}
				continue;
			case VISIT_RIGHT_FIRST_BIT: {
				stack[level] = (VISIT_LEFT_SECOND_BIT << VISITED_BIT_SHIFT) | node;
				stack[level + 1] = bvh2.right | TEST_AABB_BIT;
				level++;
			}
				continue;
			case VISIT_LEFT_SECOND_BIT: {
				stack[level] = (VISIT_DONE_BIT << VISITED_BIT_SHIFT) | node;
				stack[level + 1] = bvh2.left | TEST_AABB_BIT;
				level++;
			}
				continue;
			case VISIT_DONE_BIT: {
				if (level == 0) {
					done = true;
					break;
				} else {
					level--;
				}
			}
				continue;
		}

		if (done) {
			break;
		}
	}

	if (inters) {
		if (n.dot(r_normal) > 0) {
			r_normal = -r_normal;
		}
	}

	return inters;
}

int GodotConcavePolygonShape2D::_generate_bvh(BVH *p_bvh, int p_len, int p_depth) {
	if (p_len == 1) {
		bvh_depth = MAX(p_depth, bvh_depth);
		bvh.push_back(*p_bvh);
		return bvh.size() - 1;
	}

	//else sort best

	Rect2 global_aabb = p_bvh[0].aabb;
	for (int i = 1; i < p_len; i++) {
		global_aabb = global_aabb.merge(p_bvh[i].aabb);
	}

	// Only the median partition matters for BVH construction.
	// Selecting it instead of fully sorting every level reduces expected
	// build complexity from O(n log^2 n) to O(n log n).
	const int median = p_len / 2;
	if (global_aabb.size.x > global_aabb.size.y) {
		SortArray<BVH, BVH_CompareX> select;
		select.nth_element(0, p_len, median, p_bvh);
	} else {
		SortArray<BVH, BVH_CompareY> select;
		select.nth_element(0, p_len, median, p_bvh);
	}

	BVH node;
	node.aabb = global_aabb;
	int node_idx = bvh.size();
	bvh.push_back(node);

	int l = _generate_bvh(p_bvh, median, p_depth + 1);
	int r = _generate_bvh(&p_bvh[median], p_len - median, p_depth + 1);
	bvh.write[node_idx].left = l;
	bvh.write[node_idx].right = r;

	return node_idx;
}

void GodotConcavePolygonShape2D::set_data(const Variant &p_data) {
#ifdef REAL_T_IS_DOUBLE
	ERR_FAIL_COND(p_data.get_type() != Variant::PACKED_VECTOR2_ARRAY && p_data.get_type() != Variant::PACKED_FLOAT64_ARRAY);
#else
	ERR_FAIL_COND(p_data.get_type() != Variant::PACKED_VECTOR2_ARRAY && p_data.get_type() != Variant::PACKED_FLOAT32_ARRAY);
#endif

	Rect2 aabb_new;

	Vector<Vector2> p2arr;
	if (p_data.get_type() == Variant::PACKED_VECTOR2_ARRAY) {
		p2arr = p_data;
	} else {
		// Accept a flattened list of segment endpoints as well as Vector2 pairs.
		// Four scalar coordinates form one segment: x0, y0, x1, y1.
		Vector<real_t> scalars = p_data;
		ERR_FAIL_COND_MSG(scalars.size() % 4 != 0, "Concave polygon segment data must contain four scalars per segment.");
		p2arr.resize(scalars.size() / 2);
		Vector2 *dest = p2arr.ptrw();
		const real_t *values = scalars.ptr();
		for (int i = 0; i < p2arr.size(); i++) {
			dest[i] = Vector2(values[i * 2], values[i * 2 + 1]);
		}
	}

	{
		int len = p2arr.size();
		ERR_FAIL_COND(len % 2);

		segments.clear();
		points.clear();
		bvh.clear();
		bvh_depth = 1;

		if (len == 0) {
			configure(aabb_new);
			return;
		}

		const Vector2 *arr = p2arr.ptr();

		HashMap<Point2, int> pointmap;
		for (int i = 0; i < len; i += 2) {
			Point2 p1 = arr[i];
			Point2 p2 = arr[i + 1];
			int idx_p1, idx_p2;

			if (pointmap.has(p1)) {
				idx_p1 = pointmap[p1];
			} else {
				idx_p1 = pointmap.size();
				pointmap[p1] = idx_p1;
			}

			if (pointmap.has(p2)) {
				idx_p2 = pointmap[p2];
			} else {
				idx_p2 = pointmap.size();
				pointmap[p2] = idx_p2;
			}

			Segment s;
			s.points[0] = idx_p1;
			s.points[1] = idx_p2;
			segments.push_back(s);
		}

		points.resize(pointmap.size());
		aabb_new.position = pointmap.begin()->key;
		for (const KeyValue<Point2, int> &E : pointmap) {
			aabb_new.expand_to(E.key);
			points.write[E.value] = E.key;
		}

		Vector<BVH> main_vbh;
		main_vbh.resize(segments.size());
		for (int i = 0; i < main_vbh.size(); i++) {
			main_vbh.write[i].aabb.position = points[segments[i].points[0]];
			main_vbh.write[i].aabb.expand_to(points[segments[i].points[1]]);
			main_vbh.write[i].left = -1;
			main_vbh.write[i].right = i;
		}

		_generate_bvh(main_vbh.ptrw(), main_vbh.size(), 1);

	}

	configure(aabb_new);
}

Variant GodotConcavePolygonShape2D::get_data() const {
	Vector<Vector2> rsegments;
	int len = segments.size();
	rsegments.resize(len * 2);
	Vector2 *w = rsegments.ptrw();
	for (int i = 0; i < len; i++) {
		w[(i << 1) + 0] = points[segments[i].points[0]];
		w[(i << 1) + 1] = points[segments[i].points[1]];
	}

	return rsegments;
}

void GodotConcavePolygonShape2D::cull(const Rect2 &p_local_aabb, QueryCallback p_callback, void *p_userdata) const {
	uint32_t *stack = (uint32_t *)alloca(sizeof(int) * bvh_depth);

	enum {
		TEST_AABB_BIT = 0,
		VISIT_LEFT_BIT = 1,
		VISIT_RIGHT_BIT = 2,
		VISIT_DONE_BIT = 3,
		VISITED_BIT_SHIFT = 29,
		NODE_IDX_MASK = (1 << VISITED_BIT_SHIFT) - 1,
		VISITED_BIT_MASK = ~NODE_IDX_MASK,

	};

	/*
	for(int i=0;i<bvh_depth;i++)
		stack[i]=0;
	*/

	if (segments.is_empty() || points.is_empty() || bvh.is_empty()) {
		return;
	}

	int level = 0;

	const Segment *segmentptr = &segments[0];
	const Vector2 *pointptr = &points[0];
	const BVH *bvhptr = &bvh[0];

	stack[0] = 0;
	while (true) {
		uint32_t node = stack[level] & NODE_IDX_MASK;
		const BVH &bvh2 = bvhptr[node];

		switch (stack[level] >> VISITED_BIT_SHIFT) {
			case TEST_AABB_BIT: {
				bool valid = p_local_aabb.intersects(bvh2.aabb);
				if (!valid) {
					stack[level] = (VISIT_DONE_BIT << VISITED_BIT_SHIFT) | node;

				} else {
					if (bvh2.left < 0) {
						const Segment &s = segmentptr[bvh2.right];
						Vector2 a = pointptr[s.points[0]];
						Vector2 b = pointptr[s.points[1]];

						GodotSegmentShape2D ss(a, b, (b - a).orthogonal().normalized());

						if (p_callback(p_userdata, &ss)) {
							return;
						}
						stack[level] = (VISIT_DONE_BIT << VISITED_BIT_SHIFT) | node;

					} else {
						stack[level] = (VISIT_LEFT_BIT << VISITED_BIT_SHIFT) | node;
					}
				}
			}
				continue;
			case VISIT_LEFT_BIT: {
				stack[level] = (VISIT_RIGHT_BIT << VISITED_BIT_SHIFT) | node;
				stack[level + 1] = bvh2.left | TEST_AABB_BIT;
				level++;
			}
				continue;
			case VISIT_RIGHT_BIT: {
				stack[level] = (VISIT_DONE_BIT << VISITED_BIT_SHIFT) | node;
				stack[level + 1] = bvh2.right | TEST_AABB_BIT;
				level++;
			}
				continue;
			case VISIT_DONE_BIT: {
				if (level == 0) {
					return;
				} else {
					level--;
				}
			}
				continue;
		}
	}
}
