/**************************************************************************/
/*  jolt_space_3d.cpp                                                     */
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

#include "jolt_space_3d.h"

#include "../joints/jolt_joint_3d.h"
#include "../jolt_physics_server_3d.h"
#include "../jolt_project_settings.h"
#include "../misc/jolt_stream_wrappers.h"
#include "../objects/jolt_area_3d.h"
#include "../objects/jolt_body_3d.h"
#include "../objects/jolt_soft_body_3d.h"
#include "../shapes/jolt_shape_3d.h"
#include "jolt_body_activation_listener_3d.h"
#include "jolt_contact_listener_3d.h"
#include "jolt_layers.h"
#include "jolt_physics_direct_space_state_3d.h"

#include "core/io/file_access.h"
#include "core/os/time.h"
#include "core/string/print_string.h"
#include "core/variant/variant_utility.h"
#include "servers/physics_friction_combine.h"
#include "servers/physics_restitution_combine.h"

#include <Jolt/Physics/Collision/CollideShapeVsShapePerLeaf.h>
#include <Jolt/Physics/Collision/CollisionCollectorImpl.h>
#include <Jolt/Physics/PhysicsScene.h>
#include <Jolt/Physics/SoftBody/SoftBodyMotionProperties.h>

#include <algorithm>

namespace {

constexpr double SPACE_DEFAULT_CONTACT_RECYCLE_RADIUS = 0.01;
constexpr double SPACE_DEFAULT_CONTACT_MAX_SEPARATION = 0.05;
constexpr double SPACE_DEFAULT_CONTACT_MAX_ALLOWED_PENETRATION = 0.01;
constexpr double SPACE_DEFAULT_CONTACT_DEFAULT_BIAS = 0.8;
constexpr double SPACE_DEFAULT_SLEEP_THRESHOLD_LINEAR = 0.1;
constexpr double SPACE_DEFAULT_SLEEP_THRESHOLD_ANGULAR = 8.0 * Math::PI / 180;
constexpr double SPACE_DEFAULT_SOLVER_ITERATIONS = 8;

// Jolt requires plain function pointers for material combination. Select the
// mode once at space creation instead of branching on every hot contact.
// Shared helpers keep numerical behavior consistent with GodotPhysics2D/3D.
template <int P_MODE>
float combine_jolt_friction(const JPH::Body &p_body1, const JPH::SubShapeID &, const JPH::Body &p_body2, const JPH::SubShapeID &) {
	return (float)godot_physics_combine_friction(p_body1.GetFriction(), p_body2.GetFriction(), P_MODE);
}

template <int P_MODE>
float combine_jolt_restitution(const JPH::Body &p_body1, const JPH::SubShapeID &, const JPH::Body &p_body2, const JPH::SubShapeID &) {
	return (float)godot_physics_combine_restitution(p_body1.GetRestitution(), p_body2.GetRestitution(), P_MODE);
}

// Cache up to 4,096 BodyIDs (about 16 KiB per list) between flushes to avoid
// reallocation on streaming/spawn-heavy scenes. Release larger one-off batches.
constexpr uint32_t MAX_RETAINED_PENDING_BODY_IDS = 4096;

// Retain small open-addressing tables across repeated spawn/remove waves.
// AHashMap capacity is in slots (not entries); release oversized bursts.
constexpr uint32_t MAX_RETAINED_PENDING_INDEX_SLOTS = 4096;

// Opt-in CPU particle contacts between two Jolt soft bodies. The Jolt SDK
// only handles soft-rigid contacts, so this is a deliberately bounded,
// discrete vertex/vertex approximation, not triangle or CCD collision.
constexpr uint32_t MAX_SOFT_SOFT_BODY_PAIR_CHECKS = 2048;
constexpr float MAX_SOFT_SOFT_CONTACT_SPEED_CORRECTION = 8.0f;
constexpr float MAX_SOFT_SOFT_PENETRATION_BIAS = 2.0f;

static void resolve_soft_soft_particle_contacts(JPH::Body &p_body_a, JPH::Body &p_body_b,
		const JoltSoftBody3D &p_object_a, const JoltSoftBody3D &p_object_b, float p_step, uint32_t &r_particle_budget) {
	JPH::SoftBodyMotionProperties &properties_a = static_cast<JPH::SoftBodyMotionProperties &>(*p_body_a.GetMotionPropertiesUnchecked());
	JPH::SoftBodyMotionProperties &properties_b = static_cast<JPH::SoftBodyMotionProperties &>(*p_body_b.GetMotionPropertiesUnchecked());
	JPH::Array<JPH::SoftBodyVertex> &particles_a = properties_a.GetVertices();
	JPH::Array<JPH::SoftBodyVertex> &particles_b = properties_b.GetVertices();

	// An invisible centroid particle may have been added by the convex
	// volume fan. Never treat it as part of the collision surface.
	const uint32_t count_a = MIN(p_object_a.get_surface_particle_count(), uint32_t(particles_a.size()));
	const uint32_t count_b = MIN(p_object_b.get_surface_particle_count(), uint32_t(particles_b.size()));
	if (count_a == 0 || count_b == 0) {
		return;
	}

	const JPH::Quat rotation_a = p_body_a.GetRotation();
	const JPH::Quat rotation_b = p_body_b.GetRotation();
	const JPH::Quat inverse_rotation_a = rotation_a.Conjugated();
	const JPH::Quat inverse_rotation_b = rotation_b.Conjugated();

	// Subtract double-precision world COM positions first, so large scenes
	// do not lose contact precision when transformed to local float vectors.
	const JPH::Vec3 center_delta(p_body_b.GetCenterOfMassPosition() - p_body_a.GetCenterOfMassPosition());
	const float radius = JoltProjectSettings::soft_body_soft_contact_radius;
	const float radius_sq = radius * radius;
	const float bias_per_step = JoltProjectSettings::soft_body_soft_contact_recovery / p_step;
	const float friction = JoltProjectSettings::soft_body_soft_contact_friction;

	for (uint32_t i = 0; i < count_a && r_particle_budget > 0; ++i) {
		JPH::SoftBodyVertex &a = particles_a[i];
		const JPH::Vec3 offset_a = rotation_a * a.mPosition;
		for (uint32_t j = 0; j < count_b && r_particle_budget > 0; ++j) {
			--r_particle_budget; // Includes non-contact pairs: hard work bound.
			JPH::SoftBodyVertex &b = particles_b[j];
			const float inverse_mass_sum = a.mInvMass + b.mInvMass;
			if (!Math::is_finite(inverse_mass_sum) || inverse_mass_sum <= 0.0f) {
				continue;
			}
			const JPH::Vec3 separation = center_delta + rotation_b * b.mPosition - offset_a;
			const float distance_sq = separation.LengthSq();
			if (!Math::is_finite(distance_sq) || distance_sq >= radius_sq) {
				continue;
			}

			const JPH::Vec3 relative_velocity = rotation_b * b.mVelocity - rotation_a * a.mVelocity;
			const float distance = Math::sqrt(MAX(distance_sq, 0.0f));
			// Coincident particles need a well-defined fallback normal.
			const JPH::Vec3 normal = distance > 1.0e-6f ? separation / distance :
					(center_delta.LengthSq() > 1.0e-12f ? center_delta.Normalized() : JPH::Vec3::sAxisY());
			const float normal_speed = relative_velocity.Dot(normal);
			if (!Math::is_finite(normal_speed)) {
				continue; // Never spread a corrupt velocity to the other body.
			}
			const float penetration = radius - distance;
			const float recovery_speed = MIN(penetration * bias_per_step, MAX_SOFT_SOFT_PENETRATION_BIAS);
			const float normal_speed_correction = MIN(MAX(recovery_speed - normal_speed, 0.0f), MAX_SOFT_SOFT_CONTACT_SPEED_CORRECTION);
			if (normal_speed_correction <= 0.0f) {
				continue;
			}

			// Inverse-mass-weighted normal impulse conserves linear momentum.
			// Pinned vertices have zero inverse mass and remain immovable.
			const float normal_impulse = normal_speed_correction / inverse_mass_sum;
			JPH::Vec3 impulse = normal * normal_impulse;

			// Coulomb-limited sliding friction in the tangential plane.
			const JPH::Vec3 tangent_velocity = relative_velocity - normal * normal_speed;
			const float tangent_speed_sq = tangent_velocity.LengthSq();
			if (friction > 0.0f && Math::is_finite(tangent_speed_sq) && tangent_speed_sq > 1.0e-12f) {
				const float tangent_speed = Math::sqrt(tangent_speed_sq);
				const float tangent_impulse = MIN(tangent_speed / inverse_mass_sum, friction * normal_impulse);
				impulse -= tangent_velocity * (tangent_impulse / tangent_speed);
			}

			a.mVelocity -= inverse_rotation_a * (impulse * a.mInvMass);
			b.mVelocity += inverse_rotation_b * (impulse * b.mInvMass);
		}
	}
}


// Ericson-style closest point on a triangle. Explicit barycentric weights
// let the impulse be distributed to the actual face vertices, rather than
// treating the face like an infinitely massive static collider.
// Reject degenerate or nonfinite input before evaluating divisions.
static bool closest_soft_triangle_point(JPH::Vec3Arg p, JPH::Vec3Arg a, JPH::Vec3Arg b, JPH::Vec3Arg c,
		JPH::Vec3 &r_closest, float &r_u, float &r_v, float &r_w) {
	const JPH::Vec3 ab = b - a;
	const JPH::Vec3 ac = c - a;
	const JPH::Vec3 face_normal = ab.Cross(ac);
	const float area4 = face_normal.LengthSq();
	if (!Math::is_finite(area4) || area4 <= 1.0e-14f) {
		return false;
	}

	const JPH::Vec3 ap = p - a;
	const float d1 = ab.Dot(ap);
	const float d2 = ac.Dot(ap);
	if (d1 <= 0.0f && d2 <= 0.0f) {
		r_u = 1.0f; r_v = 0.0f; r_w = 0.0f;
	} else {
		const JPH::Vec3 bp = p - b;
		const float d3 = ab.Dot(bp);
		const float d4 = ac.Dot(bp);
		if (d3 >= 0.0f && d4 <= d3) {
			r_u = 0.0f; r_v = 1.0f; r_w = 0.0f;
		} else {
			const float vc = d1 * d4 - d3 * d2;
			if (vc <= 0.0f && d1 >= 0.0f && d3 <= 0.0f) {
				r_v = d1 / (d1 - d3);
				r_u = 1.0f - r_v; r_w = 0.0f;
			} else {
				const JPH::Vec3 cp = p - c;
				const float d5 = ab.Dot(cp);
				const float d6 = ac.Dot(cp);
				if (d6 >= 0.0f && d5 <= d6) {
					r_u = 0.0f; r_v = 0.0f; r_w = 1.0f;
				} else {
					const float vb = d5 * d2 - d1 * d6;
					if (vb <= 0.0f && d2 >= 0.0f && d6 <= 0.0f) {
						r_w = d2 / (d2 - d6);
						r_u = 1.0f - r_w; r_v = 0.0f;
					} else {
						const float va = d3 * d6 - d5 * d4;
						if (va <= 0.0f && d4 - d3 >= 0.0f && d5 - d6 >= 0.0f) {
							r_w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
							r_u = 0.0f; r_v = 1.0f - r_w;
						} else {
							const float sum = va + vb + vc;
							if (sum <= 0.0f || !Math::is_finite(sum)) {
								return false;
							}
							const float inv_sum = 1.0f / sum;
							r_v = vb * inv_sum;
							r_w = vc * inv_sum;
							r_u = 1.0f - r_v - r_w;
						}
					}
				}
			}
		}
	}
	if (!Math::is_finite(r_u) || !Math::is_finite(r_v) || !Math::is_finite(r_w)) {
		return false;
	}
	r_closest = a * r_u + b * r_v + c * r_w;
	return true;
}

// Discrete soft node vs deformable triangle. The barycentric effective mass
// w_node + u²*w_a + v²*w_b + w²*w_c correctly accounts for which face
// particles are pinned and conserves the total linear impulse.
// Lightweight, per-overlapping-body-pair BVH over *deformed* soft-body
// faces. Jolt's soft vertices move every step, so these bounds are rebuilt
// from the current positions. Use at most 4096 faces and debit the global
// contact-work budget for construction and traversal, not just leaf tests.
constexpr uint32_t MAX_SOFT_FACE_BVH_FACES = 4096;
constexpr uint32_t MIN_SOFT_FACE_BVH_FACES = 32;
constexpr uint32_t SOFT_FACE_BVH_LEAF_SIZE = 4;

struct SoftFaceBVHEntry {
	JPH::Vec3 min;
	JPH::Vec3 max;
	uint32_t face_index = 0;
};

struct SoftFaceBVHNode {
	JPH::Vec3 min;
	JPH::Vec3 max;
	uint32_t begin = 0;
	uint32_t end = 0;
	uint32_t left = 0;
	uint32_t right = 0;
};

// The same arrays are reused across all soft-soft pairs and both query
// directions within a space's pre-step, avoiding per-pair heap churn.
struct SoftFaceBVHScratch {
	JPH::Array<SoftFaceBVHEntry> entries;
	JPH::Array<SoftFaceBVHNode> nodes;
	JPH::Array<uint32_t> candidates;
	JPH::Array<uint32_t> stack;

