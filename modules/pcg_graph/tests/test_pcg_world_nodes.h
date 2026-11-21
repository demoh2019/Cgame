/**************************************************************************/
/*  test_pcg_world_nodes.h                                                */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "../pcg_core_nodes.h"
#include "../pcg_world_nodes.h"

#include "core/object/callable_mp.h"
#include "tests/test_macros.h"

namespace TestPCGWorldNodes {

// Gaussian hill (height 30, sigma 8) centered on the origin.
static float hill_height(float p_x, float p_z) {
	return 30.0f * Math::exp(-(p_x * p_x + p_z * p_z) / (2.0f * 8.0f * 8.0f));
}

// Cone-like mountain (height 50, sigma 30) with an off-center peak so lattice ties do not occur.
static float mountain_height(float p_x, float p_z) {
	const float dx = p_x - 7.0f;
	const float dz = p_z + 5.0f;
	return 50.0f * Math::exp(-(dx * dx + dz * dz) / (2.0f * 30.0f * 30.0f));
}

static bool low_is_water(float p_x, float p_z) {
	return mountain_height(p_x, p_z) < 2.0f;
}

static Ref<PCGContext> make_context(const AABB &p_bounds, int64_t p_seed = 7) {
	Ref<PCGContext> context;
	context.instantiate();
	context->set_seed(p_seed);
	context->set_bounds(p_bounds);
	return context;
}

static Ref<PCGData> run(const Ref<PCGNode> &p_node, const Ref<PCGContext> &p_context, uint64_t p_seed, const Ref<PCGData> &p_a = Ref<PCGData>(), const Ref<PCGData> &p_b = Ref<PCGData>(), const Ref<PCGData> &p_c = Ref<PCGData>()) {
	Vector<Ref<PCGData>> inputs;
	if (p_a.is_valid()) {
		inputs.push_back(p_a);
		if (p_b.is_valid() || p_c.is_valid()) {
			inputs.push_back(p_b);
		}
		if (p_c.is_valid()) {
			inputs.push_back(p_c);
		}
	}
	return p_node->execute(inputs, p_context, p_seed);
}

static Ref<PCGPointData> points_of(const Vector<Vector3> &p_positions) {
	Ref<PCGPointData> points;
	points.instantiate();
	for (int i = 0; i < p_positions.size(); i++) {
		points->add_point(p_positions[i]);
	}
	return points;
}

static Ref<PCGPointData> lattice(float p_x0, float p_z0, int p_nx, int p_nz, float p_step) {
	Ref<PCGPointData> points;
	points.instantiate();
	for (int j = 0; j < p_nz; j++) {
		for (int i = 0; i < p_nx; i++) {
			points->add_point(Vector3(p_x0 + i * p_step, 0, p_z0 + j * p_step));
		}
	}
	return points;
}

static float max_grade(const PackedVector3Array &p_line, float p_sample_step = 1.0f) {
	float worst = 0.0f;
	for (int s = 1; s < p_line.size(); s++) {
		const Vector3 a = p_line[s - 1];
		const Vector3 b = p_line[s];
		const float len = Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z));
		const int steps = MAX(1, (int)Math::ceil(len / p_sample_step));
		for (int k = 0; k < steps; k++) {
			const float t0 = float(k) / steps;
			const float t1 = float(k + 1) / steps;
			const float h0 = hill_height(Math::lerp(a.x, b.x, t0), Math::lerp(a.z, b.z, t0));
			const float h1 = hill_height(Math::lerp(a.x, b.x, t1), Math::lerp(a.z, b.z, t1));
			worst = MAX(worst, Math::abs(h1 - h0) / MAX(0.001f, len / steps));
		}
	}
	return worst;
}

static int find_root(Vector<int> &p_parent, int p_i) {
	while (p_parent[p_i] != p_i) {
		p_i = p_parent[p_i];
	}
	return p_i;
}

static Ref<PCGPointData> make_lots(int p_count) {
	Ref<PCGPointData> lots;
	lots.instantiate();
	PackedFloat32Array fx;
	PackedFloat32Array fz;
	for (int i = 0; i < p_count; i++) {
		lots->add_point(Vector3(i * 20.0f, 0, (i % 3) * 25.0f), Vector3(0, 1, 0), 1.0f, i * 0.4f, 1.0f, i + 1);
		fx.push_back(6.0f + (i % 4) * 2.0f);
		fz.push_back(6.0f + ((i + 1) % 3) * 3.0f);
	}
	lots->set_attribute("footprint_x", fx);
	lots->set_attribute("footprint_z", fz);
	return lots;
}

