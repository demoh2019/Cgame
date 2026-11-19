/**************************************************************************/
/*  jolt_soft_body_3d.cpp                                                 */
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

#include "jolt_soft_body_3d.h"

#include "../jolt_project_settings.h"
#include "../misc/jolt_type_conversions.h"
#include "../spaces/jolt_broad_phase_layer.h"
#include "../spaces/jolt_space_3d.h"
#include "jolt_area_3d.h"
#include "jolt_body_3d.h"
#include "jolt_group_filter.h"

#include "core/config/engine.h"
#include "core/templates/a_hash_map.h"
#include "servers/physics_3d/physics_server_3d_rendering_server_handler.h"
#include "servers/rendering/rendering_server.h"

#include <Jolt/Physics/SoftBody/SoftBodyMotionProperties.h>

#include <cfloat>

namespace {

// An opt-in tetrahedral fan for CLOSED CONVEX soft meshes. The fan adds an
// interior particle, with one Jolt XPBD volume constraint per surface face.
// It cannot describe concave geometry; reject unclosed, inconsistent or
// nonconvex meshes rather than silently creating inverted tetrahedra.
static bool try_build_convex_volume_fan(JPH::SoftBodySharedSettings &r_settings, float p_compliance) {
	JPH::Array<JPH::SoftBodySharedSettings::Vertex> &vertices = r_settings.mVertices;
	const JPH::Array<JPH::SoftBodySharedSettings::Face> &faces = r_settings.mFaces;

	// Bound the O(vertices * faces) convexity validation and fan solver cost.
	constexpr uint32_t MAX_VERTICES = 2048;
	constexpr uint32_t MAX_FACES = 4096;
	if (vertices.size() < 4 || vertices.size() > MAX_VERTICES || faces.size() < 4 || faces.size() > MAX_FACES) {
		return false;
	}

	double x_sum = 0.0;
	double y_sum = 0.0;
	double z_sum = 0.0;
	for (const JPH::SoftBodySharedSettings::Vertex &vertex : vertices) {
		const JPH::Float3 &p = vertex.mPosition;
		if (!Math::is_finite(p.x) || !Math::is_finite(p.y) || !Math::is_finite(p.z)) {
			return false;
		}
		x_sum += p.x;
		y_sum += p.y;
		z_sum += p.z;
	}

	const float inv_count = 1.0f / (float)vertices.size();
	const JPH::Vec3 center((float)(x_sum * inv_count), (float)(y_sum * inv_count), (float)(z_sum * inv_count));
	float max_radius_sq = 0.0f;
	for (const JPH::SoftBodySharedSettings::Vertex &vertex : vertices) {
		max_radius_sq = MAX(max_radius_sq, (JPH::Vec3(vertex.mPosition) - center).LengthSq());
	}
	if (!Math::is_finite(max_radius_sq) || max_radius_sq <= 0.0f) {
		return false;
	}

	// Each undirected edge must occur exactly twice, with opposite winding.
	// 1/-1 means an unmatched oriented edge, 0 is a completed pair.
	AHashMap<uint64_t, int8_t> edges;
	edges.reserve(uint32_t(faces.size()) * 3 / 2 + 1);
	const float radius = Math::sqrt(max_radius_sq);
	for (const JPH::SoftBodySharedSettings::Face &face : faces) {
		const uint32_t a = face.mVertex[0];
		const uint32_t b = face.mVertex[1];
		const uint32_t c = face.mVertex[2];
		if (a >= vertices.size() || b >= vertices.size() || c >= vertices.size() || face.IsDegenerate()) {
			return false;
		}
		const JPH::Vec3 p0(vertices[a].mPosition);
		const JPH::Vec3 p1(vertices[b].mPosition);
		const JPH::Vec3 p2(vertices[c].mPosition);
		const JPH::Vec3 normal = (p1 - p0).Cross(p2 - p0);
		const float normal_len_sq = normal.LengthSq();
		if (!Math::is_finite(normal_len_sq) || normal_len_sq <= max_radius_sq * max_radius_sq * 1.0e-12f) {
			return false;
		}
		const float tolerance = Math::sqrt(normal_len_sq) * radius * 1.0e-5f;
		const float center_side = normal.Dot(center - p0);
		if (!Math::is_finite(center_side) || Math::abs(center_side) <= tolerance) {
			return false;
		}
		const float side = center_side > 0.0f ? 1.0f : -1.0f;
		// Every other vertex must lie on the center-facing side of this
		// triangle plane. This rejects nonconvex or inverted mesh regions.
		for (const JPH::SoftBodySharedSettings::Vertex &vertex : vertices) {
			if (side * normal.Dot(JPH::Vec3(vertex.mPosition) - p0) < -tolerance) {
				return false;
			}
		}

		const uint32_t indices[3] = { a, b, c };
		for (int i = 0; i < 3; ++i) {
			const uint32_t v0 = indices[i];
			const uint32_t v1 = indices[(i + 1) % 3];
			const uint64_t key = (uint64_t(MIN(v0, v1)) << 32) | MAX(v0, v1);
			const int8_t direction = v0 < v1 ? 1 : -1;
			int8_t *state = edges.getptr(key);
			if (state == nullptr) {
				edges.insert(key, direction);
			} else if (*state == -direction) {
				*state = 0;
			} else {
				return false; // Repeated/same-direction or non-manifold edge.
			}
		}
	}

	for (const JPH::SoftBodySharedSettings::Face &face : faces) {
		for (int i = 0; i < 3; ++i) {
			const uint32_t v0 = face.mVertex[i];
			const uint32_t v1 = face.mVertex[(i + 1) % 3];
			const uint64_t key = (uint64_t(MIN(v0, v1)) << 32) | MAX(v0, v1);
			const int8_t *state = edges.getptr(key);
			if (state == nullptr || *state != 0) {
				return false; // Boundary edge: the surface is open.
			}
		}
	}

	// Keep the interior vertex out of the surface face list and render map.
	// The interior particle MUST exist before CreateConstraints(): that API
	// caches mClosestKinematic when LRA is enabled. Appending a vertex after
	// that cache is built would leave its size stale during Optimize().
	// The center is not part of any surface face/edge, so LRA leaves it free.
	const uint32_t center_index = (uint32_t)vertices.size();
	vertices.emplace_back(JPH::Float3(center.GetX(), center.GetY(), center.GetZ()), JPH::Float3(0.0f, 0.0f, 0.0f), 1.0f);
	r_settings.mVolumeConstraints.reserve(faces.size());
	for (const JPH::SoftBodySharedSettings::Face &face : faces) {
		const JPH::Vec3 p0(vertices[face.mVertex[0]].mPosition);
		const JPH::Vec3 p1(vertices[face.mVertex[1]].mPosition);
		const JPH::Vec3 p2(vertices[face.mVertex[2]].mPosition);
		const float signed_six_volume = (p1 - p0).Cross(p2 - p0).Dot(center - p0);
		// Jolt's volume solver uses |six_volume| for the constraint but
		// the signed-volume gradients for the correction. Keep every rest
		// tetrahedron positively oriented, irrespective of surface winding,
		// so compression/restoration acts in the physically correct direction.
		if (signed_six_volume > 0.0f) {
			r_settings.mVolumeConstraints.emplace_back(face.mVertex[0], face.mVertex[1], face.mVertex[2], center_index, p_compliance);
		} else {
			r_settings.mVolumeConstraints.emplace_back(face.mVertex[0], face.mVertex[2], face.mVertex[1], center_index, p_compliance);
		}
	}
	r_settings.CalculateVolumeConstraintVolumes();
	return true;
}

// Add these edges AFTER CreateConstraints (which clears surface edges) and
// AFTER the surface shrink operation, but BEFORE Optimize(). The centroid
// and validated convex fan were created before CreateConstraints, keeping
// the Jolt closest-kinematic cache sized for all the physics particles.
//
// Optional directional compliance allows a lightweight, mesh-local
// approximation of anisotropic radial elasticity. It is not FEM.
static void append_volume_radial_springs(JPH::SoftBodySharedSettings &r_settings, float p_compliance, int p_anisotropy_axis, float p_anisotropy_ratio) {
	JPH::Array<JPH::SoftBodySharedSettings::Vertex> &vertices = r_settings.mVertices;
	const uint32_t center_index = (uint32_t)vertices.size() - 1;
	const JPH::Vec3 center(vertices[center_index].mPosition);

	float max_distance_sq = 0.0f;
	for (uint32_t i = 0; i < center_index; ++i) {
		const float distance_sq = (JPH::Vec3(vertices[i].mPosition) - center).LengthSq();
		max_distance_sq = MAX(max_distance_sq, distance_sq);
	}
	if (max_distance_sq <= 0.0f) {
		return;
	}

	const float min_distance_sq = max_distance_sq * 1.0e-12f;
	r_settings.mEdgeConstraints.reserve(r_settings.mEdgeConstraints.size() + center_index);
	for (uint32_t i = 0; i < center_index; ++i) {
		const JPH::Vec3 offset = JPH::Vec3(vertices[i].mPosition) - center;
		const float distance_sq = offset.LengthSq();
		if (distance_sq <= min_distance_sq) {
			continue;
		}

		float compliance = p_compliance;
		if (p_anisotropy_axis != 0 && p_anisotropy_ratio != 1.0f) {
			const float axis_displacement = p_anisotropy_axis == 1 ? offset.GetX() : (p_anisotropy_axis == 2 ? offset.GetY() : offset.GetZ());
			const float alignment_sq = (axis_displacement * axis_displacement) / distance_sq;
			compliance *= 1.0f + (p_anisotropy_ratio - 1.0f) * alignment_sq;
		}
		JPH::SoftBodySharedSettings::Edge radial(center_index, i, compliance);
		radial.mRestLength = Math::sqrt(distance_sq);
		r_settings.mEdgeConstraints.push_back(radial);
	}
}

template <typename TJoltVertex>
void pin_vertices(const JoltSoftBody3D &p_body, const HashSet<int> &p_pinned_vertices, const LocalVector<int> &p_mesh_to_physics, JPH::Array<TJoltVertex> &r_physics_vertices) {
	const int mesh_vertex_count = p_mesh_to_physics.size();
	const int physics_vertex_count = (int)r_physics_vertices.size();

	for (int mesh_index : p_pinned_vertices) {
		ERR_CONTINUE_MSG(mesh_index < 0 || mesh_index >= mesh_vertex_count, vformat("Index %d of pinned vertex in soft body '%s' is out of bounds. There are only %d vertices in the current mesh.", mesh_index, p_body.to_string(), mesh_vertex_count));

		const int physics_index = p_mesh_to_physics[mesh_index];
		ERR_CONTINUE_MSG(physics_index < 0 || physics_index >= physics_vertex_count, vformat("Index %d of pinned vertex in soft body '%s' is out of bounds. There are only %d vertices in the current mesh. This should not happen. Please report this.", physics_index, p_body.to_string(), physics_vertex_count));

		r_physics_vertices[physics_index].mInvMass = 0.0f;
	}
}

} // namespace

