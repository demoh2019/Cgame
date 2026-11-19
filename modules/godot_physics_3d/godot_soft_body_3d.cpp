/**************************************************************************/
/*  godot_soft_body_3d.cpp                                                */
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

#include "godot_soft_body_3d.h"

#include "godot_space_3d.h"

#include "core/math/geometry_3d.h"
#include "servers/physics_3d/physics_server_3d_rendering_server_handler.h"
#include "servers/physics_softbody_bending_plasticity.h"
#include "servers/physics_softbody_link_damping.h"
#include "servers/physics_softbody_strain_rate_damping.h"
#include "servers/physics_softbody_membrane_damping.h"
#include "servers/physics_softbody_dihedral_damping.h"
#include "servers/physics_softbody_aero_lift.h"
#include "servers/physics_softbody_adiabatic_gas.h"
#include "servers/physics_softbody_shape_matching.h"
#include "servers/physics_fem_tetra_neo_hookean.h"
#include "servers/physics_fem_lumped_mass.h"
#include "servers/physics_fem_tetra_fiber.h"
#include "servers/physics_fem_tetra_viscosity.h"
#include "servers/physics_fem_tetra_damage.h"
#include "servers/physics_fem_tetra_inversion_recovery.h"
#include "servers/physics_softbody_shape_clusters.h"
#include "servers/physics_softbody_aerodynamic_drag.h"
#include "servers/physics_softbody_plasticity.h"
#include "servers/physics_softbody_volume_plasticity.h"
#include "servers/physics_softbody_volume_safe.h"
#include "servers/physics_softbody_volume_damping.h"
#include "servers/physics_xpbd_distance.h"
#include "servers/physics_xpbd_tension_hardening.h"
#include "servers/physics_xpbd_anisotropic_stretch.h"
#include "servers/physics_xpbd_compression_hardening.h"
#include "servers/physics_softbody_fatigue_damage.h"
#include "servers/physics_xpbd_area.h"
#include "servers/physics_xpbd_dihedral.h"
#include "servers/physics_xpbd_shear.h"
#include "servers/physics_xpbd_self_collision.h"
#include "servers/physics_softbody_pair_contact.h"
#include "servers/physics_softbody_pair_ccd.h"
#include "servers/physics_xpbd_soft_ccd.h"
#include "servers/physics_xpbd_self_friction.h"
#include "servers/physics_xpbd_edge_collision.h"
#include "servers/physics_softbody_pair_edge_contact.h"
#include "servers/physics_softbody_pair_edge_sweep.h"
#include "servers/rendering/rendering_server.h"

#include <limits>

// Based on Bullet soft body.

/*
Bullet Continuous Collision Detection and Physics Library
Copyright (c) 2003-2006 Erwin Coumans  http://continuousphysics.com/Bullet/

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the use of this software.
Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.
*/
///btSoftBody implementation by Nathanael Presson

// Compact, orientation-independent edge key. Unlike a vertex-count-squared
// matrix, this uses memory proportional to the actual mesh connectivity.
static _FORCE_INLINE_ uint64_t _soft_body_edge_key(uint32_t p_a, uint32_t p_b) {
	return (uint64_t(MIN(p_a, p_b)) << 32) | uint64_t(MAX(p_a, p_b));
}

GodotSoftBody3D::GodotSoftBody3D() :
		GodotCollisionObject3D(TYPE_SOFT_BODY),
		active_list(this) {
	_set_static(false);
}

void GodotSoftBody3D::_shapes_changed() {
}

void GodotSoftBody3D::set_state(PS3DE::BodyState p_state, const Variant &p_variant) {
	switch (p_state) {
		case PS3DE::BODY_STATE_TRANSFORM: {
			_set_transform(p_variant);
			_set_inv_transform(get_transform().inverse());

			apply_nodes_transform(get_transform());

		} break;
		case PS3DE::BODY_STATE_LINEAR_VELOCITY: {
			// Not supported.
			ERR_FAIL_MSG("Linear velocity is not supported for Soft bodies.");
		} break;
		case PS3DE::BODY_STATE_ANGULAR_VELOCITY: {
			ERR_FAIL_MSG("Angular velocity is not supported for Soft bodies.");
		} break;
		case PS3DE::BODY_STATE_SLEEPING: {
			ERR_FAIL_MSG("Sleeping state is not supported for Soft bodies.");
		} break;
		case PS3DE::BODY_STATE_CAN_SLEEP: {
			ERR_FAIL_MSG("Sleeping state is not supported for Soft bodies.");
		} break;
	}
}

Variant GodotSoftBody3D::get_state(PS3DE::BodyState p_state) const {
	switch (p_state) {
		case PS3DE::BODY_STATE_TRANSFORM: {
			return get_transform();
		} break;
		case PS3DE::BODY_STATE_LINEAR_VELOCITY: {
			ERR_FAIL_V_MSG(Vector3(), "Linear velocity is not supported for Soft bodies.");
		} break;
		case PS3DE::BODY_STATE_ANGULAR_VELOCITY: {
			ERR_FAIL_V_MSG(Vector3(), "Angular velocity is not supported for Soft bodies.");
		} break;
		case PS3DE::BODY_STATE_SLEEPING: {
			ERR_FAIL_V_MSG(false, "Sleeping state is not supported for Soft bodies.");
		} break;
		case PS3DE::BODY_STATE_CAN_SLEEP: {
			ERR_FAIL_V_MSG(false, "Sleeping state is not supported for Soft bodies.");
		} break;
	}

	return Variant();
}

void GodotSoftBody3D::set_space(GodotSpace3D *p_space) {
	if (get_space()) {
		get_space()->soft_body_remove_from_active_list(&active_list);

		deinitialize_shape();
	}

	_set_space(p_space);
	xpbd_tethers_dirty = true;
	// A mesh may have been assigned before the space was created. Validate
	// its closed rest volume after volume compliance or gas mode is available.
	initialize_volume_constraint();
	initialize_fem_tetra();
	initialize_membrane_constraints();
	initialize_shear_constraints();
	initialize_dihedral_constraints();
	initialize_shape_matching();
	initialize_self_collision_topology();

	if (get_space()) {
		get_space()->soft_body_add_to_active_list(&active_list);

		if (bounds != AABB()) {
			initialize_shape(true);
		}
	}
}

void GodotSoftBody3D::set_mesh(RID p_mesh) {
	destroy();

	soft_mesh = p_mesh;

	if (soft_mesh.is_null()) {
		return;
	}

	// TODO: calling RenderingServer::mesh_surface_get_arrays() from the physics thread
	// is not safe and can deadlock when physics/3d/run_on_separate_thread is enabled.
	// This method blocks on the main thread to return data, but the main thread may be
	// blocked waiting on us in PhysicsServer3D::sync().
	Array arrays = RenderingServer::get_singleton()->mesh_surface_get_arrays(soft_mesh, 0);
	ERR_FAIL_COND(arrays.is_empty());

	const Vector<int> &indices = arrays[RSE::ARRAY_INDEX];
	const Vector<Vector3> &vertices = arrays[RSE::ARRAY_VERTEX];
	ERR_FAIL_COND_MSG(indices.is_empty(), "Soft body's mesh needs to have indices");
	ERR_FAIL_COND_MSG(vertices.is_empty(), "Soft body's mesh needs to have vertices");

	bool success = create_from_trimesh(indices, vertices);
	if (!success) {
		destroy();
	}
}

void GodotSoftBody3D::update_rendering_server(PhysicsServer3DRenderingServerHandler *p_rendering_server_handler) {
	if (soft_mesh.is_null()) {
		return;
	}

	const uint32_t vertex_count = map_visual_to_physics.size();
	for (uint32_t i = 0; i < vertex_count; ++i) {
		const uint32_t node_index = map_visual_to_physics[i];
		const Node &node = nodes[node_index];

		p_rendering_server_handler->set_vertex(i, node.x);
		p_rendering_server_handler->set_normal(i, node.n);
	}

	p_rendering_server_handler->set_aabb(bounds);
}

void GodotSoftBody3D::update_normals_and_centroids() {
	for (Node &node : nodes) {
		node.n = Vector3();
	}

	for (Face &face : faces) {
		const Vector3 n = vec3_cross(face.n[0]->x - face.n[2]->x, face.n[0]->x - face.n[1]->x);
		face.n[0]->n += n;
		face.n[1]->n += n;
		face.n[2]->n += n;
		face.normal = n;
		face.normal.normalize();
		face.centroid = 0.33333333333 * (face.n[0]->x + face.n[1]->x + face.n[2]->x);
	}

	for (Node &node : nodes) {
		real_t len = node.n.length();
		if (len > CMP_EPSILON) {
			node.n /= len;
		}
	}
}

void GodotSoftBody3D::update_bounds() {
	AABB prev_bounds = bounds;
	prev_bounds.grow_by(collision_margin);

	bounds = AABB();

	const uint32_t nodes_count = nodes.size();
	if (nodes_count == 0) {
		deinitialize_shape();
		return;
	}

	bool first = true;
	bool moved = false;
	for (uint32_t node_index = 0; node_index < nodes_count; ++node_index) {
		const Node &node = nodes[node_index];
		if (!prev_bounds.has_point(node.x)) {
			moved = true;
		}
		if (first) {
			bounds.position = node.x;
			first = false;
		} else {
			bounds.expand_to(node.x);
		}
	}

	if (get_space()) {
		initialize_shape(moved);
	}
}

void GodotSoftBody3D::update_constants() {
	reset_link_rest_lengths();
	xpbd_tethers_dirty = true;
	update_link_constants();
	update_area();
	initialize_volume_constraint();
	initialize_fem_tetra();
	initialize_membrane_constraints();
	initialize_shear_constraints();
	initialize_dihedral_constraints();
	initialize_shape_matching();
	initialize_self_collision_topology();
}

// Capture the undeformed shape after mesh creation, transform or space
// reassignment. Other solver steps must never redefine this rest shape.
void GodotSoftBody3D::initialize_shape_matching() {
	xpbd_shape_rest_offsets.reset();
	xpbd_shape_clusters.reset();
	xpbd_shape_cluster_members.reset();
	xpbd_shape_cluster_rest_offsets.reset();
	xpbd_shape_cluster_displacements.reset();
	xpbd_shape_cluster_counts.reset();
	if (!get_space() || !(get_space()->get_soft_body_shape_matching_stiffness() > 0.0) ||
			nodes.size() < 4) {
		return;
	}

	const int core_size = get_space()->get_soft_body_shape_matching_cluster_size();
	if (core_size >= 3) {
		// Only the original triangle mesh defines locality. Generated bending
		// links can span two hops and must not silently merge distinct clusters.
		LocalVector<PhysicsSoftBodyShapeEdge> graph;
		for (const Face &face : faces) {
			for (int j = 0; j < 3; ++j) {
				graph.push_back({ face.n[j]->index, face.n[(j + 1) % 3]->index });
			}
		}
		if (!physics_softbody_build_shape_clusters(nodes.size(), graph, core_size,
					xpbd_shape_clusters, xpbd_shape_cluster_members)) {
			return;
		}

		// Store one rest offset per cluster membership, not per solver step.
		// Overlap intentionally duplicates shared vertices and provides smooth
		// rotation fitting across neighboring regions of deformable material.
		xpbd_shape_cluster_rest_offsets.resize(xpbd_shape_cluster_members.size());
		for (const PhysicsSoftBodyShapeCluster &cluster : xpbd_shape_clusters) {
			double sx = 0.0, sy = 0.0, sz = 0.0;
			for (uint32_t j = cluster.first; j < cluster.first + cluster.count; ++j) {
				const Vector3 &p = nodes[xpbd_shape_cluster_members[j]].x;
				if (!p.is_finite()) {
					xpbd_shape_clusters.reset();
					xpbd_shape_cluster_members.reset();
					xpbd_shape_cluster_rest_offsets.reset();
					return;
				}
				sx += double(p.x);
				sy += double(p.y);
				sz += double(p.z);
			}
			const double inv = 1.0 / double(cluster.count);
			const Vector3 center(real_t(sx * inv), real_t(sy * inv), real_t(sz * inv));
			if (!center.is_finite()) {
				xpbd_shape_clusters.reset();
				xpbd_shape_cluster_members.reset();
				xpbd_shape_cluster_rest_offsets.reset();
				return;
			}
			for (uint32_t j = cluster.first; j < cluster.first + cluster.count; ++j) {
				xpbd_shape_cluster_rest_offsets[j] = nodes[xpbd_shape_cluster_members[j]].x - center;
				if (!xpbd_shape_cluster_rest_offsets[j].is_finite()) {
					xpbd_shape_clusters.reset();
					xpbd_shape_cluster_members.reset();
					xpbd_shape_cluster_rest_offsets.reset();
					return;
				}
			}
		}
		xpbd_shape_cluster_displacements.resize(nodes.size());
		xpbd_shape_cluster_counts.resize(nodes.size());
		return;
	}

	// Uniform soft-body particle masses allow an unweighted centroid.
	// Use double sums to retain stability for large translated scenes.
	double sx = 0.0, sy = 0.0, sz = 0.0;
	for (const Node &node : nodes) {
		if (!node.x.is_finite()) {
			return;
		}
		sx += double(node.x.x);
		sy += double(node.x.y);
		sz += double(node.x.z);
	}
	const double inv_count = 1.0 / double(nodes.size());
	const Vector3 center(real_t(sx * inv_count), real_t(sy * inv_count), real_t(sz * inv_count));
	if (!center.is_finite()) {
		return;
	}
	xpbd_shape_rest_offsets.resize(nodes.size());
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		const Vector3 offset = nodes[i].x - center;
		if (!offset.is_finite()) {
			xpbd_shape_rest_offsets.reset();
			return;
		}
		xpbd_shape_rest_offsets[i] = offset;
	}
}

void GodotSoftBody3D::solve_shape_matching(real_t p_strength) {
	if (!(p_strength > 0.0) || dynamic_node_count == 0 || nodes.size() < 4) {
		return;
	}
	if (!xpbd_shape_clusters.is_empty()) {
		solve_shape_matching_clusters(p_strength);
		return;
	}
	if (xpbd_shape_rest_offsets.size() != nodes.size()) {
		return;
	}

	double sx = 0.0, sy = 0.0, sz = 0.0;
	for (const Node &node : nodes) {
		if (!node.x.is_finite()) {
			return;
		}
		sx += double(node.x.x);
		sy += double(node.x.y);
		sz += double(node.x.z);
	}
	const double inv_count = 1.0 / double(nodes.size());
	const Vector3 center(real_t(sx * inv_count), real_t(sy * inv_count), real_t(sz * inv_count));
	if (!center.is_finite()) {
		return;
	}

	PhysicsSoftBodyShapeMatchingCovariance covariance;
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		covariance.add(xpbd_shape_rest_offsets[i], nodes[i].x - center);
	}
	Quaternion rotation;
	if (!covariance.solve_rotation(rotation)) {
		return;
	}
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		Node &node = nodes[i];
		if (node.im > 0.0) {
			physics_softbody_shape_matching_project(node.x,
					xpbd_shape_rest_offsets[i], center, rotation, p_strength, node.im);
		}
	}
}

// Local shape matching evaluates all cluster targets against the SAME
// positions, then averages correction directions over shared nodes. In
// contrast, applying each cluster immediately would bias the result by BFS
// order and create artificial seams. O(overlap memberships) work only when
// local clusters are enabled.
void GodotSoftBody3D::solve_shape_matching_clusters(real_t p_strength) {
	if (xpbd_shape_cluster_displacements.size() != nodes.size() ||
			xpbd_shape_cluster_counts.size() != nodes.size() ||
			xpbd_shape_cluster_rest_offsets.size() != xpbd_shape_cluster_members.size()) {
		return;
	}
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		xpbd_shape_cluster_displacements[i] = Vector3();
		xpbd_shape_cluster_counts[i] = 0;
	}

	for (const PhysicsSoftBodyShapeCluster &cluster : xpbd_shape_clusters) {
		double sx = 0.0, sy = 0.0, sz = 0.0;
		bool valid = true;
		for (uint32_t j = cluster.first; j < cluster.first + cluster.count; ++j) {
			const Vector3 &p = nodes[xpbd_shape_cluster_members[j]].x;
			if (!p.is_finite()) {
				valid = false;
				break;
			}
			sx += double(p.x);
			sy += double(p.y);
			sz += double(p.z);
		}
		if (!valid) {
			continue;
		}
		const double inv_count = 1.0 / double(cluster.count);
		const Vector3 center(real_t(sx * inv_count), real_t(sy * inv_count), real_t(sz * inv_count));
		if (!center.is_finite()) {
			continue;
		}

		PhysicsSoftBodyShapeMatchingCovariance covariance;
		for (uint32_t j = cluster.first; j < cluster.first + cluster.count; ++j) {
			const uint32_t node_index = xpbd_shape_cluster_members[j];
			covariance.add(xpbd_shape_cluster_rest_offsets[j], nodes[node_index].x - center);
		}
		Quaternion rotation;
		if (!covariance.solve_rotation(rotation)) {
			continue;
		}
		for (uint32_t j = cluster.first; j < cluster.first + cluster.count; ++j) {
			const uint32_t node_index = xpbd_shape_cluster_members[j];
			const Node &node = nodes[node_index];
			if (node.im > 0.0) {
				physics_softbody_shape_cluster_accumulate(node.x,
						xpbd_shape_cluster_rest_offsets[j], center, rotation,
						xpbd_shape_cluster_displacements[node_index],
						xpbd_shape_cluster_counts[node_index]);
			}
		}
	}

	for (uint32_t i = 0; i < nodes.size(); ++i) {
		Node &node = nodes[i];
		const uint32_t count = xpbd_shape_cluster_counts[i];
		if (node.im == 0.0 || count == 0) {
			continue;
		}
		const Vector3 corrected = node.x +
				xpbd_shape_cluster_displacements[i] * (p_strength / real_t(count));
		if (corrected.is_finite()) {
			node.x = corrected;
		}
	}
}

// Cook a conservative fan of tetrahedra from a closed CONVEX surface.
// The existing oriented-edge validator runs first; nonconvex or unsuitable
// meshes are rejected without changing any other soft-body physics.
// Rest matrices, node indices and per-step XPBD multipliers remain cached.
void GodotSoftBody3D::initialize_fem_tetra() {
	const bool previously_lumped = !xpbd_fem_mass_fractions.is_empty();
	xpbd_fem_tetrahedra.reset();
	xpbd_fem_fiber_lambdas.reset();
	xpbd_fem_damage.reset();
	xpbd_fem_mass_fractions.reset();

	if (get_space() &&
			(get_space()->get_soft_body_tetra_fem_compliance() > 0.0 ||
					get_space()->get_soft_body_tetra_fem_viscosity() > 0.0 ||
					get_space()->get_soft_body_tetra_fiber_compliance() > 0.0) &&
			xpbd_volume_closed && nodes.size() >= 4 && nodes.size() <= 2048 &&
			faces.size() >= 4 && faces.size() <= 4096) {
		LocalVector<Vector3> positions;
		positions.resize(nodes.size());
		for (uint32_t i = 0; i < nodes.size(); ++i) {
			positions[i] = nodes[i].x;
		}
		LocalVector<PhysicsFEMConvexFace> triangles;
		triangles.reserve(faces.size());
		for (const Face &face : faces) {
			PhysicsFEMConvexFace triangle;
			triangle.a = face.n[0]->index;
			triangle.b = face.n[1]->index;
			triangle.c = face.n[2]->index;
			triangles.push_back(triangle);
		}
		physics_fem_build_convex_star_tetrahedra(
				positions, triangles, xpbd_volume_rest, xpbd_fem_tetrahedra);
		// Element histories are allocated only if elastic FEM and damage are enabled.
		if (!xpbd_fem_tetrahedra.is_empty() &&
				get_space()->get_soft_body_tetra_fem_compliance() > 0.0 &&
				get_space()->get_soft_body_tetra_damage_rate() > 0.0) {
			xpbd_fem_damage.resize(xpbd_fem_tetrahedra.size());
			for (double &damage : xpbd_fem_damage) {
				damage = 0.0;
			}
		}

		// The total mass is unchanged. Each tetra distributes rho*V/4
		// onto its four vertices. Include pinned vertices in the fractions;
		// pinning changes mobility rather than deleting physical mass.
		if (!xpbd_fem_tetrahedra.is_empty() &&
				get_space()->get_soft_body_tetra_fem_lumped_mass()) {
			LocalVector<double> fractions;
			LocalVector<real_t> inverse_masses;
			if (physics_fem_build_lumped_masses(nodes.size(), xpbd_fem_tetrahedra,
						total_mass, fractions, inverse_masses)) {
				xpbd_fem_mass_fractions = std::move(fractions);
				for (uint32_t i = 0; i < nodes.size(); ++i) {
					if (nodes[i].im > 0.0) {
						nodes[i].im = inverse_masses[i];
					}
				}
				link_constants_dirty = true;
				return;
			}
		}
	}

	// Disabling/rejecting FEM must not leave stale nonuniform masses behind.
	if (previously_lumped) {
		const real_t uniform_inverse = real_t(nodes.size()) * inv_total_mass;
		for (Node &node : nodes) {
			if (node.im > 0.0) {
				node.im = uniform_inverse;
			}
		}
		link_constants_dirty = true;
	}
}

