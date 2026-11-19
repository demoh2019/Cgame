/**************************************************************************/
/*  godot_collision_solver_2d_sat.cpp                                     */
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

#include "godot_collision_solver_2d_sat.h"

#include "core/math/geometry_2d.h"

struct _CollectorCallback2D {
	GodotCollisionSolver2D::CallbackResult callback = nullptr;
	void *userdata = nullptr;
	bool swap = false;
	bool collided = false;
	Vector2 normal;
	Vector2 *sep_axis = nullptr;

	_FORCE_INLINE_ void call(const Vector2 &p_point_A, const Vector2 &p_point_B) {
		if (swap) {
			callback(p_point_B, p_point_A, userdata);
		} else {
			callback(p_point_A, p_point_B, userdata);
		}
	}
};

typedef void (*GenerateContactsFunc)(const Vector2 *, int, const Vector2 *, int, _CollectorCallback2D *);

_FORCE_INLINE_ static void _generate_contacts_point_point(const Vector2 *p_points_A, int p_point_count_A, const Vector2 *p_points_B, int p_point_count_B, _CollectorCallback2D *p_collector) {
#ifdef DEBUG_ENABLED
	ERR_FAIL_COND(p_point_count_A != 1);
	ERR_FAIL_COND(p_point_count_B != 1);
#endif

	p_collector->call(*p_points_A, *p_points_B);
}

_FORCE_INLINE_ static void _generate_contacts_point_edge(const Vector2 *p_points_A, int p_point_count_A, const Vector2 *p_points_B, int p_point_count_B, _CollectorCallback2D *p_collector) {
#ifdef DEBUG_ENABLED
	ERR_FAIL_COND(p_point_count_A != 1);
	ERR_FAIL_COND(p_point_count_B != 2);
#endif

	Vector2 closest_B = Geometry2D::get_closest_point_to_segment_uncapped(*p_points_A, p_points_B[0], p_points_B[1]);
	p_collector->call(*p_points_A, closest_B);
}

struct _generate_contacts_Pair {
	bool a = false;
	int idx = 0;
	real_t d = 0.0;
	_FORCE_INLINE_ bool operator<(const _generate_contacts_Pair &l) const { return d < l.d; }
};

_FORCE_INLINE_ static void _generate_contacts_edge_edge(const Vector2 *p_points_A, int p_point_count_A, const Vector2 *p_points_B, int p_point_count_B, _CollectorCallback2D *p_collector) {
#ifdef DEBUG_ENABLED
	ERR_FAIL_COND(p_point_count_A != 2);
	ERR_FAIL_COND(p_point_count_B != 2); // circle is actually a 4x3 matrix
#endif

	Vector2 n = p_collector->normal;
	Vector2 t = n.orthogonal();
	real_t dA = n.dot(p_points_A[0]);
	real_t dB = n.dot(p_points_B[0]);

	_generate_contacts_Pair dvec[4];

	dvec[0].d = t.dot(p_points_A[0]);
	dvec[0].a = true;
	dvec[0].idx = 0;
	dvec[1].d = t.dot(p_points_A[1]);
	dvec[1].a = true;
	dvec[1].idx = 1;
	dvec[2].d = t.dot(p_points_B[0]);
	dvec[2].a = false;
	dvec[2].idx = 0;
	dvec[3].d = t.dot(p_points_B[1]);
	dvec[3].a = false;
	dvec[3].idx = 1;

	// A five-comparator sorting network for exactly four values.
	// Avoid the generic sorting machinery in this contact hot path.
	if (dvec[1] < dvec[0]) {
		SWAP(dvec[0], dvec[1]);
	}
	if (dvec[3] < dvec[2]) {
		SWAP(dvec[2], dvec[3]);
	}
	if (dvec[2] < dvec[0]) {
		SWAP(dvec[0], dvec[2]);
	}
	if (dvec[3] < dvec[1]) {
		SWAP(dvec[1], dvec[3]);
	}
	if (dvec[2] < dvec[1]) {
		SWAP(dvec[1], dvec[2]);
	}

	for (int i = 1; i <= 2; i++) {
		if (dvec[i].a) {
			Vector2 a = p_points_A[dvec[i].idx];
			Vector2 b = n.plane_project(dB, a);
			if (n.dot(a) > n.dot(b) - CMP_EPSILON) {
				continue;
			}
			p_collector->call(a, b);
		} else {
			Vector2 b = p_points_B[dvec[i].idx];
			Vector2 a = n.plane_project(dA, b);
			if (n.dot(a) > n.dot(b) - CMP_EPSILON) {
				continue;
			}
			p_collector->call(a, b);
		}
	}
}

static void _generate_contacts_from_supports(const Vector2 *p_points_A, int p_point_count_A, const Vector2 *p_points_B, int p_point_count_B, _CollectorCallback2D *p_collector) {
#ifdef DEBUG_ENABLED
	ERR_FAIL_COND(p_point_count_A < 1);
	ERR_FAIL_COND(p_point_count_B < 1);
#endif

	static const GenerateContactsFunc generate_contacts_func_table[2][2] = {
		{
				_generate_contacts_point_point,
				_generate_contacts_point_edge,
		},
		{
				nullptr,
				_generate_contacts_edge_edge,
		}
	};

	int pointcount_B = 0;
	int pointcount_A = 0;
	const Vector2 *points_A = nullptr;
	const Vector2 *points_B = nullptr;

	if (p_point_count_A > p_point_count_B) {
		//swap
		p_collector->swap = !p_collector->swap;
		p_collector->normal = -p_collector->normal;

		pointcount_B = p_point_count_A;
		pointcount_A = p_point_count_B;
		points_A = p_points_B;
		points_B = p_points_A;
	} else {
		pointcount_B = p_point_count_B;
		pointcount_A = p_point_count_A;
		points_A = p_points_A;
		points_B = p_points_B;
	}

	int version_A = (pointcount_A > 2 ? 2 : pointcount_A) - 1;
	int version_B = (pointcount_B > 2 ? 2 : pointcount_B) - 1;

	GenerateContactsFunc contacts_func = generate_contacts_func_table[version_A][version_B];
	ERR_FAIL_NULL(contacts_func);
	contacts_func(points_A, pointcount_A, points_B, pointcount_B, p_collector);
}

template <typename ShapeA, typename ShapeB>
class SeparatorAxisTest2D {
	const ShapeA *shape_A = nullptr;
	const ShapeB *shape_B = nullptr;
	const Transform2D *transform_A = nullptr;
	const Transform2D *transform_B = nullptr;
	real_t best_depth = 1e15;
	Vector2 best_axis;
#ifdef DEBUG_ENABLED
	int best_axis_count = 0;
	int best_axis_index = -1;
#endif
	Vector2 motion_A;
	Vector2 motion_B;
	bool cast_A = false;
	bool cast_B = false;
	bool with_margin = false;
	real_t margin_A = 0.0;
	real_t margin_B = 0.0;
	_CollectorCallback2D *callback;

public:
	_FORCE_INLINE_ bool test_previous_axis() {
		if (callback && callback->sep_axis && *callback->sep_axis != Vector2()) {
			return test_axis(*callback->sep_axis);
		} else {
#ifdef DEBUG_ENABLED
			best_axis_count++;
#endif
		}
		return true;
	}

	_FORCE_INLINE_ bool test_cast() {
		if (cast_A) {
			Vector2 na = motion_A.normalized();
			if (!test_axis(na)) {
				return false;
			}
			if (!test_axis(na.orthogonal())) {
				return false;
			}
		}

		if (cast_B) {
			Vector2 nb = motion_B.normalized();
			if (!test_axis(nb)) {
				return false;
			}
			if (!test_axis(nb.orthogonal())) {
				return false;
			}
		}

		return true;
	}