JPH::BroadPhaseLayer JoltSoftBody3D::_get_broad_phase_layer() const {
	return JoltBroadPhaseLayer::BODY_DYNAMIC;
}

JPH::ObjectLayer JoltSoftBody3D::_get_object_layer() const {
	ERR_FAIL_NULL_V(space, 0);

	return space->map_to_object_layer(_get_broad_phase_layer(), collision_layer, collision_mask);
}

void JoltSoftBody3D::_space_changing() {
	JoltObject3D::_space_changing();

	if (in_space()) {
		jolt_settings = new JPH::SoftBodyCreationSettings(jolt_body->GetSoftBodyCreationSettings());
		jolt_settings->mSettings = nullptr;
		jolt_settings->mVertexRadius = JoltProjectSettings::soft_body_point_radius;
	}
}

void JoltSoftBody3D::_space_changed() {
	JoltObject3D::_space_changed();

	_update_mass();
	_update_pressure();
	_update_damping();
	_update_simulation_precision();
	_update_group_filter();
}

void JoltSoftBody3D::_add_to_space() {
	if (unlikely(space == nullptr || !mesh.is_valid())) {
		return;
	}

	JPH::SoftBodySharedSettings *shared_settings = _create_shared_settings();
	ERR_FAIL_NULL(shared_settings);

	JPH::CollisionGroup::GroupID group_id = 0;
	JPH::CollisionGroup::SubGroupID sub_group_id = 0;
	JoltGroupFilter::encode_object(this, group_id, sub_group_id);

	jolt_settings->mSettings = shared_settings;
	jolt_settings->mUserData = reinterpret_cast<JPH::uint64>(this);
	jolt_settings->mObjectLayer = _get_object_layer();
	jolt_settings->mCollisionGroup = JPH::CollisionGroup(nullptr, group_id, sub_group_id);
	jolt_settings->mMaxLinearVelocity = JoltProjectSettings::max_linear_velocity;

	JPH::Body *new_jolt_body = space->add_object(*this, *jolt_settings);
	if (new_jolt_body == nullptr) {
		return;
	}

	jolt_body = new_jolt_body;

	delete jolt_settings;
	jolt_settings = nullptr;
}