	void clear() {
		entries.clear();
		nodes.clear();
		candidates.clear();
		stack.clear();
	}
};

static bool soft_face_aabb_overlaps_point(JPH::Vec3Arg p_min, JPH::Vec3Arg p_max, JPH::Vec3Arg p_point, float p_radius) {
	return p_point.GetX() >= p_min.GetX() - p_radius && p_point.GetX() <= p_max.GetX() + p_radius &&
			p_point.GetY() >= p_min.GetY() - p_radius && p_point.GetY() <= p_max.GetY() + p_radius &&
			p_point.GetZ() >= p_min.GetZ() - p_radius && p_point.GetZ() <= p_max.GetZ() + p_radius;
}

static float soft_face_bvh_midpoint(const SoftFaceBVHEntry &p_face, uint32_t p_axis) {
	if (p_axis == 0) {
		return 0.5f * p_face.min.GetX() + 0.5f * p_face.max.GetX();
	}
	if (p_axis == 1) {
		return 0.5f * p_face.min.GetY() + 0.5f * p_face.max.GetY();
	}
	return 0.5f * p_face.min.GetZ() + 0.5f * p_face.max.GetZ();
}

// Median split gives a bounded recursion depth (<= 10 for 4096 faces) and
// avoids pathological unbalanced trees even when faces occupy one plane.
static uint32_t build_soft_face_bvh(JPH::Array<SoftFaceBVHEntry> &r_entries, JPH::Array<SoftFaceBVHNode> &r_nodes, uint32_t p_begin, uint32_t p_end) {
	JPH::Vec3 min_bound = r_entries[p_begin].min;
	JPH::Vec3 max_bound = r_entries[p_begin].max;
	for (uint32_t i = p_begin + 1; i < p_end; ++i) {
		min_bound = JPH::Vec3::sMin(min_bound, r_entries[i].min);
		max_bound = JPH::Vec3::sMax(max_bound, r_entries[i].max);
	}

	const uint32_t node_id = (uint32_t)r_nodes.size();
	r_nodes.emplace_back();
	r_nodes[node_id].min = min_bound;
	r_nodes[node_id].max = max_bound;
	r_nodes[node_id].begin = p_begin;
	r_nodes[node_id].end = p_end;
	if (p_end - p_begin <= SOFT_FACE_BVH_LEAF_SIZE) {
		return node_id;
	}

	const JPH::Vec3 extent = max_bound - min_bound;
	const uint32_t axis = extent.GetX() >= extent.GetY() && extent.GetX() >= extent.GetZ() ? 0 :
			(extent.GetY() >= extent.GetZ() ? 1 : 2);
	const uint32_t mid = p_begin + (p_end - p_begin) / 2;
	std::nth_element(r_entries.begin() + p_begin, r_entries.begin() + mid, r_entries.begin() + p_end,
			[axis](const SoftFaceBVHEntry &a, const SoftFaceBVHEntry &b) {
				const float ca = soft_face_bvh_midpoint(a, axis);
				const float cb = soft_face_bvh_midpoint(b, axis);
				return ca == cb ? a.face_index < b.face_index : ca < cb;
			});
	const uint32_t left = build_soft_face_bvh(r_entries, r_nodes, p_begin, mid);
	const uint32_t right = build_soft_face_bvh(r_entries, r_nodes, mid, p_end);
	r_nodes[node_id].left = left;
	r_nodes[node_id].right = right;
	return node_id;
}

static bool prepare_soft_face_bvh(const JPH::Array<JPH::SoftBodySharedSettings::Face> &p_faces,
		const JPH::Array<JPH::SoftBodyVertex> &p_vertices, JPH::QuatArg p_rotation, JPH::Vec3Arg p_offset,
		JPH::Array<SoftFaceBVHEntry> &r_entries, JPH::Array<SoftFaceBVHNode> &r_nodes, uint32_t &r_budget) {
	if (p_faces.size() < MIN_SOFT_FACE_BVH_FACES || p_faces.size() > MAX_SOFT_FACE_BVH_FACES) {
		return false; // Small/oversized workloads retain brute force.
	}
	// Median selection scans each face at every tree level. Debit a
	// conservative O(F log F) build charge, so many overlapping pairs
	// cannot bypass the same fixed global work budget as the linear path.
	uint32_t split_levels = 0;
	for (uint32_t count = (uint32_t)p_faces.size(); count > 1; count = (count + 1) / 2) {
		++split_levels;
	}
	const uint32_t build_cost = (uint32_t)p_faces.size() * (split_levels + 1);
	if (r_budget <= build_cost) {
		return false; // Preserve budget for at least one contact query.
	}
	r_budget -= build_cost;
	r_entries.reserve(p_faces.size());
	for (uint32_t i = 0; i < p_faces.size(); ++i) {
		const JPH::SoftBodySharedSettings::Face &face = p_faces[i];
		if (face.IsDegenerate() || face.mVertex[0] >= p_vertices.size() || face.mVertex[1] >= p_vertices.size() || face.mVertex[2] >= p_vertices.size()) {
			continue;
		}
		const JPH::Vec3 a = p_offset + p_rotation * p_vertices[face.mVertex[0]].mPosition;
		const JPH::Vec3 b = p_offset + p_rotation * p_vertices[face.mVertex[1]].mPosition;
		const JPH::Vec3 c = p_offset + p_rotation * p_vertices[face.mVertex[2]].mPosition;
		const JPH::Vec3 min_bound = JPH::Vec3::sMin(a, JPH::Vec3::sMin(b, c));
		const JPH::Vec3 max_bound = JPH::Vec3::sMax(a, JPH::Vec3::sMax(b, c));
		if (!Math::is_finite(min_bound.GetX()) || !Math::is_finite(min_bound.GetY()) || !Math::is_finite(min_bound.GetZ()) ||
				!Math::is_finite(max_bound.GetX()) || !Math::is_finite(max_bound.GetY()) || !Math::is_finite(max_bound.GetZ())) {
			continue;
		}
		SoftFaceBVHEntry entry;
		entry.min = min_bound;
		entry.max = max_bound;
		entry.face_index = i;
		r_entries.push_back(entry);
	}
	if (r_entries.empty()) {
		return false;
	}
	r_nodes.reserve(2 * r_entries.size());
	build_soft_face_bvh(r_entries, r_nodes, 0, (uint32_t)r_entries.size());
	return true;
}

// Node visits also consume budget, and query returns only conservative
// candidates: no eligible triangle can be culled by the hierarchy.
static void query_soft_face_bvh(const JPH::Array<SoftFaceBVHEntry> &p_entries,
		const JPH::Array<SoftFaceBVHNode> &p_nodes, JPH::Vec3Arg p_point,
		float p_radius, uint32_t &r_budget, JPH::Array<uint32_t> &r_hits, JPH::Array<uint32_t> &r_stack) {
	r_hits.clear();
	r_stack.clear();
	r_stack.push_back(0);
	while (!r_stack.empty() && r_budget > 0) {
		const uint32_t node_id = r_stack.back();
		r_stack.pop_back();
		--r_budget;
		const SoftFaceBVHNode &node = p_nodes[node_id];
		if (!soft_face_aabb_overlaps_point(node.min, node.max, p_point, p_radius)) {
			continue;
		}
		if (node.end - node.begin <= SOFT_FACE_BVH_LEAF_SIZE) {
			for (uint32_t i = node.begin; i < node.end; ++i) {
				const SoftFaceBVHEntry &entry = p_entries[i];
				if (soft_face_aabb_overlaps_point(entry.min, entry.max, p_point, p_radius)) {
					r_hits.push_back(entry.face_index);
				}
			}
		} else {
			r_stack.push_back(node.right);
			r_stack.push_back(node.left);
		}
	}
}

static void resolve_soft_soft_vertex_face_direction(JPH::Body &p_point_body, JPH::Body &p_face_body,
		const JoltSoftBody3D &p_point_object, float p_step, uint32_t &r_contact_budget, SoftFaceBVHScratch &r_bvh_scratch) {
	JPH::SoftBodyMotionProperties &point_props = static_cast<JPH::SoftBodyMotionProperties &>(*p_point_body.GetMotionPropertiesUnchecked());
	JPH::SoftBodyMotionProperties &face_props = static_cast<JPH::SoftBodyMotionProperties &>(*p_face_body.GetMotionPropertiesUnchecked());
	JPH::Array<JPH::SoftBodyVertex> &points = point_props.GetVertices();
	JPH::Array<JPH::SoftBodyVertex> &face_vertices = face_props.GetVertices();
	const JPH::Array<JPH::SoftBodySharedSettings::Face> &faces = face_props.GetFaces();
	const uint32_t point_count = MIN(p_point_object.get_surface_particle_count(), uint32_t(points.size()));
	if (point_count == 0 || faces.empty()) {
		return;
	}

	const JPH::Quat point_rotation = p_point_body.GetRotation();
	const JPH::Quat face_rotation = p_face_body.GetRotation();
	const JPH::Quat inv_point_rotation = point_rotation.Conjugated();
	const JPH::Quat inv_face_rotation = face_rotation.Conjugated();
	const JPH::Vec3 face_relative_to_point(p_face_body.GetCenterOfMassPosition() - p_point_body.GetCenterOfMassPosition());
	const float radius = JoltProjectSettings::soft_body_soft_contact_radius;
	const float radius_sq = radius * radius;
	const float bias_per_step = JoltProjectSettings::soft_body_soft_contact_recovery / p_step;
	const float friction = JoltProjectSettings::soft_body_soft_contact_friction;

	// Build BVH only on meaningful meshes, while honoring the global work
	// budget. Rebuild from the current deformed geometry every simulation
	// step. All containers live only for this body-pair direction.
	r_bvh_scratch.clear();
	const bool use_bvh = JoltProjectSettings::soft_body_soft_vertex_face_bvh &&
			prepare_soft_face_bvh(faces, face_vertices, face_rotation, face_relative_to_point,
					r_bvh_scratch.entries, r_bvh_scratch.nodes, r_contact_budget);
	if (use_bvh) {
		r_bvh_scratch.candidates.reserve(r_bvh_scratch.entries.size());
		r_bvh_scratch.stack.reserve(32); // Median BVH <= 4096 faces: <= 10 levels.
	}
	for (uint32_t i = 0; i < point_count && r_contact_budget > 0; ++i) {
		JPH::SoftBodyVertex &point = points[i];
		const JPH::Vec3 point_position = point_rotation * point.mPosition;
		if (use_bvh) {
			query_soft_face_bvh(r_bvh_scratch.entries, r_bvh_scratch.nodes, point_position, radius,
					r_contact_budget, r_bvh_scratch.candidates, r_bvh_scratch.stack);
		}
		const uint32_t candidate_count = use_bvh ? (uint32_t)r_bvh_scratch.candidates.size() : (uint32_t)faces.size();
		for (uint32_t candidate = 0; candidate < candidate_count; ++candidate) {
			if (r_contact_budget == 0) {
				return;
			}
			--r_contact_budget; // Every exact face test consumes the same budget.
			const JPH::SoftBodySharedSettings::Face &face = faces[use_bvh ? r_bvh_scratch.candidates[candidate] : candidate];
			const uint32_t id0 = face.mVertex[0], id1 = face.mVertex[1], id2 = face.mVertex[2];
			if (id0 >= face_vertices.size() || id1 >= face_vertices.size() || id2 >= face_vertices.size() || face.IsDegenerate()) {
				continue;
			}
			JPH::SoftBodyVertex &v0 = face_vertices[id0];
			JPH::SoftBodyVertex &v1 = face_vertices[id1];
			JPH::SoftBodyVertex &v2 = face_vertices[id2];
			const JPH::Vec3 a = face_relative_to_point + face_rotation * v0.mPosition;
			const JPH::Vec3 b = face_relative_to_point + face_rotation * v1.mPosition;
			const JPH::Vec3 c = face_relative_to_point + face_rotation * v2.mPosition;
			// Conservative per-triangle AABB rejection before the relatively
			// expensive seven-region closest-point calculations. No heap/BVH.
			const JPH::Vec3 tri_min = JPH::Vec3::sMin(a, JPH::Vec3::sMin(b, c));
			const JPH::Vec3 tri_max = JPH::Vec3::sMax(a, JPH::Vec3::sMax(b, c));
			if (point_position.GetX() < tri_min.GetX() - radius || point_position.GetX() > tri_max.GetX() + radius ||
					point_position.GetY() < tri_min.GetY() - radius || point_position.GetY() > tri_max.GetY() + radius ||
					point_position.GetZ() < tri_min.GetZ() - radius || point_position.GetZ() > tri_max.GetZ() + radius) {
				continue;
			}

			JPH::Vec3 nearest = JPH::Vec3::sZero();
			float u = 0.0f, v = 0.0f, w = 0.0f;
			if (!closest_soft_triangle_point(point_position, a, b, c, nearest, u, v, w)) {
				continue;
			}
			const JPH::Vec3 diff = point_position - nearest;
			const float distance_sq = diff.LengthSq();
			if (!Math::is_finite(distance_sq) || distance_sq >= radius_sq) {
				continue;
			}
			const float inverse_mass_sum = point.mInvMass + u * u * v0.mInvMass + v * v * v1.mInvMass + w * w * v2.mInvMass;
			if (!Math::is_finite(inverse_mass_sum) || inverse_mass_sum <= 0.0f) {
				continue;
			}
			const JPH::Vec3 face_velocity = face_rotation * (u * v0.mVelocity + v * v1.mVelocity + w * v2.mVelocity);
			const JPH::Vec3 relative_velocity = point_rotation * point.mVelocity - face_velocity;
			const float distance = Math::sqrt(MAX(distance_sq, 0.0f));
			// Both sides of a triangle can collide; at exact coincidence,
			// choose the normal opposing the current normal approach.
			JPH::Vec3 normal = distance > 1.0e-6f ? diff / distance : (b - a).Cross(c - a).Normalized();
			if (distance <= 1.0e-6f && relative_velocity.Dot(normal) > 0.0f) {
				normal = -normal;
			}
			const float normal_speed = relative_velocity.Dot(normal);
			if (!Math::is_finite(normal_speed)) {
				continue;
			}
			const float recovery_speed = MIN((radius - distance) * bias_per_step, MAX_SOFT_SOFT_PENETRATION_BIAS);
			const float correction = MIN(MAX(recovery_speed - normal_speed, 0.0f), MAX_SOFT_SOFT_CONTACT_SPEED_CORRECTION);
			if (correction <= 0.0f) {
				continue;
			}
			const float normal_impulse = correction / inverse_mass_sum;
			if (!Math::is_finite(normal_impulse) || normal_impulse <= 0.0f) {
				continue;
			}
			JPH::Vec3 impulse = normal * normal_impulse;

			const JPH::Vec3 tangent_velocity = relative_velocity - normal * normal_speed;
			const float tangent_speed_sq = tangent_velocity.LengthSq();
			if (friction > 0.0f && Math::is_finite(tangent_speed_sq) && tangent_speed_sq > 1.0e-12f) {
				const float tangent_speed = Math::sqrt(tangent_speed_sq);
				const float tangent_impulse = MIN(tangent_speed / inverse_mass_sum, friction * normal_impulse);
				impulse -= tangent_velocity * (tangent_impulse / tangent_speed);
			}

			// Equal-and-opposite impulses, distributed by barycentric weights.
			point.mVelocity += inv_point_rotation * (impulse * point.mInvMass);
			const JPH::Vec3 local_face_impulse = inv_face_rotation * impulse;
			v0.mVelocity -= local_face_impulse * (u * v0.mInvMass);
			v1.mVelocity -= local_face_impulse * (v * v1.mInvMass);
			v2.mVelocity -= local_face_impulse * (w * v2.mInvMass);
		}
	}
}

static void resolve_soft_soft_vertex_face_contacts(JPH::Body &p_body_a, JPH::Body &p_body_b,
		const JoltSoftBody3D &p_object_a, const JoltSoftBody3D &p_object_b, float p_step, uint32_t &r_contact_budget, SoftFaceBVHScratch &r_bvh_scratch) {
	// Both directions are necessary: either body can be the sparse mesh.
	resolve_soft_soft_vertex_face_direction(p_body_a, p_body_b, p_object_a, p_step, r_contact_budget, r_bvh_scratch);
	if (r_contact_budget > 0) {
		resolve_soft_soft_vertex_face_direction(p_body_b, p_body_a, p_object_b, p_step, r_contact_budget, r_bvh_scratch);
	}
}

static void clear_pending_index(AHashMap<uint32_t, uint32_t> &r_indices) {
	if (r_indices.get_capacity() > MAX_RETAINED_PENDING_INDEX_SLOTS) {
		r_indices.reset();
	} else {
		r_indices.clear();
	}
}

// A hash index is unnecessary in the common case of a few queued bodies.
// For large create/destroy bursts, linear erase_unordered() becomes O(n^2).
static void ensure_pending_index(const LocalVector<JPH::BodyID> &p_bodies, AHashMap<uint32_t, uint32_t> &r_indices) {
	if (p_bodies.size() < 128 || !r_indices.is_empty()) {
		return;
	}
	// AHashMap starts growing at roughly 75% load: reserve spare slots
	// up front to avoid a second allocation while building the index.
	r_indices.reserve(p_bodies.size() + p_bodies.size() / 2 + 1);
	for (uint32_t i = 0; i < p_bodies.size(); ++i) {
		r_indices.insert(p_bodies[i].GetIndexAndSequenceNumber(), i);
	}
}

} // namespace