real_t GodotSoftBody3D::get_unpinned_node_inverse_mass(uint32_t p_node_index) const {
	ERR_FAIL_UNSIGNED_INDEX_V(p_node_index, nodes.size(), real_t(0.0));
	if (xpbd_fem_mass_fractions.size() == nodes.size()) {
		real_t result = 0.0;
		if (physics_fem_unpinned_inverse_mass(
					xpbd_fem_mass_fractions, p_node_index, total_mass, result)) {
			return result;
		}
	}
	return real_t(nodes.size()) * inv_total_mass;
}

// Cache undeformed triangle angles only for opt-in shear constraints.
// No per-triangle buffers are retained with the default zero compliance.
// Cache a 2D rest metric for each triangle; no work or buffers are needed
// for the legacy solver. Invalid/near-collinear faces remain marked by
// rest.area == 0 and are skipped during the solve.
void GodotSoftBody3D::initialize_membrane_constraints() {
	xpbd_membrane_rest.reset();
	xpbd_membrane_lambdas.reset();
	if (!get_space() || (get_space()->get_soft_body_xpbd_membrane_compliance() <= 0.0 &&
			get_space()->get_soft_body_membrane_damping_rate() <= 0.0) || faces.is_empty()) {
		return;
	}
	xpbd_membrane_rest.resize(faces.size());
	for (uint32_t face_index = 0; face_index < faces.size(); ++face_index) {
		const Face &face = faces[face_index];
		PhysicsXPBDMembraneRest rest;
		physics_xpbd_membrane_make_rest(face.n[0]->s, face.n[1]->s,
				face.n[2]->s, rest);
		xpbd_membrane_rest[face_index] = rest;
	}
}

void GodotSoftBody3D::initialize_shear_constraints() {
	xpbd_shear_rest_cosines.reset();
	if (!get_space() || get_space()->get_soft_body_xpbd_shear_compliance() <= 0.0 ||
			faces.is_empty()) {
		return;
	}
	xpbd_shear_rest_cosines.resize(faces.size());
	for (uint32_t face_index = 0; face_index < faces.size(); ++face_index) {
		const Face &face = faces[face_index];
		real_t cosine = real_t(2.0); // Invalid/degenerate triangle sentinel.
		physics_xpbd_triangle_shear_rest_cosine(face.n[0]->s, face.n[1]->s,
				face.n[2]->s, cosine);
		xpbd_shear_rest_cosines[face_index] = cosine;
	}
}

// The enclosed volume of an oriented triangle soup is the sum of signed
// tetrahedra against a common origin. Double intermediates keep large world
// coordinates from overflowing the float32 cross-product while constructing
// the rest state. Closedness is validated separately before this is used.
static _FORCE_INLINE_ double _soft_body_signed_face_volume(const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c, const Vector3 &p_origin) {
	const double ax = double(p_a.x) - double(p_origin.x);
	const double ay = double(p_a.y) - double(p_origin.y);
	const double az = double(p_a.z) - double(p_origin.z);
	const double bx = double(p_b.x) - double(p_origin.x);
	const double by = double(p_b.y) - double(p_origin.y);
	const double bz = double(p_b.z) - double(p_origin.z);
	const double cx = double(p_c.x) - double(p_origin.x);
	const double cy = double(p_c.y) - double(p_origin.y);
	const double cz = double(p_c.z) - double(p_origin.z);
	return (ax * (by * cz - bz * cy) + ay * (bz * cx - bx * cz) + az * (bx * cy - by * cx)) / 6.0;
}

void GodotSoftBody3D::initialize_volume_constraint() {
	xpbd_volume_closed = false;
	xpbd_volume_rest = 0.0;
	xpbd_volume_original_rest = 0.0;
	if (!get_space() ||
			(get_space()->get_soft_body_xpbd_volume_compliance() <= 0.0 &&
					get_space()->get_soft_body_gas_pressure_gamma() <= 0.0 &&
					get_space()->get_soft_body_tetra_fem_compliance() <= 0.0 &&
					get_space()->get_soft_body_tetra_fem_viscosity() <= 0.0 &&
					get_space()->get_soft_body_tetra_fiber_compliance() <= 0.0 &&
					get_space()->get_soft_body_volume_damping_rate() <= 0.0) ||
			nodes.size() < 4 || faces.size() < 4) {
		// Neither XPBD nor gas mode needs the volume for ordinary cloth.
		if (!xpbd_volume_gradients.is_empty()) {
			xpbd_volume_gradients.reset();
		}
		return;
	}

	// A volume constraint is meaningful only on a CLOSED and consistently
	// oriented manifold. Require each undirected edge exactly twice, with
	// opposite orientations, otherwise open cloth would be artificially
	// inflated. 0b01/0b10 are the two possible edge directions.
	HashMap<uint64_t, uint8_t> edge_winding;
	for (const Face &face : faces) {
		for (int j = 0; j < 3; ++j) {
			const uint32_t a = face.n[j]->index;
			const uint32_t b = face.n[(j + 1) % 3]->index;
			if (a == b) {
				return;
			}
			const uint64_t key = _soft_body_edge_key(a, b);
			const uint8_t direction = a < b ? uint8_t(1) : uint8_t(2);
			HashMap<uint64_t, uint8_t>::Iterator existing = edge_winding.find(key);
			if (existing) {
				if ((existing->value & direction) != 0) {
					// Same orientation twice, or an edge shared by >2 faces.
					return;
				}
				existing->value |= direction;
			} else {
				edge_winding.insert(key, direction);
			}
		}
	}
	for (const KeyValue<uint64_t, uint8_t> &entry : edge_winding) {
		if (entry.value != uint8_t(3)) {
			return;
		}
	}

	// Coordinates are relative to the first node to limit cancellation in
	// translated worlds. This signed volume supports either winding as long
	// as it is consistent across the whole closed surface.
	const Vector3 &origin = nodes[0].x;
	double volume = 0.0;
	for (const Face &face : faces) {
		volume += _soft_body_signed_face_volume(face.n[0]->x, face.n[1]->x, face.n[2]->x, origin);
	}
	// Avoid a fixed world-unit epsilon: a valid 1 mm tetrahedron
	// encloses ~1e-10 m³ and should still be considered a closed body.
	// Use a relative cubic scale derived from double-precision coordinate
	// differences, making the degeneracy test uniform-scale invariant.
	double axis_extent = 0.0;
	for (const Node &node : nodes) {
		const double dx = Math::abs(double(node.x.x) - double(origin.x));
		const double dy = Math::abs(double(node.x.y) - double(origin.y));
		const double dz = Math::abs(double(node.x.z) - double(origin.z));
		axis_extent = MAX(axis_extent, MAX(dx, MAX(dy, dz)));
	}
	if (!physics_softbody_volume_is_non_degenerate(volume, axis_extent)) {
		return;
	}
	xpbd_volume_rest = volume;
	// Gas reference volume must NEVER plastically creep: the gas mass remains
	// fixed even after permanent crushing of its enclosing soft-body shell.
	xpbd_volume_original_rest = volume;
	xpbd_volume_closed = true;
}

// Momentum-conserving bulk viscosity for closed SoftBody3D surfaces.
//
// For the signed enclosed volume V, its instantaneous derivative is
// Vdot = sum_i dot(grad(V)_i, v_i). A mass-weighted velocity impulse
// removes fraction f of ONLY this breathing mode:
//   lambda = -f * Vdot / sum_i(w_i * |grad(V)_i|^2)
//   v_i' = v_i + w_i * grad(V)_i * lambda.
//
// Closed-surface gradients sum to zero; their torque sum is also zero.
// Thus free bodies preserve both linear and angular momentum. For pins,
// the attachment supplies the reaction. Kinetic energy cannot increase:
// delta(E) = -f(2-f)*Vdot^2 / (2*K) <= 0 for 0<=f<=1.
//
// Uses the XPBD volume-gradient scratch and a two-phase commit to avoid
// leaving velocities partially modified by invalid mesh coordinates.
void GodotSoftBody3D::damp_volume_rate(double p_fraction) {
	if (!xpbd_volume_closed || !(p_fraction > 0.0 && p_fraction <= 1.0) ||
			!Math::is_finite(p_fraction) || nodes.size() < 4 || faces.size() < 4) {
		return;
	}
	xpbd_volume_gradients.resize(nodes.size());
	for (Vector3 &gradient : xpbd_volume_gradients) {
		gradient = Vector3();
	}
	const Vector3 &origin = nodes[0].x;
	for (const Face &face : faces) {
		Vector3 grad_a, grad_b, grad_c;
		if (!physics_softbody_volume_face_gradients(
					face.n[0]->x, face.n[1]->x, face.n[2]->x, origin,
					grad_a, grad_b, grad_c)) {
			return;
		}
		xpbd_volume_gradients[face.n[0]->index] += grad_a;
		xpbd_volume_gradients[face.n[1]->index] += grad_b;
		xpbd_volume_gradients[face.n[2]->index] += grad_c;
	}

	double volume_rate = 0.0;
	double inverse_mass_gradient = 0.0;
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		const Node &node = nodes[i];
		if (!node.v.is_finite() || !xpbd_volume_gradients[i].is_finite()) {
			return;
		}
		if (node.im == 0.0) {
			continue;
		}
		if (!(node.im > 0.0) || !Math::is_finite(node.im)) {
			return;
		}
		const Vector3 &g = xpbd_volume_gradients[i];
		volume_rate += double(g.x) * double(node.v.x) +
				double(g.y) * double(node.v.y) + double(g.z) * double(node.v.z);
		inverse_mass_gradient += double(node.im) *
				(double(g.x) * double(g.x) + double(g.y) * double(g.y) + double(g.z) * double(g.z));
	}

	double impulse = 0.0;
	if (!physics_softbody_bulk_viscosity_impulse(volume_rate, inverse_mass_gradient,
				p_fraction, impulse)) {
		return;
	}
	// Preflight every candidate before writing ANY velocity.
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		const Node &node = nodes[i];
		if (node.im == 0.0) {
			continue; // Pins remain exactly pinned.
		}
		Vector3 next;
		if (!physics_softbody_bulk_viscosity_velocity(
					node.v, xpbd_volume_gradients[i], node.im, impulse, next)) {
			return;
		}
	}
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		Node &node = nodes[i];
		if (node.im == 0.0) {
			continue;
		}
		Vector3 next;
		physics_softbody_bulk_viscosity_velocity(
				node.v, xpbd_volume_gradients[i], node.im, impulse, next);
		node.v = next;
	}
}

// Global closed-surface XPBD volume projection. Gradients for a face
// (u,v,w) are (v x w, w x u, u x v) / 6. For a properly oriented closed
// surface, the sum of gradients is translation invariant. The one scalar
// multiplier is updated across solver iterations, not across timesteps.
bool GodotSoftBody3D::solve_volume_constraint(double p_alpha, double &r_lambda) {
	if (!xpbd_volume_closed || !(p_alpha > 0.0) || !Math::is_finite(p_alpha)) {
		return false;
	}

	for (Vector3 &gradient : xpbd_volume_gradients) {
		gradient = Vector3();
	}
	const Vector3 &origin = nodes[0].x;
	double volume = 0.0;
	for (const Face &face : faces) {
		Vector3 grad_a, grad_b, grad_c;
		if (!physics_softbody_volume_face_gradients(
					face.n[0]->x, face.n[1]->x, face.n[2]->x, origin,
					grad_a, grad_b, grad_c)) {
			return false; // Never commit an invalid XPBD volume multiplier.
		}
		volume += _soft_body_signed_face_volume(face.n[0]->x, face.n[1]->x, face.n[2]->x, origin);
		xpbd_volume_gradients[face.n[0]->index] += grad_a;
		xpbd_volume_gradients[face.n[1]->index] += grad_b;
		xpbd_volume_gradients[face.n[2]->index] += grad_c;
	}
	if (!Math::is_finite(volume)) {
		return false;
	}
	double inverse_mass_gradient = 0.0;
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		const Node &node = nodes[i];
		if (node.im == 0.0) {
			continue;
		}
		const Vector3 &gradient = xpbd_volume_gradients[i];
		if (!(node.im > 0.0) || !Math::is_finite(node.im) || !gradient.is_finite()) {
			return false;
		}
		inverse_mass_gradient += double(node.im) *
				(double(gradient.x) * double(gradient.x) + double(gradient.y) * double(gradient.y) + double(gradient.z) * double(gradient.z));
	}
	const double denominator = inverse_mass_gradient + p_alpha;
	if (!(inverse_mass_gradient > 0.0) || !Math::is_finite(inverse_mass_gradient) ||
			!(denominator > 0.0) || !Math::is_finite(denominator)) {
		return false;
	}
	const double delta_lambda = -(volume - xpbd_volume_rest + p_alpha * r_lambda) / denominator;
	const double next_lambda = r_lambda + delta_lambda;
	if (!Math::is_finite(delta_lambda) || !Math::is_finite(next_lambda)) {
		return false;
	}

	// Validate all displacements before writing ANY vertex: malformed meshes
	// cannot leave a half-updated soft body after one non-finite correction.
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		const Node &node = nodes[i];
		if (node.im == 0.0) {
			continue;
		}
		const Vector3 &g = xpbd_volume_gradients[i];
		const double scale = double(node.im) * delta_lambda;
		const Vector3 next(real_t(double(node.x.x) + double(g.x) * scale),
				real_t(double(node.x.y) + double(g.y) * scale),
				real_t(double(node.x.z) + double(g.z) * scale));
		if (!next.is_finite()) {
			return false;
		}
	}
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		Node &node = nodes[i];
		if (node.im == 0.0) {
			continue;
		}
		const Vector3 &g = xpbd_volume_gradients[i];
		const double scale = double(node.im) * delta_lambda;
		node.x = Vector3(real_t(double(node.x.x) + double(g.x) * scale),
				real_t(double(node.x.y) + double(g.y) * scale),
				real_t(double(node.x.z) + double(g.z) * scale));
	}
	r_lambda = next_lambda;
	return true;
}

// Construct a deterministic hinge list from the ORIGINAL triangle faces.
// Two-hop bending links are a distance approximation and cannot preserve a
// non-flat rest dihedral angle, so this is an independent opt-in constraint.
// The map is temporary; runtime iteration uses only compact indexed hinges.
// Boundary edges, inconsistent winding and >2 faces per edge are rejected.
void GodotSoftBody3D::initialize_dihedral_constraints() {
	xpbd_dihedral_hinges.reset();
	xpbd_dihedral_lambdas.reset();
	if (!get_space() || get_space()->get_soft_body_xpbd_dihedral_compliance() <= 0.0 ||
			faces.size() < 2 || nodes.size() < 4) {
		return;
	}

	struct EdgeFaces {
		uint32_t a = 0;
		uint32_t b = 0;
		uint32_t c = 0;
		uint32_t d = 0;
		uint8_t count = 0;
		bool correctly_wound = false;
	};
	HashMap<uint64_t, uint32_t> edge_lookup;
	LocalVector<EdgeFaces> edge_faces;
	for (const Face &face : faces) {
		const uint32_t ids[3] = { face.n[0]->index, face.n[1]->index, face.n[2]->index };
		for (int side = 0; side < 3; ++side) {
			const uint32_t a = ids[side];
			const uint32_t b = ids[(side + 1) % 3];
			const uint32_t c = ids[(side + 2) % 3];
			if (a == b || b == c || c == a) {
				continue;
			}
			const uint64_t key = _soft_body_edge_key(a, b);
			const HashMap<uint64_t, uint32_t>::Iterator existing = edge_lookup.find(key);
			if (!existing) {
				EdgeFaces entry;
				entry.a = a;
				entry.b = b;
				entry.c = c;
				entry.count = 1;
				edge_lookup.insert(key, edge_faces.size());
				edge_faces.push_back(entry);
			} else {
				EdgeFaces &entry = edge_faces[existing->value];
				if (entry.count == 1) {
					entry.d = c;
					entry.correctly_wound = entry.a == b && entry.b == a && entry.c != c;
					entry.count = 2;
				} else {
					entry.count = 3; // Non-manifold: never generate a hinge.
				}
			}
		}
	}
	for (const EdgeFaces &edge : edge_faces) {
		if (edge.count != 2 || !edge.correctly_wound) {
			continue;
		}
		real_t rest_angle = 0.0;
		if (!physics_xpbd_dihedral_angle(nodes[edge.a].x, nodes[edge.b].x,
					nodes[edge.c].x, nodes[edge.d].x, rest_angle)) {
			continue;
		}
		DihedralHinge hinge;
		hinge.a = edge.a;
		hinge.b = edge.b;
		hinge.c = edge.c;
		hinge.d = edge.d;
		hinge.rest_angle = rest_angle;
		xpbd_dihedral_hinges.push_back(hinge);
	}
}

// Build one-ring adjacency from ORIGINAL triangle edges. Immediate mesh
// neighbors must never collide with each other's triangle surface: they
// share exactly the local bending/stretch degrees of freedom already
// handled by the material constraints. Only needed when self-collision
// is enabled on the owning physics space.
void GodotSoftBody3D::initialize_self_collision_topology() {
	xpbd_self_contacts.reset();
	xpbd_self_ccd_contacts.reset();
	xpbd_self_edge_contacts.reset();
	xpbd_self_edge_tree.clear();
	xpbd_self_edges.reset();
	if (!get_space() || !(get_space()->get_soft_body_self_collision_thickness() > 0.0)) {
		xpbd_self_neighbor_edges.reset();
		return;
	}
	const bool with_edge_contacts = get_space()->is_soft_body_self_collision_edge_edge_enabled();
	const real_t thickness = get_space()->get_soft_body_self_collision_thickness();
	// Retain topology-map capacity when rebuilding an enabled mesh.
	xpbd_self_neighbor_edges.clear();
	for (const Face &face : faces) {
		for (int side = 0; side < 3; ++side) {
			const uint32_t a = face.n[side]->index;
			const uint32_t b = face.n[(side + 1) % 3]->index;
			if (a == b) {
				continue;
			}
			const uint64_t key = _soft_body_edge_key(a, b);
			if (xpbd_self_neighbor_edges.has(key)) {
				continue;
			}
			xpbd_self_neighbor_edges.insert(key);
			if (with_edge_contacts) {
				SelfCollisionEdge edge;
				edge.a = a;
				edge.b = b;
				edge.index = xpbd_self_edges.size();
				xpbd_self_edges.push_back(edge);
			}
		}
	}
	// Insert only after all pushes, since the BVH holds raw pointers to
	// these elements. The vector does not resize while leaves are alive.
	if (with_edge_contacts) {
		for (SelfCollisionEdge &edge : xpbd_self_edges) {
			AABB bounds(nodes[edge.a].x, Vector3());
			bounds.expand_to(nodes[edge.b].x);
			bounds.grow_by(thickness);
			edge.leaf = xpbd_self_edge_tree.insert(bounds, &edge);
		}
	}
}