JPH::SoftBodySharedSettings *JoltSoftBody3D::_create_shared_settings() {
	RenderingServer *rendering = RenderingServer::get_singleton();

	// TODO: calling RenderingServer::mesh_surface_get_arrays() from the physics thread
	// is not safe and can deadlock when physics/3d/run_on_separate_thread is enabled.
	// This method blocks on the main thread to return data, but the main thread may be
	// blocked waiting on us in PhysicsServer3D::sync().
	const Array mesh_data = rendering->mesh_surface_get_arrays(mesh, 0);
	ERR_FAIL_COND_V(mesh_data.is_empty(), nullptr);

	const PackedInt32Array mesh_indices = mesh_data[RSE::ARRAY_INDEX];
	ERR_FAIL_COND_V(mesh_indices.is_empty(), nullptr);

	const PackedVector3Array mesh_vertices = mesh_data[RSE::ARRAY_VERTEX];
	ERR_FAIL_COND_V(mesh_vertices.is_empty(), nullptr);

	// Validate mesh topology before allocating Jolt settings. Invalid indices
	// must not reach mesh_to_physics or the Jolt constraint generator.
	// A truncated final triangle would also read past mesh_indices.
	const int mesh_index_count = mesh_indices.size();
	const int mesh_vertex_count = mesh_vertices.size();
	ERR_FAIL_COND_V_MSG(mesh_index_count % 3 != 0, nullptr, "Soft body mesh index count must be a multiple of three.");
	for (int mesh_index : mesh_indices) {
		ERR_FAIL_COND_V_MSG(mesh_index < 0 || mesh_index >= mesh_vertex_count, nullptr, "Soft body mesh contains an out-of-range vertex index.");
	}

	JPH::SoftBodySharedSettings *settings = new JPH::SoftBodySharedSettings();
	JPH::Array<JPH::SoftBodySharedSettings::Vertex> &physics_vertices = settings->mVertices;
	JPH::Array<JPH::SoftBodySharedSettings::Face> &physics_faces = settings->mFaces;

	// Position deduplication is only needed for the first use of each mesh
	// vertex index. AHashMap avoids node allocations for large cloth meshes.
	AHashMap<Vector3, int> vertex_to_physics;

	mesh_to_physics.resize(mesh_vertex_count);
	for (int &index : mesh_to_physics) {
		index = -1;
	}
	physics_vertices.reserve(mesh_vertex_count);
	// The map has a ~75% load factor. Reserve enough slots for the upper
	// bound of unique referenced vertices to avoid growing mid-conversion.
	const uint32_t max_referenced_vertices = MIN(uint32_t(mesh_vertex_count), uint32_t(mesh_index_count));
	vertex_to_physics.reserve(max_referenced_vertices + max_referenced_vertices / 2 + 1);

	int physics_index_count = 0;

	const JPH::RVec3 body_position = jolt_settings->mPosition;

	for (int i = 0; i < mesh_index_count; i += 3) {
		int physics_face[3];

		for (int j = 0; j < 3; ++j) {
			const int mesh_index = mesh_indices[i + j];
			int physics_index = mesh_to_physics[mesh_index];

			// Triangle indices repeatedly reference the same mesh vertex.
			// Bypass the position hash entirely after its first occurrence.
			if (physics_index == -1) {
				const Vector3 vertex = mesh_vertices[mesh_index];
				const int *existing_index = vertex_to_physics.getptr(vertex);
				if (existing_index != nullptr) {
					// Distinct mesh indices can still refer to the same position.
					physics_index = *existing_index;
				} else {
					physics_index = physics_index_count++;
					physics_vertices.emplace_back(JPH::Float3((float)(vertex.x - body_position.GetX()), (float)(vertex.y - body_position.GetY()), (float)(vertex.z - body_position.GetZ())), JPH::Float3(0.0f, 0.0f, 0.0f), 1.0f);
					vertex_to_physics.insert(vertex, physics_index);
				}
				mesh_to_physics[mesh_index] = physics_index;
			}

			physics_face[j] = physics_index;
		}

		if (physics_face[0] == physics_face[1] || physics_face[0] == physics_face[2] || physics_face[1] == physics_face[2]) {
			continue; // We skip degenerate faces, since they're problematic, and Jolt will assert about it anyway.
		}

		// Jolt uses a different winding order, so we swap the indices to account for that.
		physics_faces.emplace_back((JPH::uint32)physics_face[2], (JPH::uint32)physics_face[1], (JPH::uint32)physics_face[0]);
	}

	// Only vertices created from referenced surface faces are eligible for
	// soft-soft particle contacts: the optional tetrahedral center is internal.
	surface_particle_count = (uint32_t)physics_vertices.size();

	// Pin whatever pinned vertices we have currently. This is used during the `Optimize` call below to order the
	// constraints. Note that it's fine if the pinned vertices change later, but that will reduce the effectiveness
	// of the constraints a bit.
	pin_vertices(*this, pinned_vertices, mesh_to_physics, physics_vertices);

	// Populate the complete particle array BEFORE Jolt constructs the LRA
	// closest-kinematic cache and before computing XPBD mass/compliance.
	// Rejected convex meshes retain their original particle topology.
	bool has_convex_volume = false;
	if (JoltProjectSettings::soft_body_volume_preservation) {
		has_convex_volume = try_build_convex_volume_fan(*settings, JoltProjectSettings::soft_body_volume_compliance);
	}

	// Since Godot's stiffness is input as a coefficient between 0 and 1, and Jolt uses actual stiffness for its
	// edge constraints, we must map one to the other.
	//
	// Godot uses classic PBD edge constraints, which have a stiffness parameter k that is used in the position correction formula as follows:
	// delta_x1 = -k * w1 / (w1 + w2) * (l - l0) / l * (x2 - x1)
	// where k is the stiffness, w1 and w2 are the inverse masses of the two vertices, l is the current length of the edge = |x2 - x1|, l0 is the rest length of the edge, and x1 and x2 are the vertex positions.
	//
	// Note that the actual formula used in Godot physics seems to use an approximation of this which avoids calculating the square root:
	// delta_x1 = -k * w1 / (w1 + w2) * (l^2 - l0^2) / (l^2 + l0^2) * (x2 - x1)
	//
	// Jolt uses XPBD which goes as follows:
	// delta_x1 = -w1 / (w1 + w2 + compliance / dt^2) * (l - l0) / l * (x2 - x1)
	// where compliance is the inverse of stiffness and dt is the timestep.
	//
	// We can derive Jolt's compliance from Godot's stiffness by evaluating:
	// k * w1 / (w1 + w2) = w1 / (w1 + w2 + compliance / dt^2)
	// which simplifies to:
	// compliance = dt^2 * (1 / k - 1) * (w1 + w2)

	// Assuming that the vertices have the same mass. The validated convex
	// volume fan (when enabled) has already added its interior particle.
	// Use double here as
	// a tiny but positive mass can overflow the float intermediate.
	const double w1_plus_w2 = 2.0 * double(physics_vertices.size()) / double(mass);

	// Calculate time step of a single XPBD iteration
	const float dt = 1.0f / Engine::get_singleton()->get_user_physics_ticks_per_second() / simulation_precision;

	// Jolt uses FLT_MAX to disable an edge constraint. At zero stiffness,
	// calculating 1 / k would produce infinity (and potentially NaNs in the
	// constraint solver). Saturate in double precision for very small k.
	const double inverse_stiffness_unbounded = double(dt) * double(dt) *
			(1.0 / double(MAX(stiffness_coefficient, FLT_MIN)) - 1.0) * w1_plus_w2;
	const float inverse_stiffness = stiffness_coefficient <= 0.0f ?
			FLT_MAX : float(MIN(inverse_stiffness_unbounded, double(FLT_MAX)));

	JPH::SoftBodySharedSettings::VertexAttributes vertex_attrib;
	vertex_attrib.mCompliance = vertex_attrib.mShearCompliance = inverse_stiffness;

	// Jolt supports distance- and dihedral-based XPBD bending. Keep disabled
	// by default for backward compatibility; enable through project settings.
	vertex_attrib.mBendCompliance = JoltProjectSettings::soft_body_bend_compliance;

	// Long-range attachment constraints keep pinned cloth from stretching
	// excessively under gravity. Generate them only when requested AND at
	// least one *valid* pinned physics vertex exists. The default remains
	// zero-cost; invalid or unused mesh pin indices cannot become anchors.
	if (JoltProjectSettings::soft_body_lra_mode != 0) {
		bool has_kinematic_vertex = false;
		for (const JPH::SoftBodySharedSettings::Vertex &vertex : physics_vertices) {
			if (vertex.mInvMass == 0.0f) {
				has_kinematic_vertex = true;
				break;
			}
		}
		if (has_kinematic_vertex) {
			using LRAType = JPH::SoftBodySharedSettings::ELRAType;
			vertex_attrib.mLRAType = JoltProjectSettings::soft_body_lra_mode == 1 ? LRAType::EuclideanDistance : LRAType::GeodesicDistance;
			vertex_attrib.mLRAMaxDistanceMultiplier = JoltProjectSettings::soft_body_lra_max_distance_multiplier;
		}
	}

	using BendType = JPH::SoftBodySharedSettings::EBendType;
	const int bend_mode = JoltProjectSettings::soft_body_bend_mode;
	const BendType bend_type = bend_mode == 1 ? BendType::Distance : (bend_mode == 2 ? BendType::Dihedral : BendType::None);
	settings->CreateConstraints(&vertex_attrib, 1, bend_type);
	// Optional warp/weft response of woven cloth. Jolt stores compliance
	// per structural spring; use the rest-pose edge direction rather than a
	// world-space direction so rotating the soft body doesn't change its
	// material. 1.0 is isotropic and skips this entire construction pass.
	// The convex fan's radial springs are added *later*, so they retain
	// their independent volumetric compliance.
	const float fiber_multiplier = JoltProjectSettings::soft_body_fiber_compliance_multiplier;
	if (fiber_multiplier != 1.0f) {
		const int fiber_axis = JoltProjectSettings::soft_body_fiber_axis;
		for (JPH::SoftBodySharedSettings::Edge &edge : settings->mEdgeConstraints) {
			// FLT_MAX disables an edge in Jolt. Don't reactivate it, and
			// don't modify rigid (zero-compliance) springs.
			if (edge.mCompliance <= 0.0f || edge.mCompliance >= FLT_MAX || !Math::is_finite(edge.mCompliance)) {
				continue;
			}

			const JPH::Float3 &a = settings->mVertices[edge.mVertex[0]].mPosition;
			const JPH::Float3 &b = settings->mVertices[edge.mVertex[1]].mPosition;
			const double dx = double(b.x) - double(a.x);
			const double dy = double(b.y) - double(a.y);
			const double dz = double(b.z) - double(a.z);
			const double length_sq = dx * dx + dy * dy + dz * dz;
			if (length_sq <= 0.0 || !Math::is_finite(length_sq)) {
				continue;
			}

			const double parallel = fiber_axis == 0 ? dx : (fiber_axis == 1 ? dy : dz);
			const double alignment_sq = parallel * parallel / length_sq;
			const double compliance_scale = 1.0 + (double(fiber_multiplier) - 1.0) * alignment_sq;
			const double adjusted = double(edge.mCompliance) * compliance_scale;
			if (Math::is_finite(adjusted)) {
				edge.mCompliance = float(MIN(adjusted, double(FLT_MAX)));
			}
		}
	}

	const float multiplier = 1.0f - shrinking_factor;
	for (JPH::SoftBodySharedSettings::Edge &e : settings->mEdgeConstraints) {
		e.mRestLength *= multiplier;
	}
	// Long-range tethers also encode rest lengths. If cloth contracts
	// without scaling the tether limits, they allow the old unshrunken
	// anchor distance and defeat part of the contraction. Negative
	// shrinking_factor expands both kinds of constraint consistently.
	// Skip this pass entirely for the common shrinking_factor == 0.
	if (multiplier != 1.0f) {
		for (JPH::SoftBodySharedSettings::LRA &tether : settings->mLRAConstraints) {
			tether.mMaxDistance *= multiplier;
		}
	}
	// A compressible volumetric material has a rest-volume factor s^3
	// when its edge rest lengths scale by s. Keep the old incompressible
	// target by default; the convex fan must have been constructed first.
	const bool follow_volume_shrink = has_convex_volume &&
			JoltProjectSettings::soft_body_volume_follow_shrinking_factor &&
			multiplier > 0.0f && multiplier != 1.0f;
	if (follow_volume_shrink) {
		const double scale = double(multiplier);
		const double volume_scale = scale * scale * scale;
		if (Math::is_finite(volume_scale)) {
			for (JPH::SoftBodySharedSettings::Volume &volume : settings->mVolumeConstraints) {
				const double target = double(volume.mSixRestVolume) * volume_scale;
				volume.mSixRestVolume = float(CLAMP(target, -double(FLT_MAX), double(FLT_MAX)));
			}
		}
	}

	// The radial springs are a separate volumetric material, added AFTER
	// textile fiber compliance and LRA constraint creation.
	if (has_convex_volume && JoltProjectSettings::soft_body_volume_radial_springs) {
		const uint32_t surface_edge_count = (uint32_t)settings->mEdgeConstraints.size();
		append_volume_radial_springs(*settings, JoltProjectSettings::soft_body_volume_radial_compliance,
				JoltProjectSettings::soft_body_radial_anisotropy_axis, JoltProjectSettings::soft_body_radial_anisotropy_ratio);
		if (follow_volume_shrink) {
			const double scale = double(multiplier);
			for (uint32_t i = surface_edge_count; i < settings->mEdgeConstraints.size(); ++i) {
				JPH::SoftBodySharedSettings::Edge &radial = settings->mEdgeConstraints[i];
				const double target = double(radial.mRestLength) * scale;
				if (Math::is_finite(target)) {
					radial.mRestLength = float(MIN(target, double(FLT_MAX)));
				}
			}
		}
	}
	settings->Optimize();

	return settings;
}