void JoltSpace3D::_pending_add(LocalVector<JPH::BodyID> &p_bodies, AHashMap<uint32_t, uint32_t> &r_indices, const JPH::BodyID &p_id) {
	if (!r_indices.is_empty()) {
		r_indices.insert(p_id.GetIndexAndSequenceNumber(), p_bodies.size());
	}
	p_bodies.push_back(p_id);
}

bool JoltSpace3D::_pending_erase(LocalVector<JPH::BodyID> &p_bodies, AHashMap<uint32_t, uint32_t> &r_indices, const JPH::BodyID &p_id) {
	if (p_bodies.is_empty()) {
		return false;
	}
	ensure_pending_index(p_bodies, r_indices);
	if (r_indices.is_empty()) {
		return p_bodies.erase_unordered(p_id);
	}
	const uint32_t key = p_id.GetIndexAndSequenceNumber();
	const uint32_t *index_ptr = r_indices.getptr(key);
	if (index_ptr == nullptr) {
		return false;
	}
	const uint32_t index = *index_ptr;
	const uint32_t last_index = p_bodies.size() - 1;
	if (index != last_index) {
		const uint32_t moved_key = p_bodies[last_index].GetIndexAndSequenceNumber();
		p_bodies.remove_at_unordered(index);
		r_indices.insert(moved_key, index);
	} else {
		p_bodies.remove_at_unordered(index);
	}
	r_indices.erase(key);
	if (p_bodies.is_empty()) {
		// Keep a small index cache for the next batch, but drop large peaks.
		clear_pending_index(r_indices);
	}
	return true;
}

