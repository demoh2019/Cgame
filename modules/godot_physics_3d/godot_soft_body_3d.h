/**************************************************************************/
/*  godot_soft_body_3d.h                                                  */
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

#pragma once

#include "godot_area_3d.h"
#include "servers/physics_xpbd_tether.h"
#include "servers/physics_softbody_shape_clusters.h"
#include "servers/physics_xpbd_membrane.h"
#include "servers/physics_fem_convex_star.h"
#include "servers/physics_xpbd_strain_limit.h"
#include "godot_collision_object_3d.h"

#include "core/math/aabb.h"
#include "core/math/dynamic_bvh.h"
#include "core/math/vector3.h"
#include "core/templates/hash_set.h"
#include "core/templates/local_vector.h"
#include "core/templates/vset.h"

class GodotConstraint3D;
class PhysicsServer3DRenderingServerHandler;

class GodotSoftBody3D : public GodotCollisionObject3D {
	RID soft_mesh;

	struct Node {
		Vector3 s; // Source position
		Vector3 x; // Position
		Vector3 q; // Previous step position/Test position
		Vector3 f; // Force accumulator
		Vector3 v; // Velocity
		Vector3 bv; // Biased Velocity
		Vector3 n; // Normal
		real_t area = 0.0; // Area
		real_t im = 0.0; // 1/mass
		DynamicBVH::ID leaf; // Leaf data
		uint32_t index = 0;
	};

	struct Link {
		Node *n[2] = { nullptr, nullptr }; // Node pointers
		real_t rl = 0.0; // Rest length
		real_t c0 = 0.0; // (ima+imb)*kLST
		real_t c1 = 0.0; // rl^2
	};

	struct Face {
		Vector3 centroid;
		Node *n[3] = { nullptr, nullptr, nullptr }; // Node pointers
		Vector3 normal; // Normal
		real_t ra = 0.0; // Rest area
		DynamicBVH::ID leaf; // Leaf data
		uint32_t index = 0;
	};