// BVH-pruned structural edge/edge cloth contacts. Kept separate from the
// vertex/triangle solver so the default configuration has no edge BVH,
// contact buffer, refit, or narrowphase work.
bool GodotSoftBody3D::solve_edge_self_collisions(real_t p_delta) {
	if (!get_space() || !get_space()->is_soft_body_self_collision_edge_edge_enabled() ||
			xpbd_self_edges.size() < 2 || !(p_delta > 0.0)) {
		return false;
	}
	const real_t thickness = get_space()->get_soft_body_self_collision_thickness();
	if (!(thickness > 0.0)) {
		return false;
	}
	const double alpha_double = double(get_space()->get_soft_body_self_collision_compliance()) /
			(double(p_delta) * double(p_delta));
	if (!Math::is_finite(alpha_double) || alpha_double < 0.0) {
		return false;
	}
	const real_t alpha = real_t(MIN(alpha_double, double(std::numeric_limits<real_t>::max())));
	const uint32_t per_edge_limit = uint32_t(get_space()->get_soft_body_self_collision_max_contacts_per_vertex());
	const uint32_t global_limit = uint32_t(MIN(uint64_t(65536),
			uint64_t(xpbd_self_edges.size()) * uint64_t(per_edge_limit)));
	xpbd_self_edge_contacts.clear();

	// All material and vertex/face corrections have completed. Refit once
	// BEFORE queries; do not mutate the tree inside any callback.
	for (const SelfCollisionEdge &edge : xpbd_self_edges) {
		AABB edge_bounds(nodes[edge.a].x, Vector3());
		edge_bounds.expand_to(nodes[edge.b].x);
		edge_bounds.grow_by(thickness);
		xpbd_self_edge_tree.update(edge.leaf, edge_bounds);
	}
	xpbd_self_edge_tree.optimize_incremental(1);

	for (const SelfCollisionEdge &edge : xpbd_self_edges) {
		if (xpbd_self_edge_contacts.size() >= global_limit) {
			break;
		}
		const Node &a = nodes[edge.a];
		const Node &b = nodes[edge.b];
		if (!a.x.is_finite() || !b.x.is_finite()) {
			continue;
		}
		AABB query(a.x, Vector3());
		query.expand_to(b.x);
		query.grow_by(thickness);
		uint32_t hits = 0;
		auto visit_edge = [&](void *p_userdata) -> bool {
			const SelfCollisionEdge &other = *static_cast<const SelfCollisionEdge *>(p_userdata);
			if (other.index <= edge.index) {
				return false;
			}
			// Same/one-ring topology is handled by the cloth material rows;
			// its edges must not produce fictitious self-collision resistance.
			if (edge.a == other.a || edge.a == other.b ||
					edge.b == other.a || edge.b == other.b ||
					xpbd_self_neighbor_edges.has(_soft_body_edge_key(edge.a, other.a)) ||
					xpbd_self_neighbor_edges.has(_soft_body_edge_key(edge.a, other.b)) ||
					xpbd_self_neighbor_edges.has(_soft_body_edge_key(edge.b, other.a)) ||
					xpbd_self_neighbor_edges.has(_soft_body_edge_key(edge.b, other.b))) {
				return false;
			}
			const Node &c = nodes[other.a];
			const Node &d = nodes[other.b];
			if ((a.im + b.im + c.im + d.im) <= 0.0) {
				return false;
			}
			real_t s, t, distance;
			Vector3 normal;
			if (!physics_xpbd_closest_edges(a.x, b.x, c.x, d.x, s, t, normal, distance) ||
					distance >= thickness) {
				return false;
			}
			// Maintain the normal's side from last frame, even if the
			// current edges crossed through each other this frame.
			const Vector3 previous_a = a.q + (b.q - a.q) * s;
			const Vector3 previous_b = c.q + (d.q - c.q) * t;
			const Vector3 previous_separation = previous_a - previous_b;
			if (previous_separation.is_finite() && previous_separation.length_squared() > CMP_EPSILON * CMP_EPSILON &&
					previous_separation.dot(normal) < 0.0) {
				normal = -normal;
			}
			SelfEdgeContact contact;
			contact.first = edge.index;
			contact.second = other.index;
			contact.normal = normal;
			contact.lambda = 0.0;
			xpbd_self_edge_contacts.push_back(contact);
			++hits;
			return hits >= per_edge_limit || xpbd_self_edge_contacts.size() >= global_limit;
		};
		xpbd_self_edge_tree.aabb_query(query, visit_edge);
	}
	if (xpbd_self_edge_contacts.is_empty()) {
		return false;
	}
	const int contact_iterations = MIN(MAX(iteration_count, 1), 4);
	for (int iteration = 0; iteration < contact_iterations; ++iteration) {
		for (SelfEdgeContact &contact : xpbd_self_edge_contacts) {
			const SelfCollisionEdge &first = xpbd_self_edges[contact.first];
			const SelfCollisionEdge &second = xpbd_self_edges[contact.second];
			Node &a = nodes[first.a];
			Node &b = nodes[first.b];
			Node &c = nodes[second.a];
			Node &d = nodes[second.b];
			physics_xpbd_solve_edge_collision(a.x, b.x, c.x, d.x,
					a.im, b.im, c.im, d.im, thickness, alpha, contact.normal, contact.lambda);
		}
	}
	return true;
}

// Lazily construct a structural edge BVH specifically for inter-body
// collisions. The self-contact BVH is unavailable when self-collisions
// are disabled, and edge topology must not depend on those settings.
void GodotSoftBody3D::initialize_pair_edge_topology(real_t p_thickness) {
	xpbd_pair_edge_tree.clear();
	xpbd_pair_edges.reset();
	HashSet<uint64_t> seen;
	for (const Face &face : faces) {
		for (int side = 0; side < 3; ++side) {
			const uint32_t a = face.n[side]->index;
			const uint32_t b = face.n[(side + 1) % 3]->index;
			if (a == b) {
				continue;
			}
			const uint64_t key = _soft_body_edge_key(a, b);
			if (seen.has(key)) {
				continue;
			}
			seen.insert(key);
			SelfCollisionEdge edge;
			edge.a = a;
			edge.b = b;
			edge.index = xpbd_pair_edges.size();
			xpbd_pair_edges.push_back(edge);
		}
	}
	// BVH leaves contain pointers; only insert after all vector appends.
	for (SelfCollisionEdge &edge : xpbd_pair_edges) {
		AABB edge_bounds(nodes[edge.a].x, Vector3());
		edge_bounds.expand_to(nodes[edge.b].x);
		edge_bounds.grow_by(p_thickness);
		edge.leaf = xpbd_pair_edge_tree.insert(edge_bounds, &edge);
	}
}

void GodotSoftBody3D::update_pair_edge_tree(real_t p_thickness, bool p_swept) {
	for (const SelfCollisionEdge &edge : xpbd_pair_edges) {
		const Node &a = nodes[edge.a];
		const Node &b = nodes[edge.b];
		if (!a.x.is_finite() || !b.x.is_finite()) {
			continue;
		}
		AABB edge_bounds(a.x, Vector3());
		edge_bounds.expand_to(b.x);
		if (p_swept && pair_ccd_previous.size() == nodes.size()) {
			edge_bounds.expand_to(pair_ccd_previous[edge.a]);
			edge_bounds.expand_to(pair_ccd_previous[edge.b]);
		}
		edge_bounds.grow_by(p_thickness);
		xpbd_pair_edge_tree.update(edge.leaf, edge_bounds);
	}
}

// Bounded, two-way inter-body structural edge contacts.
// Candidates are collected BEFORE solving any position constraints;
// querying a BVH while mutating its owning nodes/leaf bounds is unsafe.
bool GodotSoftBody3D::solve_pair_edge_contacts(GodotSoftBody3D &p_other, real_t p_delta,
		real_t p_thickness, real_t p_alpha, uint32_t p_contact_budget) {
	if (p_contact_budget == 0 || faces.is_empty() || p_other.faces.is_empty()) {
		return false;
	}
	if (xpbd_pair_edges.is_empty()) {
		initialize_pair_edge_topology(p_thickness);
	}
	if (p_other.xpbd_pair_edges.is_empty()) {
		p_other.initialize_pair_edge_topology(p_thickness);
	}
	if (xpbd_pair_edges.is_empty() || p_other.xpbd_pair_edges.is_empty()) {
		return false;
	}
	// Previous positions are already captured by the vertex/face pair CCD
	// stage. The extra edge sweep requires all three opt-in controls.
	const bool swept_ccd = get_space()->is_soft_body_pair_collision_edge_ccd_enabled() &&
			get_space()->is_soft_body_pair_collision_ccd_enabled() &&
			pair_ccd_previous.size() == nodes.size() &&
			p_other.pair_ccd_previous.size() == p_other.nodes.size() &&
			!pair_ccd_previous.is_empty() && !p_other.pair_ccd_previous.is_empty();
	update_pair_edge_tree(p_thickness, swept_ccd);
	p_other.update_pair_edge_tree(p_thickness, swept_ccd);
	struct PairEdgeContact {
		uint32_t first = 0;
		uint32_t second = 0;
		Vector3 normal;
		real_t lambda = 0.0;
	};
	LocalVector<PairEdgeContact> contacts;
	contacts.reserve(MIN(p_contact_budget, uint32_t(64)));
	struct PairSweptEdgeContact {
		uint32_t first = 0;
		uint32_t second = 0;
		PhysicsSoftBodyPairEdgeSweepHit hit;
		real_t lambda = 0.0;
	};
	LocalVector<PairSweptEdgeContact> swept_contacts;
	if (swept_ccd) {
		swept_contacts.reserve(MIN(p_contact_budget, uint32_t(32)));
	}
	const auto contact_count = [&]() -> uint32_t {
		return contacts.size() + swept_contacts.size();
	};
	const uint32_t per_edge_limit = 8;
	// Swept BVHs can contain many false positives (e.g. crossing flocks).
	// Bound the expensive conservative advancement attempts per body pair.
	const uint32_t max_sweep_candidates = MIN(uint32_t(4096), MAX(uint32_t(64), p_contact_budget * uint32_t(16)));
	uint32_t visited_candidates = 0;
	for (const SelfCollisionEdge &edge : xpbd_pair_edges) {
		if (contact_count() >= p_contact_budget ||
				(swept_ccd && visited_candidates >= max_sweep_candidates)) {
			break;
		}
		const Node &a = nodes[edge.a];
		const Node &b = nodes[edge.b];
		if (!a.x.is_finite() || !b.x.is_finite()) {
			continue;
		}
		AABB query(a.x, Vector3());
		query.expand_to(b.x);
		if (swept_ccd) {
			query.expand_to(pair_ccd_previous[edge.a]);
			query.expand_to(pair_ccd_previous[edge.b]);
		}
		query.grow_by(p_thickness);
		uint32_t hits = 0;
		auto visit_edge = [&](void *p_userdata) -> bool {
			if (swept_ccd && ++visited_candidates > max_sweep_candidates) {
				return true;
			}
			const SelfCollisionEdge &other = *static_cast<const SelfCollisionEdge *>(p_userdata);
			const Node &c = p_other.nodes[other.a];
			const Node &d = p_other.nodes[other.b];
			if (!(a.im > 0.0 || b.im > 0.0 || c.im > 0.0 || d.im > 0.0)) {
				return false;
			}
			real_t s, t, distance;
			Vector3 normal;
			const bool discrete_contact = physics_xpbd_closest_edges(
						a.x, b.x, c.x, d.x, s, t, normal, distance) && distance < p_thickness;
			if (swept_ccd) {
				PhysicsSoftBodyPairEdgeSweepHit hit;
				if (physics_softbody_swept_edge_edge(
							pair_ccd_previous[edge.a], a.x,
							pair_ccd_previous[edge.b], b.x,
							p_other.pair_ccd_previous[other.a], c.x,
							p_other.pair_ccd_previous[other.b], d.x,
							p_thickness, hit)) {
					PairSweptEdgeContact contact;
					contact.first = edge.index;
					contact.second = other.index;
					contact.hit = hit;
					swept_contacts.push_back(contact);
					++hits;
					return hits >= per_edge_limit || contact_count() >= p_contact_budget;
				}
			}
			if (!discrete_contact) {
				return false;
			}
			// Prefer the original separating side when CCD history exists;
			// this is still DISCRETE edge contact, not swept edge/edge TOI.
			if (pair_ccd_previous.size() == nodes.size() &&
					p_other.pair_ccd_previous.size() == p_other.nodes.size()) {
				const Vector3 previous_first = pair_ccd_previous[edge.a].lerp(pair_ccd_previous[edge.b], s);
				const Vector3 previous_second = p_other.pair_ccd_previous[other.a].lerp(p_other.pair_ccd_previous[other.b], t);
				const Vector3 previous_delta = previous_first - previous_second;
				if (previous_delta.is_finite() &&
						previous_delta.length_squared() > CMP_EPSILON * CMP_EPSILON &&
						previous_delta.dot(normal) < real_t(0.0)) {
					normal = -normal;
				}
			}
			PairEdgeContact contact;
			contact.first = edge.index;
			contact.second = other.index;
			contact.normal = normal;
			contacts.push_back(contact);
			++hits;
			return hits >= per_edge_limit || contact_count() >= p_contact_budget;
		};
		p_other.xpbd_pair_edge_tree.aabb_query(query, visit_edge);
	}
	if (contacts.is_empty() && swept_contacts.is_empty()) {
		return false;
	}

	bool moved = false;
	const int contact_iterations = MIN(MAX(iteration_count, 1), 4);
	for (int iteration = 0; iteration < contact_iterations; ++iteration) {
		for (PairEdgeContact &contact : contacts) {
			const SelfCollisionEdge &ab = xpbd_pair_edges[contact.first];
			const SelfCollisionEdge &cd = p_other.xpbd_pair_edges[contact.second];
			Node &a = nodes[ab.a];
			Node &b = nodes[ab.b];
			Node &c = p_other.nodes[cd.a];
			Node &d = p_other.nodes[cd.b];
			if (physics_softbody_solve_pair_edge_contact(
						a.x, b.x, c.x, d.x,
						a.v, b.v, c.v, d.v,
						a.im, b.im, c.im, d.im,
						p_thickness, p_alpha, contact.normal, p_delta, contact.lambda)) {
				moved = true;
			}
		}
		for (PairSweptEdgeContact &contact : swept_contacts) {
			const SelfCollisionEdge &ab = xpbd_pair_edges[contact.first];
			const SelfCollisionEdge &cd = p_other.xpbd_pair_edges[contact.second];
			Node &a = nodes[ab.a];
			Node &b = nodes[ab.b];
			Node &c = p_other.nodes[cd.a];
			Node &d = p_other.nodes[cd.b];
			if (physics_softbody_solve_swept_pair_edges(
						a.x, b.x, c.x, d.x,
						a.v, b.v, c.v, d.v,
						a.im, b.im, c.im, d.im,
						p_thickness, p_alpha, contact.hit, p_delta, contact.lambda)) {
				moved = true;
			}
		}
	}
	return moved;
}

// Optional two-way discrete soft/soft contact stage. Unlike internal folds,
// both the vertex and the other mesh's face move according to their masses.
// Capture candidate pairs BEFORE changing any position: refitting a BVH while
// traversing it invalidates callbacks, and mutations could hide later hits.
// The scratch list and per-vertex budget are bounded by project settings.
bool GodotSoftBody3D::solve_pair_contacts(GodotSoftBody3D &p_other, real_t p_delta,
		real_t p_thickness, real_t p_compliance, real_t p_friction,
		uint32_t p_max_contacts, uint32_t p_max_contacts_per_vertex) {
	if (&p_other == this || !get_space() || get_space() != p_other.get_space() ||
			!(p_delta > real_t(0.0)) || !Math::is_finite(p_delta) ||
			!(p_thickness > real_t(0.0)) || !Math::is_finite(p_thickness) ||
			p_compliance < real_t(0.0) || !Math::is_finite(p_compliance) ||
			p_friction < real_t(0.0) || !Math::is_finite(p_friction) ||
			p_max_contacts == 0 || p_max_contacts_per_vertex == 0 ||
			nodes.is_empty() || p_other.nodes.is_empty() ||
			faces.is_empty() || p_other.faces.is_empty()) {
		return false;
	}
	const double alpha_double = double(p_compliance) / (double(p_delta) * double(p_delta));
	if (!Math::is_finite(alpha_double) || alpha_double < 0.0) {
		return false;
	}
	const real_t alpha = real_t(MIN(alpha_double, double(std::numeric_limits<real_t>::max())));
	const uint32_t max_contacts = MIN(p_max_contacts, uint32_t(2048));
	const uint32_t per_vertex_limit = MIN(p_max_contacts_per_vertex, uint32_t(32));

	// The continuous path compares swept body bounds. Current-only AABBs
	// cannot detect bodies that cross and separate within one physics tick.
	const bool swept_ccd = get_space()->is_soft_body_pair_collision_ccd_enabled() &&
			pair_ccd_previous.size() == nodes.size() &&
			p_other.pair_ccd_previous.size() == p_other.nodes.size() &&
			!pair_ccd_previous.is_empty() && !p_other.pair_ccd_previous.is_empty();
	AABB enlarged = swept_ccd ? pair_ccd_swept_bounds : bounds;
	enlarged.grow_by(p_thickness);
	if (!enlarged.intersects(swept_ccd ? p_other.pair_ccd_swept_bounds : p_other.bounds)) {
		return false;
	}

	// Ray/cloth queries may have already built either tree. Refit after the
	// body-local constraints before querying current, not predicted, faces.
	if (face_tree.is_empty()) {
		initialize_face_tree();
	} else {
		update_face_tree(real_t(0.0));
	}
	if (p_other.face_tree.is_empty()) {
		p_other.initialize_face_tree();
	} else {
		p_other.update_face_tree(real_t(0.0));
	}
	if (swept_ccd) {
		// Refit the SAME BVH with the union of previous/current triangle
		// positions. No extra persistent tree is allocated.
		update_pair_swept_face_tree(p_thickness);
		p_other.update_pair_swept_face_tree(p_thickness);
	}

	struct PairContact {
		uint32_t vertex = 0;
		uint32_t face = 0;
		bool vertex_on_first = true;
		int8_t side = 1;
		real_t lambda = 0.0;
	};
	LocalVector<PairContact> contacts;
	contacts.reserve(MIN(max_contacts, uint32_t(64)));
	// Separate opt-in scratch: discrete contacts keep their compact layout.
	struct PairCCDContact {
		uint32_t vertex = 0;
		uint32_t face = 0;
		bool vertex_on_first = true;
		PhysicsXPBDSoftCCDSweepHit hit;
		real_t lambda = 0.0;
	};
	LocalVector<PairCCDContact> ccd_contacts;
	if (swept_ccd) {
		ccd_contacts.reserve(MIN(max_contacts, uint32_t(32)));
	}
	const auto contact_count = [&]() -> uint32_t {
		return contacts.size() + ccd_contacts.size();
	};
	const Vector3 padding(p_thickness, p_thickness, p_thickness);

	auto collect = [&](GodotSoftBody3D &p_vertices, GodotSoftBody3D &p_faces, bool p_first) {
		for (uint32_t index = 0; index < p_vertices.nodes.size() && contact_count() < max_contacts; ++index) {
			const Node &node = p_vertices.nodes[index];
			if (!node.x.is_finite() ||
					(swept_ccd && !p_vertices.pair_ccd_previous[index].is_finite())) {
				continue;
			}
			uint32_t vertex_contacts = 0;
			auto visit_face = [&](void *p_data) -> bool {
				const Face &face = *static_cast<const Face *>(p_data);
				if (node.im == real_t(0.0) &&
						face.n[0]->im == real_t(0.0) &&
						face.n[1]->im == real_t(0.0) &&
						face.n[2]->im == real_t(0.0)) {
					return false;
				}
				Vector3 normal, barycentric;
				real_t distance = 0.0;
				const bool discrete_contact = physics_xpbd_self_collision_face_projection(
						node.x, face.n[0]->x, face.n[1]->x, face.n[2]->x,
						normal, barycentric, distance) &&
						Math::abs(distance) < p_thickness;
				bool accepted = false;
				if (swept_ccd) {
					// Test continuous crossing FIRST, even if the vertex ended
					// near the plane: the previous side must not be lost.
					PhysicsXPBDSoftCCDSweepHit hit;
					if (physics_xpbd_swept_vertex_triangle(
							p_vertices.pair_ccd_previous[index], node.x,
							p_faces.pair_ccd_previous[face.n[0]->index], face.n[0]->x,
							p_faces.pair_ccd_previous[face.n[1]->index], face.n[1]->x,
							p_faces.pair_ccd_previous[face.n[2]->index], face.n[2]->x, hit)) {
						PairCCDContact contact;
						contact.vertex = index;
						contact.face = face.index;
						contact.vertex_on_first = p_first;
						contact.hit = hit;
						ccd_contacts.push_back(contact);
						accepted = true;
					}
				}
				if (!accepted && discrete_contact) {
					PairContact contact;
					contact.vertex = index;
					contact.face = face.index;
					contact.vertex_on_first = p_first;
					contact.side = distance >= real_t(0.0) ? 1 : -1;
					contacts.push_back(contact);
					accepted = true;
				}
				if (accepted) {
					++vertex_contacts;
				}
				return vertex_contacts >= per_vertex_limit || contact_count() >= max_contacts;
			};
			if (swept_ccd) {
				AABB swept_query(p_vertices.pair_ccd_previous[index], Vector3());
				swept_query.expand_to(node.x);
				swept_query.grow_by(p_thickness);
				p_faces.face_tree.aabb_query(swept_query, visit_face);
			} else {
				p_faces.face_tree.aabb_query(AABB(node.x - padding, padding * real_t(2.0)), visit_face);
			}
		}
	};

	collect(*this, p_other, true);
	if (contact_count() < max_contacts) {
		collect(p_other, *this, false);
	}
	// Even without vertex-face contacts, structural edges of two separate
	// cloth meshes can meet. Keep the edge stage reachable in that case.
	bool moved = false;
	const int contact_iterations = MIN(MAX(iteration_count, 1), 4);
	for (int iteration = 0; iteration < contact_iterations; ++iteration) {
		for (PairContact &contact : contacts) {
			GodotSoftBody3D &vertex_body = contact.vertex_on_first ? *this : p_other;
			GodotSoftBody3D &face_body = contact.vertex_on_first ? p_other : *this;
			Node &vertex = vertex_body.nodes[contact.vertex];
			Face &face = face_body.faces[contact.face];
			if (physics_softbody_solve_pair_vertex_face(vertex.x,
						face.n[0]->x, face.n[1]->x, face.n[2]->x,
						vertex.v, face.n[0]->v, face.n[1]->v, face.n[2]->v,
						vertex.im, face.n[0]->im, face.n[1]->im, face.n[2]->im,
						p_thickness, alpha, contact.side, p_delta, contact.lambda)) {
				moved = true;
			}
		}
		for (PairCCDContact &contact : ccd_contacts) {
			GodotSoftBody3D &vertex_body = contact.vertex_on_first ? *this : p_other;
			GodotSoftBody3D &face_body = contact.vertex_on_first ? p_other : *this;
			Node &vertex = vertex_body.nodes[contact.vertex];
			Face &face = face_body.faces[contact.face];
			if (physics_softbody_solve_pair_swept_face(vertex.x,
						face.n[0]->x, face.n[1]->x, face.n[2]->x,
						vertex.v, face.n[0]->v, face.n[1]->v, face.n[2]->v,
						vertex.im, face.n[0]->im, face.n[1]->im, face.n[2]->im,
						p_thickness, alpha, contact.hit, p_delta, contact.lambda)) {
				moved = true;
			}
		}
	}
	if (get_space()->is_soft_body_pair_collision_edge_edge_enabled()) {
		const uint32_t remaining = max_contacts > contact_count() ? max_contacts - contact_count() : 0;
		moved = solve_pair_edge_contacts(p_other, p_delta, p_thickness, alpha, remaining) || moved;
	}
	if (!moved) {
		// CCD BVH entries are swept, so restore ordinary current-position
		// bounds even when all candidates were rejected by narrowphase.
		if (swept_ccd) {
			update_face_tree(real_t(0.0));
			p_other.update_face_tree(real_t(0.0));
		}
		return false;
	}

	// Normal lambda persists across the position iterations of this step.
	// Apply pair friction ONCE as a mass-weighted tangential velocity impulse
	// bounded by mu * normal_lambda / dt. No extra contact buffers are needed.
	if (p_friction > real_t(0.0)) {
		for (const PairContact &contact : contacts) {
			if (!(contact.lambda > real_t(0.0))) {
				continue;
			}
			GodotSoftBody3D &vertex_body = contact.vertex_on_first ? *this : p_other;
			GodotSoftBody3D &face_body = contact.vertex_on_first ? p_other : *this;
			Node &vertex = vertex_body.nodes[contact.vertex];
			Face &face = face_body.faces[contact.face];
			physics_softbody_solve_pair_friction(vertex.x,
					face.n[0]->x, face.n[1]->x, face.n[2]->x,
					vertex.v, face.n[0]->v, face.n[1]->v, face.n[2]->v,
					vertex.im, face.n[0]->im, face.n[1]->im, face.n[2]->im,
					p_friction, contact.lambda, p_thickness, p_delta);
		}
	}

	// Refit both bodies only AFTER the contact loop. They will be used by
	// subsequent pair queries, raycasts, and the next physics step.
	auto finalize = [](GodotSoftBody3D &p_body) {
		for (Node &node : p_body.nodes) {
			node.q = node.x;
			AABB node_bounds(node.x, Vector3());
			node_bounds.grow_by(p_body.collision_margin);
			p_body.node_tree.update(node.leaf, node_bounds);
		}
		p_body.update_normals_and_centroids();
		p_body.update_bounds();
		p_body.update_face_tree(real_t(0.0));
		// Another body-pair may be processed later in this same tick.
		p_body.refresh_pair_ccd_swept_bounds();
	};
	finalize(*this);
	finalize(p_other);
	return true;
}