bool JoltSpace3D::_pending_has(const LocalVector<JPH::BodyID> &p_bodies, AHashMap<uint32_t, uint32_t> &r_indices, const JPH::BodyID &p_id) {
	if (p_bodies.is_empty()) {
		return false;
	}
	ensure_pending_index(p_bodies, r_indices);
	return r_indices.is_empty() ? p_bodies.has(p_id) : r_indices.has(p_id.GetIndexAndSequenceNumber());
}


void JoltSpace3D::_pre_step(float p_step) {
	flush_pending_objects();

	while (needs_optimization_list.first()) {
		JoltShapedObject3D *object = needs_optimization_list.first()->self();
		needs_optimization_list.remove(needs_optimization_list.first());
		object->commit_shapes(true);
	}

	contact_listener->pre_step();

	const JPH::BodyLockInterface &lock_iface = get_lock_iface();
	const JPH::BodyID *active_rigid_bodies = physics_system->GetActiveBodiesUnsafe(JPH::EBodyType::RigidBody);
	const JPH::uint32 active_rigid_body_count = physics_system->GetNumActiveBodies(JPH::EBodyType::RigidBody);

	for (JPH::uint32 i = 0; i < active_rigid_body_count; i++) {
		JPH::Body *jolt_body = lock_iface.TryGetBody(active_rigid_bodies[i]);
		JoltObject3D *object = reinterpret_cast<JoltObject3D *>(jolt_body->GetUserData());
		object->pre_step(p_step);
	}

	const JPH::BodyID *active_soft_bodies = physics_system->GetActiveBodiesUnsafe(JPH::EBodyType::SoftBody);
	const JPH::uint32 active_soft_body_count = physics_system->GetNumActiveBodies(JPH::EBodyType::SoftBody);

	for (JPH::uint32 i = 0; i < active_soft_body_count; i++) {
		JPH::Body *jolt_body = lock_iface.TryGetBody(active_soft_bodies[i]);
		JoltObject3D *object = reinterpret_cast<JoltObject3D *>(jolt_body->GetUserData());
		object->pre_step(p_step);
	}

	// Jolt's native soft-body collision path only handles rigid bodies. The
	// CPU approximation runs before Jolt's parallel physics Update(), which
	// makes mutable particle velocities safe to access here.
	// Zero overhead (one branch) when disabled.
	if (JoltProjectSettings::soft_body_soft_contacts && active_soft_body_count > 1 &&
			JoltProjectSettings::soft_body_soft_contact_radius > 0.0f && Math::is_finite(p_step) && p_step > 0.0f) {
		uint32_t particle_budget = (uint32_t)JoltProjectSettings::soft_body_soft_contact_max_particle_pairs;
		uint32_t checked_body_pairs = 0;
		SoftFaceBVHScratch bvh_scratch; // No allocations when disabled.
		const float radius = JoltProjectSettings::soft_body_soft_contact_radius;

		for (JPH::uint32 i = 0; i < active_soft_body_count && particle_budget > 0 && checked_body_pairs < MAX_SOFT_SOFT_BODY_PAIR_CHECKS; ++i) {
			JPH::Body *jolt_a = lock_iface.TryGetBody(active_soft_bodies[i]);
			if (jolt_a == nullptr) {
				continue;
			}
			JoltSoftBody3D *object_a = reinterpret_cast<JoltObject3D *>(jolt_a->GetUserData())->as_soft_body();
			const AABB bounds_a = object_a->get_bounds().grow(radius);
			for (JPH::uint32 j = i + 1; j < active_soft_body_count && particle_budget > 0 && checked_body_pairs < MAX_SOFT_SOFT_BODY_PAIR_CHECKS; ++j) {
				++checked_body_pairs;
				JPH::Body *jolt_b = lock_iface.TryGetBody(active_soft_bodies[j]);
				if (jolt_b == nullptr) {
					continue;
				}
				JoltSoftBody3D *object_b = reinterpret_cast<JoltObject3D *>(jolt_b->GetUserData())->as_soft_body();
				if (!object_a->can_interact_with(*object_b) || !bounds_a.intersects(object_b->get_bounds().grow(radius))) {
					continue;
				}
				if (JoltProjectSettings::soft_body_soft_vertex_face_contacts) {
					resolve_soft_soft_vertex_face_contacts(*jolt_a, *jolt_b, *object_a, *object_b, p_step, particle_budget, bvh_scratch);
				} else {
					resolve_soft_soft_particle_contacts(*jolt_a, *jolt_b, *object_a, *object_b, p_step, particle_budget);
				}
			}
		}
	}

	physics_system->SetBodyActivationListener(body_activation_listener);
}

