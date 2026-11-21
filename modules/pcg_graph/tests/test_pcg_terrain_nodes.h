/**************************************************************************/
/*  test_pcg_terrain_nodes.h                                              */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "../pcg_core_nodes.h"
#include "../pcg_terrain_nodes.h"

#include "core/object/callable_mp.h"
#include "core/templates/hash_map.h"
#include "tests/test_macros.h"

namespace TestPCGTerrainNodes {

static Ref<PCGContext> make_context(const AABB &p_bounds, int64_t p_seed = 77) {
	Ref<PCGContext> context;
	context.instantiate();
	context->set_seed(p_seed);
	context->set_bounds(p_bounds);
	return context;
}

static Ref<PCGPointData> run_node(const Ref<PCGNode> &p_node, const Ref<PCGPointData> &p_input, const Ref<PCGContext> &p_context, uint64_t p_seed) {
	Vector<Ref<PCGData>> inputs;
	if (p_input.is_valid()) {
		inputs.push_back(p_input);
	}
	Ref<PCGData> result = p_node->execute(inputs, p_context, p_seed);
	Ref<PCGPointData> points = result;
	return points;
}

// Regular candidate grid with stable seeds.
static Ref<PCGPointData> make_grid(int p_count_x, int p_count_z, float p_step, float p_y = 0.0f) {
	Ref<PCGPointData> points;
	points.instantiate();
	for (int z = 0; z < p_count_z; z++) {
		for (int x = 0; x < p_count_x; x++) {
			points->add_point(Vector3(float(x) * p_step, p_y, float(z) * p_step), Vector3(0, 1, 0), 1.0, 0.0, 1.0, int64_t(z) * 1000 + x + 1);
		}
	}
	return points;
}

static float slope_height(float p_x, float p_z) {
	return 0.5f * p_x;
}

static String half_biome(float p_x, float p_z) {
	return p_x < 50.0f ? String("forest") : String("desert");
}

TEST_CASE("[PCGTerrain] heightfield is deterministic, seed dependent and fills height01") {
	Ref<PCGHeightfieldNode> node;
	node.instantiate();
	node->set_spacing(2.0);
	node->set_amplitude(30.0);
	const Ref<PCGContext> context = make_context(AABB(Vector3(0, -50, 0), Vector3(64, 100, 64)));
	Ref<PCGPointData> a = run_node(node, Ref<PCGPointData>(), context, 5);
	Ref<PCGPointData> b = run_node(node, Ref<PCGPointData>(), context, 5);
	Ref<PCGPointData> c = run_node(node, Ref<PCGPointData>(), context, 6);
	REQUIRE(a.is_valid());
	CHECK(a->get_point_count() == 32 * 32);
	CHECK(a->get_content_hash() == b->get_content_hash());
	CHECK(a->get_content_hash() != c->get_content_hash());
	CHECK(a->has_attribute("height01"));
	for (int i = 0; i < a->get_point_count(); i++) {
		const float h01 = a->get_attribute_value("height01", i);
		CHECK(h01 >= 0.0f);
		CHECK(h01 <= 1.0f);
		CHECK(Math::is_equal_approx(a->get_position(i).y, h01 * 30.0f));
		CHECK(a->get_normal(i).y > 0.0f);
		CHECK(Math::is_equal_approx(a->get_normal(i).length(), 1.0f));
	}
}

TEST_CASE("[PCGTerrain] heightfield tiles seamlessly, also with ridges, terraces and thermal erosion") {
	Ref<PCGHeightfieldNode> node;
	node.instantiate();
	node->set_spacing(2.0);
	node->set_ridged(true);
	node->set_terrace_steps(5);
	node->set_erosion_iterations(4);
	node->set_talus_angle(15.0);
	node->set_amplitude(40.0);
	node->set_frequency(0.03);
	const Ref<PCGPointData> whole = run_node(node, Ref<PCGPointData>(), make_context(AABB(Vector3(0, -50, 0), Vector3(64, 100, 32))), 11);
	const Ref<PCGPointData> left = run_node(node, Ref<PCGPointData>(), make_context(AABB(Vector3(0, -50, 0), Vector3(32, 100, 32))), 11);
	const Ref<PCGPointData> right = run_node(node, Ref<PCGPointData>(), make_context(AABB(Vector3(32, -50, 0), Vector3(32, 100, 32))), 11);
	REQUIRE(whole->get_point_count() > 0);
	CHECK(left->get_point_count() + right->get_point_count() == whole->get_point_count());
	int matched = 0;
	for (const Ref<PCGPointData> &half : { left, right }) {
		for (int i = 0; i < half->get_point_count(); i++) {
			for (int j = 0; j < whole->get_point_count(); j++) {
				if (whole->get_position(j) == half->get_position(i)) {
					CHECK(whole->get_normal(j) == half->get_normal(i));
					CHECK(whole->get_attribute_value("height01", j) == half->get_attribute_value("height01", i));
					matched++;
					break;
				}
			}
		}
	}
	CHECK(matched == whole->get_point_count());
}

TEST_CASE("[PCGTerrain] thermal erosion lowers the steepest slopes") {
	Ref<PCGHeightfieldNode> raw;
	raw.instantiate();
	raw->set_ridged(true);
	raw->set_amplitude(60.0);
	raw->set_frequency(0.05);
	Ref<PCGHeightfieldNode> eroded;
	eroded.instantiate();
	eroded->set_ridged(true);
	eroded->set_amplitude(60.0);
	eroded->set_frequency(0.05);
	eroded->set_erosion_iterations(16);
	eroded->set_talus_angle(10.0);
	const Ref<PCGContext> context = make_context(AABB(Vector3(0, -100, 0), Vector3(64, 200, 64)));
	const Ref<PCGPointData> a = run_node(raw, Ref<PCGPointData>(), context, 3);
	const Ref<PCGPointData> b = run_node(eroded, Ref<PCGPointData>(), context, 3);
	float steepest_raw = 0.0f;
	float steepest_eroded = 0.0f;
	for (int i = 0; i < a->get_point_count(); i++) {
		steepest_raw = MAX(steepest_raw, 1.0f - a->get_normal(i).y);
		steepest_eroded = MAX(steepest_eroded, 1.0f - b->get_normal(i).y);
	}
	CHECK(steepest_eroded < steepest_raw);
}

TEST_CASE("[PCGTerrain] terrain sample takes height and normal from the context and adds slope") {
	Ref<PCGTerrainSampleNode> node;
	node.instantiate();
	Ref<PCGContext> context = make_context(AABB(Vector3(0, -50, 0), Vector3(64, 100, 64)));
	context->set_height_sampler(callable_mp_static(&slope_height));
	const Ref<PCGPointData> input = make_grid(4, 4, 3.0f, 99.0f);
	const uint64_t input_hash = input->get_content_hash();
	const Ref<PCGPointData> out = run_node(node, input, context, 1);
	CHECK(input->get_content_hash() == input_hash); // Inputs are never mutated.
	REQUIRE(out->get_point_count() == 16);
	const float expected_slope = Math::rad_to_deg(Math::atan(0.5f));
	for (int i = 0; i < out->get_point_count(); i++) {
		const Vector3 p = out->get_position(i);
		CHECK(Math::is_equal_approx(p.y, 0.5f * p.x));
		CHECK(Math::is_equal_approx(out->get_attribute_value("height", i), 0.5f * p.x));
		CHECK(Math::abs(out->get_attribute_value("slope", i) - expected_slope) < 0.01f);
		CHECK(out->get_seed(i) == input->get_seed(i));
	}
}

TEST_CASE("[PCGTerrain] biome classification follows the rule table") {
	Array rules;
	Dictionary cold;
	cold["index"] = 0;
	cold["max_temp"] = 0.4;
	rules.push_back(cold);
	Dictionary dry;
	dry["index"] = 1;
	dry["min_temp"] = 0.4;
	dry["max_moisture"] = 0.5;
	rules.push_back(dry);
	Dictionary wet;
	wet["index"] = 2;
	wet["min_temp"] = 0.4;
	wet["min_moisture"] = 0.5;
	rules.push_back(wet);

	Ref<PCGBiomeClassifyNode> node;
	node.instantiate();
	node->set_rules(rules);
	node->set_temperature_frequency(0.08);
	node->set_moisture_frequency(0.09);
	node->set_default_biome(9);
	const Ref<PCGContext> context = make_context(AABB(Vector3(0, -10, 0), Vector3(200, 400, 200)));
	const Ref<PCGPointData> input = make_grid(20, 20, 9.0f, 0.0f);
	const Ref<PCGPointData> out = run_node(node, input, context, 21);
	const Ref<PCGPointData> again = run_node(node, input, context, 21);
	CHECK(out->get_content_hash() == again->get_content_hash());
	REQUIRE(out->get_point_count() == 400);
	for (int i = 0; i < out->get_point_count(); i++) {
		const float t = out->get_attribute_value("temperature", i);
		const float m = out->get_attribute_value("moisture", i);
		const int biome = (int)out->get_attribute_value("biome", i);
		CHECK(biome == PCGBiomeClassifyNode::classify(rules, t, m, 9));
		if (biome == 0) {
			CHECK(t <= 0.4f);
		} else if (biome == 1) {
			CHECK(t >= 0.4f);
			CHECK(m <= 0.5f);
		} else {
			CHECK(biome == 2);
			CHECK(t >= 0.4f);
			CHECK(m >= 0.5f);
		}
	}
	// Altitude lapse rate: very high points are always cold.
	Ref<PCGBiomeClassifyNode> mountain;
	mountain.instantiate();
	mountain->set_rules(rules);
	mountain->set_temperature_frequency(0.08);
	mountain->set_moisture_frequency(0.09);
	mountain->set_default_biome(9);
	mountain->set_lapse_rate(1.0);
	const Ref<PCGPointData> high = run_node(mountain, make_grid(10, 10, 9.0f, 100.0f), context, 21);
	for (int i = 0; i < high->get_point_count(); i++) {
		CHECK((int)high->get_attribute_value("biome", i) == 0);
	}
	// Rules that match nothing fall back to the default biome.
	CHECK(PCGBiomeClassifyNode::classify(Array(), 0.5f, 0.5f, 9) == 9);
}

TEST_CASE("[PCGTerrain] biome classification can map the context biome sampler to indices") {
	Ref<PCGBiomeClassifyNode> node;
	node.instantiate();
	node->set_use_context_biome(true);
	Dictionary names;
	names["forest"] = 3;
	names["desert"] = 7;
	node->set_biome_names(names);
	Ref<PCGContext> context = make_context(AABB(Vector3(0, -10, 0), Vector3(100, 100, 100)));
	context->set_biome_sampler(callable_mp_static(&half_biome));
	const Ref<PCGPointData> out = run_node(node, make_grid(10, 4, 10.0f), context, 2);
	REQUIRE(out->get_point_count() == 40);
	for (int i = 0; i < out->get_point_count(); i++) {
		const int expected = out->get_position(i).x < 50.0f ? 3 : 7;
		CHECK((int)out->get_attribute_value("biome", i) == expected);
	}
}

TEST_CASE("[PCGTerrain] vegetation layers keep spacing and the understory avoids the canopy") {
	Ref<PCGVegetationNode> node;
	node.instantiate();
	Array assets_a;
	assets_a.push_back(10);
	assets_a.push_back(11);
	Array assets_b;
	assets_b.push_back(20);
	Dictionary canopy;
	canopy["density"] = 1.0;
	canopy["min_spacing"] = 5.0;
	canopy["avoid_radius"] = 0.0;
	canopy["assets"] = assets_a;
	canopy["scale_min"] = 1.0;
	canopy["scale_max"] = 2.0;
	Dictionary understory;
	understory["density"] = 1.0;
	understory["min_spacing"] = 2.0;
	understory["avoid_radius"] = 3.0;
	understory["assets"] = assets_b;
	understory["scale_min"] = 0.5;
	understory["scale_max"] = 0.75;
	Array layers;
	layers.push_back(canopy);
	layers.push_back(understory);
	node->set_layers(layers);

	const Ref<PCGPointData> input = make_grid(40, 40, 1.0f);
	const uint64_t input_hash = input->get_content_hash();
	const Ref<PCGContext> context = make_context(AABB(Vector3(0, -1, 0), Vector3(40, 2, 40)));
	const Ref<PCGPointData> out = run_node(node, input, context, 8);
	const Ref<PCGPointData> again = run_node(node, input, context, 8);
	CHECK(input->get_content_hash() == input_hash);
	CHECK(out->get_content_hash() == again->get_content_hash());
	REQUIRE(out->get_point_count() > 10);

	int canopy_count = 0;
	int understory_count = 0;
	for (int i = 0; i < out->get_point_count(); i++) {
		const int layer = (int)out->get_attribute_value("layer", i);
		const int asset = (int)out->get_attribute_value("asset", i);
		if (layer == 0) {
			canopy_count++;
			CHECK((asset == 10 || asset == 11));
			CHECK(out->get_scale(i) >= 1.0f);
			CHECK(out->get_scale(i) <= 2.0f);
		} else {
			CHECK(layer == 1);
			understory_count++;
			CHECK(asset == 20);
			CHECK(out->get_scale(i) >= 0.5f);
			CHECK(out->get_scale(i) <= 0.75f);
		}
		for (int j = i + 1; j < out->get_point_count(); j++) {
			const int other_layer = (int)out->get_attribute_value("layer", j);
			const float distance = out->get_position(i).distance_to(out->get_position(j));
			if (layer == other_layer) {
				CHECK(distance >= (layer == 0 ? 5.0f : 2.0f));
			} else {
				CHECK(distance >= 3.0f);
			}
		}
	}
	CHECK(canopy_count > 0);
	CHECK(understory_count > 0);
}

TEST_CASE("[PCGTerrain] caves are deterministic and expose floor and wall surfaces") {
	Ref<PCGCaveNode> node;
	node.instantiate();
	const Ref<PCGContext> context = make_context(AABB(Vector3(0, 0, 0), Vector3(24, 12, 24)));
	const Ref<PCGPointData> a = run_node(node, Ref<PCGPointData>(), context, 4);
	const Ref<PCGPointData> b = run_node(node, Ref<PCGPointData>(), context, 4);
	const Ref<PCGPointData> c = run_node(node, Ref<PCGPointData>(), context, 5);
	REQUIRE(a->get_point_count() > 0);
	CHECK(a->get_content_hash() == b->get_content_hash());
	CHECK(a->get_content_hash() != c->get_content_hash());
	bool any_floor = false;
	bool any_wall = false;
	for (int i = 0; i < a->get_point_count(); i++) {
		any_floor = any_floor || a->get_attribute_value("cave_floor", i) > 0.5f;
		any_wall = any_wall || a->get_attribute_value("cave_wall", i) > 0.5f;
		CHECK(Math::is_equal_approx(a->get_normal(i).length(), 1.0f));
	}
	CHECK(any_floor);
	CHECK(any_wall);
}

static void check_cave_tiling(const Ref<PCGCaveNode> &p_node) {
	const Ref<PCGPointData> whole = run_node(p_node, Ref<PCGPointData>(), make_context(AABB(Vector3(0, 0, 0), Vector3(32, 12, 24))), 9);
	const Ref<PCGPointData> left = run_node(p_node, Ref<PCGPointData>(), make_context(AABB(Vector3(0, 0, 0), Vector3(16, 12, 24))), 9);
	const Ref<PCGPointData> right = run_node(p_node, Ref<PCGPointData>(), make_context(AABB(Vector3(16, 0, 0), Vector3(16, 12, 24))), 9);
	REQUIRE(whole->get_point_count() > 0);
	CHECK(left->get_point_count() + right->get_point_count() == whole->get_point_count());
	HashMap<int64_t, int> by_seed;
	for (int j = 0; j < whole->get_point_count(); j++) {
		by_seed[whole->get_seed(j)] = j;
	}
	int matched = 0;
	for (const Ref<PCGPointData> &half : { left, right }) {
		for (int i = 0; i < half->get_point_count(); i++) {
			if (!by_seed.has(half->get_seed(i))) {
				continue;
			}
			const int j = by_seed[half->get_seed(i)];
			CHECK(whole->get_position(j) == half->get_position(i));
			CHECK(whole->get_normal(j) == half->get_normal(i));
			CHECK(whole->get_attribute_value("cave_floor", j) == half->get_attribute_value("cave_floor", i));
			CHECK(whole->get_attribute_value("cave_wall", j) == half->get_attribute_value("cave_wall", i));
			matched++;
		}
	}
	CHECK(matched == whole->get_point_count());
}

TEST_CASE("[PCGTerrain] cave voxels tile seamlessly across bounds") {
	Ref<PCGCaveNode> node;
	node.instantiate();
	check_cave_tiling(node);
}

TEST_CASE("[PCGTerrain] cave worm tunnels are world-anchored and tile seamlessly") {
	Ref<PCGCaveNode> node;
	node.instantiate();
	node->set_worms_per_region(2);
	node->set_worm_length(24);
	node->set_worm_region(16);
	check_cave_tiling(node);
	// Worms open more space than the plain automaton.
	Ref<PCGCaveNode> plain;
	plain.instantiate();
	plain->set_worm_length(24);
	plain->set_worm_region(16);
	const Ref<PCGContext> context = make_context(AABB(Vector3(0, 0, 0), Vector3(32, 12, 24)));
	const Ref<PCGPointData> with_worms = run_node(node, Ref<PCGPointData>(), context, 9);
	const Ref<PCGPointData> without = run_node(plain, Ref<PCGPointData>(), context, 9);
	CHECK(with_worms->get_content_hash() != without->get_content_hash());
}

TEST_CASE("[PCGTerrain] dungeon rooms never overlap and every room is reachable") {
	const Rect2i area(0, 0, 64, 64);
	for (int64_t seed = 1; seed <= 25; seed++) {
		const Dictionary layout = PCGDungeonNode::generate_layout(seed, area, 4, 10, 4, 1);
		const Array rooms = layout["rooms"];
		const Array corridors = layout["corridors"];
		REQUIRE(rooms.size() >= 2);
		CHECK(corridors.size() == rooms.size() - 1);
		for (int i = 0; i < rooms.size(); i++) {
			const Rect2i a = rooms[i];
			CHECK(a.size.x >= 4);
			CHECK(a.size.y >= 4);
			CHECK(area.encloses(a));
			for (int j = i + 1; j < rooms.size(); j++) {
				const Rect2i b = rooms[j];
				CHECK_FALSE(a.intersects(b));
			}
		}
		const Dictionary same = PCGDungeonNode::generate_layout(seed, area, 4, 10, 4, 1);
		CHECK(Variant(layout).hash() == Variant(same).hash());
	}
	CHECK(Variant(PCGDungeonNode::generate_layout(1, area)).hash() != Variant(PCGDungeonNode::generate_layout(2, area)).hash());
}

TEST_CASE("[PCGTerrain] dungeon tiles form one connected walkable component with floor, door and corridor kinds") {
	Ref<PCGDungeonNode> node;
	node.instantiate();
	const Ref<PCGContext> context = make_context(AABB(Vector3(0, 0, 0), Vector3(64, 4, 64)));
	for (uint64_t seed = 1; seed <= 10; seed++) {
		const Ref<PCGPointData> out = run_node(node, Ref<PCGPointData>(), context, seed);
		const Ref<PCGPointData> again = run_node(node, Ref<PCGPointData>(), context, seed);
		CHECK(out->get_content_hash() == again->get_content_hash());
		REQUIRE(out->get_point_count() > 0);
		HashMap<Vector2i, int> tiles;
		int floors = 0;
		int doors = 0;
		int corridors = 0;
		for (int i = 0; i < out->get_point_count(); i++) {
			const Vector3 p = out->get_position(i);
			const Vector2i cell((int)Math::floor(p.x), (int)Math::floor(p.z));
			CHECK_FALSE(tiles.has(cell)); // One point per tile.
			tiles[cell] = i;
			const int kind = (int)out->get_attribute_value("kind", i);
			const int room = (int)out->get_attribute_value("room", i);
			if (kind == 0) {
				floors++;
				CHECK(room >= 0);
			} else if (kind == 1) {
				doors++;
				CHECK(room >= 0);
			} else {
				CHECK(kind == 2);
				corridors++;
				CHECK(room == -1);
			}
		}
		CHECK(floors > 0);
		CHECK(doors > 0);
		CHECK(corridors + doors > 0);
		// Flood fill (4-neighbourhood) from the first tile must reach every tile.
		HashMap<Vector2i, int> seen;
		LocalVector<Vector2i> stack;
		const Vector3 first = out->get_position(0);
		const Vector2i start((int)Math::floor(first.x), (int)Math::floor(first.z));
		stack.push_back(start);
		seen[start] = 1;
		while (!stack.is_empty()) {
			const Vector2i cell = stack[stack.size() - 1];
			stack.remove_at(stack.size() - 1);
			const Vector2i steps[4] = { Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1) };
			for (int k = 0; k < 4; k++) {
				const Vector2i next = cell + steps[k];
				if (tiles.has(next) && !seen.has(next)) {
					seen[next] = 1;
					stack.push_back(next);
				}
			}
		}
		CHECK((int)seen.size() == out->get_point_count());
	}
}