	LocalVector<Node> nodes;
	// Only allocated with experimental inter-body CCD enabled. Nodes cache
	// previous-step positions here because the solver overwrites Node::q.
	LocalVector<Vector3> pair_ccd_previous;
	AABB pair_ccd_swept_bounds;
	LocalVector<Link> links;
	// Only allocated if tethers are enabled and at least one vertex is pinned.
	LocalVector<PhysicsXPBDTether> xpbd_tethers;
	bool xpbd_tethers_dirty = true;
	// Only allocated when the experimental XPBD solver is enabled. The
	// lambda for each link is retained across iterations of the same step.
	LocalVector<real_t> xpbd_link_lambdas;
	// Optional once-per-step nonlinear compliance, zero RAM when disabled.
	LocalVector<real_t> xpbd_link_hardening_alphas;
	// Optional unilateral stretch/compression limits. Each link retains two
	// XPBD multipliers per step; the default settings allocate nothing.
	LocalVector<PhysicsXPBDStrainLimitLambdas> xpbd_strain_lambdas;
	// One compliance multiplier per triangle, allocated only in area-XPBD mode.
	LocalVector<real_t> xpbd_area_lambdas;
	// Optional per-face undeformed angle and per-step XPBD multipliers.
	// Not allocated when shear compliance is disabled.
	LocalVector<real_t> xpbd_shear_rest_cosines;
	LocalVector<double> xpbd_shear_lambdas;
	// Optional StVK surface membrane rest metrics and one XPBD lambda per face.
	// Both are absent when the membrane compliance is zero (default).
	LocalVector<PhysicsXPBDMembraneRest> xpbd_membrane_rest;
	LocalVector<double> xpbd_membrane_lambdas;
	// Hinge particles are indexed, not stored as Node pointers: rebuilding
	// the mesh cannot leave a stale pointer in the optional topology cache.
	struct DihedralHinge {
		uint32_t a = 0;
		uint32_t b = 0;
		uint32_t c = 0;
		uint32_t d = 0;
		real_t rest_angle = 0.0;
	};
	LocalVector<DihedralHinge> xpbd_dihedral_hinges;
	LocalVector<real_t> xpbd_dihedral_lambdas;
	// Optional per-particle reference offsets for meshless rigid shape fitting.
	// Zero stiffness allocates no additional per-node data.
	LocalVector<Vector3> xpbd_shape_rest_offsets;
	// Optional overlapping BFS clusters on original face edges; each node
	// can participate in multiple local rotations for non-rigid deformation.
	LocalVector<PhysicsSoftBodyShapeCluster> xpbd_shape_clusters;
	LocalVector<uint32_t> xpbd_shape_cluster_members;
	LocalVector<Vector3> xpbd_shape_cluster_rest_offsets;
	LocalVector<Vector3> xpbd_shape_cluster_displacements;
	LocalVector<uint32_t> xpbd_shape_cluster_counts;
	// Optional vertex/non-adjacent-face self contacts. Never allocate when
	// the space's self-collision thickness is zero.
	struct SelfCollisionContact {
		uint32_t vertex = 0;
		uint32_t face = 0;
		int8_t side = 1;
		real_t lambda = 0.0;
	};
	LocalVector<SelfCollisionContact> xpbd_self_contacts;
	// Allocated only in the opt-in swept vertex/face CCD path; discrete
	// self contacts retain their compact 12-byte representation.
	struct SelfCCDContact {
		uint32_t vertex = 0;
		uint32_t face = 0;
		Vector3 barycentric;
		Vector3 separating_normal;
		real_t lambda = 0.0;
	};
	LocalVector<SelfCCDContact> xpbd_self_ccd_contacts;
	HashSet<uint64_t> xpbd_self_neighbor_edges;
	// Built only with opt-in edge/edge contacts. The BVH stores pointers
	// into the fully constructed, non-resizing array of structural edges.
	struct SelfCollisionEdge {
		uint32_t a = 0;
		uint32_t b = 0;
		uint32_t index = 0;
		DynamicBVH::ID leaf;
	};
	struct SelfEdgeContact {
		uint32_t first = 0;
		uint32_t second = 0;
		Vector3 normal;
		real_t lambda = 0.0;
	};
	LocalVector<SelfCollisionEdge> xpbd_self_edges;
	LocalVector<SelfEdgeContact> xpbd_self_edge_contacts;
	DynamicBVH xpbd_self_edge_tree;
	// Separate lazy BVH for contacts with OTHER soft bodies. Mesh edits reset
	// both the topology and leaves; default-off scenes allocate no edge nodes.
	LocalVector<SelfCollisionEdge> xpbd_pair_edges;
	DynamicBVH xpbd_pair_edge_tree;
	// Lazy scratch shared by XPBD volume constraint and optional bulk viscosity.
	LocalVector<Vector3> xpbd_volume_gradients;
	double xpbd_volume_rest = 0.0; // May change via plastic creep.
	double xpbd_volume_original_rest = 0.0; // Frozen gas reference and damage baseline.
	bool xpbd_volume_closed = false;
	// Optional convex closed-shell mesh cooked into a fan of real tetrahedra.
	// Tetra rest matrices and XPBD multipliers are retained across iterations.
	// Empty unless tetra FEM compliance is explicitly enabled.
	LocalVector<PhysicsFEMConvexTetra> xpbd_fem_tetrahedra;
	// Normalized FEM rest-volume fractions; only populated with opt-in lumped mass.
	// Includes pinned nodes so unpin and mass changes restore their physical mass.
	LocalVector<double> xpbd_fem_mass_fractions;
	// Allocated only when tension-only tetra material fibers are enabled.
	// One XPBD multiplier per cooked tetra, reused across solver iterations.
	LocalVector<double> xpbd_fem_fiber_lambdas;
	LocalVector<Face> faces;
	// Number of particles with nonzero inverse mass. Maintained on pin,
	// unpin and mesh rebuild for O(1) central impulse/force normalization.
	uint32_t dynamic_node_count = 0;

	DynamicBVH node_tree;
	DynamicBVH face_tree;

	LocalVector<uint32_t> map_visual_to_physics;

	AABB bounds;

	real_t collision_margin = 0.05;

	real_t total_mass = 1.0;
	real_t inv_total_mass = 1.0;

	int iteration_count = 5;
	real_t linear_stiffness = 0.5; // [0,1]
	real_t shrinking_factor = 0.0; // [-1,1]
	real_t pressure_coefficient = 0.0; // [-inf,+inf]
	real_t damping_coefficient = 0.01; // [0,1]
	real_t drag_coefficient = 0.0; // [0,1]
	LocalVector<int> pinned_vertices;
	// Batch pin/unpin edits: update O(links) stiffness data just once before
	// the next solver pass, rather than once for every edited visual vertex.
	bool link_constants_dirty = false;

	SelfList<GodotSoftBody3D> active_list;

	HashSet<GodotConstraint3D *> constraints;

	Vector<AreaCMP> areas;

	VSet<RID> exceptions;

	uint64_t island_step = 0;

	_FORCE_INLINE_ Vector3 _compute_area_windforce(const GodotArea3D *p_area, const Face *p_face);

public:
	GodotSoftBody3D();

	const AABB &get_bounds() const { return bounds; }

	void set_state(PS3DE::BodyState p_state, const Variant &p_variant);
	Variant get_state(PS3DE::BodyState p_state) const;