void JoltSpace3D::_post_step(float p_step) {
	// We only want a listener during the step, as it will otherwise be called when pending bodies are flushed, which causes issues (e.g. GH-115322).
	physics_system->SetBodyActivationListener(nullptr);

	contact_listener->post_step();

	while (shapes_changed_list.first()) {
		JoltShapedObject3D *object = shapes_changed_list.first()->self();
		shapes_changed_list.remove(shapes_changed_list.first());
		object->clear_previous_shape();
	}
}

JoltSpace3D::JoltSpace3D(JPH::JobSystem *p_job_system, JPH::TempAllocator *p_temp_allocator) :
		job_system(p_job_system),
		temp_allocator(p_temp_allocator),
		layers(new JoltLayers()),
		contact_listener(new JoltContactListener3D(this)),
		body_activation_listener(new JoltBodyActivationListener3D()),
		physics_system(new JPH::PhysicsSystem()) {
	physics_system->Init((JPH::uint)JoltProjectSettings::max_bodies, 0, (JPH::uint)JoltProjectSettings::max_body_pairs, (JPH::uint)JoltProjectSettings::max_contact_constraints, *layers, *layers, *layers);

	JPH::PhysicsSettings settings;
	// Copy per-world tuning once; do not read project settings inside contact jobs.
	settings.mMaxInFlightBodyPairs = JoltProjectSettings::max_in_flight_body_pairs;
	settings.mUseLargeIslandSplitter = JoltProjectSettings::simulation_use_large_island_splitter;
	settings.mUseManifoldReduction = JoltProjectSettings::simulation_use_manifold_reduction;
	settings.mBaumgarte = JoltProjectSettings::baumgarte_stabilization_factor;
	settings.mSpeculativeContactDistance = JoltProjectSettings::speculative_contact_distance;
	settings.mPenetrationSlop = JoltProjectSettings::penetration_slop;
	settings.mMaxPenetrationDistance = JoltProjectSettings::max_penetration_correction_distance;
	settings.mContactNormalCosMaxDeltaRotation = JoltProjectSettings::contact_manifold_merge_normal_cos;
	settings.mContactPointPreserveLambdaMaxDistSq = JoltProjectSettings::contact_warm_start_distance_sq;
	settings.mLinearCastThreshold = JoltProjectSettings::ccd_movement_threshold;
	settings.mLinearCastMaxPenetration = JoltProjectSettings::ccd_max_penetration;
	settings.mBodyPairCacheMaxDeltaPositionSq = JoltProjectSettings::body_pair_cache_distance_sq;
	settings.mBodyPairCacheCosMaxDeltaRotationDiv2 = JoltProjectSettings::body_pair_cache_angle_cos_div2;
	settings.mNumVelocitySteps = (JPH::uint)JoltProjectSettings::simulation_velocity_steps;
	settings.mNumPositionSteps = (JPH::uint)JoltProjectSettings::simulation_position_steps;
	settings.mMinVelocityForRestitution = JoltProjectSettings::bounce_velocity_threshold;
	settings.mTimeBeforeSleep = JoltProjectSettings::sleep_time_threshold;
	settings.mPointVelocitySleepThreshold = JoltProjectSettings::sleep_velocity_threshold;
	settings.mUseBodyPairContactCache = JoltProjectSettings::body_pair_contact_cache_enabled;
	settings.mAllowSleeping = JoltProjectSettings::sleep_allowed;

	physics_system->SetPhysicsSettings(settings);
	physics_system->SetGravity(JPH::Vec3::sZero());
	physics_system->SetContactListener(contact_listener);
	physics_system->SetSoftBodyContactListener(contact_listener);

	physics_system->SetSimCollideBodyVsBody([](const JPH::Body &p_body1, const JPH::Body &p_body2, JPH::Mat44Arg p_transform_com1, JPH::Mat44Arg p_transform_com2, JPH::CollideShapeSettings &p_collide_shape_settings, JPH::CollideShapeCollector &p_collector, const JPH::ShapeFilter &p_shape_filter) {
		if (p_body1.IsSensor() || p_body2.IsSensor()) {
			JPH::SubShapeIDCreator part1, part2;
			JPH::CollideShapeVsShapePerLeaf<JPH::AnyHitCollisionCollector<JPH::CollideShapeCollector>>(p_body1.GetShape(), p_body2.GetShape(), JPH::Vec3::sOne(), JPH::Vec3::sOne(), p_transform_com1, p_transform_com2, part1, part2, p_collide_shape_settings, p_collector, p_shape_filter);
		} else {
			JPH::PhysicsSystem::sDefaultSimCollideBodyVsBody(p_body1, p_body2, p_transform_com1, p_transform_com2, p_collide_shape_settings, p_collector, p_shape_filter);
		}
	});

	// Snapshot the requested material modes per PhysicsSystem. Avoid reading
	// project settings and branching for every contact, including worker threads.
	// Existing spaces retain their combine callbacks when project settings change.
	switch (JoltProjectSettings::friction_combine_mode) {
		case 1:
			physics_system->SetCombineFriction(&combine_jolt_friction<1>);
			break;
		case 2:
			physics_system->SetCombineFriction(&combine_jolt_friction<2>);
			break;
		case 3:
			physics_system->SetCombineFriction(&combine_jolt_friction<3>);
			break;
		default:
			physics_system->SetCombineFriction(&combine_jolt_friction<0>);
			break;
	}

	switch (JoltProjectSettings::restitution_combine_mode) {
		case 1:
			physics_system->SetCombineRestitution(&combine_jolt_restitution<1>);
			break;
		case 2:
			physics_system->SetCombineRestitution(&combine_jolt_restitution<2>);
			break;
		case 3:
			physics_system->SetCombineRestitution(&combine_jolt_restitution<3>);
			break;
		case 4:
			physics_system->SetCombineRestitution(&combine_jolt_restitution<4>);
			break;
		case 5:
			physics_system->SetCombineRestitution(&combine_jolt_restitution<5>);
			break;
		default:
			physics_system->SetCombineRestitution(&combine_jolt_restitution<0>);
			break;
	}
}

