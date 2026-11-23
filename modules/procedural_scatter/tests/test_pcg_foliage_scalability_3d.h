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
	CHECK(budget->plan_visible_counts({ 1 }, { static_cast<float>(Math::NaN) }, 1).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { static_cast<float>(Math::INF) }, 1).is_empty());
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

TEST_CASE("[PCGFoliageScalability3D] temporal count deadband prevents tiny density oscillation") {
	Ref<PCGFoliageScalability3D> planner;
	planner.instantiate();
	const PackedInt32Array counts = { 100, 100, 0, 10 };
	const PackedFloat32Array distances = { 18, 30, 50, 18 };
	const PackedInt32Array history = { 68, 68, 0, -1 };
	const PackedInt32Array expected = { 68, 68, 0, 7 };
	CHECK(planner->plan_visible_counts_stable(counts, distances, history, 1) == expected);
	// Suppressed one-count changes are released once the actual requested
	// count differs by more than the two-instance threshold.
	CHECK(planner->plan_visible_counts_stable({ 100 }, { 125 }, { 68 }, 1)[0] == 42);
	CHECK(planner->plan_visible_counts_stable({ 100 }, { 125 }, { 42 }, 1)[0] == 42);
	CHECK(planner->plan_visible_counts_stable({ 100 }, { 30 }, { -1 }, 1)[0] == 67);
	CHECK(planner->plan_visible_counts_stable({ 100 }, { 30 }, { 68 }, 1, 0)[0] == 67);
	// Tier switch with -1 bypasses the deadband and restores full Ultra.
	CHECK(planner->plan_visible_counts_stable({ 10 }, { 125 }, { -1 }, 3)[0] == 10);
	CHECK(planner->plan_visible_counts_stable({ 10 }, { 125 }, { -1 }, 0)[0] == 2);
	// Nonempty foliage cannot stick at a previously hidden 0 count.
	CHECK(planner->plan_visible_counts_stable({ 1 }, { 18 }, { 0 }, 0)[0] == 1);
	CHECK(planner->plan_visible_counts_stable({ 0 }, { 18 }, { 0 }, 0)[0] == 0);
}

TEST_CASE("[PCGFoliageScalability3D] stable planner validates all prior rows atomically") {
	Ref<PCGFoliageScalability3D> planner;
	planner.instantiate();
	CHECK(planner->plan_visible_counts_stable({ 10, 20 }, { 18, 19 }, { -1 }, 1).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10, 20 }, { 18 }, { -1, -1 }, 1).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10, 20 }, { 18, 19 }, { -1, 21 }, 1).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10, 20 }, { 18, 19 }, { -1, -2 }, 1).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10 }, { 18 }, { -1 }, 1, -1).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10 }, { 18 }, { -1 }, 1, 9).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10 }, { static_cast<float>(Math::NaN) }, { -1 }, 1).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10 }, { 18 }, { -1 }, 4).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10 }, { 18 }, { -1 }, 1, 2, 20, 20).is_empty());
	CHECK(planner->plan_visible_counts_stable({}, {}, {}, 1).is_empty());
	PackedInt32Array counts;
	PackedFloat32Array distances;
	PackedInt32Array history;
	for (int i = 0; i < 4096; ++i) {
		counts.push_back(100);
		distances.push_back(30.0f);
		history.push_back(68);
	}
	const PackedInt32Array planned = planner->plan_visible_counts_stable(counts, distances, history, 1);
	REQUIRE(planned.size() == 4096);
	CHECK(planned[0] == 68);
	CHECK(planned[4095] == 68);
	counts.push_back(100);
	distances.push_back(30.0f);
	history.push_back(68);
	CHECK(planner->plan_visible_counts_stable(counts, distances, history, 1).is_empty());
}

TEST_CASE("[PCGFoliageScalability3D] per-instance geometry LOD initial and sticky boundaries") {
	Ref<PCGFoliageScalability3D> planner;
	planner.instantiate();
	const PackedVector3Array points = {
		Vector3(0, 0, 0), Vector3(24, 0, 0), Vector3(24.01, 0, 0),
		Vector3(27, 0, 0), Vector3(27.01, 0, 0), Vector3(-24, 0, 0)
	};
	const PackedInt32Array initial_expected = { 0, 0, 1, 1, 1, 0 };
	const PackedInt32Array initial = planner->plan_instance_lods(points, Vector3(), {});
	CHECK(initial == initial_expected);
	CHECK(planner->plan_instance_lods(points, Vector3(), {}) == initial);
	const PackedInt32Array near_previous = { 0, 0, 0, 0, 0, 0 };
	const PackedInt32Array near_expected = { 0, 0, 0, 0, 1, 0 };
	CHECK(planner->plan_instance_lods(points, Vector3(), near_previous) == near_expected);
	const PackedInt32Array far_previous = { 1, 1, 1, 1, 1, 1 };
	const PackedInt32Array far_expected = { 0, 1, 1, 1, 1, 1 };
	CHECK(planner->plan_instance_lods(points, Vector3(), far_previous) == far_expected);
	// Distances exactly at transition edges retain the existing tier.
	CHECK(planner->plan_instance_lods({ Vector3(21, 0, 0) }, Vector3(), { 1 })[0] == 1);
	CHECK(planner->plan_instance_lods({ Vector3(20.9, 0, 0) }, Vector3(), { 1 })[0] == 0);
	CHECK(planner->plan_instance_lods({ Vector3(27, 0, 0) }, Vector3(), { 0 })[0] == 0);
	CHECK(planner->plan_instance_lods({ Vector3(27.1, 0, 0) }, Vector3(), { 0 })[0] == 1);
	CHECK(planner->plan_instance_lods(points, Vector3(200, 0, 0), initial).size() == points.size());
	const PackedInt32Array far_move = planner->plan_instance_lods(points, Vector3(200, 0, 0), initial);
	for (int tier : far_move) {
		CHECK(tier == 1);
	}
}

