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
#include <unordered_map>

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

// Experimental speculative soft-soft CCD for an approaching vertex and a
// moving/deforming face. Linearize the face motion by the mean vertex
// velocity for the time-of-impact plane test, then re-evaluate the moving
// triangle at that time for the closest point and barycentric weights.
// This is a cheap *approximate* swept contact, NOT continuous triangle CCD,
// and it does not use Jolt's rigid-body LinearCast pipeline.
static bool predict_soft_vertex_face_sweep(JPH::Vec3Arg p_point, JPH::Vec3Arg p_point_velocity,
		JPH::Vec3Arg p_a, JPH::Vec3Arg p_b, JPH::Vec3Arg p_c,
		JPH::Vec3Arg p_va, JPH::Vec3Arg p_vb, JPH::Vec3Arg p_vc,
		float p_step, float p_radius, float p_max_sweep,
		float &r_u, float &r_v, float &r_w, JPH::Vec3 &r_normal) {
	if (p_step <= 0.0f || p_radius <= 0.0f || p_max_sweep <= 0.0f) {
		return false;
	}
	const JPH::Vec3 face_cross = (p_b - p_a).Cross(p_c - p_a);
	const float normal_length_sq = face_cross.LengthSq();
	if (!Math::is_finite(normal_length_sq) || normal_length_sq <= 1.0e-12f) {
		return false;
	}
	const JPH::Vec3 face_normal = face_cross / Math::sqrt(normal_length_sq);
	const JPH::Vec3 mean_face_velocity = (p_va + p_vb + p_vc) / 3.0f;
	const JPH::Vec3 relative_velocity = p_point_velocity - mean_face_velocity;
	const float relative_displacement_sq = (relative_velocity * p_step).LengthSq();
	if (!Math::is_finite(relative_displacement_sq) || relative_displacement_sq > p_max_sweep * p_max_sweep) {
		return false; // Fixed and documented sweep horizon.
	}
	const float plane_distance = (p_point - p_a).Dot(face_normal);
	const float plane_speed = relative_velocity.Dot(face_normal);
	if (!Math::is_finite(plane_distance) || !Math::is_finite(plane_speed)) {
		return false;
	}
	// Two-sided contact: only catch a trajectory starting *outside* the
	// contact shell and moving towards it. The discrete solver handles points
	// currently within the shell.
	float target_distance = 0.0f;
	if (plane_distance > p_radius && plane_speed < -1.0e-6f) {
		target_distance = p_radius;
	} else if (plane_distance < -p_radius && plane_speed > 1.0e-6f) {
		target_distance = -p_radius;
	} else {
		return false;
	}
	const float toi = (target_distance - plane_distance) / plane_speed;
	if (!Math::is_finite(toi) || toi < 0.0f || toi > p_step) {
		return false;
	}

	// The plane TOI is linearized, but evaluate the actual interpolated
	// triangle at the predicted time to reject faces that shear/rotate away.
	const JPH::Vec3 point_at_hit = p_point + p_point_velocity * toi;
	const JPH::Vec3 a_at_hit = p_a + p_va * toi;
	const JPH::Vec3 b_at_hit = p_b + p_vb * toi;
	const JPH::Vec3 c_at_hit = p_c + p_vc * toi;
	JPH::Vec3 nearest = JPH::Vec3::sZero();
	if (!closest_soft_triangle_point(point_at_hit, a_at_hit, b_at_hit, c_at_hit, nearest, r_u, r_v, r_w)) {
		return false;
	}
	const JPH::Vec3 contact_vector = point_at_hit - nearest;
	const float hit_distance_sq = contact_vector.LengthSq();
	// Small tolerance for finite-precision TOI. Conservatively reject a
	// speculative contact when the interpolated surface has moved away.
	const float hit_tolerance = p_radius * 1.02f + 1.0e-4f;
	if (!Math::is_finite(hit_distance_sq) || hit_distance_sq > hit_tolerance * hit_tolerance) {
		return false;
	}
	r_normal = hit_distance_sq > 1.0e-12f ? contact_vector / Math::sqrt(hit_distance_sq) :
			(plane_distance > 0.0f ? face_normal : -face_normal);
	return true;
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
	const bool speculative_ccd = JoltProjectSettings::soft_body_soft_speculative_ccd &&
			JoltProjectSettings::soft_body_soft_ccd_max_sweep > 0.0f;
	const float sweep_expansion = speculative_ccd ? JoltProjectSettings::soft_body_soft_ccd_max_sweep : 0.0f;
	const float candidate_radius = radius + sweep_expansion;

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
			query_soft_face_bvh(r_bvh_scratch.entries, r_bvh_scratch.nodes, point_position, candidate_radius,
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
			if (point_position.GetX() < tri_min.GetX() - candidate_radius || point_position.GetX() > tri_max.GetX() + candidate_radius ||
					point_position.GetY() < tri_min.GetY() - candidate_radius || point_position.GetY() > tri_max.GetY() + candidate_radius ||
					point_position.GetZ() < tri_min.GetZ() - candidate_radius || point_position.GetZ() > tri_max.GetZ() + candidate_radius) {
				continue;
			}

			JPH::Vec3 nearest = JPH::Vec3::sZero();
			float u = 0.0f, v = 0.0f, w = 0.0f;
			if (!closest_soft_triangle_point(point_position, a, b, c, nearest, u, v, w)) {
				continue;
			}
			const JPH::Vec3 diff = point_position - nearest;
			const float distance_sq = diff.LengthSq();
			if (!Math::is_finite(distance_sq)) {
				continue;
			}
			bool swept_contact = false;
			JPH::Vec3 swept_normal = JPH::Vec3::sZero();
			if (distance_sq >= radius_sq) {
				if (!speculative_ccd || !predict_soft_vertex_face_sweep(
						point_position, point_rotation * point.mVelocity, a, b, c,
						face_rotation * v0.mVelocity, face_rotation * v1.mVelocity, face_rotation * v2.mVelocity,
						p_step, radius, sweep_expansion, u, v, w, swept_normal)) {
					continue;
				}
				swept_contact = true;
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
			JPH::Vec3 normal = swept_contact ? swept_normal :
					(distance > 1.0e-6f ? diff / distance : (b - a).Cross(c - a).Normalized());
			if (!swept_contact && distance <= 1.0e-6f && relative_velocity.Dot(normal) > 0.0f) {
				normal = -normal;
			}
			const float normal_speed = relative_velocity.Dot(normal);
			if (!Math::is_finite(normal_speed)) {
				continue;
			}
			// For a future impact, remove approaching normal velocity now.
			// Using the discrete 8 m/s cap would allow a fast vertex to tunnel.
			// Speculative contacts add no penetration bias before impact.
			const float recovery_speed = swept_contact ? 0.0f :
					MIN((radius - distance) * bias_per_step, MAX_SOFT_SOFT_PENETRATION_BIAS);
			const float max_correction = swept_contact ? JoltProjectSettings::soft_body_soft_ccd_max_correction_speed :
					MAX_SOFT_SOFT_CONTACT_SPEED_CORRECTION;
			const float correction = MIN(MAX(recovery_speed - normal_speed, 0.0f), max_correction);
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

// Experimental deformable edge/edge collisions supplement vertex/face
// contacts when two thin triangle edges cross but all vertices are far
// from the opposite surface. Like the VF path, this is a pre-step velocity
// correction (not CCD). No persistent topology or new Jolt SDK APIs.
constexpr uint32_t MAX_SOFT_SOFT_EDGE_FACES = 512;
constexpr float SOFT_EDGE_EPSILON = 1.0e-12f;

struct SoftEdgeContactScratch {
	JPH::Array<uint64_t> keys_a;
	JPH::Array<uint64_t> keys_b;
};

static bool collect_soft_surface_edges(const JPH::Array<JPH::SoftBodySharedSettings::Face> &p_faces,
		uint32_t p_vertex_count, JPH::Array<uint64_t> &r_keys, uint32_t &r_budget) {
	r_keys.clear();
	if (p_faces.empty() || p_faces.size() > MAX_SOFT_SOFT_EDGE_FACES) {
		return false;
	}

	// Charge the upper-bound cost of collecting and sorting 3*F edge keys.
	const uint32_t raw_count = uint32_t(p_faces.size()) * 3;
	uint32_t levels = 0;
	for (uint32_t count = raw_count; count > 1; count = (count + 1) / 2) {
		++levels;
	}
	const uint32_t construction_cost = raw_count * (levels + 1);
	if (r_budget <= construction_cost) {
		return false;
	}
	r_budget -= construction_cost;
	r_keys.reserve(raw_count);
	for (const JPH::SoftBodySharedSettings::Face &face : p_faces) {
		if (face.IsDegenerate() || face.mVertex[0] >= p_vertex_count ||
				face.mVertex[1] >= p_vertex_count || face.mVertex[2] >= p_vertex_count) {
			continue;
		}
		for (uint32_t k = 0; k < 3; ++k) {
			const uint32_t i = face.mVertex[k];
			const uint32_t j = face.mVertex[(k + 1) % 3];
			const uint64_t key = (uint64_t(MIN(i, j)) << 32) | uint64_t(MAX(i, j));
			r_keys.push_back(key);
		}
	}
	if (r_keys.empty()) {
		return false;
	}
	// Adjacent triangles share edges. Test each geometric edge only once,
	// otherwise contact stiffness depends on triangle tessellation.
	std::sort(r_keys.begin(), r_keys.end());
	const size_t unique_count = std::unique(r_keys.begin(), r_keys.end()) - r_keys.begin();
	r_keys.resize(unique_count);
	return true;
}

// Closest parameters s,t of segments [p0,p1] and [q0,q1] (Ericson).
// Endpoints and parallel configurations are explicitly clamped. Degenerate
// segments are rejected: VV/VF already cover zero-length edge endpoints.
static bool closest_soft_edge_edge(JPH::Vec3Arg p0, JPH::Vec3Arg p1,
		JPH::Vec3Arg q0, JPH::Vec3Arg q1, float &r_s, float &r_t,
		JPH::Vec3 &r_p, JPH::Vec3 &r_q) {
	const JPH::Vec3 d1 = p1 - p0;
	const JPH::Vec3 d2 = q1 - q0;
	const JPH::Vec3 r = p0 - q0;
	const float a = d1.Dot(d1);
	const float e = d2.Dot(d2);
	if (!Math::is_finite(a) || !Math::is_finite(e) || a <= SOFT_EDGE_EPSILON || e <= SOFT_EDGE_EPSILON) {
		return false;
	}
	const float b = d1.Dot(d2);
	const float c = d1.Dot(r);
	const float f = d2.Dot(r);
	const float denominator = a * e - b * b;
	if (!Math::is_finite(denominator) || !Math::is_finite(c) || !Math::is_finite(f)) {
		return false;
	}
	r_s = denominator > SOFT_EDGE_EPSILON ? CLAMP((b * f - c * e) / denominator, 0.0f, 1.0f) : 0.0f;
	r_t = (b * r_s + f) / e;
	if (r_t < 0.0f) {
		r_t = 0.0f;
		r_s = CLAMP(-c / a, 0.0f, 1.0f);
	} else if (r_t > 1.0f) {
		r_t = 1.0f;
		r_s = CLAMP((b - c) / a, 0.0f, 1.0f);
	}
	if (!Math::is_finite(r_s) || !Math::is_finite(r_t)) {
		return false;
	}
	r_p = p0 + d1 * r_s;
	r_q = q0 + d2 * r_t;
	return true;
}

// Swept soft edge/edge approximation using conservative advancement for
// linearly moving endpoints. The minimum distance between two segments is
// Lipschitz continuous, bounded by the largest endpoint-relative speed;
// stepping by (distance - radius) / speed_bound cannot skip a first contact
// in exact arithmetic. This is NOT CCD for arbitrarily accelerated,
// internally constrained or nonlinear deformable motion during Jolt Update.
constexpr uint32_t MAX_SOFT_EDGE_SWEEP_ITERATIONS = 16;
constexpr float SOFT_EDGE_SWEEP_DISTANCE_TOLERANCE = 1.0e-4f;

static bool predict_soft_edge_edge_sweep(
		JPH::Vec3Arg p0, JPH::Vec3Arg p1, JPH::Vec3Arg q0, JPH::Vec3Arg q1,
		JPH::Vec3Arg vp0, JPH::Vec3Arg vp1, JPH::Vec3Arg vq0, JPH::Vec3Arg vq1,
		float p_step, float p_radius, float p_max_sweep, uint32_t &r_budget,
		float &r_s, float &r_t, JPH::Vec3 &r_normal) {
	if (p_step <= 0.0f || p_radius <= 0.0f || p_max_sweep <= 0.0f) {
		return false;
	}

	// A convex combination of two endpoint velocities cannot exceed
	// the maximum magnitude of these four endpoint-relative velocities.
	const float max_relative_speed_sq = MAX(
			MAX((vq0 - vp0).LengthSq(), (vq0 - vp1).LengthSq()),
			MAX((vq1 - vp0).LengthSq(), (vq1 - vp1).LengthSq()));
	if (!Math::is_finite(max_relative_speed_sq) || max_relative_speed_sq <= 1.0e-12f) {
		return false;
	}
	const float speed_bound = Math::sqrt(max_relative_speed_sq);
	const float travel_bound = speed_bound * p_step;
	if (!Math::is_finite(travel_bound) || travel_bound > p_max_sweep) {
		return false;
	}

	float time = 0.0f;
	for (uint32_t iteration = 0; iteration < MAX_SOFT_EDGE_SWEEP_ITERATIONS && r_budget > 0; ++iteration) {
		// Account for each iterative segment closest-point evaluation, in
		// addition to the initial broadphase/segment test already debited.
		--r_budget;
		const JPH::Vec3 a0 = p0 + vp0 * time;
		const JPH::Vec3 a1 = p1 + vp1 * time;
		const JPH::Vec3 b0 = q0 + vq0 * time;
		const JPH::Vec3 b1 = q1 + vq1 * time;
		JPH::Vec3 nearest_a = JPH::Vec3::sZero();
		JPH::Vec3 nearest_b = JPH::Vec3::sZero();
		float s = 0.0f, t = 0.0f;
		if (!closest_soft_edge_edge(a0, a1, b0, b1, s, t, nearest_a, nearest_b)) {
			return false;
		}
		const JPH::Vec3 gap = nearest_b - nearest_a;
		const float distance_sq = gap.LengthSq();
		if (!Math::is_finite(distance_sq)) {
			return false;
		}
		const float distance = Math::sqrt(MAX(distance_sq, 0.0f));
		if (time > 0.0f && distance <= p_radius + SOFT_EDGE_SWEEP_DISTANCE_TOLERANCE) {
			const JPH::Vec3 vel_a = vp0 * (1.0f - s) + vp1 * s;
			const JPH::Vec3 vel_b = vq0 * (1.0f - t) + vq1 * t;
			const JPH::Vec3 rel_velocity = vel_b - vel_a;
			if (distance > 1.0e-6f) {
				r_normal = gap / distance;
			} else if (rel_velocity.LengthSq() > 1.0e-12f) {
				r_normal = -rel_velocity.Normalized();
			} else {
				return false;
			}
			// Only future *approaching* contacts get speculative impulses.
			// Tangential/grazing contacts have no normal closing velocity.
			if (!Math::is_finite(rel_velocity.Dot(r_normal)) || rel_velocity.Dot(r_normal) >= -1.0e-6f) {
				return false;
			}
			r_s = s;
			r_t = t;
			return true;
		}
		if (distance <= p_radius) {
			return false; // Already overlapping: use the discrete solver.
		}

		// This is a conservative time increment from the distance bound;
		// unlike fixed substep sampling, fast narrow impacts are not
		// skipped when the remaining work budget is sufficient.
		const float advance = (distance - p_radius) / speed_bound;
		if (!Math::is_finite(advance) || advance <= 1.0e-8f * p_step || time + advance > p_step) {
			return false;
		}
		time += advance;
	}
	return false; // Work cap or iteration cap; no unbounded loop.
}

static void resolve_soft_soft_edge_edge_contacts(JPH::Body &p_body_a, JPH::Body &p_body_b,
		float p_step, uint32_t &r_budget, SoftEdgeContactScratch &r_scratch) {
	JPH::SoftBodyMotionProperties &props_a = static_cast<JPH::SoftBodyMotionProperties &>(*p_body_a.GetMotionPropertiesUnchecked());
	JPH::SoftBodyMotionProperties &props_b = static_cast<JPH::SoftBodyMotionProperties &>(*p_body_b.GetMotionPropertiesUnchecked());
	JPH::Array<JPH::SoftBodyVertex> &vertices_a = props_a.GetVertices();
	JPH::Array<JPH::SoftBodyVertex> &vertices_b = props_b.GetVertices();
	if (!collect_soft_surface_edges(props_a.GetFaces(), uint32_t(vertices_a.size()), r_scratch.keys_a, r_budget) ||
			!collect_soft_surface_edges(props_b.GetFaces(), uint32_t(vertices_b.size()), r_scratch.keys_b, r_budget)) {
		return;
	}

	const JPH::Quat rotation_a = p_body_a.GetRotation();
	const JPH::Quat rotation_b = p_body_b.GetRotation();
	const JPH::Quat inverse_a = rotation_a.Conjugated();
	const JPH::Quat inverse_b = rotation_b.Conjugated();
	const JPH::Vec3 center_delta(p_body_b.GetCenterOfMassPosition() - p_body_a.GetCenterOfMassPosition());
	const float radius = JoltProjectSettings::soft_body_soft_contact_radius;
	const float friction = JoltProjectSettings::soft_body_soft_contact_friction;
	const float bias_per_step = JoltProjectSettings::soft_body_soft_contact_recovery / p_step;
	const bool swept_edge_ccd = JoltProjectSettings::soft_body_soft_speculative_edge_ccd &&
			JoltProjectSettings::soft_body_soft_ccd_max_sweep > 0.0f;
	const float candidate_radius = radius + (swept_edge_ccd ? JoltProjectSettings::soft_body_soft_ccd_max_sweep : 0.0f);

	for (uint64_t key_a : r_scratch.keys_a) {
		if (r_budget == 0) {
			return;
		}
		JPH::SoftBodyVertex &a0 = vertices_a[uint32_t(key_a >> 32)];
		JPH::SoftBodyVertex &a1 = vertices_a[uint32_t(key_a)];
		const JPH::Vec3 p0 = rotation_a * a0.mPosition;
		const JPH::Vec3 p1 = rotation_a * a1.mPosition;
		const JPH::Vec3 p_min = JPH::Vec3::sMin(p0, p1);
		const JPH::Vec3 p_max = JPH::Vec3::sMax(p0, p1);
		for (uint64_t key_b : r_scratch.keys_b) {
			if (r_budget == 0) {
				return;
			}
			--r_budget; // Includes rejected candidates: hard per-step work cap.
			JPH::SoftBodyVertex &b0 = vertices_b[uint32_t(key_b >> 32)];
			JPH::SoftBodyVertex &b1 = vertices_b[uint32_t(key_b)];
			const JPH::Vec3 q0 = center_delta + rotation_b * b0.mPosition;
			const JPH::Vec3 q1 = center_delta + rotation_b * b1.mPosition;
			const JPH::Vec3 q_min = JPH::Vec3::sMin(q0, q1);
			const JPH::Vec3 q_max = JPH::Vec3::sMax(q0, q1);
			if (p_max.GetX() + candidate_radius < q_min.GetX() || q_max.GetX() + candidate_radius < p_min.GetX() ||
					p_max.GetY() + candidate_radius < q_min.GetY() || q_max.GetY() + candidate_radius < p_min.GetY() ||
					p_max.GetZ() + candidate_radius < q_min.GetZ() || q_max.GetZ() + candidate_radius < p_min.GetZ()) {
				continue;
			}

			float s = 0.0f, t = 0.0f;
			JPH::Vec3 near_a = JPH::Vec3::sZero(), near_b = JPH::Vec3::sZero();
			if (!closest_soft_edge_edge(p0, p1, q0, q1, s, t, near_a, near_b)) {
				continue;
			}
			const JPH::Vec3 separation = near_b - near_a;
			const float distance_sq = separation.LengthSq();
			if (!Math::is_finite(distance_sq)) {
				continue;
			}
			bool swept_contact = false;
			JPH::Vec3 swept_normal = JPH::Vec3::sZero();
			if (distance_sq >= radius * radius) {
				if (!swept_edge_ccd || !predict_soft_edge_edge_sweep(p0, p1, q0, q1,
						rotation_a * a0.mVelocity, rotation_a * a1.mVelocity,
						rotation_b * b0.mVelocity, rotation_b * b1.mVelocity,
						p_step, radius, JoltProjectSettings::soft_body_soft_ccd_max_sweep,
						r_budget, s, t, swept_normal)) {
					continue;
				}
				swept_contact = true;
			}
			const float wa0 = 1.0f - s, wa1 = s;
			const float wb0 = 1.0f - t, wb1 = t;
			const float inverse_mass_sum = wa0 * wa0 * a0.mInvMass + wa1 * wa1 * a1.mInvMass +
					wb0 * wb0 * b0.mInvMass + wb1 * wb1 * b1.mInvMass;
			if (!Math::is_finite(inverse_mass_sum) || inverse_mass_sum <= 0.0f) {
				continue;
			}

			const JPH::Vec3 vel_a = rotation_a * (wa0 * a0.mVelocity + wa1 * a1.mVelocity);
			const JPH::Vec3 vel_b = rotation_b * (wb0 * b0.mVelocity + wb1 * b1.mVelocity);
			const JPH::Vec3 relative_velocity = vel_b - vel_a;
			const float distance = swept_contact ? radius : Math::sqrt(MAX(distance_sq, 0.0f));
			JPH::Vec3 normal = swept_normal;
			if (swept_contact) {
				// The predictor has already chosen a normal at future impact.
			} else if (distance > 1.0e-6f) {
				normal = separation / distance;
			} else {
				const JPH::Vec3 crossing = (p1 - p0).Cross(q1 - q0);
				bool orientation_ambiguous = true;
				if (crossing.LengthSq() > SOFT_EDGE_EPSILON) {
					normal = crossing.Normalized();
					const float center_projection = normal.Dot(center_delta);
					if (Math::abs(center_projection) > 1.0e-6f) {
						orientation_ambiguous = false;
						if (center_projection < 0.0f) {
							normal = -normal;
						}
					}
				} else {
					normal = center_delta.LengthSq() > SOFT_EDGE_EPSILON ? center_delta.Normalized() : JPH::Vec3::sAxisY();
					orientation_ambiguous = center_delta.LengthSq() <= SOFT_EDGE_EPSILON;
				}
				// Use velocity to break ties ONLY when world-space separation
				// offers no direction. Otherwise don't reverse a contact normal
				// just because the segments are already moving apart.
				if (orientation_ambiguous && normal.Dot(relative_velocity) > 0.0f) {
					normal = -normal;
				}
			}
			const float normal_speed = relative_velocity.Dot(normal);
			if (!Math::is_finite(normal_speed)) {
				continue;
			}
			// Speculative impacts only remove future normal closing speed;
			// the discrete path retains its penetration recovery.
			const float recovery_speed = swept_contact ? 0.0f :
					MIN((radius - distance) * bias_per_step, MAX_SOFT_SOFT_PENETRATION_BIAS);
			const float max_correction = swept_contact ? JoltProjectSettings::soft_body_soft_ccd_max_correction_speed :
					MAX_SOFT_SOFT_CONTACT_SPEED_CORRECTION;
			const float correction = MIN(MAX(recovery_speed - normal_speed, 0.0f), max_correction);
			if (correction <= 0.0f) {
				continue;
			}
			const float normal_impulse = correction / inverse_mass_sum;
			if (!Math::is_finite(normal_impulse)) {
				continue;
			}
			JPH::Vec3 impulse = normal * normal_impulse;
			const JPH::Vec3 tangent_velocity = relative_velocity - normal * normal_speed;
			const float tangent_speed_sq = tangent_velocity.LengthSq();
			if (friction > 0.0f && Math::is_finite(tangent_speed_sq) && tangent_speed_sq > SOFT_EDGE_EPSILON) {
				const float tangent_speed = Math::sqrt(tangent_speed_sq);
				const float tangent_impulse = MIN(tangent_speed / inverse_mass_sum, friction * normal_impulse);
				impulse -= tangent_velocity * (tangent_impulse / tangent_speed);
			}

			const JPH::Vec3 local_impulse_a = inverse_a * impulse;
			const JPH::Vec3 local_impulse_b = inverse_b * impulse;
			a0.mVelocity -= local_impulse_a * (wa0 * a0.mInvMass);
			a1.mVelocity -= local_impulse_a * (wa1 * a1.mInvMass);
			b0.mVelocity += local_impulse_b * (wb0 * b0.mInvMass);
			b1.mVelocity += local_impulse_b * (wb1 * b1.mInvMass);
		}
	}
}

// Experimental single-body self collision. No topology mutation or Jolt
// internal solver changes: contact impulses are added to the per-particle
// velocities before Jolt's parallel Update. Exclude immediate mesh
// neighbors to avoid treating ordinary cloth springs as self contacts.
constexpr uint32_t MAX_SOFT_SELF_CONTACT_FACES = 1024;

struct SoftSelfContactScratch {
	SoftFaceBVHScratch bvh;
	SoftFaceBVHScratch edge_bvh; // Reused across active soft bodies.
	JPH::Array<uint64_t> one_ring_edges;
	// Jacobi self-contact corrections are accumulated without moving BVH
	// geometry during a candidate query, then uniformly capped and applied.
	JPH::Array<JPH::Vec3> position_deltas;
	bool position_projection_ready = false;

	// Face-array address identifies an immutable Jolt SoftBodySharedSettings
	// topology. A body rebuild gets a new BodyID, invalidating this cache.
	const void *topology_faces = nullptr;
	uint32_t topology_face_count = 0;
	uint32_t topology_vertex_count = 0;
	uint32_t edge_bvh_edge_count = 0;
	uint32_t edge_bvh_refits = 0;
	bool edge_bvh_ready = false;
};

static uint64_t soft_self_topology_edge_key(uint32_t p_a, uint32_t p_b) {
	return (uint64_t(MIN(p_a, p_b)) << 32) | uint64_t(MAX(p_a, p_b));
}

static bool prepare_soft_self_topology(const JPH::Array<JPH::SoftBodySharedSettings::Face> &p_faces,
		uint32_t p_vertex_count, JPH::Array<uint64_t> &r_edges, uint32_t &r_budget) {
	r_edges.clear();
	if (p_faces.empty() || p_faces.size() > MAX_SOFT_SELF_CONTACT_FACES) {
		return false;
	}
	// Conservative O(F log F) charge for collecting and sorting 3*F edges.
	const uint32_t raw_count = uint32_t(p_faces.size()) * 3;
	uint32_t levels = 0;
	for (uint32_t n = raw_count; n > 1; n = (n + 1) / 2) {
		++levels;
	}
	const uint32_t build_cost = raw_count * (levels + 1);
	if (r_budget <= build_cost) {
		return false;
	}
	r_budget -= build_cost;
	r_edges.reserve(raw_count);
	for (const JPH::SoftBodySharedSettings::Face &face : p_faces) {
		const uint32_t a = face.mVertex[0];
		const uint32_t b = face.mVertex[1];
		const uint32_t c = face.mVertex[2];
		if (face.IsDegenerate() || a >= p_vertex_count || b >= p_vertex_count || c >= p_vertex_count) {
			continue;
		}
		r_edges.push_back(soft_self_topology_edge_key(a, b));
		r_edges.push_back(soft_self_topology_edge_key(b, c));
		r_edges.push_back(soft_self_topology_edge_key(c, a));
	}
	std::sort(r_edges.begin(), r_edges.end());
	r_edges.resize(size_t(std::unique(r_edges.begin(), r_edges.end()) - r_edges.begin()));
	return !r_edges.empty();
}

// Jolt's shared soft-body settings are immutable at runtime. The pointer
// identity of the face array and the vertex/face counts are therefore a
// safe topology generation key for the lifetime of one Jolt BodyID. When
// the body is rebuilt, remove_object() destroys its per-body cache.
static bool ensure_soft_self_topology(const JPH::Array<JPH::SoftBodySharedSettings::Face> &p_faces,
		uint32_t p_vertex_count, SoftSelfContactScratch &r_scratch,
		uint32_t &r_budget, bool p_persistent) {
	if (r_budget == 0) {
		return false;
	}
	if (p_persistent && !r_scratch.one_ring_edges.empty() &&
			r_scratch.topology_faces == &p_faces &&
			r_scratch.topology_face_count == p_faces.size() &&
			r_scratch.topology_vertex_count == p_vertex_count) {
		--r_budget; // Account for constant-time topology validation.
		return true;
	}
	if (!p_persistent && !r_scratch.one_ring_edges.empty()) {
		return true; // Same-step reuse between VF and EE as before.
	}

	// A changed topology invalidates both the adjacency and the edge
	// tree's leaf-index mapping before any query can access it.
	r_scratch.edge_bvh_ready = false;
	r_scratch.edge_bvh_edge_count = 0;
	r_scratch.edge_bvh_refits = 0;
	r_scratch.topology_faces = nullptr;
	const bool valid = prepare_soft_self_topology(p_faces, p_vertex_count, r_scratch.one_ring_edges, r_budget);
	if (valid && p_persistent) {
		r_scratch.topology_faces = &p_faces;
		r_scratch.topology_face_count = uint32_t(p_faces.size());
		r_scratch.topology_vertex_count = p_vertex_count;
	}
	return valid;
}

static bool soft_self_is_neighbor(uint32_t p_point, const JPH::SoftBodySharedSettings::Face &p_face,
		const JPH::Array<uint64_t> &p_topology_edges) {
	// Reject points on the tested face, plus the direct one-ring of any
	// face corner. This excludes adjacent faces sharing an edge or corner.
	for (uint32_t corner = 0; corner < 3; ++corner) {
		const uint32_t face_vertex = p_face.mVertex[corner];
		if (p_point == face_vertex ||
				std::binary_search(p_topology_edges.begin(), p_topology_edges.end(),
						soft_self_topology_edge_key(p_point, face_vertex))) {
			return true;
		}
	}
	return false;
}

static void resolve_soft_body_self_contacts(JPH::Body &p_body, const JoltSoftBody3D &p_object,
		float p_step, uint32_t &r_budget, SoftSelfContactScratch &r_scratch) {
	JPH::SoftBodyMotionProperties &props = static_cast<JPH::SoftBodyMotionProperties &>(*p_body.GetMotionPropertiesUnchecked());
	JPH::Array<JPH::SoftBodyVertex> &vertices = props.GetVertices();
	const JPH::Array<JPH::SoftBodySharedSettings::Face> &faces = props.GetFaces();
	const uint32_t particle_count = MIN(p_object.get_surface_particle_count(), uint32_t(vertices.size()));
	if (particle_count == 0 || faces.empty() || faces.size() > MAX_SOFT_SELF_CONTACT_FACES || r_budget == 0) {
		return;
	}

	if (!ensure_soft_self_topology(faces, uint32_t(vertices.size()), r_scratch, r_budget,
			JoltProjectSettings::soft_body_self_persistent_bvh)) {
		return;
	}
	r_scratch.bvh.clear();
	// Use the existing bounding-volume hierarchy on the same body's
	// *local* deforming triangles. For tiny cloths brute force is cheaper.
	// Large bodies are skipped if the BVH would exhaust the work budget.
	const bool needs_bvh = faces.size() >= MIN_SOFT_FACE_BVH_FACES;
	const bool use_bvh = needs_bvh && prepare_soft_face_bvh(faces, vertices, JPH::Quat::sIdentity(),
			JPH::Vec3::sZero(), r_scratch.bvh.entries, r_scratch.bvh.nodes, r_budget);
	if (needs_bvh && !use_bvh) {
		return;
	}
	if (use_bvh) {
		r_scratch.bvh.candidates.reserve(r_scratch.bvh.entries.size());
		r_scratch.bvh.stack.reserve(32);
	}

	const float radius = JoltProjectSettings::soft_body_soft_contact_radius;
	const float radius_sq = radius * radius;
	const float bias_per_step = JoltProjectSettings::soft_body_soft_contact_recovery / p_step;
	const float friction = JoltProjectSettings::soft_body_soft_contact_friction;
	for (uint32_t i = 0; i < particle_count && r_budget > 0; ++i) {
		JPH::SoftBodyVertex &point = vertices[i];
		const JPH::Vec3 point_position = point.mPosition;
		if (use_bvh) {
			query_soft_face_bvh(r_scratch.bvh.entries, r_scratch.bvh.nodes, point_position,
					radius, r_budget, r_scratch.bvh.candidates, r_scratch.bvh.stack);
		}
		const uint32_t candidate_count = use_bvh ? uint32_t(r_scratch.bvh.candidates.size()) : uint32_t(faces.size());
		for (uint32_t j = 0; j < candidate_count && r_budget > 0; ++j) {
			--r_budget; // Count all candidate checks, including adjacent faces.
			const JPH::SoftBodySharedSettings::Face &face = faces[use_bvh ? r_scratch.bvh.candidates[j] : j];
			const uint32_t id0 = face.mVertex[0], id1 = face.mVertex[1], id2 = face.mVertex[2];
			if (face.IsDegenerate() || id0 >= vertices.size() || id1 >= vertices.size() || id2 >= vertices.size() ||
					soft_self_is_neighbor(i, face, r_scratch.one_ring_edges)) {
				continue;
			}
			JPH::SoftBodyVertex &a = vertices[id0];
			JPH::SoftBodyVertex &b = vertices[id1];
			JPH::SoftBodyVertex &c = vertices[id2];
			const JPH::Vec3 min_bound = JPH::Vec3::sMin(a.mPosition, JPH::Vec3::sMin(b.mPosition, c.mPosition));
			const JPH::Vec3 max_bound = JPH::Vec3::sMax(a.mPosition, JPH::Vec3::sMax(b.mPosition, c.mPosition));
			if (!soft_face_aabb_overlaps_point(min_bound, max_bound, point_position, radius)) {
				continue;
			}
			float u = 0.0f, v = 0.0f, w = 0.0f;
			JPH::Vec3 nearest = JPH::Vec3::sZero();
			if (!closest_soft_triangle_point(point_position, a.mPosition, b.mPosition, c.mPosition, nearest, u, v, w)) {
				continue;
			}
			const JPH::Vec3 diff = point_position - nearest;
			const float distance_sq = diff.LengthSq();
			if (!Math::is_finite(distance_sq) || distance_sq >= radius_sq) {
				continue;
			}
			const float inverse_mass_sum = point.mInvMass + u * u * a.mInvMass + v * v * b.mInvMass + w * w * c.mInvMass;
			if (!Math::is_finite(inverse_mass_sum) || inverse_mass_sum <= 0.0f) {
				continue;
			}
			const JPH::Vec3 face_velocity = u * a.mVelocity + v * b.mVelocity + w * c.mVelocity;
			const JPH::Vec3 relative_velocity = point.mVelocity - face_velocity;
			const float distance = Math::sqrt(MAX(distance_sq, 0.0f));
			JPH::Vec3 normal = distance > 1.0e-6f ? diff / distance : (b.mPosition - a.mPosition).Cross(c.mPosition - a.mPosition).Normalized();
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
			const JPH::Vec3 tangential = relative_velocity - normal * normal_speed;
			const float tangent_speed_sq = tangential.LengthSq();
			if (friction > 0.0f && Math::is_finite(tangent_speed_sq) && tangent_speed_sq > 1.0e-12f) {
				const float tangent_speed = Math::sqrt(tangent_speed_sq);
				const float tangential_impulse = MIN(tangent_speed / inverse_mass_sum, friction * normal_impulse);
				impulse -= tangential * (tangential_impulse / tangent_speed);
			}
			point.mVelocity += impulse * point.mInvMass;
			a.mVelocity -= impulse * (u * a.mInvMass);
			b.mVelocity -= impulse * (v * b.mInvMass);
			c.mVelocity -= impulse * (w * c.mInvMass);
		}
	}
}

// Skip coincident and one-ring-connected edges. Both segment endpoints
// belong to the same deforming soft-body mesh, so adjacent edges must not
// push against the springs which constrain their shared cloth surface.
static bool soft_self_edges_are_neighbors(uint64_t p_a, uint64_t p_b, const JPH::Array<uint64_t> &p_topology) {
	const uint32_t a0 = uint32_t(p_a >> 32), a1 = uint32_t(p_a);
	const uint32_t b0 = uint32_t(p_b >> 32), b1 = uint32_t(p_b);
	if (a0 == b0 || a0 == b1 || a1 == b0 || a1 == b1) {
		return true;
	}
	const uint32_t endpoints_a[2] = { a0, a1 };
	const uint32_t endpoints_b[2] = { b0, b1 };
	for (const uint32_t a : endpoints_a) {
		for (const uint32_t b : endpoints_b) {
			if (std::binary_search(p_topology.begin(), p_topology.end(), soft_self_topology_edge_key(a, b))) {
				return true;
			}
		}
	}
	return false;
}

// Self-edge BVH reuses the established median-split face BVH node/entry
// storage: entry.face_index is the *original self-edge key index* here.
// The tree is rebuilt from current local-space segment AABBs, because a
// soft-body's vertices deform at every step. This is a broadphase only:
// exact segment distances and topology exclusions remain unchanged.
constexpr uint32_t MIN_SOFT_SELF_EDGE_BVH_EDGES = 32;
constexpr uint32_t MAX_SOFT_SELF_EDGE_BVH_EDGES = 3072;

static bool prepare_soft_self_edge_bvh(const JPH::Array<uint64_t> &p_edges,
		const JPH::Array<JPH::SoftBodyVertex> &p_vertices, SoftFaceBVHScratch &r_bvh, uint32_t &r_budget) {
	r_bvh.clear();
	const uint32_t edge_count = uint32_t(p_edges.size());
	if (edge_count < MIN_SOFT_SELF_EDGE_BVH_EDGES || edge_count > MAX_SOFT_SELF_EDGE_BVH_EDGES) {
		return false;
	}
	// Median partition scans every level and the bounds pass scans each
	// segment. Charge a conservative O(E log E) work cost in advance.
	uint32_t levels = 0;
	for (uint32_t count = edge_count; count > 1; count = (count + 1) / 2) {
		++levels;
	}
	const uint32_t build_cost = edge_count * (levels + 2);
	if (r_budget <= build_cost) {
		return false; // Preserve at least one work unit for contact queries.
	}
	r_budget -= build_cost;
	r_bvh.entries.reserve(edge_count);
	for (uint32_t i = 0; i < edge_count; ++i) {
		const uint64_t edge = p_edges[i];
		const uint32_t a = uint32_t(edge >> 32), b = uint32_t(edge);
		if (a >= p_vertices.size() || b >= p_vertices.size() || a == b) {
			continue;
		}
		const JPH::Vec3 p0 = p_vertices[a].mPosition;
		const JPH::Vec3 p1 = p_vertices[b].mPosition;
		const JPH::Vec3 min_bound = JPH::Vec3::sMin(p0, p1);
		const JPH::Vec3 max_bound = JPH::Vec3::sMax(p0, p1);
		if (!Math::is_finite(min_bound.GetX()) || !Math::is_finite(min_bound.GetY()) || !Math::is_finite(min_bound.GetZ()) ||
				!Math::is_finite(max_bound.GetX()) || !Math::is_finite(max_bound.GetY()) || !Math::is_finite(max_bound.GetZ())) {
			continue;
		}
		SoftFaceBVHEntry entry;
		entry.min = min_bound;
		entry.max = max_bound;
		entry.face_index = i;
		r_bvh.entries.push_back(entry);
	}
	if (r_bvh.entries.empty()) {
		return false;
	}
	r_bvh.nodes.reserve(2 * r_bvh.entries.size());
	build_soft_face_bvh(r_bvh.entries, r_bvh.nodes, 0, uint32_t(r_bvh.entries.size()));
	r_bvh.candidates.reserve(r_bvh.entries.size());
	r_bvh.stack.reserve(32); // Median split: depth <= 12 for 3072 edges.
	return true;
}

// Refit in O(E + N) without modifying the median partitions or leaf
// indices. Children always follow their parent in build_soft_face_bvh(),
// so walking nodes backwards guarantees children have fresh bounds first.
// This refits *exact* AABBs: no speculative motion margin is cached.
static bool refit_soft_self_edge_bvh(const JPH::Array<uint64_t> &p_edges,
		const JPH::Array<JPH::SoftBodyVertex> &p_vertices,
		SoftFaceBVHScratch &r_bvh, uint32_t &r_budget) {
	const uint32_t entry_count = uint32_t(r_bvh.entries.size());
	const uint32_t node_count = uint32_t(r_bvh.nodes.size());
	if (entry_count == 0 || node_count == 0) {
		return false;
	}
	// Each segment is read, its leaf is combined, and each internal node
	// gets one union. Reserve enough work up front, or use linear fallback.
	const uint32_t refit_cost = 2 * entry_count + node_count;
	if (r_budget <= refit_cost) {
		return false;
	}
	r_budget -= refit_cost;
	for (SoftFaceBVHEntry &entry : r_bvh.entries) {
		if (entry.face_index >= p_edges.size()) {
			return false;
		}
		const uint64_t key = p_edges[entry.face_index];
		const uint32_t a = uint32_t(key >> 32), b = uint32_t(key);
		if (a == b || a >= p_vertices.size() || b >= p_vertices.size()) {
			return false;
		}
		const JPH::Vec3 p0 = p_vertices[a].mPosition;
		const JPH::Vec3 p1 = p_vertices[b].mPosition;
		entry.min = JPH::Vec3::sMin(p0, p1);
		entry.max = JPH::Vec3::sMax(p0, p1);
		if (!Math::is_finite(entry.min.GetX()) || !Math::is_finite(entry.min.GetY()) || !Math::is_finite(entry.min.GetZ()) ||
				!Math::is_finite(entry.max.GetX()) || !Math::is_finite(entry.max.GetY()) || !Math::is_finite(entry.max.GetZ())) {
			return false;
		}
	}
	for (uint32_t i = node_count; i > 0; --i) {
		SoftFaceBVHNode &node = r_bvh.nodes[i - 1];
		if (node.end <= node.begin || node.end > entry_count) {
			return false;
		}
		if (node.end - node.begin <= SOFT_FACE_BVH_LEAF_SIZE) {
			node.min = r_bvh.entries[node.begin].min;
			node.max = r_bvh.entries[node.begin].max;
			for (uint32_t j = node.begin + 1; j < node.end; ++j) {
				node.min = JPH::Vec3::sMin(node.min, r_bvh.entries[j].min);
				node.max = JPH::Vec3::sMax(node.max, r_bvh.entries[j].max);
			}
		} else {
			if (node.left <= i - 1 || node.right <= i - 1 ||
					node.left >= node_count || node.right >= node_count) {
				return false;
			}
			node.min = JPH::Vec3::sMin(r_bvh.nodes[node.left].min, r_bvh.nodes[node.right].min);
			node.max = JPH::Vec3::sMax(r_bvh.nodes[node.left].max, r_bvh.nodes[node.right].max);
		}
	}
	return true;
}

static bool soft_self_edge_bounds_overlap(JPH::Vec3Arg p_min_a, JPH::Vec3Arg p_max_a,
		JPH::Vec3Arg p_min_b, JPH::Vec3Arg p_max_b, float p_radius) {
	return p_max_a.GetX() + p_radius >= p_min_b.GetX() && p_max_b.GetX() + p_radius >= p_min_a.GetX() &&
			p_max_a.GetY() + p_radius >= p_min_b.GetY() && p_max_b.GetY() + p_radius >= p_min_a.GetY() &&
			p_max_a.GetZ() + p_radius >= p_min_b.GetZ() && p_max_b.GetZ() + p_radius >= p_min_a.GetZ();
}

static void query_soft_self_edge_bvh(JPH::Vec3Arg p_min, JPH::Vec3Arg p_max, float p_radius,
		SoftFaceBVHScratch &r_bvh, uint32_t &r_budget) {
	r_bvh.candidates.clear();
	r_bvh.stack.clear();
	r_bvh.stack.push_back(0);
	while (!r_bvh.stack.empty() && r_budget > 0) {
		const uint32_t node_index = r_bvh.stack.back();
		r_bvh.stack.pop_back();
		--r_budget; // Every visited node consumes the global EE work quota.
		const SoftFaceBVHNode &node = r_bvh.nodes[node_index];
		if (!soft_self_edge_bounds_overlap(p_min, p_max, node.min, node.max, p_radius)) {
			continue;
		}
		if (node.end - node.begin <= SOFT_FACE_BVH_LEAF_SIZE) {
			for (uint32_t i = node.begin; i < node.end; ++i) {
				const SoftFaceBVHEntry &entry = r_bvh.entries[i];
				if (soft_self_edge_bounds_overlap(p_min, p_max, entry.min, entry.max, p_radius)) {
					r_bvh.candidates.push_back(entry.face_index);
				}
			}
		} else {
			r_bvh.stack.push_back(node.right);
			r_bvh.stack.push_back(node.left);
		}
	}
}

// Supplement vertex-face self contacts with segment-segment impulses.
// A single body does not have a pair of COM transforms, so all positions,
// velocities, and impulse corrections stay in its local coordinate frame.
static void resolve_soft_body_self_edge_contacts(JPH::Body &p_body, const JoltSoftBody3D &p_object,
		float p_step, uint32_t &r_budget, SoftSelfContactScratch &r_scratch) {
	JPH::SoftBodyMotionProperties &props = static_cast<JPH::SoftBodyMotionProperties &>(*p_body.GetMotionPropertiesUnchecked());
	JPH::Array<JPH::SoftBodyVertex> &vertices = props.GetVertices();
	const JPH::Array<JPH::SoftBodySharedSettings::Face> &faces = props.GetFaces();
	if (faces.empty() || faces.size() > MAX_SOFT_SELF_CONTACT_FACES || r_budget == 0 || p_object.get_surface_particle_count() == 0) {
		return;
	}

	// Persistent mode reuses immutable mesh topology across physics frames;
	// the default linear/BVH modes still share the list within this step.
	if (!ensure_soft_self_topology(faces, uint32_t(vertices.size()), r_scratch, r_budget,
			JoltProjectSettings::soft_body_self_persistent_bvh)) {
		return;
	}
	const JPH::Array<uint64_t> &edges = r_scratch.one_ring_edges;
	const uint32_t edge_count = uint32_t(edges.size());
	if (edge_count < 2) {
		return;
	}

	const float radius = JoltProjectSettings::soft_body_soft_contact_radius;
	const float radius_sq = radius * radius;
	const float recovery = JoltProjectSettings::soft_body_soft_contact_recovery / p_step;
	const float friction = JoltProjectSettings::soft_body_soft_contact_friction;
	bool use_edge_bvh = false;
	if (JoltProjectSettings::soft_body_self_edge_bvh) {
		const bool persistent = JoltProjectSettings::soft_body_self_persistent_bvh;
		// Refit stable leaf-to-edge mappings, but rebuild periodically to
		// restore BVH quality after extensive folding/unfolding.
		if (persistent && r_scratch.edge_bvh_ready &&
				r_scratch.edge_bvh_edge_count == edge_count && r_scratch.edge_bvh_refits < 120) {
			use_edge_bvh = refit_soft_self_edge_bvh(edges, vertices, r_scratch.edge_bvh, r_budget);
			if (use_edge_bvh) {
				++r_scratch.edge_bvh_refits;
			}
		}
		if (!use_edge_bvh) {
			use_edge_bvh = prepare_soft_self_edge_bvh(edges, vertices, r_scratch.edge_bvh, r_budget);
			if (use_edge_bvh) {
				r_scratch.edge_bvh_refits = 0;
			}
		}
		if (persistent) {
			r_scratch.edge_bvh_ready = use_edge_bvh;
			r_scratch.edge_bvh_edge_count = use_edge_bvh ? edge_count : 0;
		}
	}

	// Query each unordered pair once: avoids doubling impulses on the
	// very same self-contact. Topological exclusion also skips edges
	// connected through a one-ring vertex even if they share no endpoint.
	for (uint32_t i = 0; i + 1 < edge_count && r_budget > 0; ++i) {
		const uint64_t key_a = edges[i];
		JPH::SoftBodyVertex &a0 = vertices[uint32_t(key_a >> 32)];
		JPH::SoftBodyVertex &a1 = vertices[uint32_t(key_a)];
		const JPH::Vec3 p0 = a0.mPosition;
		const JPH::Vec3 p1 = a1.mPosition;
		const JPH::Vec3 p_min = JPH::Vec3::sMin(p0, p1);
		const JPH::Vec3 p_max = JPH::Vec3::sMax(p0, p1);
		if (use_edge_bvh) {
			query_soft_self_edge_bvh(p_min, p_max, radius, r_scratch.edge_bvh, r_budget);
		}
		const uint32_t candidate_count = use_edge_bvh ? uint32_t(r_scratch.edge_bvh.candidates.size()) : edge_count;
		for (uint32_t candidate = 0; candidate < candidate_count && r_budget > 0; ++candidate) {
			// The tree permutes entries, but preserves each original
			// edge index. Retain j > i to evaluate unordered pairs once.
			const uint32_t j = use_edge_bvh ? r_scratch.edge_bvh.candidates[candidate] : candidate;
			if (j <= i) {
				continue;
			}
			--r_budget; // Every tested candidate, including topology rejects.
			const uint64_t key_b = edges[j];
			if (soft_self_edges_are_neighbors(key_a, key_b, edges)) {
				continue;
			}
			JPH::SoftBodyVertex &b0 = vertices[uint32_t(key_b >> 32)];
			JPH::SoftBodyVertex &b1 = vertices[uint32_t(key_b)];
			const JPH::Vec3 q0 = b0.mPosition;
			const JPH::Vec3 q1 = b1.mPosition;
			const JPH::Vec3 q_min = JPH::Vec3::sMin(q0, q1);
			const JPH::Vec3 q_max = JPH::Vec3::sMax(q0, q1);
			if (!soft_self_edge_bounds_overlap(p_min, p_max, q_min, q_max, radius)) {
				continue;
			}

			float s = 0.0f, t = 0.0f;
			JPH::Vec3 near_a = JPH::Vec3::sZero(), near_b = JPH::Vec3::sZero();
			if (!closest_soft_edge_edge(p0, p1, q0, q1, s, t, near_a, near_b)) {
				continue;
			}
			const JPH::Vec3 diff = near_b - near_a;
			const float distance_sq = diff.LengthSq();
			if (!Math::is_finite(distance_sq) || distance_sq >= radius_sq) {
				continue;
			}

			const float wa0 = 1.0f - s, wa1 = s, wb0 = 1.0f - t, wb1 = t;
			const float inverse_mass_sum = wa0 * wa0 * a0.mInvMass + wa1 * wa1 * a1.mInvMass +
					wb0 * wb0 * b0.mInvMass + wb1 * wb1 * b1.mInvMass;
			if (!Math::is_finite(inverse_mass_sum) || inverse_mass_sum <= 0.0f) {
				continue;
			}
			const JPH::Vec3 relative_velocity = wb0 * b0.mVelocity + wb1 * b1.mVelocity -
					wa0 * a0.mVelocity - wa1 * a1.mVelocity;
			const float distance = Math::sqrt(MAX(distance_sq, 0.0f));
			JPH::Vec3 normal;
			if (distance > 1.0e-6f) {
				normal = diff / distance;
			} else {
				const JPH::Vec3 cross_normal = (p1 - p0).Cross(q1 - q0);
				const float cross_sq = cross_normal.LengthSq();
				if (!Math::is_finite(cross_sq) || cross_sq <= SOFT_EDGE_EPSILON) {
					// Collinear coincidence has no stable separating normal.
					// Its endpoints/face contacts are handled elsewhere.
					continue;
				}
				normal = cross_normal / Math::sqrt(cross_sq);
				// Exact crossings have an ambiguous orientation; choose the
				// sign opposing current approach when moving.
				if (normal.Dot(relative_velocity) > 0.0f) {
					normal = -normal;
				}
			}

			const float normal_speed = relative_velocity.Dot(normal);
			if (!Math::is_finite(normal_speed)) {
				continue;
			}
			const float recovery_speed = MIN((radius - distance) * recovery, MAX_SOFT_SOFT_PENETRATION_BIAS);
			const float correction = MIN(MAX(recovery_speed - normal_speed, 0.0f), MAX_SOFT_SOFT_CONTACT_SPEED_CORRECTION);
			if (correction <= 0.0f) {
				continue;
			}
			const float normal_impulse = correction / inverse_mass_sum;
			if (!Math::is_finite(normal_impulse) || normal_impulse <= 0.0f) {
				continue;
			}
			JPH::Vec3 impulse = normal * normal_impulse;
			const JPH::Vec3 tangent = relative_velocity - normal * normal_speed;
			const float tangent_speed_sq = tangent.LengthSq();
			if (friction > 0.0f && Math::is_finite(tangent_speed_sq) && tangent_speed_sq > SOFT_EDGE_EPSILON) {
				const float tangent_speed = Math::sqrt(tangent_speed_sq);
				const float tangent_impulse = MIN(tangent_speed / inverse_mass_sum, friction * normal_impulse);
				impulse -= tangent * (tangent_impulse / tangent_speed);
			}
			a0.mVelocity -= impulse * (wa0 * a0.mInvMass);
			a1.mVelocity -= impulse * (wa1 * a1.mInvMass);
			b0.mVelocity += impulse * (wb0 * b0.mInvMass);
			b1.mVelocity += impulse * (wb1 * b1.mInvMass);
		}
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

// A cache belongs to one Jolt physics space, not to global project state.
// BodyID includes the generation sequence; destroyed/rebuilt bodies are
// explicitly evicted in remove_object(). Cap retained meshes to avoid a
// silently unbounded allocation for streaming or procedural scenes.
struct JoltSelfCollisionCache {
	static constexpr uint32_t MAX_RETAINED_BODIES = 64;
	std::unordered_map<uint32_t, SoftSelfContactScratch> bodies;
};

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

	// Reclaim all cached geometry as soon as this opt-in mode is disabled.
	// Cache is populated lazily, and never shared across physics spaces.
	const bool persistent_self = JoltProjectSettings::soft_body_self_contacts &&
			JoltProjectSettings::soft_body_self_edge_contacts &&
			JoltProjectSettings::soft_body_self_edge_bvh &&
			JoltProjectSettings::soft_body_self_persistent_bvh;
	if (!persistent_self && self_collision_cache != nullptr) {
		delete self_collision_cache;
		self_collision_cache = nullptr;
	}

	// Optional cloth/soft-body self collision: one-ring topology exclusion
	// prevents neighboring triangles from repelling their own mesh edges.
	// This budget is separate from inter-body soft contacts and applies
	// across all active soft bodies in this physics space per step.
	if (JoltProjectSettings::soft_body_self_contacts && active_soft_body_count > 0 &&
			JoltProjectSettings::soft_body_soft_contact_radius > 0.0f && Math::is_finite(p_step) && p_step > 0.0f) {
		uint32_t self_budget = (uint32_t)JoltProjectSettings::soft_body_self_contact_max_checks;
		const bool self_edges = JoltProjectSettings::soft_body_self_edge_contacts;
		// Keep the existing global self-contact cap unchanged: if the edge
		// pass is enabled, reserve half for VF and half for EE, so a dense
		// VF pass cannot starve edge crossings within the same cloth.
		uint32_t self_edge_budget = self_edges ? self_budget / 2 : 0;
		self_budget -= self_edge_budget;
		SoftSelfContactScratch self_scratch;
		if (persistent_self && self_collision_cache == nullptr) {
			self_collision_cache = new JoltSelfCollisionCache;
		}
		for (JPH::uint32 i = 0; i < active_soft_body_count && (self_budget > 0 || self_edge_budget > 0); ++i) {
			JPH::Body *jolt_body = lock_iface.TryGetBody(active_soft_bodies[i]);
			if (jolt_body == nullptr) {
				continue;
			}
			const JoltSoftBody3D *object = reinterpret_cast<JoltObject3D *>(jolt_body->GetUserData())->as_soft_body();
			SoftSelfContactScratch *scratch = &self_scratch;
			if (persistent_self) {
				const uint32_t id = active_soft_bodies[i].GetIndexAndSequenceNumber();
				auto existing = self_collision_cache->bodies.find(id);
				if (existing != self_collision_cache->bodies.end()) {
					scratch = &existing->second;
				} else if (self_collision_cache->bodies.size() < JoltSelfCollisionCache::MAX_RETAINED_BODIES) {
					scratch = &self_collision_cache->bodies[id];
				}
			}
			if (scratch == &self_scratch) {
				// Default and cache-overflow paths preserve old per-step
				// sharing, never reuse a different body's adjacency.
				scratch->one_ring_edges.clear();
			}
			if (self_budget > 0) {
				resolve_soft_body_self_contacts(*jolt_body, *object, p_step, self_budget, *scratch);
			}
			if (self_edges && self_edge_budget > 0) {
				resolve_soft_body_self_edge_contacts(*jolt_body, *object, p_step, self_edge_budget, *scratch);
			}
		}
	}

	// Jolt's native soft-body collision path only handles rigid bodies. The
	// CPU approximation runs before Jolt's parallel physics Update(), which
	// makes mutable particle velocities safe to access here.
	// Zero overhead (one branch) when disabled.
	if (JoltProjectSettings::soft_body_soft_contacts && active_soft_body_count > 1 &&
			JoltProjectSettings::soft_body_soft_contact_radius > 0.0f && Math::is_finite(p_step) && p_step > 0.0f) {
		uint32_t particle_budget = (uint32_t)JoltProjectSettings::soft_body_soft_contact_max_particle_pairs;
		// Edge contacts share the *same* user work cap, but have their own
		// reserved portion so dense VF work cannot starve edge crossings.
		const bool edge_contacts = JoltProjectSettings::soft_body_soft_vertex_face_contacts &&
				JoltProjectSettings::soft_body_soft_edge_edge_contacts;
		uint32_t edge_budget = edge_contacts ? particle_budget / 2 : 0;
		particle_budget -= edge_budget;
		uint32_t checked_body_pairs = 0;
		SoftFaceBVHScratch bvh_scratch; // No allocations when disabled.
		SoftEdgeContactScratch edge_scratch; // Reused for every tested body pair.
		const float radius = JoltProjectSettings::soft_body_soft_contact_radius;
		// Expand broadphase only for the opt-in swept VF approximation:
		// otherwise separated bodies never reach its narrowphase.
		const float broadphase_margin = radius +
				((JoltProjectSettings::soft_body_soft_vertex_face_contacts &&
				  JoltProjectSettings::soft_body_soft_speculative_ccd) ||
				 (edge_contacts && JoltProjectSettings::soft_body_soft_speculative_edge_ccd) ?
				 JoltProjectSettings::soft_body_soft_ccd_max_sweep : 0.0f);

		for (JPH::uint32 i = 0; i < active_soft_body_count && (particle_budget > 0 || edge_budget > 0) && checked_body_pairs < MAX_SOFT_SOFT_BODY_PAIR_CHECKS; ++i) {
			JPH::Body *jolt_a = lock_iface.TryGetBody(active_soft_bodies[i]);
			if (jolt_a == nullptr) {
				continue;
			}
			JoltSoftBody3D *object_a = reinterpret_cast<JoltObject3D *>(jolt_a->GetUserData())->as_soft_body();
			const AABB bounds_a = object_a->get_bounds().grow(broadphase_margin);
			for (JPH::uint32 j = i + 1; j < active_soft_body_count && (particle_budget > 0 || edge_budget > 0) && checked_body_pairs < MAX_SOFT_SOFT_BODY_PAIR_CHECKS; ++j) {
				++checked_body_pairs;
				JPH::Body *jolt_b = lock_iface.TryGetBody(active_soft_bodies[j]);
				if (jolt_b == nullptr) {
					continue;
				}
				JoltSoftBody3D *object_b = reinterpret_cast<JoltObject3D *>(jolt_b->GetUserData())->as_soft_body();
				if (!object_a->can_interact_with(*object_b) || !bounds_a.intersects(object_b->get_bounds().grow(broadphase_margin))) {
					continue;
				}
				if (particle_budget > 0) {
					if (JoltProjectSettings::soft_body_soft_vertex_face_contacts) {
						resolve_soft_soft_vertex_face_contacts(*jolt_a, *jolt_b, *object_a, *object_b, p_step, particle_budget, bvh_scratch);
					} else {
						resolve_soft_soft_particle_contacts(*jolt_a, *jolt_b, *object_a, *object_b, p_step, particle_budget);
					}
				}
				if (edge_contacts && edge_budget > 0) {
					resolve_soft_soft_edge_edge_contacts(*jolt_a, *jolt_b, p_step, edge_budget, edge_scratch);
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
	delete self_collision_cache;
	self_collision_cache = nullptr;

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
	// Invalidate the cached leaf-index map before body destruction/reuse.
	if (self_collision_cache != nullptr) {
		self_collision_cache->bodies.erase(p_jolt_id.GetIndexAndSequenceNumber());
	}
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