void JoltSoftBody3D::_apply_environmental_forces(float p_step) {
	// Get approximation of the center of the soft body.
	Vector3 com_position = to_godot(jolt_body->GetCenterOfMassPosition());

	// Calculate gravity and which areas affect the soft body through wind.
	bool gravity_done = false;
	bool has_distance_attenuation = false;
	Vector3 gravity;
	wind_areas_scratch.clear();
	for (JoltArea3D *area : areas) {
		if (!gravity_done) {
			gravity_done = JoltArea3D::apply_override(gravity, area->get_gravity_mode(), [&]() {
				return area->compute_gravity(com_position);
			});
		}

		if (area->get_wind_pressure() > CMP_EPSILON) {
			wind_areas_scratch.push_back(area);
			has_distance_attenuation |= area->get_wind_attenuation_factor() != 0.0f;
		}
	}

	// Add default gravity.
	if (!gravity_done) {
		gravity += space->get_default_area()->compute_gravity(com_position);
	}

	// Apply gravity to soft body. Note that this only works so long as vertices have uniform mass (excluding pinned vertices).
	jolt_body->AddForce(to_jolt(gravity) * mass);

	// Aerodynamic drag needs the same triangle traversal as wind, but must
	// also work in still air without any Area3D. Zero drag stays on the wind-only fast path.
	if (!wind_areas_scratch.is_empty() || drag_coefficient > 0.0f) {
		JPH::SoftBodyMotionProperties &motion_properties = static_cast<JPH::SoftBodyMotionProperties &>(*jolt_body->GetMotionPropertiesUnchecked());
		JPH::Array<JPH::SoftBodyVertex> &physics_vertices = motion_properties.GetVertices();

		for (const JPH::SoftBodySharedSettings::Face &physics_face : motion_properties.GetFaces()) {
			JPH::SoftBodyVertex &physics_vertex0 = physics_vertices[physics_face.mVertex[0]];
			JPH::SoftBodyVertex &physics_vertex1 = physics_vertices[physics_face.mVertex[1]];
			JPH::SoftBodyVertex &physics_vertex2 = physics_vertices[physics_face.mVertex[2]];

			// Calculate the triangle centroid.
			Vector3 v0 = to_godot(physics_vertex0.mPosition);
			Vector3 v1 = to_godot(physics_vertex1.mPosition);
			Vector3 v2 = to_godot(physics_vertex2.mPosition);
			Vector3 centroid;
			if (has_distance_attenuation) {
				centroid = com_position + (v0 + v1 + v2) * real_t(1.0 / 3.0);
			}

			// Calculate the triangle normal.
			Vector3 normal = (v2 - v0).cross(v1 - v0);
			real_t normal_length = normal.length();
			if (normal_length > real_t(1.0e-6)) { // If the normal is near zero, the area is near zero so we can skip this triangle.
				normal /= normal_length;

				// Area is half the length of the cross product of two sides.
				real_t triangle_area = real_t(0.5) * normal_length;

				// Accumulate wind forces from all wind areas.
				Vector3 wind_force;
				for (const JoltArea3D *area : wind_areas_scratch) {
					const Vector3 &wind_direction = area->get_wind_direction();
					const float attenuation_factor = area->get_wind_attenuation_factor();
					real_t attenuation_over_distance = real_t(1.0);
					if (attenuation_factor != 0.0f) {
						const Vector3 &wind_source = area->get_wind_source();
						// The projection remains >= 1 to avoid amplifying wind near its source.
						const real_t projection_toward_centroid = MAX((centroid - wind_source).dot(wind_direction), real_t(1.0));
						attenuation_over_distance = Math::pow(projection_toward_centroid, -real_t(attenuation_factor));
					}

					// Calculate force magnitude.
					real_t force_magnitude = area->get_wind_pressure() * triangle_area;

					// Calculate the resulting wind force on the triangle by projecting wind direction onto triangle normal.
					// Divide by 3 to distribute force equally over each vertex.
					wind_force += (force_magnitude * attenuation_over_distance * real_t(1.0 / 3.0) * normal.dot(wind_direction)) * normal;
				}

				// Force and impulse are per vertex (one third of each face force).
				Vector3 impulse_per_vertex = wind_force * p_step;
				if (drag_coefficient > 0.0f) {
					// Two-sided quadratic aerodynamic drag projected onto the
					// current triangle normal. This works even without wind.
					const Vector3 average_velocity = (to_godot(physics_vertex0.mVelocity) +
								to_godot(physics_vertex1.mVelocity) + to_godot(physics_vertex2.mVelocity)) * real_t(1.0 / 3.0);
					const real_t normal_speed = normal.dot(average_velocity);
					const real_t inverse_mass_sum = physics_vertex0.mInvMass + physics_vertex1.mInvMass + physics_vertex2.mInvMass;
					if (normal_speed != 0.0f && inverse_mass_sum > 0.0f) {
						// Clamp to prevent a large timestep, speed or coefficient
						// from reversing the face's average normal velocity.
						// Double precision avoids overflow in intermediate products.
						const double normal_speed_d = double(normal_speed);
						const double impulse_magnitude = MIN(
								double(drag_coefficient) * double(triangle_area) * (1.0 / 6.0) *
										normal_speed_d * normal_speed_d * double(p_step),
								3.0 * Math::abs(normal_speed_d) / double(inverse_mass_sum));
						impulse_per_vertex -= normal * real_t((normal_speed > 0.0f ? 1.0 : -1.0) * impulse_magnitude);
					}
				}

				// Apply the combined wind and drag impulse to each free vertex.
				JPH::Vec3 impulse = to_jolt(impulse_per_vertex);
				physics_vertex0.mVelocity += impulse * physics_vertex0.mInvMass;
				physics_vertex1.mVelocity += impulse * physics_vertex1.mInvMass;
				physics_vertex2.mVelocity += impulse * physics_vertex2.mInvMass;
			}
		}
	}

	// Reuse capacity under steady wind; trim the scratch after a large burst.
	// Clear pointers before another frame can remove the referenced areas.
	constexpr uint32_t MIN_CACHED_WIND_AREAS = 64;
	const uint32_t wind_count = wind_areas_scratch.size();
	const uint32_t retained_capacity = MAX(MIN_CACHED_WIND_AREAS,
			wind_count > UINT32_MAX / 4 ? UINT32_MAX : wind_count * 4);
	if (wind_areas_scratch.get_capacity() > retained_capacity) {
		wind_areas_scratch.reset();
	} else {
		wind_areas_scratch.clear();
	}
}