// Discrete vertex-vs-triangle self contacts for different cloth folds.
// A current-position face BVH avoids all-pairs vertex/face scans. Candidate
// enumeration and XPBD corrections are separate: the tree is never mutated
// inside a traversal callback. The per-vertex and global caps bound memory
// even if thousands of unrelated faces overlap the same tiny AABB.
void GodotSoftBody3D::solve_self_collisions(real_t p_delta) {
	if (!get_space()) {
		return;
	}
	const real_t thickness = get_space()->get_soft_body_self_collision_thickness();
	if (!(thickness > 0.0) || !(p_delta > 0.0) || nodes.is_empty() || faces.is_empty()) {
		if (!xpbd_self_contacts.is_empty()) {
			xpbd_self_contacts.reset();
		}
		return;
	}
	const double alpha_double = double(get_space()->get_soft_body_self_collision_compliance()) /
			(double(p_delta) * double(p_delta));
	if (!Math::is_finite(alpha_double) || alpha_double < 0.0) {
		return;
	}
	const real_t alpha = real_t(MIN(alpha_double, double(std::numeric_limits<real_t>::max())));
	const uint32_t per_vertex_limit = uint32_t(get_space()->get_soft_body_self_collision_max_contacts_per_vertex());
	const uint32_t global_limit = uint32_t(MIN(uint64_t(65536),
			uint64_t(nodes.size()) * uint64_t(per_vertex_limit)));
	xpbd_self_contacts.clear();
	xpbd_self_ccd_contacts.clear();
	const bool swept_ccd = get_space()->is_soft_body_self_collision_ccd_enabled();
	const bool face_tree_new = face_tree.is_empty();
	if (face_tree_new) {
		initialize_face_tree();
	}
	if (swept_ccd) {
		// Previous/current face positions bound full per-step trajectories.
		update_swept_face_tree(thickness);
	} else if (!face_tree_new) {
		// Material constraints may have moved the face after predict_motion().
		update_face_tree(real_t(0.0));
	}
	const Vector3 padding(thickness, thickness, thickness);
	for (uint32_t node_id = 0; node_id < nodes.size() &&
			(xpbd_self_contacts.size() + xpbd_self_ccd_contacts.size()) < global_limit; ++node_id) {
		const Node &node = nodes[node_id];
		if (!node.x.is_finite() || (swept_ccd && !node.q.is_finite())) {
			continue;
		}
		uint32_t hits = 0;
		auto visit_face = [&](void *p_userdata) -> bool {
			const Face &face = *static_cast<const Face *>(p_userdata);
			const uint32_t a = face.n[0]->index;
			const uint32_t b = face.n[1]->index;
			const uint32_t c = face.n[2]->index;
			if (node_id == a || node_id == b || node_id == c ||
					xpbd_self_neighbor_edges.has(_soft_body_edge_key(node_id, a)) ||
					xpbd_self_neighbor_edges.has(_soft_body_edge_key(node_id, b)) ||
					xpbd_self_neighbor_edges.has(_soft_body_edge_key(node_id, c))) {
				return false;
			}
			if (node.im == 0.0 && face.n[0]->im == 0.0 &&
					face.n[1]->im == 0.0 && face.n[2]->im == 0.0) {
				return false;
			}
			Vector3 face_normal, barycentric;
			real_t signed_distance = 0.0;
			const bool discrete_contact = physics_xpbd_self_collision_face_projection(
					node.x, face.n[0]->x, face.n[1]->x, face.n[2]->x,
					face_normal, barycentric, signed_distance) &&
					Math::abs(signed_distance) < thickness;
			if (discrete_contact) {
				// Preserve the previous side for short-range contacts.
				const Vector3 previous_normal = (face.n[1]->q - face.n[0]->q).cross(face.n[2]->q - face.n[0]->q);
				const real_t previous_dot = (node.q - face.n[0]->q).dot(previous_normal);
				const bool has_previous_side = Math::is_finite(previous_dot) &&
						Math::is_finite(previous_normal.length_squared()) &&
						Math::abs(previous_dot) > CMP_EPSILON * previous_normal.length();
				SelfCollisionContact contact;
				contact.vertex = node_id;
				contact.face = face.index;
				contact.side = (has_previous_side ? previous_dot : signed_distance) >= 0.0 ? 1 : -1;
				contact.lambda = 0.0;
				xpbd_self_contacts.push_back(contact);
			} else if (swept_ccd) {
				// Find the FIRST crossing of the moving triangle within [0,1].
				// A point ending far across the plane is invisible to the
				// discrete thickness-only vertex/face narrowphase.
				PhysicsXPBDSoftCCDSweepHit hit;
				if (!physics_xpbd_swept_vertex_triangle(
						node.q, node.x,
						face.n[0]->q, face.n[0]->x,
						face.n[1]->q, face.n[1]->x,
						face.n[2]->q, face.n[2]->x, hit)) {
					return false;
				}
				SelfCCDContact contact;
				contact.vertex = node_id;
				contact.face = face.index;
				contact.barycentric = hit.barycentric;
				contact.separating_normal = hit.separating_normal;
				contact.lambda = 0.0;
				xpbd_self_ccd_contacts.push_back(contact);
			} else {
				return false;
			}
			++hits;
			return hits >= per_vertex_limit ||
					(xpbd_self_contacts.size() + xpbd_self_ccd_contacts.size()) >= global_limit;
		};
		if (swept_ccd) {
			AABB swept_query(node.q, Vector3());
			swept_query.expand_to(node.x);
			swept_query.grow_by(thickness);
			face_tree.aabb_query(swept_query, visit_face);
		} else {
			face_tree.aabb_query(AABB(node.x - padding, padding * real_t(2.0)), visit_face);
		}
	}
	const bool vertex_contacts = !xpbd_self_contacts.is_empty() || !xpbd_self_ccd_contacts.is_empty();
	if (vertex_contacts) {
		const int contact_iterations = MIN(MAX(iteration_count, 1), 4);
		for (int iteration = 0; iteration < contact_iterations; ++iteration) {
			for (SelfCollisionContact &contact : xpbd_self_contacts) {
				Node &node = nodes[contact.vertex];
				Face &face = faces[contact.face];
				physics_xpbd_solve_self_collision(node.x,
						face.n[0]->x, face.n[1]->x, face.n[2]->x,
						node.im, face.n[0]->im, face.n[1]->im, face.n[2]->im,
						thickness, alpha, contact.side, contact.lambda);
			}
			for (SelfCCDContact &contact : xpbd_self_ccd_contacts) {
				Node &node = nodes[contact.vertex];
				Face &face = faces[contact.face];
				PhysicsXPBDSoftCCDSweepHit hit;
				hit.barycentric = contact.barycentric;
				hit.separating_normal = contact.separating_normal;
				physics_xpbd_solve_swept_vertex_face(node.x,
						face.n[0]->x, face.n[1]->x, face.n[2]->x,
						node.im, face.n[0]->im, face.n[1]->im, face.n[2]->im,
						thickness, alpha, hit, contact.lambda);
			}
		}
	}
	const bool edge_contacts = solve_edge_self_collisions(p_delta);
	// After normal vertex/face and edge/edge projection, apply optional
	// Coulomb-limited tangential friction to vertex/face self contacts.
	// This must act on positions: velocities are reconstructed from x-q.
	const real_t friction = get_space()->get_soft_body_self_collision_friction();
	if (friction > real_t(0.0) && !xpbd_self_contacts.is_empty()) {
		for (const SelfCollisionContact &contact : xpbd_self_contacts) {
			if (!(contact.lambda > real_t(0.0))) {
				continue; // Without a normal reaction there is no friction budget.
			}
			Node &vertex = nodes[contact.vertex];
			Face &face = faces[contact.face];
			physics_xpbd_solve_self_friction(vertex.x,
					face.n[0]->x, face.n[1]->x, face.n[2]->x,
					vertex.q, face.n[0]->q, face.n[1]->q, face.n[2]->q,
					vertex.im, face.n[0]->im, face.n[1]->im, face.n[2]->im,
					friction, contact.lambda, thickness);
		}
	}
	if (vertex_contacts || edge_contacts) {
		// Refit for ray queries only if a contact stage may move nodes.
		update_face_tree(real_t(0.0));
	}
}

void GodotSoftBody3D::update_area() {
	int i, ni;

	// Face area.
	for (Face &face : faces) {
		const Vector3 &x0 = face.n[0]->x;
		const Vector3 &x1 = face.n[1]->x;
		const Vector3 &x2 = face.n[2]->x;

		const Vector3 a = x1 - x0;
		const Vector3 b = x2 - x0;
		const Vector3 cr = vec3_cross(a, b);
		face.ra = cr.length() * 0.5;
	}

	// Node area.
	LocalVector<int> counts;
	if (nodes.size() > 0) {
		counts.resize(nodes.size());
		memset(counts.ptr(), 0, counts.size() * sizeof(int));
	}

	for (Node &node : nodes) {
		node.area = 0.0;
	}

	for (const Face &face : faces) {
		for (int j = 0; j < 3; ++j) {
			const int index = (int)(face.n[j] - &nodes[0]);
			counts[index]++;
			face.n[j]->area += Math::abs(face.ra);
		}
	}

	for (i = 0, ni = nodes.size(); i < ni; ++i) {
		if (counts[i] > 0) {
			nodes[i].area /= (real_t)counts[i];
		} else {
			nodes[i].area = 0.0;
		}
	}
}

void GodotSoftBody3D::reset_link_rest_lengths() {
	float multiplier = 1.0 - shrinking_factor;
	for (Link &link : links) {
		link.rl = (link.n[0]->x - link.n[1]->x).length();
		link.rl *= multiplier;
		link.c1 = link.rl * link.rl;
	}
}

void GodotSoftBody3D::update_link_constants() {
	link_constants_dirty = false;
	// Zero stiffness disables stretch constraints. Do not produce infinities
	// (or NaNs for pairs of pinned vertices) by dividing by zero.
	if (!(linear_stiffness > 0.0)) {
		for (Link &link : links) {
			link.c0 = 0.0;
		}
		return;
	}

	const real_t inv_linear_stiffness = 1.0 / linear_stiffness;
	for (Link &link : links) {
		link.c0 = (link.n[0]->im + link.n[1]->im) * inv_linear_stiffness;
	}
}

void GodotSoftBody3D::apply_nodes_transform(const Transform3D &p_transform) {
	if (soft_mesh.is_null()) {
		return;
	}

	uint32_t node_count = nodes.size();
	Vector3 leaf_size = Vector3(collision_margin, collision_margin, collision_margin) * 2.0;
	for (uint32_t node_index = 0; node_index < node_count; ++node_index) {
		Node &node = nodes[node_index];

		node.x = p_transform.xform(node.x);
		node.q = node.x;
		node.v = Vector3();
		node.bv = Vector3();

		AABB node_aabb(node.x, leaf_size);
		node_tree.update(node.leaf, node_aabb);
	}

	face_tree.clear();

	update_normals_and_centroids();
	update_bounds();
	update_constants();
}

Vector3 GodotSoftBody3D::get_vertex_position(int p_index) const {
	ERR_FAIL_COND_V(p_index < 0, Vector3());

	if (soft_mesh.is_null()) {
		return Vector3();
	}

	ERR_FAIL_COND_V(p_index >= (int)map_visual_to_physics.size(), Vector3());
	uint32_t node_index = map_visual_to_physics[p_index];

	ERR_FAIL_COND_V(node_index >= nodes.size(), Vector3());
	return nodes[node_index].x;
}

void GodotSoftBody3D::set_vertex_position(int p_index, const Vector3 &p_position) {
	ERR_FAIL_COND(p_index < 0);

	if (soft_mesh.is_null()) {
		return;
	}

	ERR_FAIL_COND(p_index >= (int)map_visual_to_physics.size());
	uint32_t node_index = map_visual_to_physics[p_index];

	ERR_FAIL_COND(node_index >= nodes.size());
	Node &node = nodes[node_index];
	if (node.im == 0.0) {
		// A pinned vertex is kinematic. Explicit point movement must not
		// create an artificial velocity or leave a stale bias/force cache.
		node.q = p_position;
		node.v = Vector3();
		node.bv = Vector3();
		node.f = Vector3();
	} else {
		node.q = node.x;
	}
	node.x = p_position;
}

void GodotSoftBody3D::pin_vertex(int p_index) {
	ERR_FAIL_COND(p_index < 0);

	uint32_t node_index = 0;
	if (!soft_mesh.is_null()) {
		// Validate before storing the visual index: an invalid pin must not
		// survive in pinned_vertices and poison a later mesh rebuild.
		ERR_FAIL_COND(p_index >= (int)map_visual_to_physics.size());
		node_index = map_visual_to_physics[p_index];
		ERR_FAIL_COND(node_index >= nodes.size());
	}
	if (is_vertex_pinned(p_index)) {
		return;
	}

	pinned_vertices.push_back(p_index);
	xpbd_tethers_dirty = true;
	if (!soft_mesh.is_null()) {
		Node &node = nodes[node_index];
		if (node.im > 0.0) {
			// Multiple visual seam vertices may map to this same particle.
			// Count the physical particle only on its first pin.
			--dynamic_node_count;
		}
		node.im = 0.0;
		node.v = Vector3();
		node.bv = Vector3();
		node.f = Vector3();
		node.q = node.x;
		link_constants_dirty = true;
	}
}

void GodotSoftBody3D::unpin_vertex(int p_index) {
	ERR_FAIL_COND(p_index < 0);

	const uint32_t pinned_count = pinned_vertices.size();
	for (uint32_t i = 0; i < pinned_count; ++i) {
		if (p_index == pinned_vertices[i]) {
			pinned_vertices.remove_at(i);
			xpbd_tethers_dirty = true;

			if (!soft_mesh.is_null()) {
				ERR_FAIL_COND(p_index >= (int)map_visual_to_physics.size());
				const uint32_t node_index = map_visual_to_physics[p_index];
				ERR_FAIL_COND(node_index >= nodes.size());

				// Imported meshes often contain duplicated visual vertices that
				// share a single simulated node. Keep the node pinned until all
				// visual aliases have been unpinned.
				for (const int visual_index : pinned_vertices) {
					if (visual_index >= 0 && visual_index < (int)map_visual_to_physics.size() &&
							map_visual_to_physics[visual_index] == node_index) {
						return;
					}
				}

				Node &node = nodes[node_index];
				if (node.im == 0.0) {
					// This is the last visual pin for the physical node.
					++dynamic_node_count;
				}
				node.im = get_unpinned_node_inverse_mass(node_index);
				link_constants_dirty = true;
			}

			return;
		}
	}
}

void GodotSoftBody3D::unpin_all_vertices() {
	if (!soft_mesh.is_null() && !pinned_vertices.is_empty()) {
		for (const int pinned_vertex : pinned_vertices) {
			ERR_CONTINUE(pinned_vertex < 0 || pinned_vertex >= (int)map_visual_to_physics.size());
			const uint32_t node_index = map_visual_to_physics[pinned_vertex];

			ERR_CONTINUE(node_index >= nodes.size());
			Node &node = nodes[node_index];
			if (node.im == 0.0) {
					// Repeated visual indices must not count a welded node twice.
					++dynamic_node_count;
			}
			node.im = get_unpinned_node_inverse_mass(node_index);
		}
		link_constants_dirty = true;
	}

	pinned_vertices.clear();
	xpbd_tethers_dirty = true;
}