TEST_CASE("[PCGWorld] road route is deterministic and avoids a steep hill") {
	Ref<PCGContext> context = make_context(AABB(Vector3(-100, -10, -100), Vector3(200, 100, 200)));
	context->set_height_sampler(callable_mp_static(hill_height));
	const Vector3 from(-40, 0, 0);
	const Vector3 to(40, 0, 0);
	const PackedVector3Array a = PCGRoadNetworkNode::route(5, from, to, context, 4.0);
	const PackedVector3Array b = PCGRoadNetworkNode::route(5, from, to, context, 4.0);
	REQUIRE(a.size() >= 2);
	REQUIRE(a.size() == b.size());
	for (int i = 0; i < a.size(); i++) {
		CHECK(a[i] == b[i]);
	}
	CHECK(a[0] == from);
	CHECK(a[a.size() - 1] == to);
	PackedVector3Array straight;
	straight.push_back(from);
	straight.push_back(to);
	const float routed_grade = max_grade(a);
	const float straight_grade = max_grade(straight);
	CHECK(straight_grade > 1.0f);
	CHECK(routed_grade < straight_grade * 0.5f);
}

TEST_CASE("[PCGWorld] road network connects every settlement") {
	Ref<PCGContext> context = make_context(AABB(Vector3(-100, -10, -100), Vector3(200, 100, 200)));
	context->set_height_sampler(callable_mp_static(hill_height));
	Vector<Vector3> sites;
	sites.push_back(Vector3(-40, hill_height(-40, 0), 0));
	sites.push_back(Vector3(40, hill_height(40, 0), 0));
	sites.push_back(Vector3(0, hill_height(0, 45), 45));
	sites.push_back(Vector3(0, hill_height(0, -45), -45));
	sites.push_back(Vector3(35, hill_height(35, 35), 35));
	Ref<PCGPointData> input = points_of(sites);
	Ref<PCGRoadNetworkNode> node;
	node.instantiate();
	Ref<PCGSplineData> first = run(node, context, 11, input);
	Ref<PCGSplineData> second = run(node, context, 11, input);
	REQUIRE(first.is_valid());
	CHECK(first->compute_content_hash() == second->compute_content_hash());
	CHECK(first->get_polyline_count() == sites.size() - 1); // Spanning tree, no loops.
	Vector<int> parent;
	for (int i = 0; i < sites.size(); i++) {
		parent.push_back(i);
	}
	for (int l = 0; l < first->get_polyline_count(); l++) {
		const PackedVector3Array line = first->get_polyline(l);
		int ends[2] = { -1, -1 };
		for (int i = 0; i < sites.size(); i++) {
			if (line[0].is_equal_approx(sites[i])) {
				ends[0] = i;
			}
			if (line[line.size() - 1].is_equal_approx(sites[i])) {
				ends[1] = i;
			}
		}
		REQUIRE(ends[0] >= 0);
		REQUIRE(ends[1] >= 0);
		parent.write[find_root(parent, ends[0])] = find_root(parent, ends[1]);
		CHECK(first->get_width(l) > 0.0f);
	}
	const int root = find_root(parent, 0);
	for (int i = 1; i < sites.size(); i++) {
		CHECK(find_root(parent, i) == root);
	}
	// Loops add edges only when requested.
	node->set_loop_detour_ratio(1.05);
	node->set_max_extra_edges(3);
	Ref<PCGSplineData> looped = run(node, context, 11, input);
	CHECK(looped->get_polyline_count() > first->get_polyline_count());
}