void JoltSoftBody3D::_update_mass() {
	if (!in_space()) {
		return;
	}

	JPH::SoftBodyMotionProperties &motion_properties = static_cast<JPH::SoftBodyMotionProperties &>(*jolt_body->GetMotionPropertiesUnchecked());
	JPH::Array<JPH::SoftBodyVertex> &physics_vertices = motion_properties.GetVertices();

	const float inverse_vertex_mass = (float)physics_vertices.size() / mass;

	for (JPH::SoftBodyVertex &vertex : physics_vertices) {
		vertex.mInvMass = inverse_vertex_mass;
	}

	pin_vertices(*this, pinned_vertices, mesh_to_physics, physics_vertices);
}

void JoltSoftBody3D::_update_pressure() {
	if (!in_space()) {
		jolt_settings->mPressure = pressure;
		return;
	}

	JPH::SoftBodyMotionProperties &motion_properties = static_cast<JPH::SoftBodyMotionProperties &>(*jolt_body->GetMotionPropertiesUnchecked());
	motion_properties.SetPressure(pressure);
}

void JoltSoftBody3D::_update_damping() {
	if (!in_space()) {
		jolt_settings->mLinearDamping = linear_damping;
		return;
	}

	JPH::SoftBodyMotionProperties &motion_properties = static_cast<JPH::SoftBodyMotionProperties &>(*jolt_body->GetMotionPropertiesUnchecked());
	motion_properties.SetLinearDamping(linear_damping);
}