bool GodotSoftBody3D::is_vertex_pinned(int p_index) const {
	ERR_FAIL_COND_V(p_index < 0, false);

	uint32_t pinned_count = pinned_vertices.size();
	for (uint32_t i = 0; i < pinned_count; ++i) {
		if (p_index == pinned_vertices[i]) {
			return true;
		}
	}

	return false;
}

uint32_t GodotSoftBody3D::get_node_count() const {
	return nodes.size();
}

real_t GodotSoftBody3D::get_node_inv_mass(uint32_t p_node_index) const {
	ERR_FAIL_UNSIGNED_INDEX_V(p_node_index, nodes.size(), 0.0);
	return nodes[p_node_index].im;
}

Vector3 GodotSoftBody3D::get_node_position(uint32_t p_node_index) const {
	ERR_FAIL_UNSIGNED_INDEX_V(p_node_index, nodes.size(), Vector3());
	return nodes[p_node_index].x;
}

Vector3 GodotSoftBody3D::get_node_velocity(uint32_t p_node_index) const {
	ERR_FAIL_UNSIGNED_INDEX_V(p_node_index, nodes.size(), Vector3());
	return nodes[p_node_index].v;
}

Vector3 GodotSoftBody3D::get_node_biased_velocity(uint32_t p_node_index) const {
	ERR_FAIL_UNSIGNED_INDEX_V(p_node_index, nodes.size(), Vector3());
	return nodes[p_node_index].bv;
}

void GodotSoftBody3D::apply_node_impulse(uint32_t p_node_index, const Vector3 &p_impulse) {
	ERR_FAIL_UNSIGNED_INDEX(p_node_index, nodes.size());
	Node &node = nodes[p_node_index];
	node.v += p_impulse * node.im;
}

void GodotSoftBody3D::apply_node_force(uint32_t p_node_index, const Vector3 &p_force) {
	ERR_FAIL_UNSIGNED_INDEX(p_node_index, nodes.size());
	Node &node = nodes[p_node_index];
	node.f += p_force;
}

void GodotSoftBody3D::apply_central_impulse(const Vector3 &p_impulse) {
	if (dynamic_node_count == 0) {
		return;
	}
	// Pinned particles cannot receive an impulse: divide by the dynamic
	// particle count so the sum of delivered impulses is p_impulse.
	const Vector3 impulse = p_impulse / real_t(dynamic_node_count);
	for (Node &node : nodes) {
		if (node.im > 0.0) {
			node.v += impulse * node.im;
		}
	}
}

void GodotSoftBody3D::apply_central_force(const Vector3 &p_force) {
	if (dynamic_node_count == 0) {
		return;
	}
	// Apply the requested total force only to nodes that can accelerate.
	const Vector3 force = p_force / real_t(dynamic_node_count);
	for (Node &node : nodes) {
		if (node.im > 0.0) {
			node.f += force;
		}
	}
}

void GodotSoftBody3D::apply_node_bias_impulse(uint32_t p_node_index, const Vector3 &p_impulse) {
	ERR_FAIL_UNSIGNED_INDEX(p_node_index, nodes.size());
	Node &node = nodes[p_node_index];
	node.bv += p_impulse * node.im;
}

uint32_t GodotSoftBody3D::get_face_count() const {
	return faces.size();
}

void GodotSoftBody3D::get_face_points(uint32_t p_face_index, Vector3 &r_point_1, Vector3 &r_point_2, Vector3 &r_point_3) const {
	ERR_FAIL_UNSIGNED_INDEX(p_face_index, faces.size());
	const Face &face = faces[p_face_index];
	r_point_1 = face.n[0]->x;
	r_point_2 = face.n[1]->x;
	r_point_3 = face.n[2]->x;
}

Vector3 GodotSoftBody3D::get_face_normal(uint32_t p_face_index) const {
	ERR_FAIL_UNSIGNED_INDEX_V(p_face_index, faces.size(), Vector3());
	return faces[p_face_index].normal;
}

bool GodotSoftBody3D::create_from_trimesh(const Vector<int> &p_indices, const Vector<Vector3> &p_vertices) {
	ERR_FAIL_COND_V(p_indices.is_empty(), false);
	ERR_FAIL_COND_V(p_vertices.is_empty(), false);

	uint32_t node_count = 0;
	LocalVector<Vector3> vertices;
	const int visual_vertex_count(p_vertices.size());

	LocalVector<int> triangles;
	const uint32_t triangle_count(p_indices.size() / 3);
	triangles.resize(triangle_count * 3);

	// Merge all overlapping vertices and create a map of physical vertices to visual vertices.
	{
		// Process vertices.
		{
			uint32_t vertex_count = 0;
			HashMap<Vector3, uint32_t> unique_vertices;

			vertices.resize(visual_vertex_count);
			map_visual_to_physics.resize(visual_vertex_count);

			for (int visual_vertex_index = 0; visual_vertex_index < visual_vertex_count; ++visual_vertex_index) {
				const Vector3 &vertex = p_vertices[visual_vertex_index];

				HashMap<Vector3, uint32_t>::Iterator e = unique_vertices.find(vertex);
				uint32_t vertex_id;
				if (e) {
					// Already existing.
					vertex_id = e->value;
				} else {
					// Create new one.
					vertex_id = vertex_count++;
					unique_vertices[vertex] = vertex_id;
					vertices[vertex_id] = vertex;
				}

				map_visual_to_physics[visual_vertex_index] = vertex_id;
			}

			vertices.resize(vertex_count);
		}

		// Process triangles.
		{
			for (uint32_t triangle_index = 0; triangle_index < triangle_count; ++triangle_index) {
				for (int i = 0; i < 3; ++i) {
					int visual_index = 3 * triangle_index + i;
					int physics_index = map_visual_to_physics[p_indices[visual_index]];
					triangles[visual_index] = physics_index;
					node_count = MAX((int)node_count, physics_index);
				}
			}
		}
	}

	++node_count;

	// Create nodes from vertices.
	nodes.resize(node_count);
	dynamic_node_count = node_count;
	real_t inv_node_mass = node_count * inv_total_mass;
	Vector3 leaf_size = Vector3(collision_margin, collision_margin, collision_margin) * 2.0;
	for (uint32_t i = 0; i < node_count; ++i) {
		Node &node = nodes[i];
		node.s = vertices[i];
		node.x = node.s;
		node.q = node.s;
		node.im = inv_node_mass;

		AABB node_aabb(node.x, leaf_size);
		node.leaf = node_tree.insert(node_aabb, &node);

		node.index = i;
	}

	// Deduplicate undirected triangle edges in O(E) storage, not O(V^2).
	// This avoids allocating a dense vertex-pair matrix for large soft meshes.
	HashSet<uint64_t> unique_edges;
	for (uint32_t i = 0; i < triangle_count * 3; i += 3) {
		const int idx[] = { triangles[i], triangles[i + 1], triangles[i + 2] };

		for (int j = 2, k = 0; k < 3; j = k++) {
			const uint64_t edge = _soft_body_edge_key(idx[j], idx[k]);
			if (!unique_edges.has(edge)) {
				unique_edges.insert(edge);
				append_link(idx[j], idx[k]);
			}
		}

		append_face(idx[0], idx[1], idx[2]);
	}

	// Set pinned nodes.
	uint32_t pinned_count = pinned_vertices.size();
	for (uint32_t i = 0; i < pinned_count; ++i) {
		int pinned_vertex = pinned_vertices[i];

		ERR_CONTINUE(pinned_vertex >= visual_vertex_count);
		uint32_t node_index = map_visual_to_physics[pinned_vertex];

		ERR_CONTINUE(node_index >= node_count);
		Node &node = nodes[node_index];
		if (node.im > 0.0) {
			--dynamic_node_count;
		}
		node.im = 0.0;
	}

	// Rebuild nearest-pin geodesics after the mesh topology changes.
	xpbd_tethers_dirty = true;
	generate_bending_constraints(2);
	reoptimize_link_order();

	update_constants();
	update_normals_and_centroids();
	update_bounds();

	return true;
}

void GodotSoftBody3D::generate_bending_constraints(int p_distance) {
	if (p_distance <= 1 || nodes.is_empty() || links.is_empty()) {
		return;
	}

	const uint32_t node_count = nodes.size();
	// Build adjacency from the original structural links. Bending links
	// appended below must not change graph distances in this construction.
	LocalVector<LocalVector<uint32_t>> neighbors;
	neighbors.resize(node_count);
	HashSet<uint64_t> registered_edges;
	for (const Link &link : links) {
		const uint32_t a = uint32_t(link.n[0] - &nodes[0]);
		const uint32_t b = uint32_t(link.n[1] - &nodes[0]);
		if (a == b) {
			continue;
		}
		const uint64_t key = _soft_body_edge_key(a, b);
		if (registered_edges.has(key)) {
			continue;
		}
		registered_edges.insert(key);
		neighbors[a].push_back(b);
		neighbors[b].push_back(a);
	}

	if (p_distance == 2) {
		// A two-hop link connects two neighbors of the same center. This is
		// O(sum(degree^2)) rather than O(V^2), with no dense adjacency matrix.
		// Skip structural edges and deduplicate links seen through other centers.
		for (uint32_t center = 0; center < node_count; ++center) {
			const LocalVector<uint32_t> &adjacent = neighbors[center];
			for (uint32_t i = 0; i < adjacent.size(); ++i) {
				for (uint32_t j = i + 1; j < adjacent.size(); ++j) {
					const uint32_t a = adjacent[i];
					const uint32_t b = adjacent[j];
					const uint64_t key = _soft_body_edge_key(a, b);
					if (!registered_edges.has(key)) {
						registered_edges.insert(key);
						append_link(MAX(a, b), MIN(a, b));
					}
				}
			}
		}
		return;
	}

	// Preserve support for other distances without Floyd's O(V^2) matrix.
	// A bounded breadth-first traversal gives the exact shortest-path
	// distance. Its scratch memory is O(V + E).
	LocalVector<int> distances;
	distances.resize(node_count);
	LocalVector<uint32_t> queue;
	queue.reserve(node_count);
	for (uint32_t origin = 0; origin < node_count; ++origin) {
		for (int &distance : distances) {
			distance = -1;
		}
		queue.clear();
		queue.push_back(origin);
		distances[origin] = 0;

		for (uint32_t front = 0; front < queue.size(); ++front) {
			const uint32_t current = queue[front];
			const int next_distance = distances[current] + 1;
			if (next_distance > p_distance) {
				continue;
			}
			for (const uint32_t next : neighbors[current]) {
				if (distances[next] != -1) {
					continue;
				}
				distances[next] = next_distance;
				if (next_distance == p_distance) {
					if (origin < next) {
						append_link(next, origin);
					}
				} else {
					queue.push_back(next);
				}
			}
		}
	}
}
//===================================================================
//
//
// This function takes in a list of interdependent Links and tries
// to maximize the distance between calculation
// of dependent links. This increases the amount of parallelism that can
// be exploited by out-of-order instruction processors with large but
// (inevitably) finite instruction windows.
//
//===================================================================

// A small structure to track lists of dependent link calculations.
class LinkDeps {
public:
	// A link calculation that is dependent on this one.
	// Positive values = "input A" while negative values = "input B".
	int value;
	// Next dependence in the list.
	LinkDeps *next;
};
typedef LinkDeps *LinkDepsPtr;

void GodotSoftBody3D::reoptimize_link_order() {
	const int reop_not_dependent = -1;
	const int reop_node_complete = -2;

	uint32_t link_count = links.size();
	uint32_t node_count = nodes.size();

	if (link_count < 1 || node_count < 2) {
		return;
	}

	uint32_t i;
	Link *lr;
	int ar, br;
	Node *node0 = &(nodes[0]);
	Node *node1 = &(nodes[1]);
	LinkDepsPtr link_dep;
	int ready_list_head, ready_list_tail, link_num, link_dep_frees, dep_link;

	// Allocate temporary buffers.
	int *node_written_at = memnew_arr(int, node_count + 1); // What link calculation produced this node's current values?
	int *link_dep_A = memnew_arr(int, link_count); // Link calculation input is dependent upon prior calculation #N
	int *link_dep_B = memnew_arr(int, link_count);
	int *ready_list = memnew_arr(int, link_count); // List of ready-to-process link calculations (# of links, maximum)
	LinkDeps *link_dep_free_list = memnew_arr(LinkDeps, 2 * link_count); // Dependent-on-me list elements (2x# of links, maximum)
	LinkDepsPtr *link_dep_list_starts = memnew_arr(LinkDepsPtr, link_count); // Start nodes of dependent-on-me lists, one for each link

	// Copy the original, unsorted links to a side buffer.
	Link *link_buffer = memnew_arr(Link, link_count);
	memcpy(link_buffer, &(links[0]), sizeof(Link) * link_count);

	// Clear out the node setup and ready list.
	for (i = 0; i < node_count + 1; i++) {
		node_written_at[i] = reop_not_dependent;
	}
	for (i = 0; i < link_count; i++) {
		link_dep_list_starts[i] = nullptr;
	}
	ready_list_head = ready_list_tail = link_dep_frees = 0;

	// Initial link analysis to set up data structures.
	for (i = 0; i < link_count; i++) {
		// Note which prior link calculations we are dependent upon & build up dependence lists.
		lr = &(links[i]);
		ar = (lr->n[0] - node0) / (node1 - node0);
		br = (lr->n[1] - node0) / (node1 - node0);
		if (node_written_at[ar] > reop_not_dependent) {
			link_dep_A[i] = node_written_at[ar];
			link_dep = &link_dep_free_list[link_dep_frees++];
			link_dep->value = i;
			link_dep->next = link_dep_list_starts[node_written_at[ar]];
			link_dep_list_starts[node_written_at[ar]] = link_dep;
		} else {
			link_dep_A[i] = reop_not_dependent;
		}
		if (node_written_at[br] > reop_not_dependent) {
			link_dep_B[i] = node_written_at[br];
			link_dep = &link_dep_free_list[link_dep_frees++];
			link_dep->value = -(int)(i + 1);
			link_dep->next = link_dep_list_starts[node_written_at[br]];
			link_dep_list_starts[node_written_at[br]] = link_dep;
		} else {
			link_dep_B[i] = reop_not_dependent;
		}

		// Add this link to the initial ready list, if it is not dependent on any other links.
		if ((link_dep_A[i] == reop_not_dependent) && (link_dep_B[i] == reop_not_dependent)) {
			ready_list[ready_list_tail++] = i;
			link_dep_A[i] = link_dep_B[i] = reop_node_complete; // Probably not needed now.
		}

		// Update the nodes to mark which ones are calculated by this link.
		node_written_at[ar] = node_written_at[br] = i;
	}

	// Process the ready list and create the sorted list of links:
	// -- By treating the ready list as a queue, we maximize the distance between any
	//    inter-dependent node calculations.
	// -- All other (non-related) nodes in the ready list will automatically be inserted
	//    in between each set of inter-dependent link calculations by this loop.
	i = 0;
	while (ready_list_head != ready_list_tail) {
		// Use ready list to select the next link to process.
		link_num = ready_list[ready_list_head++];
		// Copy the next-to-calculate link back into the original link array.
		links[i++] = link_buffer[link_num];

		// Free up any link inputs that are dependent on this one.
		link_dep = link_dep_list_starts[link_num];
		while (link_dep) {
			dep_link = link_dep->value;
			if (dep_link >= 0) {
				link_dep_A[dep_link] = reop_not_dependent;
			} else {
				dep_link = -dep_link - 1;
				link_dep_B[dep_link] = reop_not_dependent;
			}
			// Add this dependent link calculation to the ready list if *both* inputs are clear.
			if ((link_dep_A[dep_link] == reop_not_dependent) && (link_dep_B[dep_link] == reop_not_dependent)) {
				ready_list[ready_list_tail++] = dep_link;
				link_dep_A[dep_link] = link_dep_B[dep_link] = reop_node_complete; // Probably not needed now.
			}
			link_dep = link_dep->next;
		}
	}

	// Delete the temporary buffers.
	memdelete_arr(node_written_at);
	memdelete_arr(link_dep_A);
	memdelete_arr(link_dep_B);
	memdelete_arr(ready_list);
	memdelete_arr(link_dep_free_list);
	memdelete_arr(link_dep_list_starts);
	memdelete_arr(link_buffer);
}

void GodotSoftBody3D::append_link(uint32_t p_node1, uint32_t p_node2) {
	if (p_node1 == p_node2) {
		return;
	}

	Node *node1 = &nodes[p_node1];
	Node *node2 = &nodes[p_node2];

	Link link;
	link.n[0] = node1;
	link.n[1] = node2;
	link.rl = (node1->x - node2->x).length();
	link.rl *= 1.0 - shrinking_factor;

	links.push_back(link);
}

void GodotSoftBody3D::append_face(uint32_t p_node1, uint32_t p_node2, uint32_t p_node3) {
	if (p_node1 == p_node2) {
		return;
	}
	if (p_node1 == p_node3) {
		return;
	}
	if (p_node2 == p_node3) {
		return;
	}

	Node *node1 = &nodes[p_node1];
	Node *node2 = &nodes[p_node2];
	Node *node3 = &nodes[p_node3];

	Face face;
	face.n[0] = node1;
	face.n[1] = node2;
	face.n[2] = node3;

	face.index = faces.size();

	faces.push_back(face);
}

void GodotSoftBody3D::set_iteration_count(int p_val) {
	iteration_count = p_val;
}

void GodotSoftBody3D::set_total_mass(real_t p_val) {
	// A zero, negative, or non-finite mass would create invalid inverse masses
	// and ultimately corrupt per-vertex velocities / positions.
	ERR_FAIL_COND_MSG(!(p_val > 0.0) || !Math::is_finite(p_val), "Soft body mass must be positive and finite.");

	// With a cooked FEM mass distribution, recompute inverse masses from
	// the fixed rest-volume fractions rather than repeatedly multiplying
	// float32 values. Validate ALL nodes before mutating total_mass, so
	// invalid extreme mass edits cannot leave a partially updated body.
	if (xpbd_fem_mass_fractions.size() == nodes.size() &&
			!xpbd_fem_mass_fractions.is_empty()) {
		LocalVector<real_t> updated_inverse;
		updated_inverse.resize(nodes.size());
		for (uint32_t i = 0; i < nodes.size(); ++i) {
			ERR_FAIL_COND_MSG(!physics_fem_unpinned_inverse_mass(
						xpbd_fem_mass_fractions, i, p_val, updated_inverse[i]),
					"FEM mass is outside the finite representable inverse-mass range.");
		}
		inv_total_mass = 1.0 / p_val;
		total_mass = p_val;
		for (uint32_t i = 0; i < nodes.size(); ++i) {
			if (nodes[i].im > 0.0) {
				nodes[i].im = updated_inverse[i];
			}
		}
		update_link_constants();
		return;
	}

	inv_total_mass = 1.0 / p_val;
	real_t mass_factor = total_mass * inv_total_mass;
	total_mass = p_val;

	uint32_t node_count = nodes.size();
	for (uint32_t node_index = 0; node_index < node_count; ++node_index) {
		Node &node = nodes[node_index];
		node.im *= mass_factor;
	}

	// Mass affects inverse masses and solver coefficients, but not rest
	// lengths or surface areas. Do not silently redefine an already deformed
	// mesh as its new rest shape on every mass change.
	update_link_constants();
}

void GodotSoftBody3D::set_collision_margin(real_t p_val) {
	collision_margin = p_val;
}

void GodotSoftBody3D::set_linear_stiffness(real_t p_val) {
	linear_stiffness = p_val;
	// Make runtime changes observable immediately, without rebuilding
	// positions, rest lengths or the mesh topology.
	update_link_constants();
}

void GodotSoftBody3D::set_shrinking_factor(real_t p_val) {
	shrinking_factor = p_val;
}

void GodotSoftBody3D::set_pressure_coefficient(real_t p_val) {
	pressure_coefficient = p_val;
}

void GodotSoftBody3D::set_damping_coefficient(real_t p_val) {
	damping_coefficient = p_val;
}

void GodotSoftBody3D::set_drag_coefficient(real_t p_val) {
	ERR_FAIL_COND_MSG(p_val < 0.0 || !Math::is_finite(p_val), "Soft body drag must be nonnegative and finite.");
	drag_coefficient = p_val;
}

