/**************************************************************************/
/*  test_pcg_graph.h                                                      */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "../pcg_component_3d.h"
#include "../pcg_core_nodes.h"
#include "../pcg_graph_executor.h"

#include "tests/test_macros.h"

namespace TestPCGGraph {

static Ref<PCGGraph> make_scatter_graph(int *r_sampler, int *r_filter, int *r_prune) {
	Ref<PCGGraph> graph;
	graph.instantiate();
	Ref<PCGSurfaceSamplerNode> sampler;
	sampler.instantiate();
	sampler->set_spacing(2.0);
	Ref<PCGDensityNoiseNode> noise;
	noise.instantiate();
	Ref<PCGDensityFilterNode> filter;
	filter.instantiate();
	Ref<PCGSelfPruneNode> prune;
	prune.instantiate();
	prune->set_min_distance(3.0);
	const int a = graph->add_node(sampler);
	const int b = graph->add_node(noise);
	const int c = graph->add_node(filter);
	const int d = graph->add_node(prune);
	graph->connect_nodes(a, b);
	graph->connect_nodes(b, c);
	graph->connect_nodes(c, d);
	*r_sampler = a;
	*r_filter = c;
	*r_prune = d;
	return graph;
}

static Ref<PCGContext> make_context(const AABB &p_bounds, int64_t p_seed = 99) {
	Ref<PCGContext> context;
	context.instantiate();
	context->set_seed(p_seed);
	context->set_bounds(p_bounds);
	return context;
}

TEST_CASE("[PCGGraph] topological order, cycle rejection and output resolution") {
	int s, f, p;
	Ref<PCGGraph> graph = make_scatter_graph(&s, &f, &p);
	const PackedInt32Array order = graph->compute_order();
	REQUIRE(order.size() == 4);
	CHECK(order[0] == s);
	CHECK(order[3] == p);
	CHECK(graph->resolve_output_node_id() == p);
	ERR_PRINT_OFF;
	CHECK(graph->connect_nodes(p, s) == ERR_CYCLIC_LINK);
	CHECK(graph->connect_nodes(s, s) == ERR_CYCLIC_LINK);
	ERR_PRINT_ON;
	CHECK_FALSE(graph->has_cycle());
	CHECK(graph->validate().is_empty());
	graph->remove_node(f);
	CHECK(graph->get_node_count() == 3);
	CHECK(graph->get_input_sources(p)[0] == -1);
}

TEST_CASE("[PCGGraph] seed-based generation is deterministic and changes with the seed") {
	int s, f, p;
	Ref<PCGGraph> graph = make_scatter_graph(&s, &f, &p);
	Ref<PCGGraphExecutor> a;
	a.instantiate();
	Ref<PCGGraphExecutor> b;
	b.instantiate();
	const AABB box(Vector3(0, -10, 0), Vector3(64, 20, 64));
	Ref<PCGPointData> first = a->execute(graph, make_context(box))["output"];
	Ref<PCGPointData> second = b->execute(graph, make_context(box))["output"];
	Ref<PCGPointData> other = b->execute(graph, make_context(box, 1234))["output"];
	REQUIRE(first.is_valid());
	CHECK(first->get_point_count() > 0);
	CHECK(first->compute_content_hash() == second->compute_content_hash());
	CHECK(first->compute_content_hash() != other->compute_content_hash());
}

TEST_CASE("[PCGGraph] tiles are seamless: two halves equal the whole before pruning") {
	Ref<PCGGraph> graph;
	graph.instantiate();
	Ref<PCGSurfaceSamplerNode> sampler;
	sampler.instantiate();
	sampler->set_spacing(3.0);
	Ref<PCGDensityNoiseNode> noise;
	noise.instantiate();
	Ref<PCGDensityFilterNode> filter;
	filter.instantiate();
	const int a = graph->add_node(sampler);
	const int b = graph->add_node(noise);
	const int c = graph->add_node(filter);
	graph->connect_nodes(a, b);
	graph->connect_nodes(b, c);
	Ref<PCGGraphExecutor> executor;
	executor.instantiate();
	Ref<PCGPointData> whole = executor->execute(graph, make_context(AABB(Vector3(0, -1, 0), Vector3(64, 2, 32))))["output"];
	Ref<PCGPointData> left = executor->execute(graph, make_context(AABB(Vector3(0, -1, 0), Vector3(32, 2, 32))))["output"];
	Ref<PCGPointData> right = executor->execute(graph, make_context(AABB(Vector3(32, -1, 0), Vector3(32, 2, 32))))["output"];
	CHECK(left->get_point_count() + right->get_point_count() == whole->get_point_count());
	// Every point of the halves exists in the whole, at the same place.
	int matched = 0;
	for (int i = 0; i < left->get_point_count(); i++) {
		for (int j = 0; j < whole->get_point_count(); j++) {
			if (whole->get_position(j).is_equal_approx(left->get_position(i))) {
				matched++;
				break;
			}
		}
	}
	CHECK(matched == left->get_point_count());
}

TEST_CASE("[PCGGraph] incremental recalculation recomputes only the edited node and downstream") {
	int s, f, p;
	Ref<PCGGraph> graph = make_scatter_graph(&s, &f, &p);
	Ref<PCGGraphExecutor> executor;
	executor.instantiate();
	const AABB box(Vector3(0, -10, 0), Vector3(48, 20, 48));
	Dictionary first = executor->execute(graph, make_context(box));
	CHECK(int(first["cache_misses"]) == 4);
	Dictionary again = executor->execute(graph, make_context(box));
	CHECK(int(again["cache_hits"]) == 4);
	Ref<PCGSelfPruneNode> prune = graph->get_node_by_id(p);
	prune->set_min_distance(5.0);
	Dictionary edited = executor->execute(graph, make_context(box));
	CHECK(int(edited["cache_hits"]) == 3);
	CHECK(int(edited["cache_misses"]) == 1);
	Ref<PCGPointData> denser = again["output"];
	Ref<PCGPointData> sparser = edited["output"];
	CHECK(sparser->get_point_count() < denser->get_point_count());
	executor->clear_cache();
	CHECK(executor->get_cache_size() == 0);
}

TEST_CASE("[PCGGraph] overrides through bound graph parameters") {
	int s, f, p;
	Ref<PCGGraph> graph = make_scatter_graph(&s, &f, &p);
	graph->set_parameter("spacing", 2.0);
	Ref<PCGSurfaceSamplerNode> sampler = graph->get_node_by_id(s);
	sampler->bind_parameter("spacing", "spacing");
	CHECK(graph->validate().is_empty());
	Ref<PCGGraphExecutor> executor;
	executor.instantiate();
	const AABB box(Vector3(0, -10, 0), Vector3(40, 20, 40));
	Dictionary base = executor->execute(graph, make_context(box));
	Ref<PCGContext> sparse = make_context(box);
	Dictionary overrides;
	overrides["spacing"] = 8.0;
	sparse->set_overrides(overrides);
	Dictionary changed = executor->execute(graph, sparse);
	const int base_points = Dictionary(base["point_counts"])[s];
	const int sparse_points = Dictionary(changed["point_counts"])[s];
	CHECK(sparse_points * 8 < base_points);
}

TEST_CASE("[PCGGraph] filters: exclusion volumes, biome masks, spatial queries, asset rules, budgets") {
	Ref<PCGPointData> grid;
	grid.instantiate();
	for (int x = 0; x < 10; x++) {
		for (int z = 0; z < 10; z++) {
			grid->add_point(Vector3(x * 2.0, 0, z * 2.0), Vector3(0, 1, 0), 0.5 + x * 0.05, 0, 1, x * 100 + z);
		}
	}
	Ref<PCGContext> context = make_context(AABB(Vector3(-1, -1, -1), Vector3(30, 2, 30)));
	Array exclusions;
	Dictionary sphere;
	sphere["center"] = Vector3(0, 0, 0);
	sphere["radius"] = 3.0;
	exclusions.push_back(sphere);
	context->set_exclusions(exclusions);
	Vector<Ref<PCGData>> inputs;
	inputs.push_back(grid);

	Ref<PCGExclusionFilterNode> exclusion;
	exclusion.instantiate();
	Ref<PCGPointData> outside = exclusion->execute(inputs, context, 1);
	CHECK(outside->get_point_count() == 100 - 4); // (0,0), (2,0), (0,2), (2,2) lie within 3 m.

	Ref<PCGPointData> others;
	others.instantiate();
	others->add_point(Vector3(10, 0, 10));
	Vector<Ref<PCGData>> two;
	two.push_back(grid);
	two.push_back(others);
	Ref<PCGSpatialQueryNode> query;
	query.instantiate();
	query->set_radius(2.1);
	query->set_mode(PCGSpatialQueryNode::MODE_KEEP_INSIDE);
	Ref<PCGPointData> near = query->execute(two, context, 1);
	CHECK(near->get_point_count() == 5); // The point itself and its four lattice neighbours.

	Ref<PCGCountLimitNode> limit;
	limit.instantiate();
	limit->set_max_points(7);
	Ref<PCGPointData> few = limit->execute(inputs, context, 1);
	CHECK(few->get_point_count() == 7);
	for (int i = 0; i < few->get_point_count(); i++) {
		CHECK(few->get_density(i) >= 0.94f); // Densest column (x = 9) first.
	}

	Array rules;
	Dictionary rock;
	rock["asset"] = 3;
	rock["weight"] = 1.0;
	rock["min_density"] = 0.8;
	rules.push_back(rock);
	Ref<PCGAssetRuleNode> assets;
	assets.instantiate();
	assets->set_rules(rules);
	Ref<PCGPointData> chosen = assets->execute(inputs, context, 1);
	CHECK(chosen->get_point_count() == 40); // x >= 6: density 0.8..0.95
	CHECK(chosen->get_attribute_value("asset", 0) == 3.0f);

	Ref<PCGClusterNode> clusters;
	clusters.instantiate();
	clusters->set_cluster_size(8.0);
	Ref<PCGPointData> grouped = clusters->execute(inputs, context, 1);
	CHECK(grouped->get_attribute_value("cluster", 0) == grouped->get_attribute_value("cluster", 1));
	CHECK(PCGClusterNode::cluster_id(Vector3(1, 0, 1), 8.0) != PCGClusterNode::cluster_id(Vector3(9, 0, 1), 8.0));
	CHECK(grid->get_point_count() == 100); // Inputs are never mutated.
}

TEST_CASE("[PCGGraph] spline sampling along polylines from user data") {
	Ref<PCGContext> context = make_context(AABB(Vector3(-50, -1, -50), Vector3(100, 2, 100)));
	Dictionary user;
	PackedVector3Array road;
	road.push_back(Vector3(0, 0, 0));
	road.push_back(Vector3(30, 0, 0));
	Array roads;
	roads.push_back(road);
	user["roads"] = roads;
	context->set_user_data(user);
	Ref<PCGSplineSamplerNode> sampler;
	sampler.instantiate();
	sampler->set_spacing(5.0);
	sampler->set_lateral_offset(2.0);
	Vector<Ref<PCGData>> none;
	Ref<PCGPointData> posts = sampler->execute(none, context, 7);
	CHECK(posts->get_point_count() == 12); // 6 stations x 2 sides.
	for (int i = 0; i < posts->get_point_count(); i++) {
		CHECK(Math::is_equal_approx(Math::abs(posts->get_position(i).z), 2.0f));
	}
	Ref<PCGSplineData> spline = PCGSplineSamplerNode::spline_from_variant(roads);
	CHECK(Math::is_equal_approx(spline->distance_xz(Vector3(15, 0, 4)), 4.0f));
}

TEST_CASE("[PCGGraph] async execution matches synchronous execution") {
	int s, f, p;
	Ref<PCGGraph> graph = make_scatter_graph(&s, &f, &p);
	Ref<PCGGraphExecutor> executor;
	executor.instantiate();
	executor->set_cache_enabled(false);
	const AABB box(Vector3(-20, -10, -20), Vector3(40, 20, 40));
	Ref<PCGPointData> sync = executor->execute(graph, make_context(box))["output"];
	const int64_t job = executor->execute_async(graph, make_context(box));
	Dictionary result = executor->wait_for_job(job);
	Ref<PCGPointData> async = result["output"];
	REQUIRE(async.is_valid());
	CHECK(async->compute_content_hash() == sync->compute_content_hash());
	CHECK(executor->is_job_done(job));
}

TEST_CASE("[PCGGraph] profiling and debug capture") {
	int s, f, p;
	Ref<PCGGraph> graph = make_scatter_graph(&s, &f, &p);
	Ref<PCGGraphExecutor> executor;
	executor.instantiate();
	Ref<PCGContext> context = make_context(AABB(Vector3(0, -1, 0), Vector3(32, 2, 32)));
	context->set_debug(true);
	Dictionary result = executor->execute(graph, context);
	CHECK(Dictionary(result["timings_usec"]).size() == 4);
	CHECK(Dictionary(result["node_outputs"]).size() == 4);
	const String profile = PCGGraphExecutor::format_profile(graph, result);
	CHECK(profile.contains("SurfaceSampler"));
	CHECK(profile.contains("cache hits"));
}

TEST_CASE("[PCGComponent3D] instance grouping by asset and cluster") {
	Ref<PCGPointData> points;
	points.instantiate();
	points->add_point(Vector3(0, 0, 0));
	points->add_point(Vector3(1, 0, 0));
	points->add_point(Vector3(100, 0, 0));
	PackedFloat32Array assets;
	assets.push_back(0);
	assets.push_back(1);
	assets.push_back(0);
	points->set_attribute("asset", assets);
	PackedFloat32Array clusters;
	clusters.push_back(5);
	clusters.push_back(5);
	clusters.push_back(9);
	points->set_attribute("cluster", clusters);
	const Dictionary grouped = PCGComponent3D::group_instances(points, true);
	CHECK(grouped.size() == 3);
	CHECK(PackedInt32Array(grouped["0:5"]).size() == 1);
	const Dictionary flat = PCGComponent3D::group_instances(points, false);
	CHECK(PackedInt32Array(flat["0:0"]).size() == 2);
	CHECK(PCGComponent3D::cell_of(Vector3(-1, 0, 65), 64.0) == Vector2i(-1, 1));
}

} // namespace TestPCGGraph