void JoltSoftBody3D::_update_simulation_precision() {
	if (!in_space()) {
		jolt_settings->mNumIterations = (JPH::uint32)simulation_precision;
		return;
	}

	JPH::SoftBodyMotionProperties &motion_properties = static_cast<JPH::SoftBodyMotionProperties &>(*jolt_body->GetMotionPropertiesUnchecked());
	motion_properties.SetNumIterations((JPH::uint32)simulation_precision);
}

void JoltSoftBody3D::_update_group_filter() {
	JPH::GroupFilter *group_filter = !exceptions.is_empty() ? JoltGroupFilter::instance : nullptr;

	if (!in_space()) {
		jolt_settings->mCollisionGroup.SetGroupFilter(group_filter);
	} else {
		jolt_body->GetCollisionGroup().SetGroupFilter(group_filter);
	}
}

void JoltSoftBody3D::_try_rebuild() {
	if (space != nullptr) {
		_reset_space();
	}
}

void JoltSoftBody3D::_mesh_changed() {
	_try_rebuild();
}

void JoltSoftBody3D::_simulation_precision_changed() {
	wake_up();
}

void JoltSoftBody3D::_mass_changed() {
	_update_mass();
	wake_up();
}

void JoltSoftBody3D::_pressure_changed() {
	_update_pressure();
	wake_up();
}

void JoltSoftBody3D::_damping_changed() {
	_update_damping();
	wake_up();
}

void JoltSoftBody3D::_pins_changed() {
	_update_mass();
	wake_up();
}

void JoltSoftBody3D::_vertices_changed() {
	wake_up();
}

void JoltSoftBody3D::_exceptions_changed() {
	_update_group_filter();
}

void JoltSoftBody3D::_motion_changed() {
	wake_up();
}

void JoltSoftBody3D::_transform_changed() {
	wake_up();
}

void JoltSoftBody3D::_areas_changed() {
	wake_up();
}

JoltSoftBody3D::JoltSoftBody3D() :
		JoltObject3D(OBJECT_TYPE_SOFT_BODY) {
	jolt_settings->mRestitution = 0.0f;
	jolt_settings->mFriction = 1.0f;
	jolt_settings->mUpdatePosition = true;
	jolt_settings->mMakeRotationIdentity = false;
}

JoltSoftBody3D::~JoltSoftBody3D() {
	if (jolt_settings != nullptr) {
		delete jolt_settings;
		jolt_settings = nullptr;
	}
}

void JoltSoftBody3D::add_collision_exception(const RID &p_excepted_body) {
	exceptions.push_back(p_excepted_body);

	_exceptions_changed();
}

void JoltSoftBody3D::remove_collision_exception(const RID &p_excepted_body) {
	exceptions.erase(p_excepted_body);

	_exceptions_changed();
}

bool JoltSoftBody3D::has_collision_exception(const RID &p_excepted_body) const {
	return exceptions.find(p_excepted_body) >= 0;
}

void JoltSoftBody3D::add_area(JoltArea3D *p_area) {
	int i = 0;
	for (; i < (int)areas.size(); i++) {
		if (p_area->get_priority() > areas[i]->get_priority()) {
			break;
		}
	}

	areas.insert(i, p_area);

	_areas_changed();
}

void JoltSoftBody3D::remove_area(JoltArea3D *p_area) {
	areas.erase(p_area);

	_areas_changed();
}

bool JoltSoftBody3D::can_interact_with(const JoltBody3D &p_other) const {
	return (can_collide_with(p_other) || p_other.can_collide_with(*this)) && !has_collision_exception(p_other.get_rid()) && !p_other.has_collision_exception(rid);
}

bool JoltSoftBody3D::can_interact_with(const JoltSoftBody3D &p_other) const {
	return (can_collide_with(p_other) || p_other.can_collide_with(*this)) && !has_collision_exception(p_other.get_rid()) && !p_other.has_collision_exception(rid);
}

bool JoltSoftBody3D::can_interact_with(const JoltArea3D &p_other) const {
	return p_other.can_interact_with(*this);
}

Vector3 JoltSoftBody3D::get_velocity_at_position(const Vector3 &p_position) const {
	return Vector3();
}

void JoltSoftBody3D::pre_step(float p_step) {
	_apply_environmental_forces(p_step);
}

void JoltSoftBody3D::set_mesh(const RID &p_mesh) {
	if (unlikely(mesh == p_mesh)) {
		return;
	}

	mesh = p_mesh;
	_mesh_changed();
}

bool JoltSoftBody3D::is_sleeping() const {
	if (!in_space()) {
		return false;
	} else {
		return !jolt_body->IsActive();
	}
}

void JoltSoftBody3D::apply_vertex_impulse(int p_index, const Vector3 &p_impulse) {
	ERR_FAIL_COND_MSG(!in_space(), vformat("Failed to apply impulse to '%s'. Doing so without a physics space is not supported when using Jolt Physics. If this relates to a node, try adding the node to a scene tree first.", to_string()));

	ERR_FAIL_INDEX(p_index, (int)mesh_to_physics.size());
	const int physics_index = mesh_to_physics[p_index];
	ERR_FAIL_COND_MSG(physics_index < 0, vformat("Soft body vertex %d was not used by a face and has been omitted for '%s'. No impulse can be applied.", p_index, to_string()));
	JPH::SoftBodyMotionProperties &motion_properties = static_cast<JPH::SoftBodyMotionProperties &>(*jolt_body->GetMotionPropertiesUnchecked());

	JPH::Array<JPH::SoftBodyVertex> &physics_vertices = motion_properties.GetVertices();
	JPH::SoftBodyVertex &physics_vertex = physics_vertices[physics_index];
	// Visual mesh indices can alias the same physical particle. Check its
	// actual inverse mass rather than treating a mesh index as a physics index.
	ERR_FAIL_COND_MSG(physics_vertex.mInvMass <= 0.0f, vformat("Failed to apply impulse to pinned point %d for '%s'.", p_index, to_string()));

	physics_vertex.mVelocity += to_jolt(p_impulse) * physics_vertex.mInvMass;

	_motion_changed();
}

void JoltSoftBody3D::apply_vertex_force(int p_index, const Vector3 &p_force) {
	ERR_FAIL_COND_MSG(!in_space(), vformat("Failed to apply force to '%s'. Doing so without a physics space is not supported when using Jolt Physics. If this relates to a node, try adding the node to a scene tree first.", to_string()));

	apply_vertex_impulse(p_index, p_force * space->get_last_step());
}

void JoltSoftBody3D::apply_central_impulse(const Vector3 &p_impulse) {
	ERR_FAIL_COND_MSG(!in_space(), vformat("Failed to apply central impulse to '%s'. Doing so without a physics space is not supported when using Jolt Physics. If this relates to a node, try adding the node to a scene tree first.", to_string()));

	JPH::SoftBodyMotionProperties &motion_properties = static_cast<JPH::SoftBodyMotionProperties &>(*jolt_body->GetMotionPropertiesUnchecked());
	JPH::Array<JPH::SoftBodyVertex> &physics_vertices = motion_properties.GetVertices();

	const JPH::Vec3 impulse = to_jolt(p_impulse) / physics_vertices.size();

	for (JPH::SoftBodyVertex &physics_vertex : physics_vertices) {
		if (physics_vertex.mInvMass > 0.0f) {
			physics_vertex.mVelocity += impulse * physics_vertex.mInvMass;
		}
	}

	_motion_changed();
}