void GodotSoftBody3D::add_velocity(const Vector3 &p_velocity) {
	for (Node &node : nodes) {
		if (node.im > 0) {
			node.v += p_velocity;
		}
	}
}

void GodotSoftBody3D::apply_forces(const LocalVector<GodotArea3D *> &p_wind_areas, real_t p_delta) {
	if (nodes.is_empty()) {
		return;
	}

	const bool apply_pressure = pressure_coefficient > CMP_EPSILON && Math::is_finite(pressure_coefficient);
	const real_t gas_gamma = get_space() ? get_space()->get_soft_body_gas_pressure_gamma() : real_t(0.0);
	// A gas mode with an open mesh must not fall back to the legacy
	// pressure heuristic: pressure is only meaningful inside a sealed shell.
	const bool legacy_pressure = apply_pressure && !(gas_gamma > 0.0);
	double gas_pressure = 0.0;
	if (apply_pressure && gas_gamma > 0.0 && xpbd_volume_closed) {
		const Vector3 &origin = nodes[0].x;
		double signed_volume = 0.0;
		for (const Face &face : faces) {
			signed_volume += _soft_body_signed_face_volume(face.n[0]->x, face.n[1]->x, face.n[2]->x, origin);
		}
		physics_softbody_adiabatic_pressure(xpbd_volume_original_rest, signed_volume,
				double(pressure_coefficient), double(gas_gamma), gas_pressure);
	}
	const bool apply_wind = !p_wind_areas.is_empty();
	const bool apply_drag = drag_coefficient > 0.0;
	const real_t tangential_drag_ratio = get_space() ? get_space()->get_soft_body_tangential_drag_ratio() : real_t(0.0);
	const real_t lift_coefficient = get_space() ? get_space()->get_soft_body_lift_coefficient() : real_t(0.0);
	const bool apply_lift = lift_coefficient > 0.0;
	if (!apply_pressure && !apply_wind && !apply_drag && !apply_lift) {
		return;
	}

	real_t volume = 0.0;
	const Vector3 &org = nodes[0].x;

	// Wind needs face forces but not volume. Skip three vector differences /
	// a cross product per face when pressure is disabled.
	for (const Face &face : faces) {
		if (legacy_pressure) {
			volume += vec3_dot(face.n[0]->x - org, vec3_cross(face.n[1]->x - org, face.n[2]->x - org));
		}

		if (apply_wind || apply_drag || apply_lift || gas_pressure > 0.0) {
			Vector3 node_force;
			if (apply_wind) {
				for (const GodotArea3D *area : p_wind_areas) {
					node_force += _compute_area_windforce(area, &face);
				}
			}

			if (gas_pressure > 0.0) {
				Vector3 gas_face_force;
				const int orientation = xpbd_volume_original_rest >= 0.0 ? 1 : -1;
				if (physics_softbody_adiabatic_face_force(face.n[0]->x, face.n[1]->x, face.n[2]->x,
						gas_pressure, orientation, gas_face_force)) {
					// Only movable nodes receive gas forces; pinned vertices remain fixed.
					for (int j = 0; j < 3; ++j) {
						if (face.n[j]->im > 0.0) {
							face.n[j]->f += gas_face_force;
						}
					}
				}
			}

			if ((apply_drag || apply_lift) && face.ra > CMP_EPSILON) {
				// Share one average face velocity between aerodynamic effects.
				// Drag dissipates normal motion; lift is orthogonal to the flow.
				const Vector3 face_velocity = (face.n[0]->v + face.n[1]->v + face.n[2]->v) * real_t(1.0 / 3.0);
				if (apply_drag) {
					Vector3 drag_per_node;
					const real_t inverse_mass_sum = face.n[0]->im + face.n[1]->im + face.n[2]->im;
					if (physics_softbody_quadratic_aerodynamic_force(
								face.normal, face_velocity, drag_coefficient, tangential_drag_ratio,
								face.ra, p_delta, inverse_mass_sum, drag_per_node)) {
						node_force += drag_per_node;
					}
				}
				if (apply_lift) {
					Vector3 lift_force;
					if (physics_softbody_compute_face_lift(face.normal, face_velocity, face.ra, lift_coefficient, lift_force)) {
						// Face lift is distributed equally; no additional storage.
						node_force += lift_force * real_t(1.0 / 3.0);
					}
				}
			}

			for (int j = 0; j < 3; j++) {
				face.n[j]->f += node_force;
			}
		}
	}

	if (legacy_pressure) {
		volume /= 6.0;
		const real_t absolute_volume = Math::abs(volume);
		// An open, flattened or degenerate mesh has no enclosed volume.
		// Never divide by zero (or propagate NaNs) when applying pressure.
		if (!(absolute_volume > CMP_EPSILON)) {
			return;
		}
		const real_t pressure_scale = pressure_coefficient / absolute_volume;
		for (Node &node : nodes) {
			if (node.im > 0) {
				node.f += node.n * (node.area * pressure_scale);
			}
		}
	}
}

Vector3 GodotSoftBody3D::_compute_area_windforce(const GodotArea3D *p_area, const Face *p_face) {
	const real_t magnitude = p_area->get_wind_force_magnitude();
	const Vector3 &wind_direction = p_area->get_wind_direction();
	const real_t projected_area = vec3_dot(p_face->normal, wind_direction) * p_face->ra;
	if (magnitude == 0.0 || projected_area == 0.0) {
		return Vector3();
	}

	// Zero attenuation is the default: avoid the transcendental pow() for
	// each face. Distance must be unsigned, since negative projections along
	// the wind direction yield NaNs for fractional attenuation exponents.
	real_t attenuation = 1.0;
	const real_t falloff = p_area->get_wind_attenuation_factor();
	if (falloff != 0.0) {
		const Vector3 distance = p_face->centroid - p_area->get_wind_source();
		// A minimum radius prevents infinite forces at the wind source.
		const real_t distance_squared = MAX(distance.length_squared(), real_t(1.0));
		attenuation = std::pow(distance_squared, -falloff * real_t(0.5));
	}

	const real_t nodal_force = magnitude * real_t(1.0 / 3.0) * projected_area * attenuation;
	return nodal_force * p_face->normal;
}

void GodotSoftBody3D::predict_motion(real_t p_delta) {
	const real_t inv_delta = 1.0 / p_delta;

	ERR_FAIL_NULL(get_space());

	bool gravity_done = false;
	Vector3 gravity;

	LocalVector<GodotArea3D *> wind_areas;

	int ac = areas.size();
	if (ac) {
		areas.sort();
		const AreaCMP *aa = &areas[0];
		for (int i = ac - 1; i >= 0; i--) {
			if (!gravity_done) {
				PS3DE::AreaSpaceOverrideMode area_gravity_mode = (PS3DE::AreaSpaceOverrideMode)(int)aa[i].area->get_param(PS3DE::AREA_PARAM_GRAVITY_OVERRIDE_MODE);
				if (area_gravity_mode != PS3DE::AREA_SPACE_OVERRIDE_DISABLED) {
					Vector3 area_gravity;
					aa[i].area->compute_gravity(get_transform().get_origin(), area_gravity);
					switch (area_gravity_mode) {
						case PS3DE::AREA_SPACE_OVERRIDE_COMBINE:
						case PS3DE::AREA_SPACE_OVERRIDE_COMBINE_REPLACE: {
							gravity += area_gravity;
							gravity_done = area_gravity_mode == PS3DE::AREA_SPACE_OVERRIDE_COMBINE_REPLACE;
						} break;
						case PS3DE::AREA_SPACE_OVERRIDE_REPLACE:
						case PS3DE::AREA_SPACE_OVERRIDE_REPLACE_COMBINE: {
							gravity = area_gravity;
							gravity_done = area_gravity_mode == PS3DE::AREA_SPACE_OVERRIDE_REPLACE;
						} break;
						default: {
						}
					}
				}
			}

			if (aa[i].area->get_wind_force_magnitude() > CMP_EPSILON) {
				wind_areas.push_back(aa[i].area);
			}
		}
	}

	// Add default gravity and damping from space area.
	if (!gravity_done) {
		GodotArea3D *default_area = get_space()->get_default_area();
		ERR_FAIL_NULL(default_area);

		Vector3 default_gravity;
		default_area->compute_gravity(get_transform().get_origin(), default_gravity);
		gravity += default_gravity;
	}

	// Apply forces.
	add_velocity(gravity * p_delta);
	if ((pressure_coefficient > CMP_EPSILON && Math::is_finite(pressure_coefficient)) || !wind_areas.is_empty() || drag_coefficient > 0.0 || get_space()->get_soft_body_lift_coefficient() > 0.0) {
		apply_forces(wind_areas, p_delta);
	}

	// An objective surface dashpot damps deformation rates rather than
	// world-space translation or rotation. Reuse the cached membrane rest
	// metrics even if StVK elasticity itself is disabled. No per-step
	// scratch is allocated. Pins remain unchanged by the mass-weighted pass.
	const real_t membrane_damping_rate = get_space()->get_soft_body_membrane_damping_rate();
	if (membrane_damping_rate > 0.0 && xpbd_membrane_rest.size() == faces.size() &&
			p_delta > 0.0) {
		const double fraction = 1.0 - Math::exp(-double(membrane_damping_rate) * double(p_delta));
		if (Math::is_finite(fraction) && fraction > 0.0 && fraction <= 1.0) {
			for (uint32_t face_index = 0; face_index < faces.size(); ++face_index) {
				const PhysicsXPBDMembraneRest &rest = xpbd_membrane_rest[face_index];
				if (!(rest.area > 0.0)) {
					continue;
				}
				Face &face = faces[face_index];
				physics_softbody_damp_membrane(
						face.n[0]->x, face.n[1]->x, face.n[2]->x,
						face.n[0]->v, face.n[1]->v, face.n[2]->v,
						face.n[0]->im, face.n[1]->im, face.n[2]->im,
						rest, fraction);
			}
		}
	}

	// Avoid soft body from 'exploding' so use some upper threshold of maximum motion
	// that a node can travel per frame.
	const real_t max_displacement = 1000.0;
	real_t clamp_delta_v = max_displacement * inv_delta;

	// The pair stage executes after body-local constraints have rewritten
	// Node::q. Preserve each particle's actual previous position only when
	// continuous inter-body collisions are enabled. The disabled mode adds
	// no extra per-node storage, passes, or BVH refits.
	const bool pair_ccd_enabled = get_space()->is_soft_body_pair_collision_ccd_enabled() &&
			get_space()->get_soft_body_pair_collision_thickness() > real_t(0.0);
	if (pair_ccd_enabled) {
		pair_ccd_previous.resize(nodes.size());
	} else if (!pair_ccd_previous.is_empty()) {
		pair_ccd_previous.reset();
	}
	// Integrate.
	for (Node &node : nodes) {
		if (pair_ccd_enabled) {
			pair_ccd_previous[node.index] = node.x;
		}
		node.q = node.x;
		if (node.im == 0.0) {
			// Inverse-mass-zero particles are kinematic (Jolt-style pins).
			// Do not integrate stale pre-pin velocity or accumulated forces.
			node.v = Vector3();
			node.bv = Vector3();
			node.f = Vector3();
			continue;
		}
		Vector3 delta_v = node.f * node.im * p_delta;
		for (int c = 0; c < 3; c++) {
			delta_v[c] = CLAMP(delta_v[c], -clamp_delta_v, clamp_delta_v);
		}
		node.v += delta_v;
		node.x += node.v * p_delta;
		node.f = Vector3();
	}

	// Bounds and tree update.
	update_bounds();

	// Node tree update.
	for (const Node &node : nodes) {
		AABB node_aabb(node.x, Vector3());
		node_aabb.expand_to(node.x + node.v * p_delta);
		node_aabb.grow_by(collision_margin);

		node_tree.update(node.leaf, node_aabb);
	}

	// Face tree update.
	if (!face_tree.is_empty()) {
		update_face_tree(p_delta);
	}

	// Optimize node tree.
	node_tree.optimize_incremental(1);
	face_tree.optimize_incremental(1);
}

// Rebuild on pin/mesh/rest-length changes only. Structural mesh edges are
// identified from faces instead of relying on link ordering: the link
// optimizer intentionally interleaves stretch and generated bending links.
void GodotSoftBody3D::rebuild_xpbd_tethers(real_t p_slack) {
	xpbd_tethers_dirty = false;
	if (nodes.is_empty() || faces.is_empty() || links.is_empty() ||
			dynamic_node_count >= nodes.size()) {
		xpbd_tethers.reset();
		return;
	}
	LocalVector<uint32_t> pins;
	pins.reserve(pinned_vertices.size());
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		if (nodes[i].im == real_t(0.0)) {
			pins.push_back(i);
		}
	}
	if (pins.is_empty()) {
		xpbd_tethers.reset();
		return;
	}
	// The soft-body link optimizer reorders all links after building the
	// two-hop bending constraints. Mark the original triangle edges once
	// and read their rest lengths from the reordered link array.
	HashSet<uint64_t> structural_edges;
	for (const Face &face : faces) {
		const uint32_t a = face.n[0]->index;
		const uint32_t b = face.n[1]->index;
		const uint32_t c = face.n[2]->index;
		structural_edges.insert(_soft_body_edge_key(a, b));
		structural_edges.insert(_soft_body_edge_key(b, c));
		structural_edges.insert(_soft_body_edge_key(c, a));
	}
	LocalVector<PhysicsXPBDTetherEdge> edges;
	edges.reserve(structural_edges.size());
	for (const Link &link : links) {
		if (!link.n[0] || !link.n[1]) {
			continue;
		}
		const uint32_t a = link.n[0]->index;
		const uint32_t b = link.n[1]->index;
		if (structural_edges.has(_soft_body_edge_key(a, b))) {
			edges.push_back({ a, b, link.rl });
		}
	}
	if (!physics_xpbd_build_tethers(nodes.size(), edges, pins, p_slack, xpbd_tethers)) {
		xpbd_tethers.reset();
	}
}