TEST_CASE("[PCGWorld] rivers always descend, end at water and widen downstream") {
	Ref<PCGContext> context = make_context(AABB(Vector3(-100, -10, -100), Vector3(200, 100, 200)));
	context->set_height_sampler(callable_mp_static(mountain_height));
	context->set_water_sampler(callable_mp_static(low_is_water));
	Ref<PCGRiverNetworkNode> node;
	node.instantiate();
	node->set_min_source_height(20.0);
	Ref<PCGSplineData> a = run(node, context, 3);
	Ref<PCGSplineData> b = run(node, context, 3);
	REQUIRE(a.is_valid());
	REQUIRE(a->get_polyline_count() >= 1);
	CHECK(a->compute_content_hash() == b->compute_content_hash());
	float min_width = 1000.0f;
	float max_width = 0.0f;
	for (int l = 0; l < a->get_polyline_count(); l++) {
		const PackedVector3Array line = a->get_polyline(l);
		for (int i = 1; i < line.size(); i++) {
			CHECK(line[i].y <= line[i - 1].y + 0.0001f);
		}
		min_width = MIN(min_width, a->get_width(l));
		max_width = MAX(max_width, a->get_width(l));
	}
	CHECK(max_width > min_width);
	// The last river vertex reaches low ground.
	const PackedVector3Array last = a->get_polyline(a->get_polyline_count() - 1);
	CHECK(last[last.size() - 1].y < 5.0f);
}

TEST_CASE("[PCGWorld] settlements keep clear of roads, slopes and each other") {
	Ref<PCGContext> context = make_context(AABB(Vector3(-100, -10, -100), Vector3(200, 100, 200)));
	Vector<Vector3> centers;
	centers.push_back(Vector3(0, 0, 0));
	Ref<PCGSplineData> roads;
	roads.instantiate();
	PackedVector3Array road;
	road.push_back(Vector3(-50, 0, 2));
	road.push_back(Vector3(50, 0, 2));
	roads->add_polyline(road, 4.0);
	Ref<PCGSettlementNode> node;
	node.instantiate();
	Ref<PCGPointData> lots = run(node, context, 21, points_of(centers), roads);
	REQUIRE(lots.is_valid());
	CHECK(lots->get_point_count() >= 4);
	Ref<PCGPointData> again = run(node, context, 21, points_of(centers), roads);
	CHECK(lots->compute_content_hash() == again->compute_content_hash());
	for (int i = 0; i < lots->get_point_count(); i++) {
		const float fx = lots->get_attribute_value("footprint_x", i);
		const float fz = lots->get_attribute_value("footprint_z", i);
		CHECK(fx > 0.0f);
		CHECK(fz > 0.0f);
		const int kind = (int)lots->get_attribute_value("kind", i);
		CHECK(kind >= 0);
		CHECK(kind <= 3);
		CHECK(roads->distance_xz(lots->get_position(i)) >= 2.0f);
		for (int j = i + 1; j < lots->get_point_count(); j++) {
			const Vector3 a = lots->get_position(i);
			const Vector3 b = lots->get_position(j);
			const float ri = 0.5f * Math::sqrt(fx * fx + fz * fz);
			const float rj = 0.5f * Math::sqrt(lots->get_attribute_value("footprint_x", j) * lots->get_attribute_value("footprint_x", j) + lots->get_attribute_value("footprint_z", j) * lots->get_attribute_value("footprint_z", j));
			CHECK(Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) >= ri + rj - 0.01f);
		}
	}
}

TEST_CASE("[PCGWorld] city block layout is deterministic and lots carry districts") {
	const Rect2 rect(Vector2(-100, -100), Vector2(200, 200));
	const Array a = PCGCityNode::layout_blocks(9, rect, 40.0, 8.0);
	const Array b = PCGCityNode::layout_blocks(9, rect, 40.0, 8.0);
	CHECK(a.size() > 4);
	CHECK(a == b);
	for (int i = 0; i < a.size(); i++) {
		const Rect2 block = a[i];
		CHECK(rect.encloses(block));
		for (int j = i + 1; j < a.size(); j++) {
			const Rect2 other = a[j];
			CHECK_FALSE(block.intersects(other));
		}
	}
	Ref<PCGContext> context = make_context(AABB(Vector3(-200, -10, -200), Vector3(400, 100, 400)));
	Vector<Vector3> centers;
	centers.push_back(Vector3(0, 0, 0));
	Ref<PCGCityNode> node;
	node.instantiate();
	node->set_half_extent(100.0);
	node->set_core_radius(25.0);
	node->set_residential_radius(55.0);
	Ref<PCGPointData> lots = run(node, context, 5, points_of(centers));
	REQUIRE(lots->get_point_count() > 10);
	bool seen[3] = { false, false, false };
	for (int i = 0; i < lots->get_point_count(); i++) {
		const int district = (int)lots->get_attribute_value("district", i, -1.0f);
		REQUIRE(district >= 0);
		REQUIRE(district <= 2);
		seen[district] = true;
	}
	CHECK(seen[0]);
	CHECK(seen[1]);
	CHECK(seen[2]);
	node->set_layout(1);
	Ref<PCGPointData> radial = run(node, context, 5, points_of(centers));
	CHECK(radial->get_point_count() > 10);
}

