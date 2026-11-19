/**************************************************************************/
/*  test_physics_softbody_shape_clusters.cpp                              */
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
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_softbody_shape_clusters.h"
#include "servers/physics_softbody_shape_covariance.h"
#include "servers/physics_softbody_shape_matching.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_shape_clusters)

namespace TestPhysicsSoftBodyShapeClusters {

static void append_ring(LocalVector<PhysicsSoftBodyShapeEdge> &r_edges, uint32_t p_count) {
	for (uint32_t i = 0; i < p_count; ++i) {
		r_edges.push_back({ i, (i + 1) % p_count });
	}
}

TEST_CASE("[PhysicsSoftBody] Shape clusters partition BFS cores and overlap at boundaries") {
	LocalVector<PhysicsSoftBodyShapeEdge> edges;
	append_ring(edges, 8);
	LocalVector<PhysicsSoftBodyShapeCluster> clusters;
	LocalVector<uint32_t> members;
	CHECK(physics_softbody_build_shape_clusters(8, edges, 3, clusters, members));
	CHECK(clusters.size() >= 2);
	LocalVector<uint32_t> counts;
	counts.resize(8);
	for (uint32_t i = 0; i < 8; ++i) {
		counts[i] = 0;
	}
	for (const PhysicsSoftBodyShapeCluster &cluster : clusters) {
		CHECK(cluster.count >= 3);
		for (uint32_t j = cluster.first; j < cluster.first + cluster.count; ++j) {
			CHECK(members[j] < 8);
			++counts[members[j]];
		}
	}
	bool has_shared = false;
	for (uint32_t i = 0; i < 8; ++i) {
		CHECK(counts[i] >= 1);
		has_shared |= counts[i] > 1;
	}
	CHECK(has_shared);
}

TEST_CASE("[PhysicsSoftBody] Disconnected shape clusters never join unrelated components") {
	LocalVector<PhysicsSoftBodyShapeEdge> edges;
	edges.push_back({ 0, 1 }); edges.push_back({ 1, 2 }); edges.push_back({ 2, 0 });
	edges.push_back({ 3, 4 }); edges.push_back({ 4, 5 }); edges.push_back({ 5, 3 });
	LocalVector<PhysicsSoftBodyShapeCluster> clusters;
	LocalVector<uint32_t> members;
	CHECK(physics_softbody_build_shape_clusters(6, edges, 3, clusters, members));
	CHECK(clusters.size() == 2);
	for (const PhysicsSoftBodyShapeCluster &cluster : clusters) {
		const bool group = members[cluster.first] < 3;
		for (uint32_t j = cluster.first; j < cluster.first + cluster.count; ++j) {
			CHECK((members[j] < 3) == group);
		}
	}
}

TEST_CASE("[PhysicsSoftBody] Shape cluster generation is deterministic") {
	LocalVector<PhysicsSoftBodyShapeEdge> edges;
	append_ring(edges, 12);
	LocalVector<PhysicsSoftBodyShapeCluster> a, b;
	LocalVector<uint32_t> am, bm;
	CHECK(physics_softbody_build_shape_clusters(12, edges, 4, a, am));
	CHECK(physics_softbody_build_shape_clusters(12, edges, 4, b, bm));
	CHECK(a.size() == b.size());
	CHECK(am.size() == bm.size());
	for (uint32_t i = 0; i < a.size(); ++i) {
		CHECK(a[i].first == b[i].first);
		CHECK(a[i].count == b[i].count);
	}
	for (uint32_t i = 0; i < am.size(); ++i) {
		CHECK(am[i] == bm[i]);
	}
}

TEST_CASE("[PhysicsSoftBody] Shape clusters ignore duplicate face edges") {
	LocalVector<PhysicsSoftBodyShapeEdge> edges;
	edges.push_back({ 0, 1 }); edges.push_back({ 0, 1 }); edges.push_back({ 1, 2 });
	edges.push_back({ 2, 0 }); edges.push_back({ 2, 0 });
	LocalVector<PhysicsSoftBodyShapeCluster> clusters;
	LocalVector<uint32_t> members;
	CHECK(physics_softbody_build_shape_clusters(3, edges, 3, clusters, members));
	CHECK(clusters.size() == 1);
	CHECK(clusters[0].count == 3);
}

TEST_CASE("[PhysicsSoftBody] Shape clusters reject invalid topology without touching output") {
	LocalVector<PhysicsSoftBodyShapeEdge> edges;
	edges.push_back({ 0, 3 });
	LocalVector<PhysicsSoftBodyShapeCluster> clusters;
	LocalVector<uint32_t> members;
	clusters.push_back({ 7, 4 });
	members.push_back(17);
	CHECK_FALSE(physics_softbody_build_shape_clusters(3, edges, 3, clusters, members));
	CHECK_FALSE(physics_softbody_build_shape_clusters(3, edges, 65, clusters, members));
	CHECK(clusters[0].first == 7);
	CHECK(members[0] == 17);
}

TEST_CASE("[PhysicsSoftBody] Isolated nodes do not produce fake fitting clusters") {
	LocalVector<PhysicsSoftBodyShapeEdge> edges;
	LocalVector<PhysicsSoftBodyShapeCluster> clusters;
	LocalVector<uint32_t> members;
	CHECK_FALSE(physics_softbody_build_shape_clusters(8, edges, 4, clusters, members));
	CHECK(clusters.is_empty());
	CHECK(members.is_empty());
}

TEST_CASE("[PhysicsSoftBody] Overlapping shape goals average to avoid overcorrection") {
	Vector3 sum;
	uint32_t count = 0;
	CHECK(physics_softbody_shape_cluster_accumulate(Vector3(2, 0, 0),
			Vector3(1, 0, 0), Vector3(), Quaternion(), sum, count));
	CHECK(physics_softbody_shape_cluster_accumulate(Vector3(2, 0, 0),
			Vector3(3, 0, 0), Vector3(), Quaternion(), sum, count));
	CHECK(count == 2);
	CHECK((sum / real_t(count)).is_equal_approx(Vector3()));
}

TEST_CASE("[PhysicsSoftBody] Cluster fitting is invariant to rigid translation") {
	const Vector3 rest[4] = { Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1) };
	const Quaternion rotation(Vector3(1, 2, 3).normalized(), real_t(0.65));
	const Vector3 translation(11, 17, -5);
	PhysicsSoftBodyShapeMatchingCovariance covariance;
	Vector3 center;
	for (int i = 0; i < 4; ++i) {
		center += rest[i] * real_t(0.25);
	}
	for (int i = 0; i < 4; ++i) {
		covariance.add(rest[i] - center, rotation.xform(rest[i] - center));
	}
	Quaternion fitted;
	CHECK(covariance.solve_rotation(fitted));
	Vector3 sum;
	uint32_t count = 0;
	CHECK(physics_softbody_shape_cluster_accumulate(
			rotation.xform(rest[1] - center) + translation,
			rest[1] - center, translation, fitted, sum, count));
	CHECK(sum.length() < real_t(1e-4));
}

TEST_CASE("[PhysicsSoftBody] Invalid cluster displacement never mutates accumulator") {
	Vector3 sum(1, 2, 3);
	uint32_t count = 4;
	CHECK_FALSE(physics_softbody_shape_cluster_accumulate(
			Vector3(std::numeric_limits<real_t>::infinity(), 0, 0),
			Vector3(), Vector3(), Quaternion(), sum, count));
	CHECK(sum == Vector3(1, 2, 3));
	CHECK(count == 4);
}

} // namespace TestPhysicsSoftBodyShapeClusters