TEST_CASE("[PCGFoliageScalability3D] combined variant and LOD batches conserve all source instances") {
	Ref<PCGFoliageScalability3D> planner;
	planner.instantiate();
	const PackedInt32Array variants = { 0, 1, 0, 1, 2, 1 };
	const PackedInt32Array lods = { 0, 1, 1, 0, 0, 1 };
	const PackedInt32Array copy = variants;
	const Array groups = planner->partition_variant_lods(variants, lods, 3);
	REQUIRE(groups.size() == 6);
	const PackedInt32Array expected0 = { 0 };
	const PackedInt32Array expected1 = { 2 };
	const PackedInt32Array expected2 = { 3 };
	const PackedInt32Array expected3 = { 1, 5 };
	const PackedInt32Array expected4 = { 4 };
	const PackedInt32Array group0 = groups[0];
	CHECK(group0 == expected0);
	const PackedInt32Array group1 = groups[1];
	CHECK(group1 == expected1);
	const PackedInt32Array group2 = groups[2];
	CHECK(group2 == expected2);
	const PackedInt32Array group3 = groups[3];
	CHECK(group3 == expected3);
	const PackedInt32Array group4 = groups[4];
	CHECK(group4 == expected4);
	const PackedInt32Array group5 = groups[5];
	CHECK(group5.is_empty());
	CHECK(planner->partition_variant_lods(variants, lods, 3) == groups);
	CHECK(variants == copy);
	int visited[6] = {};
	for (int group_index = 0; group_index < groups.size(); ++group_index) {
		const PackedInt32Array indices = groups[group_index];
		for (int index : indices) {
			REQUIRE(index >= 0);
			REQUIRE(index < 6);
			CHECK(variants[index] == group_index / 2);
			CHECK(lods[index] == group_index % 2);
			visited[index]++;
		}
	}
	for (int count : visited) {
		CHECK(count == 1);
	}
	const Array empty = planner->partition_variant_lods({}, {}, 3);
	REQUIRE(empty.size() == 6);
	for (int i = 0; i < 6; ++i) {
		const PackedInt32Array indices = empty[i];
		CHECK(indices.is_empty());
	}
}

TEST_CASE("[PCGFoliageScalability3D] invalid per-point LOD input rejects atomically") {
	Ref<PCGFoliageScalability3D> planner;
	planner.instantiate();
	const PackedVector3Array positions = { Vector3(), Vector3(25, 0, 0) };
	CHECK(planner->plan_instance_lods(positions, Vector3(), { 0 }).is_empty());
	CHECK(planner->plan_instance_lods(positions, Vector3(), { 0, 2 }).is_empty());
	CHECK(planner->plan_instance_lods(positions, Vector3(), {}, -1).is_empty());
	CHECK(planner->plan_instance_lods(positions, Vector3(), {}, Math::INF).is_empty());
	CHECK(planner->plan_instance_lods(positions, Vector3(), {}, 24, -1).is_empty());
	CHECK(planner->plan_instance_lods(positions, Vector3(), {}, 24, 24).is_empty());
	CHECK(planner->plan_instance_lods(positions, Vector3(), {}, 24, Math::NaN).is_empty());
	CHECK(planner->plan_instance_lods(positions, Vector3(Math::NaN, 0, 0), {}).is_empty());
	CHECK(planner->plan_instance_lods({ Vector3(), Vector3(Math::NaN, 0, 0) }, Vector3(), {}).is_empty());
	CHECK(planner->plan_instance_lods({ Vector3(), Vector3(10000001, 0, 0) }, Vector3(), {}).is_empty());
	CHECK(planner->partition_variant_lods({ 0, 0 }, { 0 }, 2).is_empty());
	CHECK(planner->partition_variant_lods({ 0, 2 }, { 0, 1 }, 2).is_empty());
	CHECK(planner->partition_variant_lods({ 0, 1 }, { 0, -1 }, 2).is_empty());
	CHECK(planner->partition_variant_lods({ 0, 1 }, { 0, 2 }, 2).is_empty());
	CHECK(planner->partition_variant_lods({ 0, 1 }, { 0, 1 }, 0).is_empty());
	CHECK(planner->partition_variant_lods({ 0, 1 }, { 0, 1 }, 33).is_empty());
	PackedVector3Array many;
	many.resize(16385);
	CHECK(planner->plan_instance_lods(many, Vector3(), {}).is_empty());
	PackedInt32Array ids;
	PackedInt32Array tiers;
	ids.resize(16385);
	tiers.resize(16385);
	CHECK(planner->partition_variant_lods(ids, tiers, 3).is_empty());
	many.resize(16384);
	const PackedInt32Array max_lods = planner->plan_instance_lods(many, Vector3(), {});
	REQUIRE(max_lods.size() == 16384);
	CHECK(max_lods[0] == 0);
	ids.resize(16384);
	tiers.resize(16384);
	const Array max_groups = planner->partition_variant_lods(ids, tiers, 3);
	REQUIRE(max_groups.size() == 6);
	const PackedInt32Array max_near = max_groups[0];
	CHECK(max_near.size() == 16384);
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
			{ 1.0f, static_cast<float>(Math::NaN) }, Vector3(), forward, 220, false, 0).is_empty());
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