TEST_CASE("[PCGTerrain] GPU density equals the CPU path (headless fallback) and the value noise node") {
	Ref<PCGGpuDensityNode> gpu;
	gpu.instantiate();
	Ref<PCGDensityNoiseNode> cpu;
	cpu.instantiate();
	const Ref<PCGContext> context = make_context(AABB(Vector3(-100, -10, -100), Vector3(400, 20, 400)));
	const Ref<PCGPointData> input = make_grid(30, 30, 7.3f, 0.0f);
	const Ref<PCGPointData> gpu_out = run_node(gpu, input, context, 31);
	const Ref<PCGPointData> cpu_out = run_node(cpu, input, context, 31);
	REQUIRE(gpu_out->get_point_count() == cpu_out->get_point_count());
	if (!PCGGpuDensityNode::is_gpu_available()) {
		// Headless: exactly the CPU result.
		CHECK(gpu_out->get_content_hash() == cpu_out->get_content_hash());
		bool used_gpu = true;
		PCGGpuDensityNode::compute_noise(1, input->get_positions(), 0.02f, 3, true, &used_gpu);
		CHECK_FALSE(used_gpu);
	} else {
		// Real device: float32 shader, equal up to rounding.
		for (int i = 0; i < gpu_out->get_point_count(); i++) {
			CHECK(Math::abs(gpu_out->get_density(i) - cpu_out->get_density(i)) < 0.01f);
		}
	}
	// Forcing the CPU path always matches exactly.
	gpu->set_use_gpu(false);
	CHECK(run_node(gpu, input, context, 31)->get_content_hash() == cpu_out->get_content_hash());
	// The noise matches PCGDensityNoiseNode::value_noise value by value.
	const PackedFloat32Array noise = PCGGpuDensityNode::compute_noise(31, input->get_positions(), 0.02f, 3, false);
	for (int i = 0; i < noise.size(); i++) {
		const Vector3 p = input->get_position(i);
		CHECK(noise[i] == PCGDensityNoiseNode::value_noise(31, p.x, p.z, 0.02f, 3));
	}
}

} // namespace TestPCGTerrainNodes
