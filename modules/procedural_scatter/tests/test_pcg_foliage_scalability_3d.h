/**************************************************************************/
/*  test_pcg_foliage_scalability_3d.h                                       */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "../pcg_foliage_scalability_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGFoliageScalability3D {

TEST_CASE("[PCGFoliageScalability3D] stable bit-reversed distributed prefixes") {
	Ref<PCGFoliageScalability3D> budget;
	budget.instantiate();
	const PackedInt32Array expected = { 0, 8, 4, 2, 6, 1, 9, 5, 3, 7 };
	CHECK(budget->spread_indices(10) == expected);
	CHECK(budget->spread_indices(10) == expected); // Idempotent; no RNG.
	CHECK(budget->spread_indices(0).is_empty());
	const PackedInt32Array one = { 0 };
	CHECK(budget->spread_indices(1) == one);
	CHECK(budget->spread_indices(-1).is_empty());
	CHECK(budget->spread_indices(65537).is_empty());
	const PackedInt32Array max_order = budget->spread_indices(65536);
	REQUIRE(max_order.size() == 65536);
	CHECK(max_order[0] == 0);
	CHECK(max_order[1] == 32768);
	CHECK(max_order[2] == 16384);
	CHECK(max_order[65535] == 65535);
	// Every original index occurs once, including non-power-of-two sizes.
	bool seen[10] = {};
	for (int i = 0; i < expected.size(); ++i) {
		const int source = expected[i];
		REQUIRE(source >= 0);
		REQUIRE(source < 10);
		CHECK(!seen[source]);
		seen[source] = true;
	}
}

TEST_CASE("[PCGFoliageScalability3D] reversible density tiers and smooth distance") {
	Ref<PCGFoliageScalability3D> budget;
	budget.instantiate();
	const PackedInt32Array counts = { 100, 100, 100, 0, 1 };
	const PackedFloat32Array distances = { 18, 71.5f, 125, 70, 125 };
	const PackedInt32Array performance = { 42, 31, 20, 0, 1 };
	CHECK(budget->plan_visible_counts(counts, distances, 0) == performance);
	const PackedInt32Array balanced = { 68, 55, 42, 0, 1 };
	CHECK(budget->plan_visible_counts(counts, distances, 1) == balanced);
	const PackedInt32Array high = { 88, 79, 70, 0, 1 };
	CHECK(budget->plan_visible_counts(counts, distances, 2) == high);
	CHECK(budget->plan_visible_counts(counts, distances, 3) == counts);
	CHECK(budget->plan_visible_counts(counts, distances, 1) ==
			budget->plan_visible_counts(counts, distances, 1));
	const PackedInt32Array near_and_far = { 42, 20 };
	CHECK(budget->plan_visible_counts({ 100, 100 }, { 0, 1000 }, 0) == near_and_far);
	CHECK(budget->plan_visible_counts({ 100, 100 }, { 10, 30 }, 0, 10, 30) == near_and_far);
}

TEST_CASE("[PCGFoliageScalability3D] atomic validation and bounded cluster counts") {
	Ref<PCGFoliageScalability3D> budget;
	budget.instantiate();
	CHECK(budget->plan_visible_counts({ 1, 1 }, { 1 }, 0).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, -1).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 4).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { Math::NaN }, 1).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { Math::INF }, 1).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { -1 }, 1).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 10000001 }, 1).is_empty());
	CHECK(budget->plan_visible_counts({ -1 }, { 1 }, 1).is_empty());
	CHECK(budget->plan_visible_counts({ 65537 }, { 1 }, 1).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 1, -1, 125).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 1, 125, 125).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 1, 20, 10).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 1, Math::NaN, 125).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 1, 18, Math::INF).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 1, 18, 1000001).is_empty());
	CHECK(budget->plan_visible_counts({ 100, 20, -1 }, { 10, 20, 30 }, 0).is_empty());
	CHECK(budget->plan_visible_counts({}, {}, 0).is_empty());
	PackedInt32Array many_counts;
	PackedFloat32Array many_distances;
	for (int i = 0; i < 4097; ++i) {
		many_counts.push_back(10);
		many_distances.push_back(100.0f);
	}
	CHECK(budget->plan_visible_counts(many_counts, many_distances, 1).is_empty());
	many_counts.resize(4096);
	many_distances.resize(4096);
	const PackedInt32Array planned = budget->plan_visible_counts(many_counts, many_distances, 1);
	REQUIRE(planned.size() == 4096);
	CHECK(planned[0] >= 1);
	CHECK(planned[4095] >= 1);
}