	_FORCE_INLINE_ bool test_axis(const Vector2 &p_axis) {
		Vector2 axis = p_axis;

		if (Math::is_zero_approx(axis.x) &&
				Math::is_zero_approx(axis.y)) {
			// strange case, try an upwards separator
			axis = Vector2(0.0, 1.0);
		}

		real_t min_A = 0.0, max_A = 0.0, min_B = 0.0, max_B = 0.0;

		if (cast_A) {
			shape_A->project_range_cast(motion_A, axis, *transform_A, min_A, max_A);
		} else {
			shape_A->project_range(axis, *transform_A, min_A, max_A);
		}

		if (cast_B) {
			shape_B->project_range_cast(motion_B, axis, *transform_B, min_B, max_B);
		} else {
			shape_B->project_range(axis, *transform_B, min_B, max_B);
		}

		if (with_margin) {
			min_A -= margin_A;
			max_A += margin_A;
			min_B -= margin_B;
			max_B += margin_B;
		}

		min_B -= (max_A - min_A) * 0.5;
		max_B += (max_A - min_A) * 0.5;

		real_t dmin = min_B - (min_A + max_A) * 0.5;
		real_t dmax = max_B - (min_A + max_A) * 0.5;

		if (dmin > 0.0 || dmax < 0.0) {
			if (callback && callback->sep_axis) {
				*callback->sep_axis = axis;
			}
#ifdef DEBUG_ENABLED
			best_axis_count++;
#endif

			return false; // doesn't contain 0
		}

		//use the smallest depth

		dmin = Math::abs(dmin);

		if (dmax < dmin) {
			if (dmax < best_depth) {
				best_depth = dmax;
				best_axis = axis;
#ifdef DEBUG_ENABLED
				best_axis_index = best_axis_count;
#endif
			}
		} else {
			if (dmin < best_depth) {
				best_depth = dmin;
				best_axis = -axis; // keep it as A axis
#ifdef DEBUG_ENABLED
				best_axis_index = best_axis_count;
#endif
			}
		}

#ifdef DEBUG_ENABLED
		best_axis_count++;
#endif

		return true;
	}

	_FORCE_INLINE_ void generate_contacts() {
		// nothing to do, don't generate
		if (best_axis == Vector2(0.0, 0.0)) {
			return;
		}

		if (callback) {
			callback->collided = true;

			if (!callback->callback) {
				return; //only collide, no callback
			}
		}
		static const int max_supports = 2;

		Vector2 supports_A[max_supports];
		int support_count_A;
		if (cast_A) {
			shape_A->get_supports_transformed_cast(motion_A, -best_axis, *transform_A, supports_A, support_count_A);
		} else {
			shape_A->get_supports(transform_A->basis_xform_inv(-best_axis).normalized(), supports_A, support_count_A);
			for (int i = 0; i < support_count_A; i++) {
				supports_A[i] = transform_A->xform(supports_A[i]);
			}
		}

		if (with_margin) {
			for (int i = 0; i < support_count_A; i++) {
				supports_A[i] += -best_axis * margin_A;
			}
		}

		Vector2 supports_B[max_supports];
		int support_count_B;
		if (cast_B) {
			shape_B->get_supports_transformed_cast(motion_B, best_axis, *transform_B, supports_B, support_count_B);
		} else {
			shape_B->get_supports(transform_B->basis_xform_inv(best_axis).normalized(), supports_B, support_count_B);
			for (int i = 0; i < support_count_B; i++) {
				supports_B[i] = transform_B->xform(supports_B[i]);
			}
		}

		if (with_margin) {
			for (int i = 0; i < support_count_B; i++) {
				supports_B[i] += best_axis * margin_B;
			}
		}
		if (callback) {
			callback->normal = best_axis;
			_generate_contacts_from_supports(supports_A, support_count_A, supports_B, support_count_B, callback);

			if (callback->sep_axis && *callback->sep_axis != Vector2()) {
				*callback->sep_axis = Vector2(); //invalidate previous axis (no test)
			}
		}
	}

	_FORCE_INLINE_ SeparatorAxisTest2D(const ShapeA *p_shape_A, const Transform2D &p_transform_a, const ShapeB *p_shape_B, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_A, const Vector2 &p_motion_B, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A = 0, real_t p_margin_B = 0) {
		margin_A = p_margin_A;
		margin_B = p_margin_B;
		shape_A = p_shape_A;
		shape_B = p_shape_B;
		transform_A = &p_transform_a;
		transform_B = &p_transform_b;
		motion_A = p_motion_A;
		motion_B = p_motion_B;
		cast_A = p_cast_A;
		cast_B = p_cast_B;
		with_margin = p_with_margin;
		callback = p_collector;
	}
};

/****** SAT TESTS *******/

#define TEST_POINT(m_a, m_b) \
	((!separator.test_axis(((m_a) - (m_b)).normalized())) || \
			(p_cast_A && !separator.test_axis(((m_a) + p_motion_a - (m_b)).normalized())) || \
			(p_cast_B && !separator.test_axis(((m_a) - ((m_b) + p_motion_b)).normalized())) || \
			(p_cast_A && p_cast_B && !separator.test_axis(((m_a) + p_motion_a - ((m_b) + p_motion_b)).normalized())))

typedef void (*CollisionFunc)(const GodotShape2D *, const Transform2D &, const GodotShape2D *, const Transform2D &, _CollectorCallback2D *p_collector, const Vector2 &, const Vector2 &, bool, bool, bool, real_t, real_t);

static void _collision_segment_segment(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotSegmentShape2D *segment_A = static_cast<const GodotSegmentShape2D *>(p_a);
	const GodotSegmentShape2D *segment_B = static_cast<const GodotSegmentShape2D *>(p_b);

	SeparatorAxisTest2D<GodotSegmentShape2D, GodotSegmentShape2D> separator(segment_A, p_transform_a, segment_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}
	//this collision is kind of pointless

	if (!separator.test_cast()) {
		return;
	}

	if (!separator.test_axis(segment_A->get_xformed_normal(p_transform_a))) {
		return;
	}
	if (!separator.test_axis(segment_B->get_xformed_normal(p_transform_b))) {
		return;
	}

	if (p_with_margin) {
		//points grow to circles

		if (TEST_POINT(p_transform_a.xform(segment_A->get_a()), p_transform_b.xform(segment_B->get_a()))) {
			return;
		}
		if (TEST_POINT(p_transform_a.xform(segment_A->get_a()), p_transform_b.xform(segment_B->get_b()))) {
			return;
		}
		if (TEST_POINT(p_transform_a.xform(segment_A->get_b()), p_transform_b.xform(segment_B->get_a()))) {
			return;
		}
		if (TEST_POINT(p_transform_a.xform(segment_A->get_b()), p_transform_b.xform(segment_B->get_b()))) {
			return;
		}
	}

	separator.generate_contacts();
}

// Shared by the analytic narrow-phase paths below.
_FORCE_INLINE_ static bool _is_unit_orthogonal_transform(const Transform2D &p_transform);