	_FORCE_INLINE_ void add_constraint(GodotConstraint3D *p_constraint) { constraints.insert(p_constraint); }
	_FORCE_INLINE_ void remove_constraint(GodotConstraint3D *p_constraint) { constraints.erase(p_constraint); }
	_FORCE_INLINE_ const HashSet<GodotConstraint3D *> &get_constraints() const { return constraints; }
	_FORCE_INLINE_ void clear_constraints() { constraints.clear(); }

	_FORCE_INLINE_ void add_exception(const RID &p_exception) { exceptions.insert(p_exception); }
	_FORCE_INLINE_ void remove_exception(const RID &p_exception) { exceptions.erase(p_exception); }
	_FORCE_INLINE_ bool has_exception(const RID &p_exception) const { return exceptions.has(p_exception); }
	_FORCE_INLINE_ const VSet<RID> &get_exceptions() const { return exceptions; }

	_FORCE_INLINE_ uint64_t get_island_step() const { return island_step; }
	_FORCE_INLINE_ void set_island_step(uint64_t p_step) { island_step = p_step; }

	_FORCE_INLINE_ void add_area(GodotArea3D *p_area) {
		int index = areas.find(AreaCMP(p_area));
		if (index > -1) {
			areas.write[index].refCount += 1;
		} else {
			areas.ordered_insert(AreaCMP(p_area));
		}
	}

	_FORCE_INLINE_ void remove_area(GodotArea3D *p_area) {
		int index = areas.find(AreaCMP(p_area));
		if (index > -1) {
			areas.write[index].refCount -= 1;
			if (areas[index].refCount < 1) {
				areas.remove_at(index);
			}
		}
	}

	virtual void set_space(GodotSpace3D *p_space) override;

	void set_mesh(RID p_mesh);

	void update_rendering_server(PhysicsServer3DRenderingServerHandler *p_rendering_server_handler);

	Vector3 get_vertex_position(int p_index) const;
	void set_vertex_position(int p_index, const Vector3 &p_position);

	void pin_vertex(int p_index);
	void unpin_vertex(int p_index);
	void unpin_all_vertices();
	bool is_vertex_pinned(int p_index) const;

	uint32_t get_node_count() const;
	real_t get_node_inv_mass(uint32_t p_node_index) const;
	Vector3 get_node_position(uint32_t p_node_index) const;
	Vector3 get_node_velocity(uint32_t p_node_index) const;
	Vector3 get_node_biased_velocity(uint32_t p_node_index) const;
	void apply_node_impulse(uint32_t p_node_index, const Vector3 &p_impulse);
	void apply_node_force(uint32_t p_node_index, const Vector3 &p_force);
	void apply_central_impulse(const Vector3 &p_impulse);
	void apply_central_force(const Vector3 &p_force);
	void apply_node_bias_impulse(uint32_t p_node_index, const Vector3 &p_impulse);

	uint32_t get_face_count() const;
	void get_face_points(uint32_t p_face_index, Vector3 &r_point_1, Vector3 &r_point_2, Vector3 &r_point_3) const;
	Vector3 get_face_normal(uint32_t p_face_index) const;

	void set_iteration_count(int p_val);
	_FORCE_INLINE_ real_t get_iteration_count() const { return iteration_count; }

	void set_total_mass(real_t p_val);
	_FORCE_INLINE_ real_t get_total_mass() const { return total_mass; }
	_FORCE_INLINE_ real_t get_total_inv_mass() const { return inv_total_mass; }

	void set_collision_margin(real_t p_val);
	_FORCE_INLINE_ real_t get_collision_margin() const { return collision_margin; }

	void set_linear_stiffness(real_t p_val);
	_FORCE_INLINE_ real_t get_linear_stiffness() const { return linear_stiffness; }

	void set_shrinking_factor(real_t p_val);
	_FORCE_INLINE_ real_t get_shrinking_factor() const { return shrinking_factor; }

	void set_pressure_coefficient(real_t p_val);
	_FORCE_INLINE_ real_t get_pressure_coefficient() const { return pressure_coefficient; }

	void set_damping_coefficient(real_t p_val);
	_FORCE_INLINE_ real_t get_damping_coefficient() const { return damping_coefficient; }

	void set_drag_coefficient(real_t p_val);
	_FORCE_INLINE_ real_t get_drag_coefficient() const { return drag_coefficient; }

	void predict_motion(real_t p_delta);
	void solve_constraints(real_t p_delta);
	const AABB &get_pair_swept_bounds() const {
		return !pair_ccd_previous.is_empty() && pair_ccd_previous.size() == nodes.size() ? pair_ccd_swept_bounds : bounds;
	}
	// Two-way discrete contacts with another SoftBody3D after both bodies
	// finish their own constraints. Reuses each body's existing face BVH.
	bool solve_pair_contacts(GodotSoftBody3D &p_other, real_t p_delta,
			real_t p_thickness, real_t p_compliance, real_t p_friction,
			uint32_t p_max_contacts, uint32_t p_max_contacts_per_vertex);