TEST_CASE("[PCGWorld] buildings have exactly one door and a seeded floor count") {
	Ref<PCGContext> context = make_context(AABB(Vector3(-200, -10, -200), Vector3(400, 100, 400)));
	Ref<PCGPointData> lots = make_lots(8);
	Ref<PCGBuildingNode> node;
	node.instantiate();
	node->set_max_floors(3);
	Ref<PCGPointData> a = run(node, context, 17, lots);
	Ref<PCGPointData> b = run(node, context, 17, lots);
	Ref<PCGPointData> c = run(node, context, 18, lots);
	REQUIRE(a.is_valid());
	CHECK(a->get_point_count() > 100);
	CHECK(a->compute_content_hash() == b->compute_content_hash());
	CHECK(a->compute_content_hash() != c->compute_content_hash());
	Vector<int> doors;
	Vector<int> corners;
	Vector<int> floors_seen;
	for (int i = 0; i < lots->get_point_count(); i++) {
		doors.push_back(0);
		corners.push_back(0);
		floors_seen.push_back(0);
	}
	for (int i = 0; i < a->get_point_count(); i++) {
		const int building = (int)a->get_attribute_value("building", i);
		const int piece = (int)a->get_attribute_value("piece", i);
		const int floors = (int)a->get_attribute_value("floors", i);
		CHECK(floors >= 1);
		CHECK(floors <= 3);
		floors_seen.write[building] = floors;
		if (piece == PCGBuildingNode::PIECE_DOOR) {
			doors.write[building]++;
			CHECK((int)a->get_attribute_value("floor", i) == 0);
		}
		if (piece == PCGBuildingNode::PIECE_CORNER) {
			corners.write[building]++;
		}
	}
	for (int i = 0; i < lots->get_point_count(); i++) {
		CHECK(doors[i] == 1);
		CHECK(corners[i] == 4 * floors_seen[i]);
	}
}

TEST_CASE("[PCGWorld] ruins remove pieces, decay upper floors more and add rubble") {
	Ref<PCGContext> context = make_context(AABB(Vector3(-200, -10, -200), Vector3(400, 100, 400)));
	Ref<PCGBuildingNode> builder;
	builder.instantiate();
	builder->set_max_floors(3);
	Ref<PCGPointData> pieces = run(builder, context, 17, make_lots(12));
	Ref<PCGRuinNode> ruin;
	ruin.instantiate();
	const uint64_t hash_before = pieces->compute_content_hash();
	Ref<PCGPointData> a = run(ruin, context, 4, pieces);
	Ref<PCGPointData> b = run(ruin, context, 4, pieces);
	REQUIRE(a.is_valid());
	CHECK(a->compute_content_hash() == b->compute_content_hash());
	int kept = 0;
	int rubble = 0;
	int floor_in = 0;
	int floor_kept = 0;
	int roof_in = 0;
	int roof_kept = 0;
	for (int i = 0; i < pieces->get_point_count(); i++) {
		const int piece = (int)pieces->get_attribute_value("piece", i);
		floor_in += piece == PCGBuildingNode::PIECE_FLOOR ? 1 : 0;
		roof_in += piece == PCGBuildingNode::PIECE_ROOF ? 1 : 0;
	}
	for (int i = 0; i < a->get_point_count(); i++) {
		const int piece = (int)a->get_attribute_value("piece", i);
		if (piece == PCGBuildingNode::PIECE_RUBBLE) {
			rubble++;
			continue;
		}
		kept++;
		floor_kept += piece == PCGBuildingNode::PIECE_FLOOR ? 1 : 0;
		roof_kept += piece == PCGBuildingNode::PIECE_ROOF ? 1 : 0;
	}
	CHECK(kept < pieces->get_point_count());
	CHECK(kept > 0);
	CHECK(rubble > 0);
	CHECK(float(roof_kept) / roof_in < float(floor_kept) / floor_in);
	// Inputs are never mutated.
	CHECK(pieces->compute_content_hash() == hash_before);
}