TEST_CASE("[PCGFoliageScalability3D] screen-space foliage depends on projected pixels") {
	Ref<PCGFoliageScalability3D> budget;
	budget.instantiate();
	const PackedInt32Array counts = { 100, 100, 100, 100, 0 };
	const PackedVector3Array centers = {
		Vector3(0, 0, -11), Vector3(0, 0, -20),
		Vector3(0, 0, -110), Vector3(0, 0, 10),
		Vector3(0, 0, -20)
	};
	const PackedFloat32Array mesh_diameters = { 1, 1, 1, 1, 1 };
	const Vector3 camera = Vector3();
	const Vector3 forward = Vector3(0, 0, -1);
	const PackedInt32Array performance = { 42, 31, 20, 100, 0 };
	CHECK(budget->plan_projected_visible_counts(counts, centers, mesh_diameters,
			camera, forward, 220.0, false, 0) == performance);
	const PackedInt32Array balanced = { 68, 55, 42, 100, 0 };
	CHECK(budget->plan_projected_visible_counts(counts, centers, mesh_diameters,
			camera, forward, 220.0, false, 1) == balanced);
	CHECK(budget->plan_projected_visible_counts(counts, centers, mesh_diameters,
			camera, forward, 220.0, false, 3) == counts);
	// Orthographic scale is independent of perspective depth.
	const PackedInt32Array ortho = { 31, 31, 31, 100, 0 };
	CHECK(budget->plan_projected_visible_counts(counts, centers, mesh_diameters,
			camera, forward, 11.0, true, 0) == ortho);
	// Higher pixel resolution or narrower FOV increases preserved detail.
	const PackedInt32Array zoomed = budget->plan_projected_visible_counts(
			counts, centers, mesh_diameters, camera, forward, 440.0, false, 0);
	REQUIRE(zoomed.size() == counts.size());
	CHECK(zoomed[0] >= performance[0]);
	CHECK(zoomed[1] >= performance[1]);
	CHECK(zoomed[2] >= performance[2]);
	// Behind-camera nodes are left at full count, never culled manually.
	CHECK(performance[3] == counts[3]);
	CHECK(budget->plan_projected_visible_counts(counts, centers, mesh_diameters,
			camera, forward, 220.0, false, 0) == performance);
}

TEST_CASE("[PCGFoliageScalability3D] screen-space validation rejects invalid late groups") {
	Ref<PCGFoliageScalability3D> budget;
	budget.instantiate();
	const PackedInt32Array counts = { 10, 20 };
	const PackedVector3Array centers = { Vector3(0, 0, -10), Vector3(0, 0, -20) };
	const PackedFloat32Array diameters = { 1, 2 };
	const Vector3 forward(0, 0, -1);
	CHECK(budget->plan_projected_visible_counts(counts, centers, { 1 },
			Vector3(), forward, 220, false, 0).is_empty());
	CHECK(budget->plan_projected_visible_counts(counts, {}, diameters,
			Vector3(), forward, 220, false, 0).is_empty());
	CHECK(budget->plan_projected_visible_counts(counts, centers, diameters,
			Vector3(), Vector3(), 220, false, 0).is_empty());
	CHECK(budget->plan_projected_visible_counts(counts, centers, diameters,
			Vector3(Math::NaN, 0, 0), forward, 220, false, 0).is_empty());
	CHECK(budget->plan_projected_visible_counts(counts, centers, diameters,
			Vector3(), forward, Math::NaN, false, 0).is_empty());
	CHECK(budget->plan_projected_visible_counts(counts, centers, diameters,
			Vector3(), forward, 0, false, 0).is_empty());
	CHECK(budget->plan_projected_visible_counts(counts, centers, diameters,
			Vector3(), forward, 220, false, -1).is_empty());
	CHECK(budget->plan_projected_visible_counts(counts, centers, diameters,
			Vector3(), forward, 220, false, 4).is_empty());
	CHECK(budget->plan_projected_visible_counts(counts, centers, diameters,
			Vector3(), forward, 220, false, 0, 2, 2).is_empty());
	CHECK(budget->plan_projected_visible_counts(counts, centers, diameters,
			Vector3(), forward, 220, false, 0, 20, -1).is_empty());
	CHECK(budget->plan_projected_visible_counts(counts,
			{ Vector3(0, 0, -10), Vector3(Math::INF, 0, -20) }, diameters,
			Vector3(), forward, 220, false, 0).is_empty());
	CHECK(budget->plan_projected_visible_counts(counts, centers,
			{ 1, Math::NaN }, Vector3(), forward, 220, false, 0).is_empty());
	CHECK(budget->plan_projected_visible_counts(counts, centers,
			{ 1, -1 }, Vector3(), forward, 220, false, 0).is_empty());
	CHECK(budget->plan_projected_visible_counts({ 10, 65537 }, centers, diameters,
			Vector3(), forward, 220, false, 0).is_empty());
	PackedInt32Array many_counts;
	PackedVector3Array many_centers;
	PackedFloat32Array many_diameters;
	for (int i = 0; i < 4097; ++i) {
		many_counts.push_back(50);
		many_centers.push_back(Vector3(0, 0, -10));
		many_diameters.push_back(1);
	}
	CHECK(budget->plan_projected_visible_counts(many_counts, many_centers,
			many_diameters, Vector3(), forward, 220, false, 0).is_empty());
	many_counts.resize(4096);
	many_centers.resize(4096);
	many_diameters.resize(4096);
	const PackedInt32Array bounded = budget->plan_projected_visible_counts(
			many_counts, many_centers, many_diameters,
			Vector3(), forward, 220, false, 0);
	REQUIRE(bounded.size() == 4096);
	CHECK(bounded[0] == 21);
	CHECK(bounded[4095] == 21);
}

} // namespace TestPCGFoliageScalability3D