	_FORCE_INLINE_ uint32_t get_node_index(void *p_node) const { return static_cast<Node *>(p_node)->index; }
	_FORCE_INLINE_ uint32_t get_face_index(void *p_face) const { return static_cast<Face *>(p_face)->index; }

	// Return true to stop the query.
	// p_index is the node index for AABB query, face index for Ray query.
	typedef bool (*QueryResultCallback)(uint32_t p_index, void *p_userdata);

	void query_aabb(const AABB &p_aabb, QueryResultCallback p_result_callback, void *p_userdata);
	void query_ray(const Vector3 &p_from, const Vector3 &p_to, QueryResultCallback p_result_callback, void *p_userdata);

protected:
	virtual void _shapes_changed() override;

private:
	void update_normals_and_centroids();
	void update_bounds();
	void update_constants();
	void update_area();
	void initialize_membrane_constraints();
	void initialize_fem_tetra();
	real_t get_unpinned_node_inverse_mass(uint32_t p_node_index) const;
	void initialize_shear_constraints();
	void initialize_dihedral_constraints();
	void initialize_shape_matching();
	void solve_shape_matching(real_t p_strength);
	void solve_shape_matching_clusters(real_t p_strength);
	void initialize_self_collision_topology();
	void solve_self_collisions(real_t p_delta);
	bool solve_edge_self_collisions(real_t p_delta);
	void initialize_pair_edge_topology(real_t p_thickness);
	void update_pair_edge_tree(real_t p_thickness, bool p_swept);
	bool solve_pair_edge_contacts(GodotSoftBody3D &p_other, real_t p_delta,
			real_t p_thickness, real_t p_alpha, uint32_t p_contact_budget);
	void initialize_volume_constraint();
	bool solve_volume_constraint(double p_alpha, double &r_lambda);
	void damp_volume_rate(double p_fraction);
	void reset_link_rest_lengths();
	void update_link_constants();
	void rebuild_xpbd_tethers(real_t p_slack);

	void apply_nodes_transform(const Transform3D &p_transform);

	void add_velocity(const Vector3 &p_velocity);

	void apply_forces(const LocalVector<GodotArea3D *> &p_wind_areas, real_t p_delta);

	bool create_from_trimesh(const Vector<int> &p_indices, const Vector<Vector3> &p_vertices);
	void generate_bending_constraints(int p_distance);
	void reoptimize_link_order();
	void append_link(uint32_t p_node1, uint32_t p_node2);
	void append_face(uint32_t p_node1, uint32_t p_node2, uint32_t p_node3);

	void solve_links(real_t kst, real_t ti);

	void initialize_face_tree();
	void update_face_tree(real_t p_delta);
	void update_swept_face_tree(real_t p_thickness);
	void update_pair_swept_face_tree(real_t p_thickness);
	void refresh_pair_ccd_swept_bounds();

	void initialize_shape(bool p_force_move = true);
	void deinitialize_shape();

	void destroy();
};

class GodotSoftBodyShape3D : public GodotShape3D {
	GodotSoftBody3D *soft_body = nullptr;

public:
	GodotSoftBody3D *get_soft_body() const { return soft_body; }

	virtual PS3DE::ShapeType get_type() const override { return PS3DE::SHAPE_SOFT_BODY; }
	virtual void project_range(const Vector3 &p_normal, const Transform3D &p_transform, real_t &r_min, real_t &r_max) const override { r_min = r_max = 0.0; }
	virtual Vector3 get_support(const Vector3 &p_normal) const override { return Vector3(); }
	virtual void get_supports(const Vector3 &p_normal, int p_max, Vector3 *r_supports, int &r_amount, FeatureType &r_type) const override { r_amount = 0; }

	virtual bool intersect_segment(const Vector3 &p_begin, const Vector3 &p_end, Vector3 &r_result, Vector3 &r_normal, int &r_face_index, bool p_hit_back_faces) const override;
	virtual bool intersect_point(const Vector3 &p_point) const override;
	virtual Vector3 get_closest_point_to(const Vector3 &p_point) const override;
	virtual Vector3 get_moment_of_inertia(real_t p_mass) const override { return Vector3(); }

	virtual void set_data(const Variant &p_data) override {}
	virtual Variant get_data() const override { return Variant(); }

	void update_bounds();

	GodotSoftBodyShape3D(GodotSoftBody3D *p_soft_body);
	~GodotSoftBodyShape3D() {}
};