TEST_CASE("[PCGWorld] structures never overlap and record rule id and radius") {
	Ref<PCGContext> context = make_context(AABB(Vector3(-10, -10, -10), Vector3(200, 100, 200)));
	Ref<PCGPointData> candidates = lattice(0, 0, 25, 25, 5.0);
	Array rules;
	Dictionary small_rule;
	small_rule["id"] = 1;
	small_rule["radius"] = 4.0;
	small_rule["weight"] = 3.0;
	Dictionary big_rule;
	big_rule["id"] = 2;
	big_rule["radius"] = 7.0;
	big_rule["weight"] = 1.0;
	rules.push_back(small_rule);
	rules.push_back(big_rule);
	Ref<PCGStructureNode> node;
	node.instantiate();
	node->set_rules(rules);
	node->set_min_gap(0.5);
	Ref<PCGPointData> a = run(node, context, 8, candidates);
	Ref<PCGPointData> b = run(node, context, 8, candidates);
	REQUIRE(a.is_valid());
	CHECK(a->compute_content_hash() == b->compute_content_hash());
	CHECK(a->get_point_count() > 10);
	CHECK(a->get_point_count() < candidates->get_point_count());
	for (int i = 0; i < a->get_point_count(); i++) {
		const int id = (int)a->get_attribute_value("structure", i);
		CHECK((id == 1 || id == 2));
		CHECK(a->get_attribute_value("footprint_radius", i) == (id == 1 ? 4.0f : 7.0f));
		for (int j = i + 1; j < a->get_point_count(); j++) {
			const Vector3 p = a->get_position(i);
			const Vector3 q = a->get_position(j);
			const float d = Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z));
			CHECK(d >= a->get_attribute_value("footprint_radius", i) + a->get_attribute_value("footprint_radius", j) + 0.5f - 0.001f);
		}
	}
}

TEST_CASE("[PCGWorld] loot respects max-per-structure, spacing and tier tables") {
	Ref<PCGContext> context = make_context(AABB(Vector3(-10, -10, -10), Vector3(100, 100, 100)));
	Ref<PCGPointData> spots = lattice(0, 0, 21, 21, 1.5);
	Vector<Vector3> structure_positions;
	structure_positions.push_back(Vector3(5, 0, 5));
	structure_positions.push_back(Vector3(25, 0, 25));
	Ref<PCGPointData> structures = points_of(structure_positions);
	Array rules;
	Dictionary common;
	common["table"] = 1;
	common["min_tier"] = 0;
	common["max_tier"] = 1;
	Dictionary rare;
	rare["table"] = 2;
	rare["min_tier"] = 2;
	rare["max_tier"] = 2;
	rules.push_back(common);
	rules.push_back(rare);
	PackedFloat32Array bands;
	bands.push_back(10.0f);
	bands.push_back(25.0f);
	Ref<PCGLootPlacementNode> node;
	node.instantiate();
	node->set_rarity_rules(rules);
	node->set_tier_bands(bands);
	node->set_max_per_structure(3);
	node->set_min_spacing(2.5);
	Ref<PCGPointData> a = run(node, context, 2, spots, structures);
	Ref<PCGPointData> b = run(node, context, 2, spots, structures);
	REQUIRE(a.is_valid());
	CHECK(a->compute_content_hash() == b->compute_content_hash());
	CHECK(a->get_point_count() > 0);
	CHECK(a->get_point_count() <= 6);
	int per_structure[2] = { 0, 0 };
	for (int i = 0; i < a->get_point_count(); i++) {
		const Vector3 p = a->get_position(i);
		const int nearest = Vector2(p.x, p.z).distance_to(Vector2(5, 5)) <= Vector2(p.x, p.z).distance_to(Vector2(25, 25)) ? 0 : 1;
		per_structure[nearest]++;
		const int tier = (int)a->get_attribute_value("loot_tier", i);
		const int table = (int)a->get_attribute_value("loot_table", i);
		CHECK(tier >= 0);
		CHECK(tier <= 2);
		CHECK(table == (tier == 2 ? 2 : 1));
		for (int j = i + 1; j < a->get_point_count(); j++) {
			const Vector3 q = a->get_position(j);
			CHECK(Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z)) >= 2.5f - 0.001f);
		}
	}
	CHECK(per_structure[0] <= 3);
	CHECK(per_structure[1] <= 3);
}