JoltSpace3D::~JoltSpace3D() {
	if (direct_state != nullptr) {
		memdelete(direct_state);
		direct_state = nullptr;
	}

	if (physics_system != nullptr) {
		delete physics_system;
		physics_system = nullptr;
	}

	if (body_activation_listener != nullptr) {
		delete body_activation_listener;
		body_activation_listener = nullptr;
	}

	if (contact_listener != nullptr) {
		delete contact_listener;
		contact_listener = nullptr;
	}

	if (layers != nullptr) {
		delete layers;
		layers = nullptr;
	}
}

void JoltSpace3D::step(float p_step) {
	stepping = true;
	last_step = p_step;

	_pre_step(p_step);

	// Jolt runs collision detection and integration for each collision step.
	// Keep the default single step for low overhead, but allow finer time steps
	// for high-speed scenes or projects using a lower physics tick rate.
	int collision_steps = CLAMP(JoltProjectSettings::simulation_collision_steps, 1, 8);
	const float max_step_seconds = JoltProjectSettings::simulation_max_collision_step_seconds;
	if (max_step_seconds > 0.0f && p_step > max_step_seconds) {
		const float estimated_steps = p_step / max_step_seconds;
		// Bound before converting to int, including extremely small thresholds.
		const int needed_steps = estimated_steps >= 8.0f ? 8 : int(Math::ceil(estimated_steps));
		collision_steps = MAX(collision_steps, needed_steps);
	}
	const JPH::EPhysicsUpdateError update_error = physics_system->Update(p_step, collision_steps, temp_allocator, job_system);

	if ((update_error & JPH::EPhysicsUpdateError::ManifoldCacheFull) != JPH::EPhysicsUpdateError::None) {
		WARN_PRINT_ONCE(vformat("Jolt Physics manifold cache exceeded capacity and contacts were ignored. "
								"Consider increasing maximum number of contact constraints in project settings. "
								"Maximum number of contact constraints is currently set to %d.",
				JoltProjectSettings::max_contact_constraints));
	}

	if ((update_error & JPH::EPhysicsUpdateError::BodyPairCacheFull) != JPH::EPhysicsUpdateError::None) {
		WARN_PRINT_ONCE(vformat("Jolt Physics body pair cache exceeded capacity and contacts were ignored. "
								"Consider increasing maximum number of body pairs in project settings. "
								"Maximum number of body pairs is currently set to %d.",
				JoltProjectSettings::max_body_pairs));
	}

	if ((update_error & JPH::EPhysicsUpdateError::ContactConstraintsFull) != JPH::EPhysicsUpdateError::None) {
		WARN_PRINT_ONCE(vformat("Jolt Physics contact constraint buffer exceeded capacity and contacts were ignored. "
								"Consider increasing maximum number of contact constraints in project settings. "
								"Maximum number of contact constraints is currently set to %d.",
				JoltProjectSettings::max_contact_constraints));
	}

	_post_step(p_step);

	stepping = false;
}

void JoltSpace3D::call_queries() {
	while (body_call_queries_list.first()) {
		JoltBody3D *body = body_call_queries_list.first()->self();
		body_call_queries_list.remove(body_call_queries_list.first());
		body->call_queries();
	}

	while (area_call_queries_list.first()) {
		JoltArea3D *body = area_call_queries_list.first()->self();
		area_call_queries_list.remove(area_call_queries_list.first());
		body->call_queries();
	}
}

double JoltSpace3D::get_param(PS3DE::SpaceParameter p_param) const {
	switch (p_param) {
		case PS3DE::SPACE_PARAM_CONTACT_RECYCLE_RADIUS: {
			return SPACE_DEFAULT_CONTACT_RECYCLE_RADIUS;
		}
		case PS3DE::SPACE_PARAM_CONTACT_MAX_SEPARATION: {
			return SPACE_DEFAULT_CONTACT_MAX_SEPARATION;
		}
		case PS3DE::SPACE_PARAM_CONTACT_MAX_ALLOWED_PENETRATION: {
			return SPACE_DEFAULT_CONTACT_MAX_ALLOWED_PENETRATION;
		}
		case PS3DE::SPACE_PARAM_CONTACT_DEFAULT_BIAS: {
			return SPACE_DEFAULT_CONTACT_DEFAULT_BIAS;
		}
		case PS3DE::SPACE_PARAM_BODY_LINEAR_VELOCITY_SLEEP_THRESHOLD: {
			return SPACE_DEFAULT_SLEEP_THRESHOLD_LINEAR;
		}
		case PS3DE::SPACE_PARAM_BODY_ANGULAR_VELOCITY_SLEEP_THRESHOLD: {
			return SPACE_DEFAULT_SLEEP_THRESHOLD_ANGULAR;
		}
		case PS3DE::SPACE_PARAM_BODY_TIME_TO_SLEEP: {
			return JoltProjectSettings::sleep_time_threshold;
		}
		case PS3DE::SPACE_PARAM_SOLVER_ITERATIONS: {
			return SPACE_DEFAULT_SOLVER_ITERATIONS;
		}
		default: {
			ERR_FAIL_V_MSG(0.0, vformat("Unhandled space parameter: '%d'. This should not happen. Please report this.", p_param));
		}
	}
}

