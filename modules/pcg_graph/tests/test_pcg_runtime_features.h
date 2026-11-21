/**************************************************************************/
/*  test_pcg_runtime_features.h                                           */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "../pcg_component_3d.h"
#include "../pcg_core_nodes.h"
#include "../pcg_exclusion_volume_3d.h"
#include "../pcg_graph_executor.h"

#include "core/object/callable_mp.h"
#include "scene/3d/multimesh_instance_3d.h"
#include "scene/main/window.h"
#include "scene/resources/3d/primitive_meshes.h"
#include "tests/test_macros.h"

namespace TestPCGRuntimeFeatures {

static float ramp_height(float p_x, float p_z) {
	return p_x * 0.25f + p_z * 0.1f;
}

static bool west_is_water(float p_x, float p_z) {
	return p_x < 4.0f;
}

static Ref<PCGGraph> sampler_graph(float p_spacing) {
	Ref<PCGGraph> graph;
	graph.instantiate();
	Ref<PCGSurfaceSamplerNode> sampler;
	sampler.instantiate();
	sampler->set_spacing(p_spacing);
	Ref<PCGExclusionFilterNode> exclusion;
	exclusion.instantiate();
	const int a = graph->add_node(sampler);
	const int b = graph->add_node(exclusion);
	graph->connect_nodes(a, b);
	return graph;
}

TEST_CASE("[PCGRuntime] baked environment grids reproduce the samplers without calling them") {
	Ref<PCGContext> context;
	context.instantiate();
	context->set_height_sampler(callable_mp_static(&ramp_height));
	context->set_water_sampler(callable_mp_static(&west_is_water));
	context->bake_environment(Rect2(0, 0, 32, 32), 2.0);
	REQUIRE(context->has_baked_environment());
	CHECK(context->get_baked_area().has_point(Vector2(-3.9, -3.9))); // Grown by two steps.
	// Samplers gone: grid answers alone (what a worker thread sees).
	context->set_height_sampler(Callable());
	context->set_water_sampler(Callable());
	CHECK(Math::is_equal_approx(context->sample_height(10.0, 6.0), ramp_height(10.0, 6.0)));
	CHECK(Math::is_equal_approx(context->sample_height(11.3, 7.7), ramp_height(11.3, 7.7))); // Bilinear is exact on a plane.
	CHECK(context->sample_water(0.0, 10.0));
	CHECK_FALSE(context->sample_water(20.0, 10.0));
	const Vector3 n = context->sample_normal(16.0, 16.0);
	CHECK(n.y > 0.9f);
	CHECK(n.x < 0.0f); // Ground rises to +x, so the normal leans to -x.
	Ref<PCGContext> copy = context->duplicate_context();
	CHECK(copy->has_baked_environment());
	CHECK(Math::is_equal_approx(copy->sample_height(10.0, 6.0), context->sample_height(10.0, 6.0)));
	context->clear_baked_environment();
	CHECK_FALSE(context->has_baked_environment());
	CHECK(context->sample_height(10.0, 6.0) == 0.0f);
}

TEST_CASE("[PCGRuntime] graphs with parameters keep baked grids through the executor") {
	Ref<PCGGraph> graph = sampler_graph(4.0);
	graph->set_parameter("unused", 1.0); // Forces the executor to layer overrides on a context copy.
	Ref<PCGContext> context;
	context.instantiate();
	context->set_bounds(AABB(Vector3(0, -50, 0), Vector3(32, 100, 32)));
	context->set_height_sampler(callable_mp_static(&ramp_height));
	context->bake_environment(Rect2(0, 0, 32, 32), 1.0);
	context->set_height_sampler(Callable());
	Ref<PCGGraphExecutor> executor;
	executor.instantiate();
	Ref<PCGPointData> points = executor->execute(graph, context)["output"];
	REQUIRE(points->get_point_count() > 0);
	for (int i = 0; i < points->get_point_count(); i++) {
		const Vector3 p = points->get_position(i);
		CHECK(Math::is_equal_approx(p.y, ramp_height(p.x, p.z), 0.001f));
	}
}

TEST_CASE("[SceneTree][PCGRuntime] exclusion volumes in the scene are gathered by overlap") {
	Window *root = SceneTree::get_singleton()->get_root();
	PCGExclusionVolume3D *box = memnew(PCGExclusionVolume3D);
	box->set_size(Vector3(4, 4, 4));
	root->add_child(box);
	box->set_global_position(Vector3(10, 0, 10));
	PCGExclusionVolume3D *cylinder = memnew(PCGExclusionVolume3D);
	cylinder->set_shape(PCGExclusionVolume3D::SHAPE_CYLINDER);
	cylinder->set_radius(3.0);
	root->add_child(cylinder);
	cylinder->set_global_position(Vector3(100, 0, 100));

	const Array near = PCGExclusionVolume3D::gather(SceneTree::get_singleton(), AABB(Vector3(0, -10, 0), Vector3(16, 20, 16)));
	REQUIRE(near.size() == 1);
	CHECK(AABB(near[0]).has_point(Vector3(11, 0, 11)));
	const Array far = PCGExclusionVolume3D::gather(SceneTree::get_singleton(), AABB(Vector3(95, -10, 95), Vector3(4, 20, 4)));
	REQUIRE(far.size() == 1);
	CHECK(Dictionary(far[0]).has("radius"));
	cylinder->set_active(false);
	CHECK(PCGExclusionVolume3D::gather(SceneTree::get_singleton(), AABB(Vector3(95, -10, 95), Vector3(4, 20, 4))).is_empty());

	// A component in the tree picks the box up: no points inside it.
	PCGComponent3D *component = memnew(PCGComponent3D);
	component->set_graph(sampler_graph(1.0));
	component->set_extents(Vector3(16, 50, 16));
	root->add_child(component);
	component->set_global_position(Vector3(8, 0, 8));
	component->generate();
	Ref<PCGPointData> points = component->get_all_points();
	REQUIRE(points->get_point_count() > 0);
	for (int i = 0; i < points->get_point_count(); i++) {
		CHECK_FALSE(box->get_world_aabb().has_point(points->get_position(i)));
	}
	memdelete(component);
	memdelete(cylinder);
	memdelete(box);
}

TEST_CASE("[PCGRuntime] point data survives the on-disk form and corrupt data is rejected") {
	Ref<PCGPointData> points;
	points.instantiate();
	points->add_point(Vector3(1, 2, 3), Vector3(0, 1, 0), 0.5, 1.0, 2.0, 77);
	points->set_attribute_value("asset", 0, 4.0);
	Ref<PCGPointData> back = PCGPointData::from_dictionary(points->to_dictionary());
	REQUIRE(back.is_valid());
	CHECK(back->compute_content_hash() == points->compute_content_hash());
	Dictionary broken = points->to_dictionary();
	broken["yaw"] = PackedFloat32Array();
	CHECK(PCGPointData::from_dictionary(broken).is_null());
	Dictionary foreign;
	CHECK(PCGPointData::from_dictionary(foreign).is_null());
}

TEST_CASE("[PCGRuntime] persistent cell cache: second component loads instead of generating") {
	const String dir = vformat("user://pcg_test_cache_%d", (int64_t)OS::get_singleton()->get_ticks_usec());
	Ref<PCGGraph> graph = sampler_graph(4.0);
	PCGComponent3D *first = memnew(PCGComponent3D);
	first->set_graph(graph);
	first->set_streaming_enabled(true);
	first->set_cell_size(32.0);
	first->set_persistent_cache_dir(dir);
	Ref<PCGPointData> made = first->generate_cell(Vector2i(2, -1));
	REQUIRE(made.is_valid());
	CHECK(int(first->get_cache_stats()["saves"]) == 1);
	CHECK(int(first->get_cache_stats()["loads"]) == 0);

	PCGComponent3D *second = memnew(PCGComponent3D);
	second->set_graph(graph);
	second->set_streaming_enabled(true);
	second->set_cell_size(32.0);
	second->set_persistent_cache_dir(dir);
	Ref<PCGPointData> loaded = second->generate_cell(Vector2i(2, -1));
	REQUIRE(loaded.is_valid());
	CHECK(int(second->get_cache_stats()["loads"]) == 1);
	CHECK(loaded->compute_content_hash() == made->compute_content_hash());

	const int64_t key = second->compute_cell_cache_key(Vector2i(2, -1));
	second->set_generation_seed(4242);
	CHECK(second->compute_cell_cache_key(Vector2i(2, -1)) != key);
	second->set_generation_seed(1337);
	second->set_cache_version(2);
	CHECK(second->compute_cell_cache_key(Vector2i(2, -1)) != key);
	Ref<PCGSurfaceSamplerNode> sampler = graph->get_node_by_id(graph->get_node_ids()[0]);
	sampler->set_spacing(5.0);
	second->set_cache_version(0);
	CHECK(second->compute_cell_cache_key(Vector2i(2, -1)) != key); // Graph edits change the fingerprint.

	CHECK(first->clear_persistent_cache() == 1);
	memdelete(first);
	memdelete(second);
}

TEST_CASE("[SceneTree][PCGRuntime] HLOD proxies and runtime debug draw") {
	Window *root = SceneTree::get_singleton()->get_root();
	Ref<PCGGraph> graph = sampler_graph(4.0);
	PCGComponent3D *component = memnew(PCGComponent3D);
	component->set_graph(graph);
	component->set_extents(Vector3(8, 50, 8));
	component->set_use_scene_exclusion_volumes(false);
	Ref<BoxMesh> detail;
	detail.instantiate();
	Ref<BoxMesh> proxy;
	proxy.instantiate();
	TypedArray<Mesh> meshes;
	meshes.push_back(detail);
	TypedArray<Mesh> proxies;
	proxies.push_back(proxy);
	component->set_asset_meshes(meshes);
	component->set_asset_proxy_meshes(proxies);
	component->set_visibility_range_end(50.0);
	component->set_proxy_range_end(400.0);
	component->set_debug_draw(true);
	root->add_child(component);
	component->generate();
	Node3D *cell = Object::cast_to<Node3D>(component->get_child(0, true));
	REQUIRE(cell != nullptr);
	int detail_count = 0;
	int proxy_count = 0;
	int debug_count = 0;
	for (int i = 0; i < cell->get_child_count(); i++) {
		MultiMeshInstance3D *mmi = Object::cast_to<MultiMeshInstance3D>(cell->get_child(i));
		if (mmi != nullptr) {
			if (String(mmi->get_name()).ends_with("_hlod")) {
				proxy_count++;
				CHECK(Math::is_equal_approx(mmi->get_visibility_range_begin(), 50.0f));
				CHECK(Math::is_equal_approx(mmi->get_visibility_range_end(), 400.0f));
				CHECK(mmi->get_cast_shadows_setting() == GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
			} else {
				detail_count++;
				CHECK(Math::is_equal_approx(mmi->get_visibility_range_end(), 50.0f));
			}
		} else if (String(cell->get_child(i)->get_name()) == "PCGDebugPoints") {
			debug_count++;
		}
	}
	CHECK(detail_count == 1);
	CHECK(proxy_count == 1);
	CHECK(debug_count == 1);
	memdelete(component);
}

} // namespace TestPCGRuntimeFeatures