TEST_CASE("[PCGFoliageScalability3D] dirty geometry tier masks update only the affected mesh groups") {
	Ref<PCGFoliageScalability3D> planner;
	planner.instantiate();
	const PackedInt32Array variants = { 0, 0, 1, 1, 2, 2 };
	const PackedInt32Array prior = { 0, 1, 0, 1, 0, 1 };
	const PackedInt32Array one_move = { 1, 1, 0, 1, 0, 1 };
	const PackedInt32Array prior_copy = prior;
	const PackedByteArray expected = { 1, 1, 0, 0, 0, 0 };
	const PackedByteArray dirty = planner->plan_dirty_variant_lod_groups(
			variants, prior, one_move, 3);
	CHECK(dirty == expected);
	CHECK(prior == prior_copy);
	CHECK(planner->plan_dirty_variant_lod_groups(variants, prior, one_move, 3) == dirty);
	const PackedByteArray none = { 0, 0, 0, 0, 0, 0 };
	CHECK(planner->plan_dirty_variant_lod_groups(variants, prior, prior, 3) == none);
	const PackedInt32Array two_moves = { 1, 1, 0, 1, 1, 1 };
	const PackedByteArray expected_two = { 1, 1, 0, 0, 1, 1 };
	CHECK(planner->plan_dirty_variant_lod_groups(variants, prior, two_moves, 3) == expected_two);
	const PackedInt32Array all_far = { 1, 1, 1, 1, 1, 1 };
	const PackedByteArray expected_all = { 1, 1, 1, 1, 1, 1 };
	CHECK(planner->plan_dirty_variant_lod_groups(variants, prior, all_far, 3) == expected_all);
}

TEST_CASE("[PCGFoliageScalability3D] dirty flags support valid empty scenes and reject invalid tail data") {
	Ref<PCGFoliageScalability3D> planner;
	planner.instantiate();
	const PackedByteArray none = { 0, 0, 0, 0, 0, 0 };
	CHECK(planner->plan_dirty_variant_lod_groups({}, {}, {}, 3) == none);
	const PackedByteArray pair_dirty = { 1, 1 };
	CHECK(planner->plan_dirty_variant_lod_groups({ 0, 0 }, { 0, 1 }, { 1, 0 }, 1)
			== pair_dirty);
	CHECK(planner->plan_dirty_variant_lod_groups({ 0, 1 }, { 0, 1 }, { 1 }, 2).is_empty());
	CHECK(planner->plan_dirty_variant_lod_groups({ 0, 1 }, { 0 }, { 1, 0 }, 2).is_empty());
	CHECK(planner->plan_dirty_variant_lod_groups({ 0, 2 }, { 0, 1 }, { 1, 0 }, 2).is_empty());
	CHECK(planner->plan_dirty_variant_lod_groups({ -1, 0 }, { 0, 1 }, { 1, 0 }, 2).is_empty());
	CHECK(planner->plan_dirty_variant_lod_groups({ 0, 1 }, { 0, 2 }, { 1, 0 }, 2).is_empty());
	CHECK(planner->plan_dirty_variant_lod_groups({ 0, 1 }, { 0, 1 }, { 1, -1 }, 2).is_empty());
	CHECK(planner->plan_dirty_variant_lod_groups({ 0 }, { 0 }, { 1 }, 0).is_empty());
	CHECK(planner->plan_dirty_variant_lod_groups({ 0 }, { 0 }, { 1 }, 33).is_empty());
	PackedInt32Array ids;
	PackedInt32Array previous;
	PackedInt32Array next;
	ids.resize(16385);
	previous.resize(16385);
	next.resize(16385);
	CHECK(planner->plan_dirty_variant_lod_groups(ids, previous, next, 3).is_empty());
	ids.resize(16384);
	previous.resize(16384);
	next.resize(16384);
	CHECK(planner->plan_dirty_variant_lod_groups(ids, previous, next, 3) == none);
	next.set(16383, 1);
	const PackedByteArray expected_change = { 1, 1, 0, 0, 0, 0 };
	CHECK(planner->plan_dirty_variant_lod_groups(ids, previous, next, 3) == expected_change);
}

} // namespace TestPCGFoliageScalability3D