void JoltSpace3D::set_param(PS3DE::SpaceParameter p_param, double p_value) {
	switch (p_param) {
		case PS3DE::SPACE_PARAM_CONTACT_RECYCLE_RADIUS: {
			WARN_PRINT("Space-specific contact recycle radius is not supported when using Jolt Physics. Any such value will be ignored.");
		} break;
		case PS3DE::SPACE_PARAM_CONTACT_MAX_SEPARATION: {
			WARN_PRINT("Space-specific contact max separation is not supported when using Jolt Physics. Any such value will be ignored.");
		} break;
		case PS3DE::SPACE_PARAM_CONTACT_MAX_ALLOWED_PENETRATION: {
			WARN_PRINT("Space-specific contact max allowed penetration is not supported when using Jolt Physics. Any such value will be ignored.");
		} break;
		case PS3DE::SPACE_PARAM_CONTACT_DEFAULT_BIAS: {
			WARN_PRINT("Space-specific contact default bias is not supported when using Jolt Physics. Any such value will be ignored.");
		} break;
		case PS3DE::SPACE_PARAM_BODY_LINEAR_VELOCITY_SLEEP_THRESHOLD: {
			WARN_PRINT("Space-specific linear velocity sleep threshold is not supported when using Jolt Physics. Any such value will be ignored.");
		} break;
		case PS3DE::SPACE_PARAM_BODY_ANGULAR_VELOCITY_SLEEP_THRESHOLD: {
			WARN_PRINT("Space-specific angular velocity sleep threshold is not supported when using Jolt Physics. Any such value will be ignored.");
		} break;
		case PS3DE::SPACE_PARAM_BODY_TIME_TO_SLEEP: {
			WARN_PRINT("Space-specific body sleep time is not supported when using Jolt Physics. Any such value will be ignored.");
		} break;
		case PS3DE::SPACE_PARAM_SOLVER_ITERATIONS: {
			WARN_PRINT("Space-specific solver iterations is not supported when using Jolt Physics. Any such value will be ignored.");
		} break;
		default: {
			ERR_FAIL_MSG(vformat("Unhandled space parameter: '%d'. This should not happen. Please report this.", p_param));
		} break;
	}
}

JPH::BodyInterface &JoltSpace3D::get_body_iface() {
	return physics_system->GetBodyInterfaceNoLock();
}

const JPH::BodyInterface &JoltSpace3D::get_body_iface() const {
	return physics_system->GetBodyInterfaceNoLock();
}

const JPH::BodyLockInterface &JoltSpace3D::get_lock_iface() const {
	return physics_system->GetBodyLockInterfaceNoLock();
}

const JPH::BroadPhaseQuery &JoltSpace3D::get_broad_phase_query() const {
	return physics_system->GetBroadPhaseQuery();
}

const JPH::NarrowPhaseQuery &JoltSpace3D::get_narrow_phase_query() const {
	return physics_system->GetNarrowPhaseQueryNoLock();
}

JPH::ObjectLayer JoltSpace3D::map_to_object_layer(JPH::BroadPhaseLayer p_broad_phase_layer, uint32_t p_collision_layer, uint32_t p_collision_mask) {
	return layers->to_object_layer(p_broad_phase_layer, p_collision_layer, p_collision_mask);
}

void JoltSpace3D::map_from_object_layer(JPH::ObjectLayer p_object_layer, JPH::BroadPhaseLayer &r_broad_phase_layer, uint32_t &r_collision_layer, uint32_t &r_collision_mask) const {
	layers->from_object_layer(p_object_layer, r_broad_phase_layer, r_collision_layer, r_collision_mask);
}

JPH::Body *JoltSpace3D::try_get_jolt_body(const JPH::BodyID &p_body_id) const {
	return get_lock_iface().TryGetBody(p_body_id);
}

JoltObject3D *JoltSpace3D::try_get_object(const JPH::BodyID &p_body_id) const {
	const JPH::Body *jolt_body = try_get_jolt_body(p_body_id);
	if (unlikely(jolt_body == nullptr)) {
		return nullptr;
	}

	return reinterpret_cast<JoltObject3D *>(jolt_body->GetUserData());
}

JoltShapedObject3D *JoltSpace3D::try_get_shaped(const JPH::BodyID &p_body_id) const {
	JoltObject3D *object = try_get_object(p_body_id);
	if (unlikely(object == nullptr)) {
		return nullptr;
	}

	return object->as_shaped();
}

JoltBody3D *JoltSpace3D::try_get_body(const JPH::BodyID &p_body_id) const {
	JoltObject3D *object = try_get_object(p_body_id);
	if (unlikely(object == nullptr)) {
		return nullptr;
	}

	return object->as_body();
}

JoltArea3D *JoltSpace3D::try_get_area(const JPH::BodyID &p_body_id) const {
	JoltObject3D *object = try_get_object(p_body_id);
	if (unlikely(object == nullptr)) {
		return nullptr;
	}

	return object->as_area();
}

JoltSoftBody3D *JoltSpace3D::try_get_soft_body(const JPH::BodyID &p_body_id) const {
	JoltObject3D *object = try_get_object(p_body_id);
	if (unlikely(object == nullptr)) {
		return nullptr;
	}

	return object->as_soft_body();
}

int JoltSpace3D::get_contact_manifold_count() const {
	return contact_listener->get_contact_manifold_count();
}

JoltPhysicsDirectSpaceState3D *JoltSpace3D::get_direct_state() {
	if (direct_state == nullptr) {
		direct_state = memnew(JoltPhysicsDirectSpaceState3D(this));
	}

	return direct_state;
}

JPH::Body *JoltSpace3D::add_object(const JoltObject3D &p_object, const JPH::BodyCreationSettings &p_settings, bool p_sleeping) {
	JPH::BodyInterface &body_iface = get_body_iface();
	JPH::Body *jolt_body = body_iface.CreateBody(p_settings);
	if (unlikely(jolt_body == nullptr)) {
		ERR_PRINT_ONCE(vformat("Failed to create underlying Jolt Physics body for '%s'. "
							   "Consider increasing maximum number of bodies in project settings. "
							   "Maximum number of bodies is currently set to %d.",
				p_object.to_string(), JoltProjectSettings::max_bodies));

		return nullptr;
	}

	if (p_sleeping) {
		_pending_add(pending_objects_sleeping, pending_sleeping_indices, jolt_body->GetID());
	} else {
		_pending_add(pending_objects_awake, pending_awake_indices, jolt_body->GetID());
	}

	return jolt_body;
}

JPH::Body *JoltSpace3D::add_object(const JoltObject3D &p_object, const JPH::SoftBodyCreationSettings &p_settings, bool p_sleeping) {
	JPH::BodyInterface &body_iface = get_body_iface();
	JPH::Body *jolt_body = body_iface.CreateSoftBody(p_settings);
	if (unlikely(jolt_body == nullptr)) {
		ERR_PRINT_ONCE(vformat("Failed to create underlying Jolt Physics body for '%s'. "
							   "Consider increasing maximum number of bodies in project settings. "
							   "Maximum number of bodies is currently set to %d.",
				p_object.to_string(), JoltProjectSettings::max_bodies));

		return nullptr;
	}

	if (p_sleeping) {
		_pending_add(pending_objects_sleeping, pending_sleeping_indices, jolt_body->GetID());
	} else {
		_pending_add(pending_objects_awake, pending_awake_indices, jolt_body->GetID());
	}

	return jolt_body;
}