TEST_CASE("[PCGWorld] encounters keep away from settlements and roads") {
	Ref<PCGContext> context = make_context(AABB(Vector3(-10, -10, -10), Vector3(300, 100, 300)));
	Ref<PCGPointData> candidates = lattice(0, 0, 21, 21, 10.0);
	Vector<Vector3> settlements;
	settlements.push_back(Vector3(100, 0, 100));
	settlements.push_back(Vector3(30, 0, 30));
	Ref<PCGSplineData> roads;
	roads.instantiate();
	PackedVector3Array road;
	road.push_back(Vector3(0, 0, 150));
	road.push_back(Vector3(200, 0, 150));
	roads->add_polyline(road, 4.0);
	PackedFloat32Array bands;
	bands.push_back(80.0f);
	bands.push_back(160.0f);
	Ref<PCGEncounterPlacementNode> node;
	node.instantiate();
	node->set_difficulty_bands(bands);
	node->set_min_point_distance(40.0);
	node->set_min_spline_distance(15.0);
	node->set_min_spacing(30.0);
	Ref<PCGPointData> a = run(node, context, 6, candidates, points_of(settlements), roads);
	Ref<PCGPointData> b = run(node, context, 6, candidates, points_of(settlements), roads);
	REQUIRE(a.is_valid());
	CHECK(a->compute_content_hash() == b->compute_content_hash());
	CHECK(a->get_point_count() > 3);
	for (int i = 0; i < a->get_point_count(); i++) {
		const Vector3 p = a->get_position(i);
		for (int s = 0; s < settlements.size(); s++) {
			CHECK(Vector2(p.x, p.z).distance_to(Vector2(settlements[s].x, settlements[s].z)) >= 40.0f);
		}
		CHECK(roads->distance_xz(p) >= 15.0f);
		CHECK(a->get_attribute_value("group_size", i) >= 2.0f);
		CHECK(a->get_attribute_value("difficulty", i) >= 0.0f);
		for (int j = i + 1; j < a->get_point_count(); j++) {
			const Vector3 q = a->get_position(j);
			CHECK(Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z)) >= 30.0f - 0.001f);
		}
	}
}

TEST_CASE("[PCGWorld] environment dressing scatters around matching sources and along roads") {
	Ref<PCGContext> context = make_context(AABB(Vector3(-200, -10, -200), Vector3(400, 100, 400)));
	Ref<PCGBuildingNode> builder;
	builder.instantiate();
	Ref<PCGRuinNode> ruin;
	ruin.instantiate();
	Ref<PCGPointData> ruined = run(ruin, context, 4, run(builder, context, 17, make_lots(6)));
	Array rules;
	Dictionary rule;
	rule["asset"] = 5;
	rule["attribute"] = "piece";
	rule["value"] = (double)PCGBuildingNode::PIECE_RUBBLE;
	rule["count_min"] = 1;
	rule["count_max"] = 2;
	rule["ring_min"] = 0.5;
	rule["ring_max"] = 2.0;
	rules.push_back(rule);
	Ref<PCGSplineData> roads;
	roads.instantiate();
	PackedVector3Array road;
	road.push_back(Vector3(-50, 0, -60));
	road.push_back(Vector3(50, 0, -60));
	roads->add_polyline(road, 4.0);
	Ref<PCGEnvironmentDressingNode> node;
	node.instantiate();
	node->set_rules(rules);
	node->set_lamp_asset(9);
	node->set_lamp_spacing(10.0);
	Ref<PCGPointData> a = run(node, context, 12, ruined, roads);
	Ref<PCGPointData> b = run(node, context, 12, ruined, roads);
	REQUIRE(a.is_valid());
	CHECK(a->compute_content_hash() == b->compute_content_hash());
	int clutter = 0;
	int lamps = 0;
	for (int i = 0; i < a->get_point_count(); i++) {
		const int asset = (int)a->get_attribute_value("asset", i);
		if (asset == 5) {
			clutter++;
			const int source = (int)a->get_attribute_value("source", i);
			REQUIRE(source >= 0);
			REQUIRE(source < ruined->get_point_count());
			CHECK((int)ruined->get_attribute_value("piece", source) == PCGBuildingNode::PIECE_RUBBLE);
			const Vector3 p = a->get_position(i);
			const Vector3 s = ruined->get_position(source);
			CHECK(Vector2(p.x, p.z).distance_to(Vector2(s.x, s.z)) <= 2.001f);
		} else if (asset == 9) {
			lamps++;
			CHECK(roads->distance_xz(a->get_position(i)) >= 2.0f);
		}
	}
	CHECK(clutter > 0);
	CHECK(lamps >= 9);
}

} // namespace TestPCGWorldNodes