void GodotSoftBody3D::solve_constraints(real_t p_delta) {
	const real_t inv_delta = 1.0 / p_delta;

	if (link_constants_dirty) {
		update_link_constants();
	}

	// An optional link-aligned dashpot dissipates longitudinal spring
	// oscillation without damping rigid translation, rotation or tangential
	// motion. The exponential fraction is computed once per physics tick.
	// The default rate is zero, skipping the entire O(links) pass.
	const real_t link_damping = get_space()->get_soft_body_link_damping();
	if (link_damping > real_t(0.0) && p_delta > real_t(0.0)) {
		const double fraction = 1.0 - Math::exp(-double(link_damping) * double(p_delta));
		if (fraction > 0.0) {
			for (Link &link : links) {
				Node &a = *link.n[0];
				Node &b = *link.n[1];
				physics_softbody_damp_link(a.x, b.x, a.v, b.v, a.im, b.im, fraction);
			}
		}
	}

	// Rate-sensitive dashpots model viscoelastic shock absorption: only link
	// strain rates above the yield threshold are damped. Mass-weighted impulses
	// conserve momentum and leave pinned vertices untouched. With the default
	// coefficient=0, this entire O(links) pass is skipped.
	const real_t strain_rate_damping = get_space()->get_soft_body_strain_rate_damping();
	if (strain_rate_damping > real_t(0.0) && p_delta > real_t(0.0)) {
		const real_t strain_rate_yield = get_space()->get_soft_body_strain_rate_yield();
		for (Link &link : links) {
			Node &a = *link.n[0];
			Node &b = *link.n[1];
			physics_softbody_damp_strain_rate(a.x, b.x, a.v, b.v,
					a.im, b.im, link.rl, strain_rate_damping, strain_rate_yield, double(p_delta));
		}
	}

	// Angular dashpots remove relative hinge folding velocity (the mode that
	// longitudinal link damping does not damp). This belongs before the
	// velocity-to-position prediction below: after positional projections,
	// velocities are reconstructed from x-q and would overwrite late damping.
	// The rest-angle plasticity pass and XPBD bending stiffness are independent.
	const real_t dihedral_damping = get_space()->get_soft_body_dihedral_damping();
	if (dihedral_damping > real_t(0.0) && p_delta > real_t(0.0) && !xpbd_dihedral_hinges.is_empty()) {
		const double fraction = 1.0 - Math::exp(-double(dihedral_damping) * double(p_delta));
		if (Math::is_finite(fraction) && fraction > 0.0) {
			for (const DihedralHinge &hinge : xpbd_dihedral_hinges) {
				Node &a = nodes[hinge.a];
				Node &b = nodes[hinge.b];
				Node &c = nodes[hinge.c];
				Node &d = nodes[hinge.d];
				physics_softbody_damp_dihedral(a.x, b.x, c.x, d.x,
						a.v, b.v, c.v, d.v, a.im, b.im, c.im, d.im, fraction);
			}
		}
	}

	// Bulk (volumetric) viscosity removes rapid closed-shell breathing,
	// independently of link, bending and membrane shear damping. Apply at
	// velocity level BEFORE prediction, or post-solve reconstruction would
	// overwrite it. A zero rate avoids any face traversal or scratch work.
	const real_t volume_damping_rate = get_space()->get_soft_body_volume_damping_rate();
	if (volume_damping_rate > real_t(0.0) && p_delta > real_t(0.0) && xpbd_volume_closed) {
		const double fraction = 1.0 - Math::exp(-double(volume_damping_rate) * double(p_delta));
		damp_volume_rate(fraction);
	}

	// Objective Kelvin-Voigt viscosity is intrinsic to each 3D FEM element.
	// Unlike vertex damping, it leaves translation and rotation unchanged.
	// Apply at velocity level before the position prediction; each local
	// impulse is bounded to avoid increasing movable kinetic energy.
	// Zero viscosity skips all extra O(tetrahedra) work.
	const real_t tetra_viscosity = get_space()->get_soft_body_tetra_fem_viscosity();
	if (tetra_viscosity > real_t(0.0) && p_delta > real_t(0.0) &&
			!xpbd_fem_tetrahedra.is_empty()) {
		const double tetra_poisson = double(get_space()->get_soft_body_tetra_fem_poisson_ratio());
		for (const PhysicsFEMConvexTetra &tet : xpbd_fem_tetrahedra) {
			Node &a = nodes[tet.a];
			Node &b = nodes[tet.b];
			Node &c = nodes[tet.c];
			Node &d = nodes[tet.d];
			const Vector3 positions[4] = { a.x, b.x, c.x, d.x };
			Vector3 velocities[4] = { a.v, b.v, c.v, d.v };
			const real_t inv_mass[4] = { a.im, b.im, c.im, d.im };
			if (physics_fem_tetra_viscous_damp(positions, velocities, inv_mass,
						tet.rest, tetra_poisson, double(tetra_viscosity), double(p_delta))) {
				a.v = velocities[0];
				b.v = velocities[1];
				c.v = velocities[2];
				d.v = velocities[3];
			}
		}
	}

	// The old c2/c3 link-gradient prepass was unused by solve_links().
	// Avoid a full O(links) traversal and its potential division by zero.
	// Solve velocities.
	for (Node &node : nodes) {
		if (node.im == 0.0) {
			// A pin may have been edited after prediction but before solving.
			node.q = node.x;
			node.v = Vector3();
			continue;
		}
		node.x = node.q + node.v * p_delta;
	}

	// Local scalar continuum damage is evaluated on predicted positions
	// BEFORE the elastic XPBD projection removes the over-yield strain.
	// The strength history is updated once per fixed physics tick, not
	// per solver iteration, and remains irreversible until the rest mesh
	// is explicitly rebuilt. By default no damage arrays/loops exist.
	const real_t fem_damage_rate = get_space()->get_soft_body_tetra_damage_rate();
	if (fem_damage_rate > 0.0 && p_delta > 0.0 &&
			xpbd_fem_damage.size() == xpbd_fem_tetrahedra.size() &&
			!xpbd_fem_damage.is_empty()) {
		const double yield_strain = double(get_space()->get_soft_body_tetra_damage_yield_strain());
		const double poisson = double(get_space()->get_soft_body_tetra_fem_poisson_ratio());
		for (uint32_t i = 0; i < xpbd_fem_tetrahedra.size(); ++i) {
			const PhysicsFEMConvexTetra &tet = xpbd_fem_tetrahedra[i];
			const Vector3 positions[4] = {
				nodes[tet.a].x, nodes[tet.b].x,
				nodes[tet.c].x, nodes[tet.d].x
			};
			double equivalent_strain = 0.0;
			if (PhysicsFEMTetraDamage::equivalent_strain(
						positions, tet.rest, poisson, equivalent_strain)) {
				PhysicsFEMTetraDamage::evolve(equivalent_strain,
						yield_strain, double(fem_damage_rate),
						double(p_delta), xpbd_fem_damage[i]);
			}
		}
	}

	// Viscoplasticity acts on the *predicted* stretch before constraints
	// project it away. This also works with the stiff legacy PBD solver,
	// where post-solve links may be too close to rest to detect yielding.
	// By default the creep rate is zero and the entire pass is skipped.
	const real_t plastic_creep_rate = get_space()->get_soft_body_plastic_creep_rate();
	if (plastic_creep_rate > real_t(0.0) && p_delta > real_t(0.0)) {
		// Exponential integration makes creep independent of physics tick rate
		// for constant strain: f = 1 - exp(-creep_rate * delta_time).
		const double creep_fraction = 1.0 - Math::exp(-double(plastic_creep_rate) * double(p_delta));
		if (creep_fraction > 0.0) {
			const real_t yield_strain = get_space()->get_soft_body_plastic_yield_strain();
			const double max_length = double(std::numeric_limits<real_t>::max());
			for (Link &link : links) {
				const Vector3 &a = link.n[0]->x;
				const Vector3 &b = link.n[1]->x;
				const double dx = double(b.x) - double(a.x);
				const double dy = double(b.y) - double(a.y);
				const double dz = double(b.z) - double(a.z);
				const double length = Math::sqrt(dx * dx + dy * dy + dz * dz);
				if (length <= max_length &&
						physics_softbody_creep_rest_length(real_t(length), yield_strain, creep_fraction, link.rl)) {
					// Legacy PBD uses squared rest length; XPBD reads link.rl.
					link.c1 = link.rl * link.rl;
					xpbd_tethers_dirty = true;
				}
			}
		}
	}

	// Optional volumetric viscoplasticity, evaluated ONCE on predicted
	// positions before XPBD projects volume. This is separate from elastic
	// link creep and requires a validated closed shell and volume compliance.
	// No additional mesh storage or per-step face scan at the default rate=0.
	const real_t volume_creep_rate = get_space()->get_soft_body_volume_plastic_creep_rate();
	if (xpbd_volume_closed && get_space()->get_soft_body_xpbd_volume_compliance() > 0.0 &&
			volume_creep_rate > 0.0 && p_delta > 0.0) {
		const double creep_fraction = 1.0 - Math::exp(-double(volume_creep_rate) * double(p_delta));
		if (creep_fraction > 0.0 && Math::is_finite(creep_fraction)) {
			const Vector3 &origin = nodes[0].x;
			double current_volume = 0.0;
			for (const Face &face : faces) {
				current_volume += _soft_body_signed_face_volume(face.n[0]->x,
						face.n[1]->x, face.n[2]->x, origin);
			}
			physics_softbody_creep_rest_volume(current_volume,
					xpbd_volume_original_rest,
					get_space()->get_soft_body_volume_plastic_yield_strain(),
					creep_fraction, xpbd_volume_rest);
		}
	}

	// Optional, independent XPBD stretch and triangle area constraints.
	// Area preservation resists cloth shear/compression that edge lengths
	// alone do not fully control. Each lambda persists only within one step.
	const real_t configured_compliance = get_space() ? get_space()->get_soft_body_xpbd_compliance() : real_t(0.0);
	const double compliance = linear_stiffness > 0.0 ? double(configured_compliance) / double(linear_stiffness) : 0.0;
	const double alpha_double = p_delta > 0.0 ? compliance / (double(p_delta) * p_delta) : 0.0;
	const bool use_xpbd = compliance > 0.0 && Math::is_finite(alpha_double) && alpha_double > 0.0;
	const real_t tension_hardening = get_space() ? get_space()->get_soft_body_xpbd_tension_hardening() : real_t(0.0);
	const bool use_tension_hardening = use_xpbd && tension_hardening > real_t(0.0);
	const real_t compression_hardening = get_space() ? get_space()->get_soft_body_xpbd_compression_hardening() : real_t(0.0);
	const bool use_compression_hardening = use_xpbd && compression_hardening > real_t(0.0);
	const real_t parallel_ratio = get_space() ? get_space()->get_soft_body_xpbd_parallel_compliance_ratio() : real_t(1.0);
	const bool use_anisotropic_stretch = use_xpbd && parallel_ratio != real_t(1.0);
	const real_t fatigue_rate = get_space() ? get_space()->get_soft_body_fatigue_damage_rate() : real_t(0.0);
	const real_t fatigue_max = get_space() ? get_space()->get_soft_body_fatigue_max_damage() : real_t(0.0);
	const bool use_fatigue = use_xpbd && fatigue_rate > real_t(0.0) &&
			fatigue_max > real_t(0.0) && p_delta > real_t(0.0);
	// Unilateral strain limits supplement (rather than replace) the elastic
	// stretch solver. No extra per-link scratch or work with both ratios 0.
	const real_t strain_max_ratio = get_space() ? get_space()->get_soft_body_xpbd_strain_max_stretch_ratio() : real_t(0.0);
	const real_t strain_min_ratio = get_space() ? get_space()->get_soft_body_xpbd_strain_min_compression_ratio() : real_t(0.0);
	const double strain_compliance = get_space() ? double(get_space()->get_soft_body_xpbd_strain_limit_compliance()) : 0.0;
	const double strain_alpha = p_delta > 0.0 ? strain_compliance / (double(p_delta) * double(p_delta)) : 0.0;
	const bool use_strain_limits = (strain_min_ratio > 0.0 || strain_max_ratio > 0.0) &&
			!links.is_empty() && p_delta > 0.0 && Math::is_finite(strain_alpha);
	const real_t configured_area_compliance = get_space() ? get_space()->get_soft_body_xpbd_area_compliance() : real_t(0.0);
	const double area_alpha_double = p_delta > 0.0 ? double(configured_area_compliance) / (double(p_delta) * p_delta) : 0.0;
	const bool use_area_xpbd = configured_area_compliance > 0.0 && !faces.is_empty() &&
			Math::is_finite(area_alpha_double) && area_alpha_double > 0.0;
	const real_t alpha = use_xpbd ? real_t(MIN(alpha_double, double(std::numeric_limits<real_t>::max()))) : real_t(0.0);
	const real_t area_alpha = use_area_xpbd ? real_t(MIN(area_alpha_double, double(std::numeric_limits<real_t>::max()))) : real_t(0.0);
	const double membrane_compliance = get_space() ? double(get_space()->get_soft_body_xpbd_membrane_compliance()) : 0.0;
	const double membrane_alpha = p_delta > 0.0 ? membrane_compliance / (double(p_delta) * double(p_delta)) : 0.0;
	const bool use_membrane_xpbd = membrane_compliance > 0.0 && p_delta > 0.0 &&
			xpbd_membrane_rest.size() == faces.size() && !faces.is_empty() &&
			Math::is_finite(membrane_alpha) && membrane_alpha > 0.0;
	const double membrane_poisson = get_space() ? double(get_space()->get_soft_body_membrane_poisson_ratio()) : 0.3;
	const real_t configured_shear_compliance = get_space() ? get_space()->get_soft_body_xpbd_shear_compliance() : real_t(0.0);
	const double shear_alpha_double = p_delta > 0.0 ? double(configured_shear_compliance) / (double(p_delta) * double(p_delta)) : 0.0;
	const bool use_shear_xpbd = configured_shear_compliance > 0.0 && !faces.is_empty() &&
			xpbd_shear_rest_cosines.size() == faces.size() &&
			Math::is_finite(shear_alpha_double) && shear_alpha_double > 0.0;
	const real_t shear_alpha = use_shear_xpbd ? real_t(MIN(shear_alpha_double, double(std::numeric_limits<real_t>::max()))) : real_t(0.0);
	const double dihedral_compliance = get_space() ? double(get_space()->get_soft_body_xpbd_dihedral_compliance()) : 0.0;
	const double dihedral_alpha_double = p_delta > 0.0 ? dihedral_compliance / (double(p_delta) * double(p_delta)) : 0.0;
	const bool use_dihedral_xpbd = dihedral_compliance > 0.0 && !xpbd_dihedral_hinges.is_empty() &&
			Math::is_finite(dihedral_alpha_double) && dihedral_alpha_double > 0.0;
	const real_t dihedral_alpha = use_dihedral_xpbd ? real_t(MIN(dihedral_alpha_double, double(std::numeric_limits<real_t>::max()))) : real_t(0.0);
	const double fem_compliance = get_space() ? double(get_space()->get_soft_body_tetra_fem_compliance()) : 0.0;
	const double fem_alpha = p_delta > 0.0 ? fem_compliance / (double(p_delta) * double(p_delta)) : 0.0;
	const bool use_fem = !xpbd_fem_tetrahedra.is_empty() && fem_compliance > 0.0 && p_delta > 0.0 &&
			Math::is_finite(fem_alpha) && fem_alpha > 0.0;
	const double fem_poisson = get_space() ? double(get_space()->get_soft_body_tetra_fem_poisson_ratio()) : 0.3;
	const double fem_fiber_compliance = get_space() ? double(get_space()->get_soft_body_tetra_fiber_compliance()) : 0.0;
	const double fem_fiber_alpha = p_delta > 0.0 ? fem_fiber_compliance / (double(p_delta) * double(p_delta)) : 0.0;
	const bool use_fem_fiber = use_fem && fem_fiber_compliance > 0.0 &&
			Math::is_finite(fem_fiber_alpha) && fem_fiber_alpha > 0.0;
	const Vector3 fem_fiber_axis = get_space() ? get_space()->get_soft_body_tetra_fiber_axis() : Vector3(1, 0, 0);
	const bool use_fem_inversion_recovery = use_fem && get_space()->is_soft_body_tetra_inversion_recovery_enabled();
	const double fem_inversion_min_j = double(get_space()->get_soft_body_tetra_inversion_min_j());
	const double volume_compliance = get_space() ? double(get_space()->get_soft_body_xpbd_volume_compliance()) : 0.0;
	const double volume_alpha = p_delta > 0.0 ? volume_compliance / (double(p_delta) * double(p_delta)) : 0.0;
	const bool use_volume_xpbd = xpbd_volume_closed && volume_compliance > 0.0 &&
			Math::is_finite(volume_alpha) && volume_alpha > 0.0;
	// Long-range attachments cap distance from fixed vertices along the
	// structural mesh, without applying compression or creating ghost
	// forces inside the reachable range. They are opt-in and O(nodes)
	// per iteration once the nearest-pin graph has been built.
	const double tether_compliance = get_space() ? double(get_space()->get_soft_body_xpbd_tether_compliance()) : 0.0;
	const double tether_alpha_double = p_delta > 0.0 ? tether_compliance / (double(p_delta) * double(p_delta)) : 0.0;
	const bool use_tethers = tether_compliance > 0.0 && dynamic_node_count < nodes.size() &&
			Math::is_finite(tether_alpha_double) && tether_alpha_double > 0.0;
	const real_t tether_alpha = use_tethers ? real_t(MIN(tether_alpha_double, double(std::numeric_limits<real_t>::max()))) : real_t(0.0);
	if (use_tethers) {
		if (xpbd_tethers_dirty || xpbd_tethers.size() != nodes.size()) {
			rebuild_xpbd_tethers(get_space()->get_soft_body_xpbd_tether_slack());
		}
		for (PhysicsXPBDTether &tether : xpbd_tethers) {
			tether.lambda = 0.0; // XPBD lambda persists only within one step.
		}
	} else {
		if (!xpbd_tethers.is_empty()) {
			xpbd_tethers.reset();
		}
		xpbd_tethers_dirty = true;
	}

	if (use_xpbd) {
		xpbd_link_lambdas.resize(links.size());
		for (real_t &lambda : xpbd_link_lambdas) {
			lambda = real_t(0.0);
		}
	} else if (!xpbd_link_lambdas.is_empty()) {
		xpbd_link_lambdas.reset();
	}

	// Fatigue is stateful and follows the mesh's link ordering. Lazy storage
	// is allocated once, retained across frames, and destroyed on mesh reset.
	// Default damage rate=0 adds no per-link work or memory allocation.
	if (use_fatigue) {
		if (xpbd_link_fatigue_damage.size() != links.size()) {
			xpbd_link_fatigue_damage.resize(links.size());
			for (real_t &damage : xpbd_link_fatigue_damage) {
				damage = real_t(0.0);
			}
		}
	} else if (!xpbd_link_fatigue_damage.is_empty()) {
		xpbd_link_fatigue_damage.reset();
	}

	// Freeze nonlinear compliance for the whole physics step. Recomputing
	// alpha within iterations while retaining lambda causes oscillation.
	if (use_tension_hardening || use_compression_hardening || use_anisotropic_stretch || use_fatigue) {
		xpbd_link_hardening_alphas.resize(links.size());
		const real_t yield_strain = get_space()->get_soft_body_xpbd_tension_yield_strain();
		const real_t compression_yield = get_space()->get_soft_body_xpbd_compression_yield_strain();
		const Vector3 material_axis = get_space()->get_soft_body_xpbd_material_axis();
		const real_t fatigue_yield = use_fatigue ? get_space()->get_soft_body_fatigue_yield_strain() : real_t(0.0);
		for (uint32_t link_index = 0; link_index < links.size(); ++link_index) {
			const Link &link = links[link_index];
			real_t link_alpha = alpha;
			if (use_anisotropic_stretch) {
				// Use undeformed mesh coordinates, not live world-space link
				// directions. The fiber frame must follow the moving cloth.
				physics_xpbd_anisotropic_stretch_alpha(link.n[0]->s, link.n[1]->s,
						material_axis, alpha, parallel_ratio, link_alpha);
			}
			if (use_tension_hardening) {
				physics_xpbd_tension_hardening_alpha(link.n[0]->x, link.n[1]->x,
						link.rl, link_alpha, yield_strain, tension_hardening, link_alpha);
			}
			if (use_compression_hardening) {
				// Tension and compression are disjoint. Preserve the alpha set
				// above if this link happens to be in tension.
				physics_xpbd_compression_hardening_alpha(link.n[0]->x, link.n[1]->x,
						link.rl, link_alpha, compression_yield, compression_hardening, link_alpha);
			}
			if (use_fatigue) {
				// Use predicted deformation, before distance projection.
				// Damage evolves once per simulation step, never per iteration.
				real_t &damage = xpbd_link_fatigue_damage[link_index];
				physics_softbody_accumulate_fatigue_damage(link.n[0]->x, link.n[1]->x,
						link.rl, fatigue_yield, fatigue_rate, fatigue_max, double(p_delta), damage);
				physics_softbody_fatigue_compliance_alpha(link_alpha, damage, link_alpha);
			}
			xpbd_link_hardening_alphas[link_index] = link_alpha;
		}
	} else if (!xpbd_link_hardening_alphas.is_empty()) {
		xpbd_link_hardening_alphas.reset();
	}

	if (use_strain_limits) {
		xpbd_strain_lambdas.resize(links.size());
		for (PhysicsXPBDStrainLimitLambdas &multipliers : xpbd_strain_lambdas) {
			multipliers.stretch = 0.0;
			multipliers.compression = 0.0;
		}
	} else if (!xpbd_strain_lambdas.is_empty()) {
		xpbd_strain_lambdas.reset();
	}

	if (use_area_xpbd) {
		xpbd_area_lambdas.resize(faces.size());
		for (real_t &lambda : xpbd_area_lambdas) {
			lambda = real_t(0.0);
		}
	} else if (!xpbd_area_lambdas.is_empty()) {
		// The default zero-compliance setting consumes no per-face scratch.
		xpbd_area_lambdas.reset();
	}

	// A separate viscoplastic pass permanently changes the rest angle of
	// bent cloth hinges after exceeding their angular yield. Update at most
	// once per timestep (not once per solver iteration), before the XPBD
	// multipliers are reset; no extra per-hinge storage is necessary.
	const real_t bending_creep_rate = get_space() ? get_space()->get_soft_body_bending_plastic_creep_rate() : real_t(0.0);
	if (use_dihedral_xpbd && bending_creep_rate > real_t(0.0) && p_delta > real_t(0.0)) {
		const double creep_fraction = 1.0 - Math::exp(-double(bending_creep_rate) * double(p_delta));
		if (Math::is_finite(creep_fraction) && creep_fraction > 0.0) {
			const real_t yield = get_space()->get_soft_body_bending_plastic_yield_angle();
			for (DihedralHinge &hinge : xpbd_dihedral_hinges) {
				real_t angle = 0.0;
				if (physics_xpbd_dihedral_angle(nodes[hinge.a].x, nodes[hinge.b].x,
							nodes[hinge.c].x, nodes[hinge.d].x, angle)) {
					physics_softbody_creep_rest_dihedral(angle, yield, creep_fraction, hinge.rest_angle);
				}
			}
		}
	}

	if (use_membrane_xpbd) {
		xpbd_membrane_lambdas.resize(faces.size());
		for (double &lambda : xpbd_membrane_lambdas) {
			lambda = 0.0;
		}
	} else if (!xpbd_membrane_lambdas.is_empty()) {
		xpbd_membrane_lambdas.reset();
	}

	if (use_shear_xpbd) {
		xpbd_shear_lambdas.resize(faces.size());
		for (double &lambda : xpbd_shear_lambdas) {
			lambda = 0.0;
		}
	} else if (!xpbd_shear_lambdas.is_empty()) {
		xpbd_shear_lambdas.reset();
	}

	if (use_dihedral_xpbd) {
		xpbd_dihedral_lambdas.resize(xpbd_dihedral_hinges.size());
		for (real_t &lambda : xpbd_dihedral_lambdas) {
			lambda = real_t(0.0);
		}
	} else if (!xpbd_dihedral_lambdas.is_empty()) {
		xpbd_dihedral_lambdas.reset();
	}

	if (use_volume_xpbd) {
		// Reuse scratch at every iteration; one volume scalar lambda per step.
		xpbd_volume_gradients.resize(nodes.size());
	} else if (!xpbd_volume_gradients.is_empty() && get_space()->get_soft_body_volume_damping_rate() <= 0.0) {
		// Keep bulk-viscosity scratch across steps without reallocation.
		xpbd_volume_gradients.reset();
	}
	double volume_lambda = 0.0;
	// Each FEM tetrahedron owns its XPBD multiplier. Reset once per
	// physics tick; retain it across all nonlinear solver iterations.
	if (use_fem) {
		for (PhysicsFEMConvexTetra &tetra : xpbd_fem_tetrahedra) {
			tetra.lambda = 0.0;
		}
	}
	// Fiber multipliers are per-tet and persist only within the current
	// step. The default 0 compliance allocates no scratch or solver work.
	if (use_fem_fiber) {
		xpbd_fem_fiber_lambdas.resize(xpbd_fem_tetrahedra.size());
		for (double &lambda : xpbd_fem_fiber_lambdas) {
			lambda = 0.0;
		}
	} else if (!xpbd_fem_fiber_lambdas.is_empty()) {
		xpbd_fem_fiber_lambdas.reset();
	}

	// Distribute frame-level shape stiffness over solver iterations. For a
	// fixed total stiffness, increasing iteration_count should not multiply
	// the corrective strength by that many times.
	const real_t shape_matching_stiffness = get_space()->get_soft_body_shape_matching_stiffness();
	const real_t shape_matching_iteration_strength =
			shape_matching_stiffness > 0.0 && iteration_count > 0 &&
					(!xpbd_shape_rest_offsets.is_empty() || !xpbd_shape_clusters.is_empty()) ?
			real_t(1.0 - Math::pow(1.0 - double(shape_matching_stiffness),
					1.0 / double(iteration_count))) :
			real_t(0.0);

	for (int isolve = 0; isolve < iteration_count; ++isolve) {
		if (use_xpbd) {
			for (uint32_t link_index = 0; link_index < links.size(); ++link_index) {
				Link &link = links[link_index];
				if (link.c0 > 0.0) {
					physics_xpbd_solve_distance(link.n[0]->x, link.n[1]->x,
							link.n[0]->im, link.n[1]->im, link.rl,
							(use_tension_hardening || use_compression_hardening || use_anisotropic_stretch || use_fatigue) ? xpbd_link_hardening_alphas[link_index] : alpha,
							xpbd_link_lambdas[link_index]);
				}
			}
		} else {
			// Preserve the legacy link solver when XPBD stretch is disabled.
			const real_t ti = isolve / (real_t)iteration_count;
			solve_links(1.0, ti);
		}
		if (use_strain_limits) {
			for (uint32_t link_index = 0; link_index < links.size(); ++link_index) {
				Link &link = links[link_index];
				physics_xpbd_solve_strain_limits(link.n[0]->x, link.n[1]->x,
						link.n[0]->im, link.n[1]->im, link.rl,
						strain_min_ratio, strain_max_ratio, strain_alpha,
						xpbd_strain_lambdas[link_index]);
			}
		}
		if (use_area_xpbd) {
			for (uint32_t face_index = 0; face_index < faces.size(); ++face_index) {
				Face &face = faces[face_index];
				physics_xpbd_solve_triangle_area(face.n[0]->x, face.n[1]->x, face.n[2]->x,
						face.n[0]->im, face.n[1]->im, face.n[2]->im,
						face.ra, area_alpha, xpbd_area_lambdas[face_index]);
			}
		}
		if (use_membrane_xpbd) {
			for (uint32_t face_index = 0; face_index < faces.size(); ++face_index) {
				const PhysicsXPBDMembraneRest &rest = xpbd_membrane_rest[face_index];
				if (!(rest.area > 0.0)) {
					continue;
				}
				Face &face = faces[face_index];
				physics_xpbd_membrane_solve(face.n[0]->x, face.n[1]->x, face.n[2]->x,
						face.n[0]->im, face.n[1]->im, face.n[2]->im,
						rest, membrane_poisson, membrane_alpha, xpbd_membrane_lambdas[face_index]);
			}
		}
		if (use_shear_xpbd) {
			for (uint32_t face_index = 0; face_index < faces.size(); ++face_index) {
				const real_t rest_cosine = xpbd_shear_rest_cosines[face_index];
				if (rest_cosine < -1.0 || rest_cosine > 1.0) {
					continue;
				}
				Face &face = faces[face_index];
				physics_xpbd_solve_triangle_shear(face.n[0]->x, face.n[1]->x, face.n[2]->x,
						face.n[0]->im, face.n[1]->im, face.n[2]->im,
						rest_cosine, shear_alpha, xpbd_shear_lambdas[face_index]);
			}
		}
		if (use_dihedral_xpbd) {
			for (uint32_t hinge_index = 0; hinge_index < xpbd_dihedral_hinges.size(); ++hinge_index) {
				const DihedralHinge &hinge = xpbd_dihedral_hinges[hinge_index];
				Node &a = nodes[hinge.a];
				Node &b = nodes[hinge.b];
				Node &c = nodes[hinge.c];
				Node &d = nodes[hinge.d];
				physics_xpbd_solve_dihedral(a.x, b.x, c.x, d.x,
						a.im, b.im, c.im, d.im, hinge.rest_angle,
						dihedral_alpha, xpbd_dihedral_lambdas[hinge_index]);
			}
		}
		if (shape_matching_iteration_strength > 0.0) {
			solve_shape_matching(shape_matching_iteration_strength);
		}
		if (use_fem) {
			const bool has_damage = xpbd_fem_damage.size() == xpbd_fem_tetrahedra.size() &&
					!xpbd_fem_damage.is_empty();
			for (uint32_t i = 0; i < xpbd_fem_tetrahedra.size(); ++i) {
				PhysicsFEMConvexTetra &tetra = xpbd_fem_tetrahedra[i];
				Node &a = nodes[tetra.a];
				Node &b = nodes[tetra.b];
				Node &c = nodes[tetra.c];
				Node &d = nodes[tetra.d];
				// Neo-Hookean log(J) has no valid gradient for J<=0. Repair
				// strongly compressed or inverted elements first using a bounded,
				// mass-weighted unilateral volume constraint. An intact element
				// is untouched, as is the whole solver with recovery disabled.
				if (use_fem_inversion_recovery) {
					physics_fem_tetra_recover_orientation(a.x, b.x, c.x, d.x,
							a.im, b.im, c.im, d.im, tetra.rest, fem_inversion_min_j);
				}
				double local_alpha = fem_alpha;
				if (has_damage) {
					PhysicsFEMTetraDamage::effective_compliance(
							fem_alpha, xpbd_fem_damage[i], local_alpha);
				}
				physics_fem_tetra_solve(a.x, b.x, c.x, d.x,
						a.im, b.im, c.im, d.im,
						tetra.rest, fem_poisson, local_alpha, tetra.lambda);
			}
		}
		if (use_fem_fiber) {
			// A damaged tetrahedron must also lose reinforcement strength:
			// leaving its fiber stiffness untouched makes the apparent
			// fracture yield anisotropically inconsistent. The per-tetra
			// scalar is already cached for Neo-Hookean softening.
			const bool fibers_have_damage = xpbd_fem_damage.size() == xpbd_fem_tetrahedra.size() &&
					!xpbd_fem_damage.is_empty();
			for (uint32_t tet_index = 0; tet_index < xpbd_fem_tetrahedra.size(); ++tet_index) {
				const PhysicsFEMConvexTetra &tetra = xpbd_fem_tetrahedra[tet_index];
				Node &a = nodes[tetra.a];
				Node &b = nodes[tetra.b];
				Node &c = nodes[tetra.c];
				Node &d = nodes[tetra.d];
				double local_fiber_alpha = fem_fiber_alpha;
				if (fibers_have_damage) {
					PhysicsFEMTetraDamage::effective_compliance(
							fem_fiber_alpha, xpbd_fem_damage[tet_index], local_fiber_alpha);
				}
				physics_fem_tetra_solve_fiber(a.x, b.x, c.x, d.x,
						a.im, b.im, c.im, d.im, tetra.rest,
						fem_fiber_axis, local_fiber_alpha, xpbd_fem_fiber_lambdas[tet_index]);
			}
		}
		if (use_volume_xpbd) {
			solve_volume_constraint(volume_alpha, volume_lambda);
		}
		if (use_tethers) {
			for (uint32_t node_index = 0; node_index < xpbd_tethers.size(); ++node_index) {
				PhysicsXPBDTether &tether = xpbd_tethers[node_index];
				if (tether.anchor >= nodes.size() || tether.anchor == node_index ||
						nodes[node_index].im <= 0.0 || nodes[tether.anchor].im != 0.0) {
					continue;
				}
				physics_xpbd_solve_tether(nodes[node_index].x, nodes[tether.anchor].x,
						nodes[node_index].im, tether.max_length, tether_alpha, tether.lambda);
			}
		}
	}
	// Run non-adjacent fold self-contacts after all material projections.
	solve_self_collisions(p_delta);
	const real_t vc = (1.0 - damping_coefficient) * inv_delta;
	for (Node &node : nodes) {
		if (node.im == 0.0) {
			// Pinned positions are controlled externally, not by bias impulses.
			node.bv = Vector3();
			node.v = Vector3();
			node.q = node.x;
			continue;
		}
		node.x += node.bv * p_delta;
		node.bv = Vector3();

		node.v = (node.x - node.q) * vc;

		node.q = node.x;
	}

	update_normals_and_centroids();
	// Local XPBD projections have finished; cache a conservative union of
	// the previous and the FINAL current positions for the pair broadphase.
	refresh_pair_ccd_swept_bounds();
}

