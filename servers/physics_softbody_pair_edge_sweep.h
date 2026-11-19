/**************************************************************************/
/*  physics_softbody_pair_edge_sweep.h                                    */
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
/* MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "servers/physics_softbody_pair_edge_contact.h"

// Two LINEARLY moving nonparallel edges, with the nearest-point parameters
// strictly in the interior of each segment. The relative endpoint motions
// provide a conservative Lipschitz bound on segment/segment distance.
// Advance only by (distance - thickness) / max_relative_endpoint_speed:
// such a step cannot jump across the first proximity event. Bounded
// iterations and swept BVH candidate pruning keep CPU costs predictable.
//
// This is a proximity-based first-contact detector, not exact polynomial
// edge-edge TOI. Degenerate/parallel and initial-overlap cases are left to
// separate narrowphases (parallel contacts are not yet supported).
struct PhysicsSoftBodyPairEdgeSweepHit {
	Vector3 normal; // From edge CD toward edge AB, at first approach.
	real_t s = 0.0; // Closest position along AB at impact.
	real_t t = 0.0; // Closest position along CD at impact.
	real_t time = 1.0; // Fraction of current physics step.
};

_FORCE_INLINE_ static bool physics_softbody_swept_edge_edge(
		const Vector3 &p_prev_a, const Vector3 &p_curr_a,
		const Vector3 &p_prev_b, const Vector3 &p_curr_b,
		const Vector3 &p_prev_c, const Vector3 &p_curr_c,
		const Vector3 &p_prev_d, const Vector3 &p_curr_d,
		real_t p_thickness, PhysicsSoftBodyPairEdgeSweepHit &r_hit) {
	if (!(p_thickness > real_t(0.0)) || !Math::is_finite(p_thickness) ||
			!p_prev_a.is_finite() || !p_curr_a.is_finite() ||
			!p_prev_b.is_finite() || !p_curr_b.is_finite() ||
			!p_prev_c.is_finite() || !p_curr_c.is_finite() ||
			!p_prev_d.is_finite() || !p_curr_d.is_finite()) {
		return false;
	}
	const Vector3 motion[4] = {
		p_curr_a - p_prev_a, p_curr_b - p_prev_b,
		p_curr_c - p_prev_c, p_curr_d - p_prev_d
	};
	for (const Vector3 &v : motion) {
		if (!v.is_finite()) {
			return false;
		}
	}

	// Normalized time in [0,1]: no per-frame division required.
	double speed_bound_squared = 0.0;
	for (int i = 0; i < 2; ++i) {
		for (int j = 2; j < 4; ++j) {
			const double x = double(motion[i].x) - double(motion[j].x);
			const double y = double(motion[i].y) - double(motion[j].y);
			const double z = double(motion[i].z) - double(motion[j].z);
			speed_bound_squared = MAX(speed_bound_squared, x * x + y * y + z * z);
		}
	}
	if (!(speed_bound_squared > 0.0) || !Math::is_finite(speed_bound_squared)) {
		return false;
	}
	const double speed_bound = Math::sqrt(speed_bound_squared);
	const double tolerance = MAX(double(p_thickness) * 1.0e-4, 1.0e-7);
	double time = 0.0;
	for (int iteration = 0; iteration < 24; ++iteration) {
		const real_t fraction = real_t(time);
		const Vector3 a = p_prev_a.lerp(p_curr_a, fraction);
		const Vector3 b = p_prev_b.lerp(p_curr_b, fraction);
		const Vector3 c = p_prev_c.lerp(p_curr_c, fraction);
		const Vector3 d = p_prev_d.lerp(p_curr_d, fraction);
		real_t s = 0.0, t = 0.0, distance = 0.0;
		Vector3 normal;
		if (!physics_xpbd_closest_edges(a, b, c, d, s, t, normal, distance)) {
			return false;
		}
		if (time > 0.0 && double(distance) <= double(p_thickness) + tolerance) {
			const Vector3 first_velocity = motion[0].lerp(motion[1], s);
			const Vector3 second_velocity = motion[2].lerp(motion[3], t);
			const Vector3 relative_velocity = first_velocity - second_velocity;
			// Reject moving-apart / grazing witnesses.
			if (!relative_velocity.is_finite() ||
					!(double(relative_velocity.dot(normal)) < -1.0e-8 * speed_bound)) {
				return false;
			}
			const PhysicsSoftBodyPairEdgeSweepHit next = { normal, s, t, fraction };
			r_hit = next;
			return true;
		}
		if (!(double(distance) > double(p_thickness))) {
			return false; // Already overlapping at t=0: discrete stage.
		}
		const double advance = (double(distance) - double(p_thickness)) / speed_bound;
		if (!(advance > 1.0e-9) || !Math::is_finite(advance) ||
				time + advance >= 1.0) {
			return false; // Outside this tick or insufficient progress.
		}
		time += advance;
	}
	return false;
}

// Resolve the swept contact using its impact-time closest-point parameters
// and ORIGINAL separating normal, even if the edges have already crossed
// and are far apart at the end of the step. The normal is held fixed across
// XPBD iterations. The four positions and velocities are transactional.
_FORCE_INLINE_ static bool physics_softbody_solve_swept_pair_edges(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		Vector3 &r_va, Vector3 &r_vb, Vector3 &r_vc, Vector3 &r_vd,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		real_t p_thickness, real_t p_alpha,
		const PhysicsSoftBodyPairEdgeSweepHit &p_hit,
		real_t p_delta, real_t &r_lambda) {
	if (!(p_thickness > real_t(0.0)) || !(p_delta > real_t(0.0)) ||
			!Math::is_finite(p_thickness) || !Math::is_finite(p_delta) ||
			!Math::is_finite(p_alpha) || p_alpha < 0.0 ||
			!Math::is_finite(r_lambda) || r_lambda < 0.0 ||
			!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_b) ||
			!Math::is_finite(p_inv_c) || !Math::is_finite(p_inv_d) ||
			p_inv_a < 0.0 || p_inv_b < 0.0 || p_inv_c < 0.0 || p_inv_d < 0.0 ||
			!p_hit.normal.is_finite() || !Math::is_finite(p_hit.s) ||
			!Math::is_finite(p_hit.t) || !Math::is_finite(p_hit.time) ||
			!(p_hit.s > real_t(0.0) && p_hit.s < real_t(1.0)) ||
			!(p_hit.t > real_t(0.0) && p_hit.t < real_t(1.0)) ||
			!(p_hit.time > real_t(0.0) && p_hit.time < real_t(1.0)) ||
			!r_a.is_finite() || !r_b.is_finite() || !r_c.is_finite() ||
			!r_d.is_finite() || !r_va.is_finite() || !r_vb.is_finite() ||
			!r_vc.is_finite() || !r_vd.is_finite()) {
		return false;
	}
	const double normal_squared = double(p_hit.normal.length_squared());
	if (!(normal_squared > 0.5 && normal_squared < 1.5)) {
		return false;
	}
	const double weights[4] = {
		1.0 - double(p_hit.s), double(p_hit.s),
		-(1.0 - double(p_hit.t)), -double(p_hit.t)
	};
	const double inverse_masses[4] = {
		double(p_inv_a), double(p_inv_b), double(p_inv_c), double(p_inv_d)
	};
	const Vector3 positions[4] = { r_a, r_b, r_c, r_d };
	Vector3 *velocities[4] = { &r_va, &r_vb, &r_vc, &r_vd };
	double mass = 0.0;
	double relative[3] = { 0.0, 0.0, 0.0 };
	for (int i = 0; i < 4; ++i) {
		const double w = weights[i];
		mass += inverse_masses[i] * w * w;
		relative[0] += double(positions[i].x) * w;
		relative[1] += double(positions[i].y) * w;
		relative[2] += double(positions[i].z) * w;
	}
	const double separation = relative[0] * double(p_hit.normal.x) +
			relative[1] * double(p_hit.normal.y) + relative[2] * double(p_hit.normal.z);
	const double denominator = mass * normal_squared + double(p_alpha);
	if (!(mass > 0.0) || !(denominator > 0.0) ||
			!Math::is_finite(separation) || !Math::is_finite(denominator)) {
		return false;
	}
	const double delta_lambda =
			(double(p_thickness) - separation - double(p_alpha) * double(r_lambda)) / denominator;
	if (!Math::is_finite(delta_lambda)) {
		return false;
	}
	const double next_lambda_double = MAX(0.0, double(r_lambda) + delta_lambda);
	const real_t next_lambda = real_t(next_lambda_double);
	if (!Math::is_finite(next_lambda)) {
		return false;
	}
	const double impulse = next_lambda_double - double(r_lambda);
	const double inverse_dt = 1.0 / double(p_delta);
	Vector3 next_positions[4];
	Vector3 next_velocities[4];
	for (int i = 0; i < 4; ++i) {
		const double displacement_scale = impulse * weights[i] * inverse_masses[i];
		const Vector3 &p = positions[i];
		const Vector3 &v = *velocities[i];
		next_positions[i] = Vector3(
				real_t(double(p.x) + double(p_hit.normal.x) * displacement_scale),
				real_t(double(p.y) + double(p_hit.normal.y) * displacement_scale),
				real_t(double(p.z) + double(p_hit.normal.z) * displacement_scale));
		if (inverse_masses[i] == 0.0) {
			next_velocities[i] = v;
		} else {
			next_velocities[i] = Vector3(
					real_t(double(v.x) + (double(next_positions[i].x) - double(p.x)) * inverse_dt),
					real_t(double(v.y) + (double(next_positions[i].y) - double(p.y)) * inverse_dt),
					real_t(double(v.z) + (double(next_positions[i].z) - double(p.z)) * inverse_dt));
		}
		if (!next_positions[i].is_finite() || !next_velocities[i].is_finite()) {
			return false;
		}
	}
	r_a = next_positions[0];
	r_b = next_positions[1];
	r_c = next_positions[2];
	r_d = next_positions[3];
	r_va = next_velocities[0];
	r_vb = next_velocities[1];
	r_vc = next_velocities[2];
	r_vd = next_velocities[3];
	r_lambda = next_lambda;
	return true;
}
