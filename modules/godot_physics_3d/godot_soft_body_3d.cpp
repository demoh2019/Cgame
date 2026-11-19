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
#include "servers/physics_softbody_plasticity.h"
#include "servers/physics_softbody_volume_safe.h"
#include "servers/physics_xpbd_distance.h"
#include "servers/physics_xpbd_area.h"
#include "servers/physics_xpbd_dihedral.h"
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
	// its rest volume only after space-level compliance is available.
	initialize_volume_constraint();
	initialize_dihedral_constraints();

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
	initialize_dihedral_constraints();
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
	if (!get_space() || get_space()->get_soft_body_xpbd_volume_compliance() <= 0.0 ||
			nodes.size() < 4 || faces.size() < 4) {
		// Never keep the per-node buffer for ordinary cloth/disabled settings.
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
	xpbd_volume_closed = true;
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
				node.im = nodes.size() * inv_total_mass;
				link_constants_dirty = true;
			}

			return;
		}
	}
}

void GodotSoftBody3D::unpin_all_vertices() {
	if (!soft_mesh.is_null() && !pinned_vertices.is_empty()) {
		const real_t inv_node_mass = nodes.size() * inv_total_mass;
		for (const int pinned_vertex : pinned_vertices) {
			ERR_CONTINUE(pinned_vertex < 0 || pinned_vertex >= (int)map_visual_to_physics.size());
			const uint32_t node_index = map_visual_to_physics[pinned_vertex];

			ERR_CONTINUE(node_index >= nodes.size());
			Node &node = nodes[node_index];
			if (node.im == 0.0) {
					// Repeated visual indices must not count a welded node twice.
					++dynamic_node_count;
			}
			node.im = inv_node_mass;
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

void GodotSoftBody3D::apply_forces(const LocalVector<GodotArea3D *> &p_wind_areas) {
	if (nodes.is_empty()) {
		return;
	}

	const bool apply_pressure = pressure_coefficient > CMP_EPSILON;
	const bool apply_wind = !p_wind_areas.is_empty();
	const bool apply_drag = drag_coefficient > 0.0;
	if (!apply_pressure && !apply_wind && !apply_drag) {
		return;
	}

	real_t volume = 0.0;
	const Vector3 &org = nodes[0].x;

	// Wind needs face forces but not volume. Skip three vector differences /
	// a cross product per face when pressure is disabled.
	for (const Face &face : faces) {
		if (apply_pressure) {
			volume += vec3_dot(face.n[0]->x - org, vec3_cross(face.n[1]->x - org, face.n[2]->x - org));
		}

		if (apply_wind || apply_drag) {
			Vector3 node_force;
			if (apply_wind) {
				for (const GodotArea3D *area : p_wind_areas) {
					node_force += _compute_area_windforce(area, &face);
				}
			}

			if (apply_drag && face.ra > CMP_EPSILON) {
				// Quadratic aerodynamic drag against still air, projected onto
				// the triangle normal (two-sided cloth). Average node velocity
				// prevents seams from receiving inconsistent drag directions.
				// The face force -0.5 * Cd * area * vn * abs(vn) is shared by
				// its three nodes, requiring no additional per-vertex storage.
				const Vector3 face_velocity = (face.n[0]->v + face.n[1]->v + face.n[2]->v) * real_t(1.0 / 3.0);
				const real_t normal_speed = face.normal.dot(face_velocity);
				if (Math::abs(normal_speed) > CMP_EPSILON) {
					const real_t drag_per_node = -drag_coefficient * face.ra * real_t(1.0 / 6.0) * normal_speed * Math::abs(normal_speed);
					node_force += face.normal * drag_per_node;
				}
			}

			for (int j = 0; j < 3; j++) {
				face.n[j]->f += node_force;
			}
		}
	}

	if (apply_pressure) {
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
	if (pressure_coefficient > CMP_EPSILON || !wind_areas.is_empty() || drag_coefficient > 0.0) {
		apply_forces(wind_areas);
	}

	// Avoid soft body from 'exploding' so use some upper threshold of maximum motion
	// that a node can travel per frame.
	const real_t max_displacement = 1000.0;
	real_t clamp_delta_v = max_displacement * inv_delta;

	// Integrate.
	for (Node &node : nodes) {
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

	// Optional, independent XPBD stretch and triangle area constraints.
	// Area preservation resists cloth shear/compression that edge lengths
	// alone do not fully control. Each lambda persists only within one step.
	const real_t configured_compliance = get_space() ? get_space()->get_soft_body_xpbd_compliance() : real_t(0.0);
	const double compliance = linear_stiffness > 0.0 ? double(configured_compliance) / double(linear_stiffness) : 0.0;
	const double alpha_double = p_delta > 0.0 ? compliance / (double(p_delta) * p_delta) : 0.0;
	const bool use_xpbd = compliance > 0.0 && Math::is_finite(alpha_double) && alpha_double > 0.0;
	const real_t configured_area_compliance = get_space() ? get_space()->get_soft_body_xpbd_area_compliance() : real_t(0.0);
	const double area_alpha_double = p_delta > 0.0 ? double(configured_area_compliance) / (double(p_delta) * p_delta) : 0.0;
	const bool use_area_xpbd = configured_area_compliance > 0.0 && !faces.is_empty() &&
			Math::is_finite(area_alpha_double) && area_alpha_double > 0.0;
	const real_t alpha = use_xpbd ? real_t(MIN(alpha_double, double(std::numeric_limits<real_t>::max()))) : real_t(0.0);
	const real_t area_alpha = use_area_xpbd ? real_t(MIN(area_alpha_double, double(std::numeric_limits<real_t>::max()))) : real_t(0.0);
	const double dihedral_compliance = get_space() ? double(get_space()->get_soft_body_xpbd_dihedral_compliance()) : 0.0;
	const double dihedral_alpha_double = p_delta > 0.0 ? dihedral_compliance / (double(p_delta) * double(p_delta)) : 0.0;
	const bool use_dihedral_xpbd = dihedral_compliance > 0.0 && !xpbd_dihedral_hinges.is_empty() &&
			Math::is_finite(dihedral_alpha_double) && dihedral_alpha_double > 0.0;
	const real_t dihedral_alpha = use_dihedral_xpbd ? real_t(MIN(dihedral_alpha_double, double(std::numeric_limits<real_t>::max()))) : real_t(0.0);
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

	if (use_area_xpbd) {
		xpbd_area_lambdas.resize(faces.size());
		for (real_t &lambda : xpbd_area_lambdas) {
			lambda = real_t(0.0);
		}
	} else if (!xpbd_area_lambdas.is_empty()) {
		// The default zero-compliance setting consumes no per-face scratch.
		xpbd_area_lambdas.reset();
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
	} else if (!xpbd_volume_gradients.is_empty()) {
		xpbd_volume_gradients.reset();
	}
	double volume_lambda = 0.0;

	for (int isolve = 0; isolve < iteration_count; ++isolve) {
		if (use_xpbd) {
			for (uint32_t link_index = 0; link_index < links.size(); ++link_index) {
				Link &link = links[link_index];
				if (link.c0 > 0.0) {
					physics_xpbd_solve_distance(link.n[0]->x, link.n[1]->x,
							link.n[0]->im, link.n[1]->im, link.rl,
							alpha, xpbd_link_lambdas[link_index]);
				}
			}
		} else {
			// Preserve the legacy link solver when XPBD stretch is disabled.
			const real_t ti = isolve / (real_t)iteration_count;
			solve_links(1.0, ti);
		}
		if (use_area_xpbd) {
			for (uint32_t face_index = 0; face_index < faces.size(); ++face_index) {
				Face &face = faces[face_index];
				physics_xpbd_solve_triangle_area(face.n[0]->x, face.n[1]->x, face.n[2]->x,
						face.n[0]->im, face.n[1]->im, face.n[2]->im,
						face.ra, area_alpha, xpbd_area_lambdas[face_index]);
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
	xpbd_area_lambdas.reset();
	xpbd_dihedral_hinges.reset();
	xpbd_dihedral_lambdas.reset();
	xpbd_volume_gradients.reset();
	xpbd_volume_closed = false;
	xpbd_volume_rest = 0.0;
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