void JoltSpace3D::remove_object(const JPH::BodyID &p_jolt_id) {
	JPH::BodyInterface &body_iface = get_body_iface();

	// A body queued by CreateBody/CreateSoftBody has not been inserted in
	// Jolt's broadphase. Its destruction cannot leave stale broadphase nodes.
	const bool was_pending = _pending_erase(pending_objects_sleeping, pending_sleeping_indices, p_jolt_id) ||
			_pending_erase(pending_objects_awake, pending_awake_indices, p_jolt_id);
	if (!was_pending) {
		body_iface.RemoveBody(p_jolt_id);
	}

	body_iface.DestroyBody(p_jolt_id);

	// Unstepped editor spaces still need a rebuild after the last *inserted*
	// body is removed. A pending-only deletion needs no rebuild and can
	// otherwise trigger thousands of expensive, redundant rebuilds while
	// streaming or canceling large scene loads.
	// A space normally retains the default area, hence the <= 1 check.
	if (!was_pending && !JoltPhysicsServer3D::get_singleton()->is_active() && physics_system->GetNumBodies() <= 1) {
		physics_system->OptimizeBroadPhase();
	}
}

void JoltSpace3D::flush_pending_objects() {
	if (pending_objects_sleeping.is_empty() && pending_objects_awake.is_empty()) {
		return;
	}

	// We only care about locking within this method, because it's called when performing queries, which aren't covered by `PhysicsServer3DWrapMT`.
	MutexLock pending_objects_lock(pending_objects_mutex);

	JPH::BodyInterface &body_iface = get_body_iface();

	if (!pending_objects_sleeping.is_empty()) {
		JPH::BodyInterface::AddState add_state = body_iface.AddBodiesPrepare(pending_objects_sleeping.ptr(), pending_objects_sleeping.size());
		body_iface.AddBodiesFinalize(pending_objects_sleeping.ptr(), pending_objects_sleeping.size(), add_state, JPH::EActivation::DontActivate);
		if (pending_objects_sleeping.get_capacity() > MAX_RETAINED_PENDING_BODY_IDS) {
			pending_objects_sleeping.reset();
		} else {
			pending_objects_sleeping.clear();
		}
		clear_pending_index(pending_sleeping_indices);
	}

	if (!pending_objects_awake.is_empty()) {
		JPH::BodyInterface::AddState add_state = body_iface.AddBodiesPrepare(pending_objects_awake.ptr(), pending_objects_awake.size());
		body_iface.AddBodiesFinalize(pending_objects_awake.ptr(), pending_objects_awake.size(), add_state, JPH::EActivation::Activate);
		if (pending_objects_awake.get_capacity() > MAX_RETAINED_PENDING_BODY_IDS) {
			pending_objects_awake.reset();
		} else {
			pending_objects_awake.clear();
		}
		clear_pending_index(pending_awake_indices);
	}
}

void JoltSpace3D::set_is_object_sleeping(const JPH::BodyID &p_jolt_id, bool p_enable) {
	if (p_enable) {
		if (_pending_erase(pending_objects_awake, pending_awake_indices, p_jolt_id)) {
			_pending_add(pending_objects_sleeping, pending_sleeping_indices, p_jolt_id);
		} else if (_pending_has(pending_objects_sleeping, pending_sleeping_indices, p_jolt_id)) {
			// Do nothing.
		} else {
			get_body_iface().DeactivateBody(p_jolt_id);
		}
	} else {
		if (_pending_erase(pending_objects_sleeping, pending_sleeping_indices, p_jolt_id)) {
			_pending_add(pending_objects_awake, pending_awake_indices, p_jolt_id);
		} else if (_pending_has(pending_objects_awake, pending_awake_indices, p_jolt_id)) {
			// Do nothing.
		} else {
			get_body_iface().ActivateBody(p_jolt_id);
		}
	}
}

void JoltSpace3D::enqueue_call_queries(SelfList<JoltBody3D> *p_body) {
	// This method will be called from the body activation listener on multiple threads during the simulation step.
	MutexLock body_call_queries_lock(body_call_queries_mutex);

	if (!p_body->in_list()) {
		body_call_queries_list.add(p_body);
	}
}

void JoltSpace3D::enqueue_call_queries(SelfList<JoltArea3D> *p_area) {
	if (!p_area->in_list()) {
		area_call_queries_list.add(p_area);
	}
}

void JoltSpace3D::dequeue_call_queries(SelfList<JoltBody3D> *p_body) {
	if (p_body->in_list()) {
		body_call_queries_list.remove(p_body);
	}
}

void JoltSpace3D::dequeue_call_queries(SelfList<JoltArea3D> *p_area) {
	if (p_area->in_list()) {
		area_call_queries_list.remove(p_area);
	}
}

void JoltSpace3D::enqueue_shapes_changed(SelfList<JoltShapedObject3D> *p_object) {
	if (!p_object->in_list()) {
		shapes_changed_list.add(p_object);
	}
}

void JoltSpace3D::dequeue_shapes_changed(SelfList<JoltShapedObject3D> *p_object) {
	if (p_object->in_list()) {
		shapes_changed_list.remove(p_object);
	}
}

void JoltSpace3D::enqueue_needs_optimization(SelfList<JoltShapedObject3D> *p_object) {
	if (!p_object->in_list()) {
		needs_optimization_list.add(p_object);
	}
}

void JoltSpace3D::dequeue_needs_optimization(SelfList<JoltShapedObject3D> *p_object) {
	if (p_object->in_list()) {
		needs_optimization_list.remove(p_object);
	}
}

void JoltSpace3D::add_joint(JPH::Constraint *p_jolt_ref) {
	physics_system->AddConstraint(p_jolt_ref);
}

void JoltSpace3D::add_joint(JoltJoint3D *p_joint) {
	add_joint(p_joint->get_jolt_ref());
}

void JoltSpace3D::remove_joint(JPH::Constraint *p_jolt_ref) {
	physics_system->RemoveConstraint(p_jolt_ref);
}

void JoltSpace3D::remove_joint(JoltJoint3D *p_joint) {
	remove_joint(p_joint->get_jolt_ref());
}

#ifdef DEBUG_ENABLED

void JoltSpace3D::dump_debug_snapshot(const String &p_dir) {
	const Dictionary datetime = Time::get_singleton()->get_datetime_dict_from_system();
	const String datetime_str = vformat("%04d-%02d-%02d_%02d-%02d-%02d", datetime["year"], datetime["month"], datetime["day"], datetime["hour"], datetime["minute"], datetime["second"]);
	const String path = p_dir + vformat("/jolt_snapshot_%s_%d.bin", datetime_str, rid.get_id());

	Ref<FileAccess> file_access = FileAccess::open(path, FileAccess::ModeFlags::WRITE);
	ERR_FAIL_COND_MSG(file_access.is_null(), vformat("Failed to open '%s' for writing when saving snapshot of physics space with RID '%d'.", path, rid.get_id()));

	JPH::PhysicsScene physics_scene;
	physics_scene.FromPhysicsSystem(physics_system);

	for (JPH::BodyCreationSettings &settings : physics_scene.GetBodies()) {
		const JoltObject3D *object = reinterpret_cast<const JoltObject3D *>(settings.mUserData);

		if (const JoltBody3D *body = object->as_body()) {
			// Since we apply our own damping, while leaving Jolt's own values at zero, we need to transfer over the correct values.
			settings.mLinearDamping = body->get_total_linear_damp();
			settings.mAngularDamping = body->get_total_angular_damp();
		}

		settings.SetShape(JoltShape3D::without_custom_shapes(settings.GetShape()));
	}

	JoltStreamOutputWrapper output_stream(file_access);
	physics_scene.SaveBinaryState(output_stream, true, false);

	ERR_FAIL_COND_MSG(file_access->get_error() != OK, vformat("Writing snapshot of physics space with RID '%d' to '%s' failed with error '%s'.", rid.get_id(), path, VariantUtilityFunctions::error_string(file_access->get_error())));

	print_line(vformat("Snapshot of physics space with RID '%d' saved to '%s'.", rid.get_id(), path));
}

const PackedVector3Array &JoltSpace3D::get_debug_contacts() const {
	return contact_listener->get_debug_contacts();
}

int JoltSpace3D::get_debug_contact_count() const {
	return contact_listener->get_debug_contact_count();
}

int JoltSpace3D::get_max_debug_contacts() const {
	return contact_listener->get_max_debug_contacts();
}

void JoltSpace3D::set_max_debug_contacts(int p_count) {
	contact_listener->set_max_debug_contacts(p_count);
}

#endif
