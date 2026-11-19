/**************************************************************************/
/*  physics_rigid_convex_aero_facets_3d.h                                 */
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
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OR CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/geometry_3d.h"
#include "core/math/transform_3d.h"

#include <limits>

// Each convex hull polygon is one aerodynamic panel. Panel geometry is
// integrated from a triangle fan, preserving the *true affine world-space*
// face area, area-weighted polygon centroid, and outward normal EVEN for
// nonuniformly scaled, sheared or mirrored convex collision shapes.
//
// Geometric center of the complete hull is the arithmetic mean of vertices.
// For a valid nondegenerate closed convex hull this lies inside the hull and
// disambiguates winding even if the affine transform reverses orientation.
//
// This is a deterministic pressure/shear model, not wake-coupled CFD.
// It intentionally avoids triangulating coplanar faces into independently
// moving panels, which introduces spurious mesh-dependent torque.
struct GodotPhysicsConvexAeroFacet3D {
	Vector3 center;
	Vector3 outward_normal;
	real_t area = 0.0;
};

_FORCE_INLINE_ static bool godot_physics_convex_aero_facet_3d(
		const Geometry3D::MeshData &p_mesh,
		const Geometry3D::MeshData::Face &p_face,
		const Transform3D &p_world,
		const Vector3 &p_interior_world,
		GodotPhysicsConvexAeroFacet3D &r_facet) {
	const uint32_t n = p_face.indices.size();
	if (n < 3 || n > 512 || !p_world.basis.is_finite() ||
			!p_world.origin.is_finite() || !p_interior_world.is_finite()) {
		return false;
	}
	const uint32_t vertex_count = p_mesh.vertices.size();
	for (uint32_t i = 0; i < n; ++i) {
		if (p_face.indices[i] < 0 ||
				uint32_t(p_face.indices[i]) >= vertex_count) {
			return false;
		}
	}
	const Vector3 a = p_world.xform(p_mesh.vertices[p_face.indices[0]]);
	if (!a.is_finite()) {
		return false;
	}
	double normal[3] = { 0.0, 0.0, 0.0 };
	double first_moment[3] = { 0.0, 0.0, 0.0 };
	double total_area = 0.0;
	for (uint32_t i = 1; i + 1 < n; ++i) {
		const Vector3 b = p_world.xform(p_mesh.vertices[p_face.indices[i]]);
		const Vector3 c = p_world.xform(p_mesh.vertices[p_face.indices[i + 1]]);
		if (!b.is_finite() || !c.is_finite()) {
			return false;
		}
		const double ab[3] = {
			double(b.x) - double(a.x),
			double(b.y) - double(a.y),
			double(b.z) - double(a.z)
		};
		const double ac[3] = {
			double(c.x) - double(a.x),
			double(c.y) - double(a.y),
			double(c.z) - double(a.z)
		};
		const double cross[3] = {
			ab[1] * ac[2] - ab[2] * ac[1],
			ab[2] * ac[0] - ab[0] * ac[2],
			ab[0] * ac[1] - ab[1] * ac[0]
		};
		const double cross_length = Math::sqrt(
				cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2]);
		if (!Math::is_finite(cross_length) || cross_length < 0.0) {
			return false;
		}
		if (cross_length == 0.0) {
			continue;
		}
		const double area = cross_length * 0.5;
		const double centroid[3] = {
			(double(a.x) + double(b.x) + double(c.x)) / 3.0,
			(double(a.y) + double(b.y) + double(c.y)) / 3.0,
			(double(a.z) + double(b.z) + double(c.z)) / 3.0
		};
		for (int j = 0; j < 3; ++j) {
			normal[j] += cross[j];
			first_moment[j] += centroid[j] * area;
		}
		total_area += area;
	}
	if (!(total_area > 0.0) || !Math::is_finite(total_area) ||
			total_area > double(std::numeric_limits<real_t>::max())) {
		return false;
	}
	const double normal_length = Math::sqrt(normal[0] * normal[0] +
			normal[1] * normal[1] + normal[2] * normal[2]);
	if (!(normal_length > 0.0) || !Math::is_finite(normal_length)) {
		return false;
	}
	double centroid[3];
	double orientation = 0.0;
	const double interior[3] = {
		double(p_interior_world.x), double(p_interior_world.y),
		double(p_interior_world.z)
	};
	const double max_real = double(std::numeric_limits<real_t>::max());
	for (int j = 0; j < 3; ++j) {
		centroid[j] = first_moment[j] / total_area;
		orientation += normal[j] * (centroid[j] - interior[j]);
		if (!Math::is_finite(centroid[j]) ||
				Math::abs(centroid[j]) > max_real) {
			return false;
		}
	}
	if (!(Math::abs(orientation) > 0.0) || !Math::is_finite(orientation)) {
		return false; // Hull is planar, self-intersecting or collapsed.
	}
	const double sign = orientation > 0.0 ? 1.0 : -1.0;
	const Vector3 next_normal(
			real_t(sign * normal[0] / normal_length),
			real_t(sign * normal[1] / normal_length),
			real_t(sign * normal[2] / normal_length));
	const Vector3 next_center(real_t(centroid[0]), real_t(centroid[1]), real_t(centroid[2]));
	if (!next_normal.is_finite() || !next_center.is_finite()) {
		return false;
	}
	r_facet.center = next_center;
	r_facet.outward_normal = next_normal;
	r_facet.area = real_t(total_area);
	return true;
}