void JoltSoftBody3D::apply_central_force(const Vector3 &p_force) {
	ERR_FAIL_COND_MSG(!in_space(), vformat("Failed to apply central force to '%s'. Doing so without a physics space is not supported when using Jolt Physics. If this relates to a node, try adding the node to a scene tree first.", to_string()));

	jolt_body->AddForce(to_jolt(p_force));

	_motion_changed();
}

void JoltSoftBody3D::set_is_sleeping(bool p_enabled) {
	if (!in_space()) {
		return;
	}

	space->set_is_object_sleeping(jolt_body->GetID(), p_enabled);
}

bool JoltSoftBody3D::is_sleep_allowed() const {
	if (!in_space()) {
		return jolt_settings->mAllowSleeping;
	} else {
		return jolt_body->GetAllowSleeping();
	}
}

void JoltSoftBody3D::set_is_sleep_allowed(bool p_enabled) {
	if (!in_space()) {
		jolt_settings->mAllowSleeping = p_enabled;
	} else {
		jolt_body->SetAllowSleeping(p_enabled);
	}
}

void JoltSoftBody3D::set_simulation_precision(int p_precision) {
	// XPBD computes a per-iteration timestep by dividing by this number.
	// Zero iterations would create a non-finite compliance at mesh creation.
	const int precision = MAX(p_precision, 1);
	if (unlikely(simulation_precision == precision)) {
		return;
	}

	simulation_precision = precision;

	_simulation_precision_changed();
}

void JoltSoftBody3D::set_mass(float p_mass) {
	ERR_FAIL_COND(p_mass <= 0.0f || !Math::is_finite(p_mass)); // Avoid infinite or non-finite inverse mass.

	if (unlikely(mass == p_mass)) {
		return;
	}

	mass = p_mass;

	_mass_changed();
}

float JoltSoftBody3D::get_stiffness_coefficient() const {
	return stiffness_coefficient;
}

void JoltSoftBody3D::set_stiffness_coefficient(float p_coefficient) {
	ERR_FAIL_COND(!Math::is_finite(p_coefficient));
	stiffness_coefficient = CLAMP(p_coefficient, 0.0f, 1.0f);
}

float JoltSoftBody3D::get_shrinking_factor() const {
	return shrinking_factor;
}

void JoltSoftBody3D::set_shrinking_factor(float p_shrinking_factor) {
	shrinking_factor = p_shrinking_factor;
}

void JoltSoftBody3D::set_pressure(float p_pressure) {
	if (unlikely(pressure == p_pressure)) {
		return;
	}

	pressure = MAX(p_pressure, 0.0f);

	_pressure_changed();
}

void JoltSoftBody3D::set_linear_damping(float p_damping) {
	if (unlikely(linear_damping == p_damping)) {
		return;
	}

	linear_damping = MAX(p_damping, 0.0f);

	_damping_changed();
}

float JoltSoftBody3D::get_drag() const {
	return drag_coefficient;
}

void JoltSoftBody3D::set_drag(float p_drag) {
	ERR_FAIL_COND_MSG(p_drag < 0.0f || !Math::is_finite(p_drag), "Soft body drag must be nonnegative and finite.");
	drag_coefficient = p_drag;
}

Variant JoltSoftBody3D::get_state(PS3DE::BodyState p_state) const {
	switch (p_state) {
		case PS3DE::BODY_STATE_TRANSFORM: {
			return get_transform();
		}
		case PS3DE::BODY_STATE_LINEAR_VELOCITY: {
			ERR_FAIL_V_MSG(Variant(), "Linear velocity is not supported for soft bodies.");
		}
		case PS3DE::BODY_STATE_ANGULAR_VELOCITY: {
			ERR_FAIL_V_MSG(Variant(), "Angular velocity is not supported for soft bodies.");
		}
		case PS3DE::BODY_STATE_SLEEPING: {
			return is_sleeping();
		}
		case PS3DE::BODY_STATE_CAN_SLEEP: {
			return is_sleep_allowed();
		}
		default: {
			ERR_FAIL_V_MSG(Variant(), vformat("Unhandled body state: '%d'. This should not happen. Please report this.", p_state));
		}
	}
}

void JoltSoftBody3D::set_state(PS3DE::BodyState p_state, const Variant &p_value) {
	switch (p_state) {
		case PS3DE::BODY_STATE_TRANSFORM: {
			set_transform(p_value);
		} break;
		case PS3DE::BODY_STATE_LINEAR_VELOCITY: {
			ERR_FAIL_MSG("Linear velocity is not supported for soft bodies.");
		} break;
		case PS3DE::BODY_STATE_ANGULAR_VELOCITY: {
			ERR_FAIL_MSG("Angular velocity is not supported for soft bodies.");
		} break;
		case PS3DE::BODY_STATE_SLEEPING: {
			set_is_sleeping(p_value);
		} break;
		case PS3DE::BODY_STATE_CAN_SLEEP: {
			set_is_sleep_allowed(p_value);
		} break;
		default: {
			ERR_FAIL_MSG(vformat("Unhandled body state: '%d'. This should not happen. Please report this.", p_state));
		} break;
	}
}

Transform3D JoltSoftBody3D::get_transform() const {
	// Since any transform gets baked into the vertices anyway we can just return identity here.
	return Transform3D();
}

void JoltSoftBody3D::set_transform(const Transform3D &p_transform) {
	ERR_FAIL_COND_MSG(!in_space(), vformat("Failed to set transform for '%s'. Doing so without a physics space is not supported when using Jolt Physics. If this relates to a node, try adding the node to a scene tree first.", to_string()));

	// For whatever reason this has to be interpreted as a relative global-space transform rather than an absolute one,
	// because `SoftBody3D` will immediately upon entering the scene tree set itself to be top-level and also set its
	// transform to be identity, while still expecting to stay in its original position.
	//
	// We also discard any scaling, since we have no way of scaling the actual edge lengths.
	const JPH::Mat44 relative_transform = to_jolt(p_transform.orthonormalized());

	// The translation delta goes to the body's position to avoid vertices getting too far away from it.
	JPH::BodyInterface &body_iface = space->get_body_iface();
	body_iface.SetPosition(jolt_body->GetID(), jolt_body->GetPosition() + relative_transform.GetTranslation(), JPH::EActivation::DontActivate);

	// The rotation difference goes to the vertices. We also reset the velocity of these vertices.
	JPH::SoftBodyMotionProperties &motion_properties = static_cast<JPH::SoftBodyMotionProperties &>(*jolt_body->GetMotionPropertiesUnchecked());
	JPH::Array<JPH::SoftBodyVertex> &physics_vertices = motion_properties.GetVertices();

	for (JPH::SoftBodyVertex &vertex : physics_vertices) {
		vertex.mPosition = vertex.mPreviousPosition = relative_transform.Multiply3x3(vertex.mPosition);
		vertex.mVelocity = JPH::Vec3::sZero();
	}

	_transform_changed();
}