void GodotSoftBody3D::solve_links(real_t kst, real_t ti) {
	for (Link &link : links) {
		if (link.c0 > 0) {
			Node &node_a = *link.n[0];
			Node &node_b = *link.n[1];
			const Vector3 del = node_b.x - node_a.x;
			const real_t len = del.length_squared();
			if (link.c1 + len > CMP_EPSILON) {
				const real_t k = ((link.c1 - len) / (link.c0 * (link.c1 + len))) * kst;
				node_a.x -= del * (k * node_a.im);
				node_b.x += del * (k * node_b.im);
			}
		}
	}
}

struct AABBQueryResult {
	const GodotSoftBody3D *soft_body = nullptr;
	void *userdata = nullptr;
	GodotSoftBody3D::QueryResultCallback result_callback = nullptr;

	_FORCE_INLINE_ bool operator()(void *p_data) {
		return result_callback(soft_body->get_node_index(p_data), userdata);
	}
};

void GodotSoftBody3D::query_aabb(const AABB &p_aabb, GodotSoftBody3D::QueryResultCallback p_result_callback, void *p_userdata) {
	AABBQueryResult query_result;
	query_result.soft_body = this;
	query_result.result_callback = p_result_callback;
	query_result.userdata = p_userdata;

	node_tree.aabb_query(p_aabb, query_result);
}

struct RayQueryResult {
	const GodotSoftBody3D *soft_body = nullptr;
	void *userdata = nullptr;
	GodotSoftBody3D::QueryResultCallback result_callback = nullptr;

	_FORCE_INLINE_ bool operator()(void *p_data) {
		return result_callback(soft_body->get_face_index(p_data), userdata);
	}
};

void GodotSoftBody3D::query_ray(const Vector3 &p_from, const Vector3 &p_to, GodotSoftBody3D::QueryResultCallback p_result_callback, void *p_userdata) {
	if (face_tree.is_empty()) {
		initialize_face_tree();
	}

	RayQueryResult query_result;
	query_result.soft_body = this;
	query_result.result_callback = p_result_callback;
	query_result.userdata = p_userdata;

	face_tree.ray_query(p_from, p_to, query_result);
}

void GodotSoftBody3D::initialize_face_tree() {
	face_tree.clear();
	for (Face &face : faces) {
		AABB face_aabb;

		face_aabb.position = face.n[0]->x;
		face_aabb.expand_to(face.n[1]->x);
		face_aabb.expand_to(face.n[2]->x);

		face_aabb.grow_by(collision_margin);

		face.leaf = face_tree.insert(face_aabb, &face);
	}
}

void GodotSoftBody3D::update_face_tree(real_t p_delta) {
	for (const Face &face : faces) {
		AABB face_aabb;

		const Node *node0 = face.n[0];
		face_aabb.position = node0->x;
		face_aabb.expand_to(node0->x + node0->v * p_delta);

		const Node *node1 = face.n[1];
		face_aabb.expand_to(node1->x);
		face_aabb.expand_to(node1->x + node1->v * p_delta);

		const Node *node2 = face.n[2];
		face_aabb.expand_to(node2->x);
		face_aabb.expand_to(node2->x + node2->v * p_delta);

		face_aabb.grow_by(collision_margin);

		face_tree.update(face.leaf, face_aabb);
	}
}

// Continuous self-contact broadphase: union of previous (q) and current
// (x) triangle endpoints, expanded by the collision thickness. Even when
// a vertex and face are far apart at the END of a frame, their swept
// volumes can intersect. This is conservative for linear trajectories.
void GodotSoftBody3D::update_swept_face_tree(real_t p_thickness) {
	const real_t margin = MAX(real_t(0.0), collision_margin) + p_thickness;
	for (const Face &face : faces) {
		const Node *a = face.n[0];
		const Node *b = face.n[1];
		const Node *c = face.n[2];
		if (!a->q.is_finite() || !b->q.is_finite() || !c->q.is_finite() ||
				!a->x.is_finite() || !b->x.is_finite() || !c->x.is_finite()) {
			continue;
		}
		AABB swept(a->q, Vector3());
		swept.expand_to(b->q);
		swept.expand_to(c->q);
		swept.expand_to(a->x);
		swept.expand_to(b->x);
		swept.expand_to(c->x);
		swept.grow_by(margin);
		face_tree.update(face.leaf, swept);
	}
}

// A swept BVH for INTER-body contacts, using the opt-in history vector
// rather than Node::q (which the local solver has already overwritten).
// Both endpoints of each moving face are enclosed conservatively.
void GodotSoftBody3D::update_pair_swept_face_tree(real_t p_thickness) {
	if (pair_ccd_previous.size() != nodes.size()) {
		return;
	}
	const real_t margin = MAX(real_t(0.0), collision_margin) + p_thickness;
	for (const Face &face : faces) {
		const Node &a = *face.n[0];
		const Node &b = *face.n[1];
		const Node &c = *face.n[2];
		const Vector3 &pa = pair_ccd_previous[a.index];
		const Vector3 &pb = pair_ccd_previous[b.index];
		const Vector3 &pc = pair_ccd_previous[c.index];
		if (!pa.is_finite() || !pb.is_finite() || !pc.is_finite() ||
				!a.x.is_finite() || !b.x.is_finite() || !c.x.is_finite()) {
			continue;
		}
		AABB swept(pa, Vector3());
		swept.expand_to(pb);
		swept.expand_to(pc);
		swept.expand_to(a.x);
		swept.expand_to(b.x);
		swept.expand_to(c.x);
		swept.grow_by(margin);
		face_tree.update(face.leaf, swept);
	}
}

void GodotSoftBody3D::refresh_pair_ccd_swept_bounds() {
	if (pair_ccd_previous.is_empty() || pair_ccd_previous.size() != nodes.size()) {
		return;
	}
	if (!nodes[0].x.is_finite()) {
		pair_ccd_previous.reset();
		return;
	}
	AABB swept(nodes[0].x, Vector3());
	for (const Node &node : nodes) {
		const Vector3 &previous = pair_ccd_previous[node.index];
		if (!previous.is_finite() || !node.x.is_finite()) {
			pair_ccd_previous.reset();
			return;
		}
		swept.expand_to(previous);
		swept.expand_to(node.x);
	}
	pair_ccd_swept_bounds = swept;
}

void GodotSoftBody3D::initialize_shape(bool p_force_move) {
	if (get_shape_count() == 0) {
		GodotSoftBodyShape3D *soft_body_shape = memnew(GodotSoftBodyShape3D(this));
		add_shape(soft_body_shape);
	} else if (p_force_move) {
		GodotSoftBodyShape3D *soft_body_shape = static_cast<GodotSoftBodyShape3D *>(get_shape(0));
		soft_body_shape->update_bounds();
	}
}

void GodotSoftBody3D::deinitialize_shape() {
	if (get_shape_count() > 0) {
		GodotShape3D *shape = get_shape(0);
		remove_shape(shape);
		memdelete(shape);
	}
}

void GodotSoftBody3D::destroy() {
	link_constants_dirty = false;
	xpbd_tethers.reset();
	xpbd_tethers_dirty = true;
	dynamic_node_count = 0;
	soft_mesh = RID();

	map_visual_to_physics.clear();

	node_tree.clear();
	face_tree.clear();

	xpbd_link_lambdas.reset();
	xpbd_link_hardening_alphas.reset();
	xpbd_link_fatigue_damage.reset();
	xpbd_strain_lambdas.reset();
	xpbd_area_lambdas.reset();
	xpbd_shear_rest_cosines.reset();
	xpbd_shear_lambdas.reset();
	xpbd_membrane_rest.reset();
	xpbd_membrane_lambdas.reset();
	xpbd_dihedral_hinges.reset();
	xpbd_dihedral_lambdas.reset();
	xpbd_shape_rest_offsets.reset();
	xpbd_shape_clusters.reset();
	xpbd_shape_cluster_members.reset();
	xpbd_shape_cluster_rest_offsets.reset();
	xpbd_shape_cluster_displacements.reset();
	xpbd_shape_cluster_counts.reset();
	xpbd_self_contacts.reset();
	xpbd_self_ccd_contacts.reset();
	xpbd_self_neighbor_edges.reset();
	xpbd_self_edge_tree.clear();
	xpbd_self_edges.reset();
	xpbd_self_edge_contacts.reset();
	xpbd_pair_edge_tree.clear();
	xpbd_pair_edges.reset();
	xpbd_volume_gradients.reset();
	xpbd_volume_closed = false;
	xpbd_volume_rest = 0.0;
	xpbd_volume_original_rest = 0.0;
	xpbd_fem_tetrahedra.reset();
	xpbd_fem_fiber_lambdas.reset();
	xpbd_fem_damage.reset();
	xpbd_fem_mass_fractions.reset();
	nodes.clear();
	links.clear();
	faces.clear();

	bounds = AABB();
	deinitialize_shape();
}

void GodotSoftBodyShape3D::update_bounds() {
	ERR_FAIL_NULL(soft_body);

	AABB collision_aabb = soft_body->get_bounds();
	collision_aabb.grow_by(soft_body->get_collision_margin());
	configure(collision_aabb);
}

GodotSoftBodyShape3D::GodotSoftBodyShape3D(GodotSoftBody3D *p_soft_body) {
	soft_body = p_soft_body;
	update_bounds();
}

struct _SoftBodyIntersectSegmentInfo {
	const GodotSoftBody3D *soft_body = nullptr;
	Vector3 from;
	Vector3 direction;
	Vector3 hit_position;
	Vector3 hit_normal;
	uint32_t hit_face_index = UINT32_MAX;
	real_t closest_fraction = 1.0;
	real_t minimum_fraction = 0.0;
	bool hit_back_faces = false;

	static bool process_hit(uint32_t p_face_index, void *p_userdata) {
		_SoftBodyIntersectSegmentInfo &query_info = *(static_cast<_SoftBodyIntersectSegmentInfo *>(p_userdata));

		Vector3 points[3];
		query_info.soft_body->get_face_points(p_face_index, points[0], points[1], points[2]);

		// Moller-Trumbore on the *finite* segment, without normalizing its
		// direction. The intersection parameter is already the segment
		// fraction, so there is no squared-distance overflow or extra
		// division to determine which triangle is closest.
		const Vector3 e1 = points[1] - points[0];
		const Vector3 e2 = points[2] - points[0];
		const Vector3 h = query_info.direction.cross(e2);
		const real_t determinant = e1.dot(h);
		if (Math::is_zero_approx(determinant)) {
			return false;
		}
		const bool back_face = determinant < 0.0;
		if (back_face && !query_info.hit_back_faces) {
			return false;
		}

		const real_t inverse_determinant = 1.0 / determinant;
		const Vector3 relative_origin = query_info.from - points[0];
		const real_t u = relative_origin.dot(h) * inverse_determinant;
		if (u < 0.0 || u > 1.0) {
			return false;
		}
		const Vector3 q = relative_origin.cross(e1);
		const real_t v = query_info.direction.dot(q) * inverse_determinant;
		if (v < 0.0 || u + v > 1.0) {
			return false;
		}

		const real_t fraction = e2.dot(q) * inverse_determinant;
		// Compare against a world-distance epsilon. A fixed fraction epsilon
		// incorrectly rejects valid near-origin hits on kilometer-long rays.
		if (!(fraction > query_info.minimum_fraction && fraction <= 1.0) ||
				(query_info.hit_face_index != UINT32_MAX && fraction >= query_info.closest_fraction)) {
			return false;
		}

		Vector3 normal = e1.cross(e2);
		normal.normalize();
		query_info.closest_fraction = fraction;
		query_info.hit_position = query_info.from + query_info.direction * fraction;
		query_info.hit_normal = back_face ? -normal : normal;
		query_info.hit_face_index = p_face_index;
		return false; // Continue: another BVH leaf may contain a closer face.
	}
};

bool GodotSoftBodyShape3D::intersect_segment(const Vector3 &p_begin, const Vector3 &p_end, Vector3 &r_result, Vector3 &r_normal, int &r_face_index, bool p_hit_back_faces) const {
	const Vector3 direction = p_end - p_begin;
	const real_t max_component = MAX(Math::abs(direction.x), MAX(Math::abs(direction.y), Math::abs(direction.z)));
	if (!(max_component > CMP_EPSILON)) {
		return false;
	}

	_SoftBodyIntersectSegmentInfo query_info;
	query_info.soft_body = soft_body;
	query_info.from = p_begin;
	query_info.direction = direction;
	query_info.hit_back_faces = p_hit_back_faces;
	query_info.minimum_fraction = CMP_EPSILON / max_component;

	soft_body->query_ray(p_begin, p_end, _SoftBodyIntersectSegmentInfo::process_hit, &query_info);

	if (query_info.hit_face_index != UINT32_MAX) {
		r_result = query_info.hit_position;
		r_normal = query_info.hit_normal;
		r_face_index = int(query_info.hit_face_index);
		return true;
	}

	return false;
}

bool GodotSoftBodyShape3D::intersect_point(const Vector3 &p_point) const {
	return false;
}

Vector3 GodotSoftBodyShape3D::get_closest_point_to(const Vector3 &p_point) const {
	ERR_FAIL_V_MSG(Vector3(), "Get closest point is not supported for soft bodies.");
}