// Rigid convex-hull aerodynamic integration, one panel per polygon.
// For the velocity u at each face centroid, pressure acts only when
// u points outward into the medium, shear opposes tangent slip:
//   Fp = -0.5*rho*Cp*A*max(dot(u,n),0)^2*n
//   Fs = -0.5*rho*Cs*A*|u_tangent|*u_tangent.
//
// Apply a point impulse J with directional effective inverse mass
// k = m^-1 + (lever×dir)·I_world^-1·(lever×dir). It is capped by
// max(0,-dot(u,dir))/k, preventing the single face impulse from
// reversing slip, including rotational lever-arm coupling.
// Face order is stable, temp velocities update sequentially, and
// neither output is written until the ENTIRE mesh validates.
// Max 512 vertices and 256 polygon faces avoids pathological
// custom hulls from stalling a physics tick. No heap allocations.
_FORCE_INLINE_ static bool godot_physics_rigid_convex_aero_step_3d(
		Vector3 &r_linear_velocity, Vector3 &r_angular_velocity,
		const Geometry3D::MeshData &p_mesh, const Transform3D &p_world,
		const Vector3 &p_world_com, const Vector3 &p_wind,
		real_t p_density, real_t p_pressure_coefficient,
		real_t p_skin_coefficient, real_t p_inv_mass,
		const Basis &p_inv_inertia_world, real_t p_dt) {
	if (!r_linear_velocity.is_finite() || !r_angular_velocity.is_finite() ||
			!p_world.basis.is_finite() || !p_world.origin.is_finite() ||
			!p_world_com.is_finite() || !p_wind.is_finite() ||
			!p_inv_inertia_world.is_finite() ||
			!Math::is_finite(p_density) || p_density < 0.0 ||
			!Math::is_finite(p_pressure_coefficient) || p_pressure_coefficient < 0.0 ||
			!Math::is_finite(p_skin_coefficient) || p_skin_coefficient < 0.0 ||
			!Math::is_finite(p_inv_mass) || !(p_inv_mass > 0.0) ||
			!Math::is_finite(p_dt) || p_dt < 0.0) {
		return false;
	}
	if (p_dt == 0.0 || p_density == 0.0 ||
			(p_pressure_coefficient == 0.0 && p_skin_coefficient == 0.0)) {
		return true;
	}
	const uint32_t vertices = p_mesh.vertices.size();
	const uint32_t faces = p_mesh.faces.size();
	if (vertices < 4 || faces < 4 || vertices > 512 || faces > 256) {
		return false;
	}
	// A convex hull's vertex mean lies inside it. Calculate mean in
	// double and subtract an arbitrary world-space origin before
	// accumulating, avoiding large world-origin cancellation.
	double sum[3] = { 0.0, 0.0, 0.0 };
	for (uint32_t i = 0; i < vertices; ++i) {
		const Vector3 &vertex = p_mesh.vertices[i];
		if (!vertex.is_finite()) {
			return false;
		}
		const Vector3 p = p_world.xform(vertex);
		if (!p.is_finite()) {
			return false;
		}
		sum[0] += double(p.x) - double(p_world.origin.x);
		sum[1] += double(p.y) - double(p_world.origin.y);
		sum[2] += double(p.z) - double(p_world.origin.z);
	}
	const Vector3 interior(
			real_t(double(p_world.origin.x) + sum[0] / vertices),
			real_t(double(p_world.origin.y) + sum[1] / vertices),
			real_t(double(p_world.origin.z) + sum[2] / vertices));
	if (!interior.is_finite()) {
		return false;
	}
	Vector3 linear = r_linear_velocity;
	Vector3 angular = r_angular_velocity;
	for (uint32_t i = 0; i < faces; ++i) {
		GodotPhysicsConvexAeroFacet3D facet;
		if (!godot_physics_convex_aero_facet_3d(
					p_mesh, p_mesh.faces[i], p_world, interior, facet)) {
			return false;
		}
		const Vector3 lever = facet.center - p_world_com;
		const Vector3 relative = linear + angular.cross(lever) - p_wind;
		const real_t normal_speed = relative.dot(facet.outward_normal);
		const Vector3 tangent = relative - facet.outward_normal * normal_speed;
		const real_t tangent_speed = tangent.length();
		if (!lever.is_finite() || !relative.is_finite() ||
				!Math::is_finite(normal_speed) || !tangent.is_finite() ||
				!Math::is_finite(tangent_speed)) {
			return false;
		}
		const real_t windward = MAX(real_t(0.0), normal_speed);
		const real_t scale = real_t(-0.5) * p_density * facet.area;
		const Vector3 force = facet.outward_normal *
				(scale * p_pressure_coefficient * windward * windward) +
				tangent * (scale * p_skin_coefficient * tangent_speed);
		const real_t force_length = force.length();
		if (!force.is_finite() || !Math::is_finite(force_length)) {
			return false;
		}
		if (!(force_length > 0.0)) {
			continue;
		}
		const Vector3 direction = force / force_length;
		const Vector3 arm = lever.cross(direction);
		const Vector3 inverse_arm = p_inv_inertia_world.xform(arm);
		const real_t k = p_inv_mass + arm.dot(inverse_arm);
		const real_t opposing_speed = -relative.dot(direction);
		if (!direction.is_finite() || !arm.is_finite() ||
				!inverse_arm.is_finite() || !Math::is_finite(k) ||
				!(k > 0.0) || !Math::is_finite(opposing_speed)) {
			return false;
		}
		if (!(opposing_speed > 0.0)) {
			continue;
		}
		const double proposed = double(force_length) * double(p_dt);
		const double maximal = double(opposing_speed) / double(k);
		if (!Math::is_finite(proposed) || !Math::is_finite(maximal)) {
			return false;
		}
		const double amount = MIN(proposed, maximal);
		if (!(amount >= 0.0) ||
				amount > double(std::numeric_limits<real_t>::max())) {
			return false;
		}
		const Vector3 impulse = direction * real_t(amount);
		const Vector3 next_linear = linear + impulse * p_inv_mass;
		const Vector3 next_angular = angular +
				p_inv_inertia_world.xform(lever.cross(impulse));
		if (!impulse.is_finite() || !next_linear.is_finite() ||
				!next_angular.is_finite()) {
			return false;
		}
		linear = next_linear;
		angular = next_angular;
	}
	r_linear_velocity = linear;
	r_angular_velocity = angular;
	return true;
}