static void _collision_segment_circle(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotSegmentShape2D *segment_A = static_cast<const GodotSegmentShape2D *>(p_a);
	const GodotCircleShape2D *circle_B = static_cast<const GodotCircleShape2D *>(p_b);

	// Like Box2D's specialized segment/circle manifold, use the closest point
	// on the segment instead of projecting both shapes onto multiple SAT axes.
	// Swept shapes, non-rigid transforms, and degenerate cases retain SAT.
	if (!p_cast_A && !p_cast_B && p_margin_A >= 0.0 && p_margin_B >= 0.0 &&
			circle_B->get_radius() >= 0.0 && _is_unit_orthogonal_transform(p_transform_a) &&
			_is_unit_orthogonal_transform(p_transform_b)) {
		const Vector2 segment_start = p_transform_a.xform(segment_A->get_a());
		const Vector2 segment_direction = p_transform_a.xform(segment_A->get_b()) - segment_start;
		const real_t segment_length_squared = segment_direction.length_squared();
		if (segment_length_squared > CMP_EPSILON * CMP_EPSILON) {
			const Vector2 center = p_transform_b.get_origin();
			const real_t fraction = CLAMP((center - segment_start).dot(segment_direction) / segment_length_squared, real_t(0.0), real_t(1.0));
			const Vector2 closest = segment_start + segment_direction * fraction;
			const Vector2 separation = closest - center;
			const real_t distance_squared = separation.length_squared();

			// The SAT fallback provides a stable axis for coincident points.
			if (distance_squared > 0.0) {
				const real_t radius = circle_B->get_radius() + p_margin_B;
				const real_t combined_radius = radius + p_margin_A;
				if (distance_squared > combined_radius * combined_radius) {
					if (p_collector->sep_axis) {
						*p_collector->sep_axis = separation / Math::sqrt(distance_squared);
					}
					return;
				}

				p_collector->collided = true;
				if (p_collector->callback) {
					const Vector2 normal = separation / Math::sqrt(distance_squared);
					p_collector->normal = normal;
					p_collector->call(closest - normal * p_margin_A, center + normal * radius);
				}
				if (p_collector->sep_axis) {
					*p_collector->sep_axis = Vector2();
				}
				return;
			}
		}
	}

	SeparatorAxisTest2D<GodotSegmentShape2D, GodotCircleShape2D> separator(segment_A, p_transform_a, circle_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	if (!separator.test_cast()) {
		return;
	}

	//segment normal
	if (!separator.test_axis(
				(p_transform_a.xform(segment_A->get_b()) - p_transform_a.xform(segment_A->get_a())).normalized().orthogonal())) {
		return;
	}

	//endpoint a vs circle
	if (TEST_POINT(p_transform_a.xform(segment_A->get_a()), p_transform_b.get_origin())) {
		return;
	}
	//endpoint b vs circle
	if (TEST_POINT(p_transform_a.xform(segment_A->get_b()), p_transform_b.get_origin())) {
		return;
	}

	separator.generate_contacts();
}

static void _collision_segment_rectangle(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotSegmentShape2D *segment_A = static_cast<const GodotSegmentShape2D *>(p_a);
	const GodotRectangleShape2D *rectangle_B = static_cast<const GodotRectangleShape2D *>(p_b);

	SeparatorAxisTest2D<GodotSegmentShape2D, GodotRectangleShape2D> separator(segment_A, p_transform_a, rectangle_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	if (!separator.test_cast()) {
		return;
	}

	if (!separator.test_axis(segment_A->get_xformed_normal(p_transform_a))) {
		return;
	}

	if (!separator.test_axis(p_transform_b.columns[0].normalized())) {
		return;
	}

	if (!separator.test_axis(p_transform_b.columns[1].normalized())) {
		return;
	}

	if (p_with_margin) {
		Transform2D inv = p_transform_b.affine_inverse();

		Vector2 a = p_transform_a.xform(segment_A->get_a());
		Vector2 b = p_transform_a.xform(segment_A->get_b());

		if (!separator.test_axis(rectangle_B->get_circle_axis(p_transform_b, inv, a))) {
			return;
		}
		if (!separator.test_axis(rectangle_B->get_circle_axis(p_transform_b, inv, b))) {
			return;
		}

		if (p_cast_A) {
			if (!separator.test_axis(rectangle_B->get_circle_axis(p_transform_b, inv, a + p_motion_a))) {
				return;
			}
			if (!separator.test_axis(rectangle_B->get_circle_axis(p_transform_b, inv, b + p_motion_a))) {
				return;
			}
		}

		if (p_cast_B) {
			if (!separator.test_axis(rectangle_B->get_circle_axis(p_transform_b, inv, a - p_motion_b))) {
				return;
			}
			if (!separator.test_axis(rectangle_B->get_circle_axis(p_transform_b, inv, b - p_motion_b))) {
				return;
			}
		}

		if (p_cast_A && p_cast_B) {
			if (!separator.test_axis(rectangle_B->get_circle_axis(p_transform_b, inv, a - p_motion_b + p_motion_a))) {
				return;
			}
			if (!separator.test_axis(rectangle_B->get_circle_axis(p_transform_b, inv, b - p_motion_b + p_motion_a))) {
				return;
			}
		}
	}

	separator.generate_contacts();
}

static void _collision_segment_capsule(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotSegmentShape2D *segment_A = static_cast<const GodotSegmentShape2D *>(p_a);
	const GodotCapsuleShape2D *capsule_B = static_cast<const GodotCapsuleShape2D *>(p_b);

	// Closest-segment distance is sufficient for overlap-only queries.
	// Contacts still use SAT to preserve edge manifolds, warm-start impulses
	// and stable face normals in stacking configurations.
	const real_t half_capsule_segment = capsule_B->get_height() * real_t(0.5) - capsule_B->get_radius();
	if (!p_cast_A && !p_cast_B && !p_collector->callback && p_margin_A >= 0.0 && p_margin_B >= 0.0 &&
			capsule_B->get_radius() >= 0.0 && half_capsule_segment >= 0.0 &&
			_is_unit_orthogonal_transform(p_transform_a) && _is_unit_orthogonal_transform(p_transform_b)) {
		const Vector2 segment_start = p_transform_a.xform(segment_A->get_a());
		const Vector2 segment_end = p_transform_a.xform(segment_A->get_b());
		if (segment_start.distance_squared_to(segment_end) > CMP_EPSILON2) {
			const Vector2 capsule_offset = p_transform_b.columns[1] * half_capsule_segment;
			const Vector2 capsule_center = p_transform_b.get_origin();
			Vector2 closest_segment;
			Vector2 closest_capsule;
			const real_t distance = Geometry2D::get_closest_points_between_segments(
					segment_start, segment_end,
					capsule_center - capsule_offset, capsule_center + capsule_offset,
					closest_segment, closest_capsule);
			const real_t combined_radius = capsule_B->get_radius() + p_margin_A + p_margin_B;

			if (distance > combined_radius) {
				if (p_collector->sep_axis) {
					*p_collector->sep_axis = (closest_segment - closest_capsule) / distance;
				}
				return;
			}

			p_collector->collided = true;
			if (p_collector->sep_axis) {
				*p_collector->sep_axis = Vector2();
			}
			return;
		}
	}

	SeparatorAxisTest2D<GodotSegmentShape2D, GodotCapsuleShape2D> separator(segment_A, p_transform_a, capsule_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	if (!separator.test_cast()) {
		return;
	}

	if (!separator.test_axis(segment_A->get_xformed_normal(p_transform_a))) {
		return;
	}

	if (!separator.test_axis(p_transform_b.columns[0].normalized())) {
		return;
	}

	real_t capsule_dir = capsule_B->get_height() * 0.5 - capsule_B->get_radius();

	if (TEST_POINT(p_transform_a.xform(segment_A->get_a()), (p_transform_b.get_origin() + p_transform_b.columns[1] * capsule_dir))) {
		return;
	}
	if (TEST_POINT(p_transform_a.xform(segment_A->get_a()), (p_transform_b.get_origin() - p_transform_b.columns[1] * capsule_dir))) {
		return;
	}
	if (TEST_POINT(p_transform_a.xform(segment_A->get_b()), (p_transform_b.get_origin() + p_transform_b.columns[1] * capsule_dir))) {
		return;
	}
	if (TEST_POINT(p_transform_a.xform(segment_A->get_b()), (p_transform_b.get_origin() - p_transform_b.columns[1] * capsule_dir))) {
		return;
	}

	separator.generate_contacts();
}

static void _collision_segment_convex_polygon(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotSegmentShape2D *segment_A = static_cast<const GodotSegmentShape2D *>(p_a);
	const GodotConvexPolygonShape2D *convex_B = static_cast<const GodotConvexPolygonShape2D *>(p_b);

	SeparatorAxisTest2D<GodotSegmentShape2D, GodotConvexPolygonShape2D> separator(segment_A, p_transform_a, convex_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	if (!separator.test_cast()) {
		return;
	}

	if (!separator.test_axis(segment_A->get_xformed_normal(p_transform_a))) {
		return;
	}

	for (int i = 0; i < convex_B->get_point_count(); i++) {
		if (!separator.test_axis(convex_B->get_xformed_segment_normal(p_transform_b, i))) {
			return;
		}

		if (p_with_margin) {
			if (TEST_POINT(p_transform_a.xform(segment_A->get_a()), p_transform_b.xform(convex_B->get_point(i)))) {
				return;
			}
			if (TEST_POINT(p_transform_a.xform(segment_A->get_b()), p_transform_b.xform(convex_B->get_point(i)))) {
				return;
			}
		}
	}

	separator.generate_contacts();
}

/////////

_FORCE_INLINE_ static bool _is_unit_orthogonal_transform(const Transform2D &p_transform) {
	return Math::is_equal_approx(p_transform.columns[0].length_squared(), real_t(1.0)) &&
			Math::is_equal_approx(p_transform.columns[1].length_squared(), real_t(1.0)) &&
			Math::is_zero_approx(p_transform.columns[0].dot(p_transform.columns[1]));
}

static void _collision_circle_circle(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotCircleShape2D *circle_A = static_cast<const GodotCircleShape2D *>(p_a);
	const GodotCircleShape2D *circle_B = static_cast<const GodotCircleShape2D *>(p_b);

	// Like the direct circle manifold used by Box2D, avoid general SAT and
	// support-point generation for stationary, rigidly transformed circles.
	// Non-uniform scale, shear and swept shapes retain the original SAT path.
	if (!p_cast_A && !p_cast_B && _is_unit_orthogonal_transform(p_transform_a) && _is_unit_orthogonal_transform(p_transform_b)) {
		const real_t radius_A = circle_A->get_radius() + p_margin_A;
		const real_t radius_B = circle_B->get_radius() + p_margin_B;
		const real_t combined_radius = radius_A + radius_B;
		const Vector2 separation = p_transform_a.get_origin() - p_transform_b.get_origin();
		const real_t distance_squared = separation.length_squared();

		// Coincident centers are handled by SAT to retain its previous-axis
		// behavior. Negative effective radii are not valid for this shortcut.
		if (radius_A >= 0.0 && radius_B >= 0.0 && distance_squared > 0.0) {
			if (distance_squared > combined_radius * combined_radius) {
				if (p_collector->sep_axis) {
					*p_collector->sep_axis = separation / Math::sqrt(distance_squared);
				}
				return;
			}

			p_collector->collided = true;
			if (p_collector->callback) {
				const Vector2 axis = separation / Math::sqrt(distance_squared);
				p_collector->normal = axis;
				p_collector->call(p_transform_a.get_origin() - axis * radius_A,
						p_transform_b.get_origin() + axis * radius_B);
				if (p_collector->sep_axis && *p_collector->sep_axis != Vector2()) {
					*p_collector->sep_axis = Vector2();
				}
			}
			return;
		}
	}

	SeparatorAxisTest2D<GodotCircleShape2D, GodotCircleShape2D> separator(circle_A, p_transform_a, circle_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	if (!separator.test_cast()) {
		return;
	}

	if (TEST_POINT(p_transform_a.get_origin(), p_transform_b.get_origin())) {
		return;
	}

	separator.generate_contacts();
}

static void _collision_circle_rectangle(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotCircleShape2D *circle_A = static_cast<const GodotCircleShape2D *>(p_a);
	const GodotRectangleShape2D *rectangle_B = static_cast<const GodotRectangleShape2D *>(p_b);

// Specialized circle/rectangle manifold for rigid transforms. The generic SAT
	// path below handles degenerate rectangles, scaling, shearing and swept shapes.
	if (!p_cast_A && !p_cast_B && p_margin_A >= 0.0 && p_margin_B >= 0.0 &&
			circle_A->get_radius() >= 0.0 && _is_unit_orthogonal_transform(p_transform_a) &&
			_is_unit_orthogonal_transform(p_transform_b)) {
		const Vector2 center = p_transform_a.get_origin();
		const Vector2 local_center = p_transform_b.basis_xform_inv(center - p_transform_b.get_origin());
		const Vector2 half_extents = rectangle_B->get_half_extents();
		const Vector2 closest_local(
				CLAMP(local_center.x, -half_extents.x, half_extents.x),
				CLAMP(local_center.y, -half_extents.y, half_extents.y));
		const Vector2 closest = p_transform_b.xform(closest_local);
		const Vector2 separation = center - closest;
		const real_t distance_squared = separation.length_squared();

		// Box2D-style embedded circle/rectangle manifold: a fully contained
		// center is not a closest-point separation test. Select the nearest
		// *exit* face in the box's local space and use the opposite support
		// point on the circle. This produces a positive penetration depth
		// even for a circle that fits completely inside the rectangle.
		// The basis is guaranteed unit-orthogonal by the guard above.
		if (half_extents.x > real_t(0.0) && half_extents.y > real_t(0.0) &&
				Math::abs(local_center.x) <= half_extents.x &&
				Math::abs(local_center.y) <= half_extents.y) {
			const real_t clearance_x = half_extents.x - Math::abs(local_center.x);
			const real_t clearance_y = half_extents.y - Math::abs(local_center.y);
			const bool nearest_x_face = clearance_x <= clearance_y;
			const Vector2 local_exit_normal = nearest_x_face ?
					Vector2(local_center.x < 0.0 ? -1.0 : 1.0, 0.0) :
					Vector2(0.0, local_center.y < 0.0 ? -1.0 : 1.0);
			const Vector2 exit_normal = p_transform_b.basis_xform(local_exit_normal);
			const Vector2 normal = -exit_normal;
			const real_t circle_radius = circle_A->get_radius() + p_margin_A;
			const real_t nearest_face_distance = nearest_x_face ? clearance_x : clearance_y;

			p_collector->collided = true;
			if (p_collector->callback) {
				p_collector->normal = normal;
				p_collector->call(center + normal * circle_radius,
						center + exit_normal * (nearest_face_distance + p_margin_B));
				if (p_collector->sep_axis && *p_collector->sep_axis != Vector2()) {
					*p_collector->sep_axis = Vector2();
				}
			}
			return;
		}

		// The regular closest-point path only handles centers outside the
		// rectangle. Leave all degenerate cases to the general SAT solver.
		if (distance_squared > 0.0) {
			const real_t circle_radius = circle_A->get_radius() + p_margin_A;
			const real_t combined_radius = circle_radius + p_margin_B;
			if (distance_squared > combined_radius * combined_radius) {
				if (p_collector->sep_axis) {
					*p_collector->sep_axis = separation / Math::sqrt(distance_squared);
				}
				return;
			}

			p_collector->collided = true;
			if (p_collector->callback) {
				const Vector2 normal = separation / Math::sqrt(distance_squared);
				p_collector->normal = normal;
				p_collector->call(center - normal * circle_radius, closest + normal * p_margin_B);
				if (p_collector->sep_axis && *p_collector->sep_axis != Vector2()) {
					*p_collector->sep_axis = Vector2();
				}
			}
			return;
		}
	}

	SeparatorAxisTest2D<GodotCircleShape2D, GodotRectangleShape2D> separator(circle_A, p_transform_a, rectangle_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	if (!separator.test_cast()) {
		return;
	}

	const Vector2 &sphere = p_transform_a.columns[2];
	const Vector2 *axis = &p_transform_b.columns[0];
	//const Vector2& half_extents = rectangle_B->get_half_extents();

	if (!separator.test_axis(axis[0].normalized())) {
		return;
	}

	if (!separator.test_axis(axis[1].normalized())) {
		return;
	}

	Transform2D binv = p_transform_b.affine_inverse();
	{
		if (!separator.test_axis(rectangle_B->get_circle_axis(p_transform_b, binv, sphere))) {
			return;
		}
	}

	if (p_cast_A) {
		Vector2 sphereofs = sphere + p_motion_a;
		if (!separator.test_axis(rectangle_B->get_circle_axis(p_transform_b, binv, sphereofs))) {
			return;
		}
	}

	if (p_cast_B) {
		Vector2 sphereofs = sphere - p_motion_b;
		if (!separator.test_axis(rectangle_B->get_circle_axis(p_transform_b, binv, sphereofs))) {
			return;
		}
	}

	if (p_cast_A && p_cast_B) {
		Vector2 sphereofs = sphere - p_motion_b + p_motion_a;
		if (!separator.test_axis(rectangle_B->get_circle_axis(p_transform_b, binv, sphereofs))) {
			return;
		}
	}

	separator.generate_contacts();
}

static void _collision_circle_capsule(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotCircleShape2D *circle_A = static_cast<const GodotCircleShape2D *>(p_a);
	const GodotCapsuleShape2D *capsule_B = static_cast<const GodotCapsuleShape2D *>(p_b);

	// Like the specialized capsule/circle manifold in Box2D, find the nearest
	// point on the capsule's center segment instead of testing multiple SAT axes.
	// Preserve the SAT path for moving, scaled, degenerate or coincident shapes.
	const real_t half_segment = capsule_B->get_height() * real_t(0.5) - capsule_B->get_radius();
	if (!p_cast_A && !p_cast_B && p_margin_A >= 0.0 && p_margin_B >= 0.0 &&
			circle_A->get_radius() >= 0.0 && capsule_B->get_radius() >= 0.0 &&
			half_segment >= 0.0 && _is_unit_orthogonal_transform(p_transform_a) &&
			_is_unit_orthogonal_transform(p_transform_b)) {
		const Vector2 center_A = p_transform_a.get_origin();
		const Vector2 center_B = p_transform_b.get_origin();
		const Vector2 capsule_axis = p_transform_b.columns[1];
		const real_t position = CLAMP((center_A - center_B).dot(capsule_axis), -half_segment, half_segment);
		const Vector2 closest_B = center_B + capsule_axis * position;
		const Vector2 difference = center_A - closest_B;
		const real_t distance_squared = difference.length_squared();

		// At an exact centerline coincidence the SAT solver determines a stable
		// contact direction from the capsule axis (or its cached separating axis).
		if (distance_squared > 0.0) {
			const real_t radius_A = circle_A->get_radius() + p_margin_A;
			const real_t radius_B = capsule_B->get_radius() + p_margin_B;
			const real_t total_radius = radius_A + radius_B;
			if (distance_squared > total_radius * total_radius) {
				if (p_collector->sep_axis) {
					*p_collector->sep_axis = difference / Math::sqrt(distance_squared);
				}
				return;
			}

			p_collector->collided = true;
			if (p_collector->callback) {
				const Vector2 normal = difference / Math::sqrt(distance_squared);
				p_collector->normal = normal;
				p_collector->call(center_A - normal * radius_A, closest_B + normal * radius_B);
				if (p_collector->sep_axis && *p_collector->sep_axis != Vector2()) {
					*p_collector->sep_axis = Vector2();
				}
			}
			return;
		}
	}

	SeparatorAxisTest2D<GodotCircleShape2D, GodotCapsuleShape2D> separator(circle_A, p_transform_a, capsule_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	if (!separator.test_cast()) {
		return;
	}

	//capsule axis
	if (!separator.test_axis(p_transform_b.columns[0].normalized())) {
		return;
	}

	real_t capsule_dir = capsule_B->get_height() * 0.5 - capsule_B->get_radius();

	//capsule endpoints
	if (TEST_POINT(p_transform_a.get_origin(), (p_transform_b.get_origin() + p_transform_b.columns[1] * capsule_dir))) {
		return;
	}
	if (TEST_POINT(p_transform_a.get_origin(), (p_transform_b.get_origin() - p_transform_b.columns[1] * capsule_dir))) {
		return;
	}

	separator.generate_contacts();
}

static void _collision_circle_convex_polygon(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotCircleShape2D *circle_A = static_cast<const GodotCircleShape2D *>(p_a);
	const GodotConvexPolygonShape2D *convex_B = static_cast<const GodotConvexPolygonShape2D *>(p_b);

	// Specialized circle/polygon narrow phase inspired by Box2D: compare the
	// circle against the nearest polygon boundary point in polygon-local space.
	// This avoids SAT support projections on separated and exterior contacts.
	// Embedded centers, degenerate edges, casts and non-rigid transforms use SAT.
	if (!p_cast_A && !p_cast_B && p_margin_A >= 0.0 && p_margin_B >= 0.0 &&
			circle_A->get_radius() >= 0.0 && convex_B->get_point_count() >= 3 &&
			_is_unit_orthogonal_transform(p_transform_a) &&
			_is_unit_orthogonal_transform(p_transform_b)) {
		const Vector2 center_world = p_transform_a.get_origin();
		const Vector2 center_local = p_transform_b.basis_xform_inv(center_world - p_transform_b.get_origin());
		const int point_count = convex_B->get_point_count();
		real_t distance_squared = -1.0;
		Vector2 closest_local;
		bool has_positive_cross = false;
		bool has_negative_cross = false;
		bool valid_edges = true;

		for (int i = 0; i < point_count; i++) {
			const Vector2 start = convex_B->get_point(i);
			const Vector2 end = convex_B->get_point(i + 1 == point_count ? 0 : i + 1);
			const Vector2 edge = end - start;
			const real_t edge_length_squared = edge.length_squared();
			if (edge_length_squared <= CMP_EPSILON * CMP_EPSILON) {
				valid_edges = false;
				break;
			}

			const Vector2 from_start = center_local - start;
			const real_t cross = edge.cross(from_start);
			has_positive_cross |= cross > 0.0;
			has_negative_cross |= cross < 0.0;

			const real_t fraction = CLAMP(from_start.dot(edge) / edge_length_squared, real_t(0.0), real_t(1.0));
			const Vector2 candidate = start + edge * fraction;
			const real_t candidate_distance_squared = center_local.distance_squared_to(candidate);
			if (distance_squared < 0.0 || candidate_distance_squared < distance_squared) {
				distance_squared = candidate_distance_squared;
				closest_local = candidate;
			}
		}

		// Interior containment is sufficient for overlap-only queries; they
		// do not need a contact normal or SAT support projections.
		if (valid_edges && (has_positive_cross != has_negative_cross) && !p_collector->callback) {
			p_collector->collided = true;
			if (p_collector->sep_axis) {
				*p_collector->sep_axis = Vector2();
			}
			return;
		}

		// A valid convex polygon has a consistent edge orientation. If the
		// center is inside (or on the boundary), SAT retains its stable normal.
		if (valid_edges && has_positive_cross && has_negative_cross && distance_squared > 0.0) {
			const real_t radius_A = circle_A->get_radius() + p_margin_A;
			const real_t total_radius = radius_A + p_margin_B;
			const Vector2 outward_local = center_local - closest_local;
			if (distance_squared > total_radius * total_radius) {
				if (p_collector->sep_axis) {
					*p_collector->sep_axis = p_transform_b.basis_xform(outward_local / Math::sqrt(distance_squared));
				}
				return;
			}

			p_collector->collided = true;
			if (p_collector->callback) {
				const Vector2 normal = p_transform_b.basis_xform(outward_local / Math::sqrt(distance_squared));
				p_collector->normal = normal;
				p_collector->call(center_world - normal * radius_A,
						p_transform_b.xform(closest_local) + normal * p_margin_B);
			}
			if (p_collector->sep_axis) {
				*p_collector->sep_axis = Vector2();
			}
			return;
		}
	}

	SeparatorAxisTest2D<GodotCircleShape2D, GodotConvexPolygonShape2D> separator(circle_A, p_transform_a, convex_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	if (!separator.test_cast()) {
		return;
	}

	//poly faces and poly points vs circle
	for (int i = 0; i < convex_B->get_point_count(); i++) {
		if (TEST_POINT(p_transform_a.get_origin(), p_transform_b.xform(convex_B->get_point(i)))) {
			return;
		}

		if (!separator.test_axis(convex_B->get_xformed_segment_normal(p_transform_b, i))) {
			return;
		}
	}

	separator.generate_contacts();
}

/////////

static void _collision_rectangle_rectangle(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotRectangleShape2D *rectangle_A = static_cast<const GodotRectangleShape2D *>(p_a);
	const GodotRectangleShape2D *rectangle_B = static_cast<const GodotRectangleShape2D *>(p_b);

	SeparatorAxisTest2D<GodotRectangleShape2D, GodotRectangleShape2D> separator(rectangle_A, p_transform_a, rectangle_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	if (!separator.test_cast()) {
		return;
	}

	//box faces A
	if (!separator.test_axis(p_transform_a.columns[0].normalized())) {
		return;
	}

	if (!separator.test_axis(p_transform_a.columns[1].normalized())) {
		return;
	}

	// Box2D-style SAT axis deduplication: rectangles with exactly equal
	// basis vectors have identical face directions. The two axes of B
	// would repeat the same support projections already tested for A.
	// Exact comparison is important: even a small relative rotation can
	// introduce new separating axes. The cast, margin and manifold paths
	// remain unchanged for all configurations.
	const bool identical_rectangle_axes = p_transform_a.columns[0] == p_transform_b.columns[0] &&
			p_transform_a.columns[1] == p_transform_b.columns[1];
	if (!identical_rectangle_axes) {
		// box faces B
		if (!separator.test_axis(p_transform_b.columns[0].normalized())) {
			return;
		}

		if (!separator.test_axis(p_transform_b.columns[1].normalized())) {
			return;
		}
	}

	if (p_with_margin) {
		Transform2D invA = p_transform_a.affine_inverse();
		Transform2D invB = p_transform_b.affine_inverse();

		if (!separator.test_axis(rectangle_A->get_box_axis(p_transform_a, invA, rectangle_B, p_transform_b, invB))) {
			return;
		}

		if (p_cast_A || p_cast_B) {
			Transform2D aofs = p_transform_a;
			aofs.columns[2] += p_motion_a;

			Transform2D bofs = p_transform_b;
			bofs.columns[2] += p_motion_b;

			[[maybe_unused]] Transform2D aofsinv = aofs.affine_inverse();
			[[maybe_unused]] Transform2D bofsinv = bofs.affine_inverse();

			if (p_cast_A) {
				if (!separator.test_axis(rectangle_A->get_box_axis(aofs, aofsinv, rectangle_B, p_transform_b, invB))) {
					return;
				}
			}

			if (p_cast_B) {
				if (!separator.test_axis(rectangle_A->get_box_axis(p_transform_a, invA, rectangle_B, bofs, bofsinv))) {
					return;
				}
			}

			if (p_cast_A && p_cast_B) {
				if (!separator.test_axis(rectangle_A->get_box_axis(aofs, aofsinv, rectangle_B, bofs, bofsinv))) {
					return;
				}
			}
		}
	}

	separator.generate_contacts();
}

static void _collision_rectangle_capsule(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotRectangleShape2D *rectangle_A = static_cast<const GodotRectangleShape2D *>(p_a);
	const GodotCapsuleShape2D *capsule_B = static_cast<const GodotCapsuleShape2D *>(p_b);

	SeparatorAxisTest2D<GodotRectangleShape2D, GodotCapsuleShape2D> separator(rectangle_A, p_transform_a, capsule_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	if (!separator.test_cast()) {
		return;
	}

	//box faces
	if (!separator.test_axis(p_transform_a.columns[0].normalized())) {
		return;
	}

	if (!separator.test_axis(p_transform_a.columns[1].normalized())) {
		return;
	}

	//capsule axis
	if (!separator.test_axis(p_transform_b.columns[0].normalized())) {
		return;
	}

	//box endpoints to capsule circles

	Transform2D boxinv = p_transform_a.affine_inverse();

	real_t capsule_dir = capsule_B->get_height() * 0.5 - capsule_B->get_radius();

	for (int i = 0; i < 2; i++) {
		{
			Vector2 capsule_endpoint = p_transform_b.get_origin() + p_transform_b.columns[1] * capsule_dir;

			if (!separator.test_axis(rectangle_A->get_circle_axis(p_transform_a, boxinv, capsule_endpoint))) {
				return;
			}
		}

		if (p_cast_A) {
			Vector2 capsule_endpoint = p_transform_b.get_origin() + p_transform_b.columns[1] * capsule_dir;
			capsule_endpoint -= p_motion_a;

			if (!separator.test_axis(rectangle_A->get_circle_axis(p_transform_a, boxinv, capsule_endpoint))) {
				return;
			}
		}

		if (p_cast_B) {
			Vector2 capsule_endpoint = p_transform_b.get_origin() + p_transform_b.columns[1] * capsule_dir;
			capsule_endpoint += p_motion_b;

			if (!separator.test_axis(rectangle_A->get_circle_axis(p_transform_a, boxinv, capsule_endpoint))) {
				return;
			}
		}

		if (p_cast_A && p_cast_B) {
			Vector2 capsule_endpoint = p_transform_b.get_origin() + p_transform_b.columns[1] * capsule_dir;
			capsule_endpoint -= p_motion_a;
			capsule_endpoint += p_motion_b;

			if (!separator.test_axis(rectangle_A->get_circle_axis(p_transform_a, boxinv, capsule_endpoint))) {
				return;
			}
		}

		capsule_dir *= -1.0;
	}

	separator.generate_contacts();
}

static void _collision_rectangle_convex_polygon(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotRectangleShape2D *rectangle_A = static_cast<const GodotRectangleShape2D *>(p_a);
	const GodotConvexPolygonShape2D *convex_B = static_cast<const GodotConvexPolygonShape2D *>(p_b);

	SeparatorAxisTest2D<GodotRectangleShape2D, GodotConvexPolygonShape2D> separator(rectangle_A, p_transform_a, convex_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	if (!separator.test_cast()) {
		return;
	}

	//box faces
	if (!separator.test_axis(p_transform_a.columns[0].normalized())) {
		return;
	}

	if (!separator.test_axis(p_transform_a.columns[1].normalized())) {
		return;
	}

	//convex faces
	Transform2D boxinv;
	if (p_with_margin) {
		boxinv = p_transform_a.affine_inverse();
	}
	for (int i = 0; i < convex_B->get_point_count(); i++) {
		if (!separator.test_axis(convex_B->get_xformed_segment_normal(p_transform_b, i))) {
			return;
		}

		if (p_with_margin) {
			//all points vs all points need to be tested if margin exist
			if (!separator.test_axis(rectangle_A->get_circle_axis(p_transform_a, boxinv, p_transform_b.xform(convex_B->get_point(i))))) {
				return;
			}
			if (p_cast_A) {
				if (!separator.test_axis(rectangle_A->get_circle_axis(p_transform_a, boxinv, p_transform_b.xform(convex_B->get_point(i)) - p_motion_a))) {
					return;
				}
			}
			if (p_cast_B) {
				if (!separator.test_axis(rectangle_A->get_circle_axis(p_transform_a, boxinv, p_transform_b.xform(convex_B->get_point(i)) + p_motion_b))) {
					return;
				}
			}
			if (p_cast_A && p_cast_B) {
				if (!separator.test_axis(rectangle_A->get_circle_axis(p_transform_a, boxinv, p_transform_b.xform(convex_B->get_point(i)) + p_motion_b - p_motion_a))) {
					return;
				}
			}
		}
	}

	separator.generate_contacts();
}

/////////

static void _collision_capsule_capsule(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotCapsuleShape2D *capsule_A = static_cast<const GodotCapsuleShape2D *>(p_a);
	const GodotCapsuleShape2D *capsule_B = static_cast<const GodotCapsuleShape2D *>(p_b);

	SeparatorAxisTest2D<GodotCapsuleShape2D, GodotCapsuleShape2D> separator(capsule_A, p_transform_a, capsule_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	bool exact_overlap_known = false;

	// Box2D-style closest-segment test: avoid SAT projections and support queries
	// for separated capsules, and directly resolve unambiguous end-cap contacts.
	// Parallel/overlapping segment contacts still use SAT for a stable manifold.
	const real_t half_A = capsule_A->get_height() * real_t(0.5) - capsule_A->get_radius();
	const real_t half_B = capsule_B->get_height() * real_t(0.5) - capsule_B->get_radius();
	if (!p_cast_A && !p_cast_B && p_margin_A >= 0.0 && p_margin_B >= 0.0 &&
			capsule_A->get_radius() >= 0.0 && capsule_B->get_radius() >= 0.0 &&
			half_A > 0.0 && half_B > 0.0 &&
			_is_unit_orthogonal_transform(p_transform_a) && _is_unit_orthogonal_transform(p_transform_b)) {
		const Vector2 start_A = p_transform_a.get_origin() - p_transform_a.columns[1] * half_A;
		const Vector2 start_B = p_transform_b.get_origin() - p_transform_b.columns[1] * half_B;
		const Vector2 direction_A = p_transform_a.columns[1] * (real_t(2.0) * half_A);
		const Vector2 direction_B = p_transform_b.columns[1] * (real_t(2.0) * half_B);
		const Vector2 between = start_A - start_B;
		const real_t length_squared_A = direction_A.length_squared();
		const real_t length_squared_B = direction_B.length_squared();
		const real_t dot_AB = direction_A.dot(direction_B);
		const real_t dot_A_between = direction_A.dot(between);
		const real_t dot_B_between = direction_B.dot(between);
		const real_t denominator = length_squared_A * length_squared_B - dot_AB * dot_AB;

		// Skip the shortcut entirely for nearly parallel axes: picking the
		// first endpoint as a closest-point seed can miss long shallow crossings.
		if (denominator > length_squared_A * length_squared_B * real_t(0.0001)) {
			// Closest points on two finite center segments.
			real_t fraction_A = CLAMP((dot_AB * dot_B_between - dot_A_between * length_squared_B) / denominator, real_t(0.0), real_t(1.0));
			real_t fraction_B = (dot_AB * fraction_A + dot_B_between) / length_squared_B;
			if (fraction_B < 0.0) {
				fraction_B = 0.0;
				fraction_A = CLAMP(-dot_A_between / length_squared_A, real_t(0.0), real_t(1.0));
			} else if (fraction_B > 1.0) {
				fraction_B = 1.0;
				fraction_A = CLAMP((dot_AB - dot_A_between) / length_squared_A, real_t(0.0), real_t(1.0));
			}

			const Vector2 closest_A = start_A + direction_A * fraction_A;
			const Vector2 closest_B = start_B + direction_B * fraction_B;
			const Vector2 separation = closest_A - closest_B;
			const real_t distance_squared = separation.length_squared();
			const real_t radius_A = capsule_A->get_radius() + p_margin_A;
			const real_t radius_B = capsule_B->get_radius() + p_margin_B;
			const real_t combined_radius = radius_A + radius_B;

			if (distance_squared > combined_radius * combined_radius) {
				if (p_collector->sep_axis) {
					*p_collector->sep_axis = separation / Math::sqrt(distance_squared);
				}
				return;
			}

			// The exact centerline-distance test has already ruled out separation.
			// Boolean queries don't need to run through SAT again.
			if (!p_collector->callback) {
				p_collector->collided = true;
				if (p_collector->sep_axis) {
					*p_collector->sep_axis = Vector2();
				}
				return;
			}

			// Endpoint contacts have a single well-defined normal. For side-side
			// contacts, parallelism or coincident centerlines preserve SAT clipping.
			if (distance_squared > 0.0 &&
					(fraction_A == 0.0 || fraction_A == 1.0 || fraction_B == 0.0 || fraction_B == 1.0)) {
				p_collector->collided = true;
				if (p_collector->callback) {
					const Vector2 normal = separation / Math::sqrt(distance_squared);
					p_collector->normal = normal;
					p_collector->call(closest_A - normal * radius_A, closest_B + normal * radius_B);
				}
				if (p_collector->sep_axis) {
					*p_collector->sep_axis = Vector2();
				}
				return;
			}
			exact_overlap_known = true;
		}
	}

	// Capsule center segments give an exact distance test for rigid, stationary
	// capsules. Reject noncontacts before the SAT support projections, and
	// answer overlap-only queries without constructing a contact manifold.
	// Contact-producing queries still use SAT to retain side-side manifolds.
	if (!exact_overlap_known && !p_cast_A && !p_cast_B && p_margin_A >= 0.0 && p_margin_B >= 0.0 &&
			capsule_A->get_radius() > 0.0 && capsule_B->get_radius() > 0.0 &&
			_is_unit_orthogonal_transform(p_transform_a) && _is_unit_orthogonal_transform(p_transform_b)) {
		const real_t half_segment_A = capsule_A->get_height() * real_t(0.5) - capsule_A->get_radius();
		const real_t half_segment_B = capsule_B->get_height() * real_t(0.5) - capsule_B->get_radius();
		if (half_segment_A >= 0.0 && half_segment_B >= 0.0) {
			const real_t combined_radius = capsule_A->get_radius() + capsule_B->get_radius() + p_margin_A + p_margin_B;
			const Vector2 center_delta = p_transform_a.get_origin() - p_transform_b.get_origin();
			const real_t center_distance_squared = center_delta.length_squared();
			const real_t enclosing_radius = half_segment_A + half_segment_B + combined_radius;

			// A quick conservative enclosing-circle test avoids segment work for
			// widely separated capsules, including rotated broad-phase false hits.
			if (center_distance_squared > enclosing_radius * enclosing_radius) {
				if (p_collector->sep_axis) {
					*p_collector->sep_axis = center_delta / Math::sqrt(center_distance_squared);
				}
				return;
			}

			// Most dense contacts have nearby centers; retain the old SAT path
			// there unless the caller needs only a boolean overlap result.
			if (!p_collector->callback || center_distance_squared > combined_radius * combined_radius) {
				const Vector2 segment_A = p_transform_a.columns[1] * half_segment_A;
				const Vector2 segment_B = p_transform_b.columns[1] * half_segment_B;
				Vector2 closest_A;
				Vector2 closest_B;
				const real_t segment_distance = Geometry2D::get_closest_points_between_segments(
						p_transform_a.get_origin() - segment_A, p_transform_a.get_origin() + segment_A,
						p_transform_b.get_origin() - segment_B, p_transform_b.get_origin() + segment_B,
						closest_A, closest_B);

				if (segment_distance > combined_radius) {
					if (p_collector->sep_axis) {
						*p_collector->sep_axis = (closest_A - closest_B) / segment_distance;
					}
					return;
				}

				if (!p_collector->callback) {
					p_collector->collided = true;
					if (p_collector->sep_axis) {
						*p_collector->sep_axis = Vector2();
					}
					return;
				}
			}
		}
	}

	if (!separator.test_cast()) {
		return;
	}

	//capsule axis

	if (!separator.test_axis(p_transform_b.columns[0].normalized())) {
		return;
	}

	if (!separator.test_axis(p_transform_a.columns[0].normalized())) {
		return;
	}

	//capsule endpoints

	real_t capsule_dir_A = capsule_A->get_height() * 0.5 - capsule_A->get_radius();
	for (int i = 0; i < 2; i++) {
		Vector2 capsule_endpoint_A = p_transform_a.get_origin() + p_transform_a.columns[1] * capsule_dir_A;

		real_t capsule_dir_B = capsule_B->get_height() * 0.5 - capsule_B->get_radius();
		for (int j = 0; j < 2; j++) {
			Vector2 capsule_endpoint_B = p_transform_b.get_origin() + p_transform_b.columns[1] * capsule_dir_B;

			if (TEST_POINT(capsule_endpoint_A, capsule_endpoint_B)) {
				return;
			}

			capsule_dir_B *= -1.0;
		}

		capsule_dir_A *= -1.0;
	}

	separator.generate_contacts();
}

static void _collision_capsule_convex_polygon(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotCapsuleShape2D *capsule_A = static_cast<const GodotCapsuleShape2D *>(p_a);
	const GodotConvexPolygonShape2D *convex_B = static_cast<const GodotConvexPolygonShape2D *>(p_b);

	SeparatorAxisTest2D<GodotCapsuleShape2D, GodotConvexPolygonShape2D> separator(capsule_A, p_transform_a, convex_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	if (!separator.test_cast()) {
		return;
	}

	//capsule axis

	if (!separator.test_axis(p_transform_a.columns[0].normalized())) {
		return;
	}

	//poly vs capsule
	for (int i = 0; i < convex_B->get_point_count(); i++) {
		Vector2 cpoint = p_transform_b.xform(convex_B->get_point(i));

		real_t capsule_dir = capsule_A->get_height() * 0.5 - capsule_A->get_radius();
		for (int j = 0; j < 2; j++) {
			Vector2 capsule_endpoint_A = p_transform_a.get_origin() + p_transform_a.columns[1] * capsule_dir;

			if (TEST_POINT(capsule_endpoint_A, cpoint)) {
				return;
			}

			capsule_dir *= -1.0;
		}

		if (!separator.test_axis(convex_B->get_xformed_segment_normal(p_transform_b, i))) {
			return;
		}
	}

	separator.generate_contacts();
}

/////////

static void _collision_convex_polygon_convex_polygon(const GodotShape2D *p_a, const Transform2D &p_transform_a, const GodotShape2D *p_b, const Transform2D &p_transform_b, _CollectorCallback2D *p_collector, const Vector2 &p_motion_a, const Vector2 &p_motion_b, bool p_cast_A, bool p_cast_B, bool p_with_margin, real_t p_margin_A, real_t p_margin_B) {
	const GodotConvexPolygonShape2D *convex_A = static_cast<const GodotConvexPolygonShape2D *>(p_a);
	const GodotConvexPolygonShape2D *convex_B = static_cast<const GodotConvexPolygonShape2D *>(p_b);

	SeparatorAxisTest2D<GodotConvexPolygonShape2D, GodotConvexPolygonShape2D> separator(convex_A, p_transform_a, convex_B, p_transform_b, p_collector, p_motion_a, p_motion_b, p_cast_A, p_cast_B, p_with_margin, p_margin_A, p_margin_B);

	if (!separator.test_previous_axis()) {
		return;
	}

	if (!separator.test_cast()) {
		return;
	}

	for (int i = 0; i < convex_A->get_point_count(); i++) {
		if (!separator.test_axis(convex_A->get_xformed_segment_normal(p_transform_a, i))) {
			return;
		}
	}

	for (int i = 0; i < convex_B->get_point_count(); i++) {
		if (!separator.test_axis(convex_B->get_xformed_segment_normal(p_transform_b, i))) {
			return;
		}
	}

	if (p_with_margin) {
		for (int i = 0; i < convex_A->get_point_count(); i++) {
			for (int j = 0; j < convex_B->get_point_count(); j++) {
				if (TEST_POINT(p_transform_a.xform(convex_A->get_point(i)), p_transform_b.xform(convex_B->get_point(j)))) {
					return;
				}
			}
		}
	}

	separator.generate_contacts();
}

////////

bool sat_2d_calculate_penetration(const GodotShape2D *p_shape_A, const Transform2D &p_transform_A, const Vector2 &p_motion_A, const GodotShape2D *p_shape_B, const Transform2D &p_transform_B, const Vector2 &p_motion_B, GodotCollisionSolver2D::CallbackResult p_result_callback, void *p_userdata, bool p_swap, Vector2 *sep_axis, real_t p_margin_A, real_t p_margin_B) {
	PS2DE::ShapeType type_A = p_shape_A->get_type();

	ERR_FAIL_COND_V(type_A == PS2DE::SHAPE_WORLD_BOUNDARY, false);
	ERR_FAIL_COND_V(type_A == PS2DE::SHAPE_SEPARATION_RAY, false);
	ERR_FAIL_COND_V(p_shape_A->is_concave(), false);

	PS2DE::ShapeType type_B = p_shape_B->get_type();

	ERR_FAIL_COND_V(type_B == PS2DE::SHAPE_WORLD_BOUNDARY, false);
	ERR_FAIL_COND_V(type_B == PS2DE::SHAPE_SEPARATION_RAY, false);
	ERR_FAIL_COND_V(p_shape_B->is_concave(), false);

	static const CollisionFunc collision_table[5][5] = {
		{ _collision_segment_segment,
				_collision_segment_circle,
				_collision_segment_rectangle,
				_collision_segment_capsule,
				_collision_segment_convex_polygon },
		{ nullptr,
				_collision_circle_circle,
				_collision_circle_rectangle,
				_collision_circle_capsule,
				_collision_circle_convex_polygon },
		{ nullptr,
				nullptr,
				_collision_rectangle_rectangle,
				_collision_rectangle_capsule,
				_collision_rectangle_convex_polygon },
		{ nullptr,
				nullptr,
				nullptr,
				_collision_capsule_capsule,
				_collision_capsule_convex_polygon },
		{ nullptr,
				nullptr,
				nullptr,
				nullptr,
				_collision_convex_polygon_convex_polygon }

	};

	_CollectorCallback2D callback;
	callback.callback = p_result_callback;
	callback.swap = p_swap;
	callback.userdata = p_userdata;
	callback.collided = false;
	callback.sep_axis = sep_axis;

	const GodotShape2D *A = p_shape_A;
	const GodotShape2D *B = p_shape_B;
	const Transform2D *transform_A = &p_transform_A;
	const Transform2D *transform_B = &p_transform_B;
	const Vector2 *motion_A = &p_motion_A;
	const Vector2 *motion_B = &p_motion_B;
	real_t margin_A = p_margin_A, margin_B = p_margin_B;

	if (type_A > type_B) {
		SWAP(A, B);
		SWAP(transform_A, transform_B);
		SWAP(type_A, type_B);
		SWAP(motion_A, motion_B);
		SWAP(margin_A, margin_B);
		callback.swap = !callback.swap;
	}

	CollisionFunc collision_func = collision_table[type_A - 2][type_B - 2];
	ERR_FAIL_NULL_V(collision_func, false);

	const bool cast_A = *motion_A != Vector2();
	const bool cast_B = *motion_B != Vector2();
	const bool with_margin = p_margin_A || p_margin_B;
	collision_func(A, *transform_A, B, *transform_B, &callback, *motion_A, *motion_B, cast_A, cast_B, with_margin, margin_A, margin_B);

	return callback.collided;
}