AABB JoltSoftBody3D::get_bounds() const {
	ERR_FAIL_COND_V_MSG(!in_space(), AABB(), vformat("Failed to retrieve world bounds of '%s'. Doing so without a physics space is not supported when using Jolt Physics. If this relates to a node, try adding the node to a scene tree first.", to_string()));
	return to_godot(jolt_body->GetWorldSpaceBounds());
}

void JoltSoftBody3D::update_rendering_server(PhysicsServer3DRenderingServerHandler *p_rendering_server_handler) {
	// Ideally we would emit an actual error here, but that would spam the logs to the point where the actual cause will be drowned out.
	if (unlikely(!in_space())) {
		return;
	}

	const JPH::SoftBodyMotionProperties &motion_properties = static_cast<const JPH::SoftBodyMotionProperties &>(*jolt_body->GetMotionPropertiesUnchecked());

	typedef JPH::SoftBodyMotionProperties::Vertex SoftBodyVertex;
	typedef JPH::SoftBodyMotionProperties::Face SoftBodyFace;

	const JPH::Array<SoftBodyVertex> &physics_vertices = motion_properties.GetVertices();
	const JPH::Array<SoftBodyFace> &physics_faces = motion_properties.GetFaces();

	const int physics_vertex_count = (int)physics_vertices.size();

	normals.clear();
	normals.resize(physics_vertex_count);

	// Compute vertex normals using smooth-shading:
	// Each vertex should use the average normal of all faces it is a part of.
	// Iterate over each face, and add the face normal to each of the face vertices.
	// By the end of the loop, each vertex normal will be the sum of all face normals it belongs to.
	for (const SoftBodyFace &physics_face : physics_faces) {
		// Jolt uses a different winding order, so we swap the indices to account for that.

		const uint32_t i0 = physics_face.mVertex[2];
		const uint32_t i1 = physics_face.mVertex[1];
		const uint32_t i2 = physics_face.mVertex[0];

		const Vector3 v0 = to_godot(physics_vertices[i0].mPosition);
		const Vector3 v1 = to_godot(physics_vertices[i1].mPosition);
		const Vector3 v2 = to_godot(physics_vertices[i2].mPosition);

		const Vector3 normal = (v2 - v0).cross(v1 - v0).normalized();

		normals[i0] += normal;
		normals[i1] += normal;
		normals[i2] += normal;
	}
	// Normalize the vertex normals to have length 1.0
	for (Vector3 &n : normals) {
		real_t len = n.length();
		// Some normals may have length 0 if the face was degenerate,
		// so don't divide by zero.
		if (len > CMP_EPSILON) {
			n /= len;
		}
	}

	const int mesh_vertex_count = mesh_to_physics.size();
	const JPH::RVec3 body_position = jolt_body->GetCenterOfMassPosition();

	for (int i = 0; i < mesh_vertex_count; ++i) {
		const int physics_index = mesh_to_physics[i];
		if (physics_index >= 0) {
			const Vector3 vertex = to_godot(body_position + physics_vertices[(size_t)physics_index].mPosition);
			const Vector3 normal = normals[(uint32_t)physics_index];

			p_rendering_server_handler->set_vertex(i, vertex);
			p_rendering_server_handler->set_normal(i, normal);
		}
	}

	p_rendering_server_handler->set_aabb(get_bounds());
}

Vector3 JoltSoftBody3D::get_vertex_position(int p_index) {
	ERR_FAIL_COND_V_MSG(!in_space(), Vector3(), vformat("Failed to retrieve point position for '%s'. Doing so without a physics space is not supported when using Jolt Physics. If this relates to a node, try adding the node to a scene tree first.", to_string()));

	ERR_FAIL_INDEX_V(p_index, (int)mesh_to_physics.size(), Vector3());
	const int physics_index = mesh_to_physics[p_index];
	ERR_FAIL_COND_V_MSG(physics_index < 0, Vector3(), vformat("Soft body vertex %d was not used by a face and has been omitted for '%s'. Position cannot be returned.", p_index, to_string()));

	const JPH::SoftBodyMotionProperties &motion_properties = static_cast<const JPH::SoftBodyMotionProperties &>(*jolt_body->GetMotionPropertiesUnchecked());
	const JPH::Array<JPH::SoftBodyVertex> &physics_vertices = motion_properties.GetVertices();
	const JPH::SoftBodyVertex &physics_vertex = physics_vertices[physics_index];

	return to_godot(jolt_body->GetCenterOfMassPosition() + physics_vertex.mPosition);
}

void JoltSoftBody3D::set_vertex_position(int p_index, const Vector3 &p_position) {
	ERR_FAIL_COND_MSG(!in_space(), vformat("Failed to set point position for '%s'. Doing so without a physics space is not supported when using Jolt Physics. If this relates to a node, try adding the node to a scene tree first.", to_string()));

	ERR_FAIL_INDEX(p_index, (int)mesh_to_physics.size());
	const int physics_index = mesh_to_physics[p_index];
	ERR_FAIL_COND_MSG(physics_index < 0, vformat("Soft body vertex %d was not used by a face and has been omitted for '%s'. Position cannot be set.", p_index, to_string()));

	JPH::SoftBodyMotionProperties &motion_properties = static_cast<JPH::SoftBodyMotionProperties &>(*jolt_body->GetMotionPropertiesUnchecked());
	JPH::Array<JPH::SoftBodyVertex> &physics_vertices = motion_properties.GetVertices();
	JPH::SoftBodyVertex &physics_vertex = physics_vertices[physics_index];

	const JPH::RVec3 center_of_mass = jolt_body->GetCenterOfMassPosition();
	physics_vertex.mPosition = JPH::Vec3(to_jolt_r(p_position) - center_of_mass);

	_vertices_changed();
}

void JoltSoftBody3D::pin_vertex(int p_index) {
	pinned_vertices.insert(p_index);

	_pins_changed();
}

void JoltSoftBody3D::unpin_vertex(int p_index) {
	pinned_vertices.erase(p_index);

	_pins_changed();
}

void JoltSoftBody3D::unpin_all_vertices() {
	pinned_vertices.clear();

	_pins_changed();
}

bool JoltSoftBody3D::is_vertex_pinned(int p_index) const {
	ERR_FAIL_COND_V_MSG(!in_space(), false, vformat("Failed retrieve pin status of point for '%s'. Doing so without a physics space is not supported when using Jolt Physics. If this relates to a node, try adding the node to a scene tree first.", to_string()));

	ERR_FAIL_INDEX_V(p_index, (int)mesh_to_physics.size(), false);
	const int physics_index = mesh_to_physics[p_index];
	ERR_FAIL_COND_V_MSG(physics_index < 0, false, "Cannot query an unused soft body mesh vertex.");

	// Mesh vertices may be welded: every visual alias of a pinned physical
	// particle must report the same pin status.
	const JPH::SoftBodyMotionProperties &motion_properties = static_cast<const JPH::SoftBodyMotionProperties &>(*jolt_body->GetMotionPropertiesUnchecked());
	return motion_properties.GetVertices()[physics_index].mInvMass == 0.0f;
}
