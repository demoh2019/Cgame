/**************************************************************************/
/*  test_chunked_terrain_3d.cpp                                         */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_chunked_terrain_3d)

#include "scene/3d/chunked_terrain_3d.h"
#include "scene/3d/terrain_streaming_budget_policy.h"
#include "scene/3d/terrain_streaming_priority_policy.h"
#include "scene/3d/node_3d.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/resources/3d/world_3d.h"
#include "servers/physics_3d/physics_server_3d.h"

namespace TestChunkedTerrain3D {

// A sloped terrain: height 0 at the west edge rising to 1 at the east edge, so the world height at
// x is simply (x / width + 0.5) * height_scale for a centered terrain.
static PackedFloat32Array make_ramp(int p_width, int p_depth) {
	PackedFloat32Array heights;
	heights.resize(p_width * p_depth);
	float *out = heights.ptrw();
	for (int z = 0; z < p_depth; z++) {
		for (int x = 0; x < p_width; x++) {
			out[z * p_width + x] = float(x) / float(p_width - 1);
		}
	}
	return heights;
}

static ChunkedTerrain3D *make_terrain(int p_samples, real_t p_size, real_t p_height_scale) {
	ChunkedTerrain3D *terrain = memnew(ChunkedTerrain3D);
	terrain->set_height_data(make_ramp(p_samples, p_samples), Vector2i(p_samples, p_samples));
	terrain->set_size(Vector2(p_size, p_size));
	terrain->set_height_scale(p_height_scale);
	terrain->set_chunk_quads(32);
	terrain->set_update_interval(0.0);
	return terrain;
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Static GI flag survives streamed LOD setup") {
	ChunkedTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
	CHECK_FALSE(terrain->is_contributing_to_gi());
	terrain->set_contribute_to_gi(true);
	CHECK(terrain->is_contributing_to_gi());

	SceneTree::get_singleton()->get_root()->add_child(terrain);
	terrain->force_update();
	const int original_chunks = terrain->get_chunk_count();
	terrain->set_contribute_to_gi(true); // No redundant RID updates.
	terrain->set_contribute_to_gi(false);
	CHECK_FALSE(terrain->is_contributing_to_gi());
	terrain->set_contribute_to_gi(true);
	terrain->force_update();
	CHECK(terrain->is_contributing_to_gi());
	CHECK(terrain->get_chunk_count() == original_chunks);
	// GI participation must not change the terrain mesh or collision policy.
	CHECK(terrain->is_collision_enabled());
	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Heights and normals follow the field") {
	ChunkedTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	terrain->force_update();

	CHECK(terrain->get_height_dimensions() == Vector2i(65, 65));
	CHECK(terrain->get_chunk_grid_size() == Vector2i(2, 2));
	CHECK(terrain->get_chunk_count() == 4);

	// Centered 64 m terrain: x runs from -32 to 32 and the height from 0 to 10.
	CHECK(terrain->get_height_at(Vector3(-32, 99, 0)) == doctest::Approx(0.0).epsilon(0.01));
	CHECK(terrain->get_height_at(Vector3(0, 99, 5)) == doctest::Approx(5.0).epsilon(0.01));
	CHECK(terrain->get_height_at(Vector3(16, -50, -10)) == doctest::Approx(7.5).epsilon(0.01));
	CHECK(terrain->get_height_at(Vector3(32, 0, 0)) == doctest::Approx(10.0).epsilon(0.01));
	// Beyond the edge the border height is used.
	CHECK(terrain->get_height_at(Vector3(500, 0, 0)) == doctest::Approx(10.0).epsilon(0.01));

	CHECK(terrain->is_over_terrain(Vector3(0, 0, 0)));
	CHECK(terrain->is_over_terrain(Vector3(31.9, 0, -31.9)));
	CHECK_FALSE(terrain->is_over_terrain(Vector3(40, 0, 0)));
	CHECK_FALSE(terrain->is_over_terrain(Vector3(0, 0, -33)));

	// A slope of 10 m over 64 m tilts the normal toward -x.
	const Vector3 normal = terrain->get_normal_at(Vector3(0, 0, 0));
	CHECK(normal.is_equal_approx(Vector3(-10.0 / 64.0, 1, 0).normalized()));

	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Screen-space terrain LOD is opt-in") {
	ChunkedTerrain3D *terrain = make_terrain(33, 64.0, 10.0);
	CHECK_FALSE(terrain->is_screen_space_lod_enabled());
	CHECK(terrain->get_lod_reference_fov() == doctest::Approx(60.0));
	terrain->set_screen_space_lod_enabled(true);
	terrain->set_lod_reference_fov(38.0);
	CHECK(terrain->is_screen_space_lod_enabled());
	CHECK(terrain->get_lod_reference_fov() == doctest::Approx(38.0));
	terrain->set_lod_reference_fov(500.0);
	CHECK(terrain->get_lod_reference_fov() < real_t(179.0));
	CHECK(terrain->is_collision_enabled());
	terrain->set_screen_space_lod_enabled(false);
	CHECK_FALSE(terrain->is_screen_space_lod_enabled());
	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Geometric-error LOD is optional") {
	ChunkedTerrain3D *terrain = make_terrain(33, 64.0, 10.0);
	CHECK(terrain->get_lod_geometric_error_strength() == doctest::Approx(0.0));
	CHECK(terrain->is_collision_enabled());
	terrain->set_lod_geometric_error_strength(0.75);
	CHECK(terrain->get_lod_geometric_error_strength() == doctest::Approx(0.75));
	terrain->set_lod_geometric_error_strength(5.0);
	CHECK(terrain->get_lod_geometric_error_strength() == doctest::Approx(1.0));
	terrain->set_lod_geometric_error_strength(-2.0);
	CHECK(terrain->get_lod_geometric_error_strength() == doctest::Approx(0.0));
	CHECK(terrain->is_collision_enabled());
	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] The node's transform moves the terrain") {
	ChunkedTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	terrain->set_global_position(Vector3(1000, 20, -500));
	terrain->force_update();

	// Terrain spans x 968..1032; at its center the height is 5 above the node.
	CHECK(terrain->get_height_at(Vector3(1000, 0, -500)) == doctest::Approx(25.0).epsilon(0.01));
	CHECK(terrain->is_over_terrain(Vector3(1000, 0, -500)));
	CHECK_FALSE(terrain->is_over_terrain(Vector3(0, 0, 0)));
	CHECK(terrain->get_height_at(Vector3(968, 0, -500)) == doctest::Approx(20.0).epsilon(0.01));

	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Detail drops with distance and collision stays near the focus") {
	ChunkedTerrain3D *terrain = make_terrain(257, 256.0, 20.0);
	Node3D *focus = memnew(Node3D);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	SceneTree::get_singleton()->get_root()->add_child(focus);
	terrain->set_lod_count(4);
	terrain->set_lod_distance(40.0);
	terrain->set_collision_distance(50.0);
	terrain->set_focus(terrain->get_path_to(focus));
	REQUIRE(terrain->get_chunk_grid_size() == Vector2i(8, 8));

	// Stand in the north-west corner chunk (0, 0): x, z in -128..-96.
	focus->set_global_position(Vector3(-120, 30, -120));
	terrain->force_update();
	CHECK(terrain->get_chunk_lod(Vector2i(0, 0)) == 0);
	CHECK(terrain->get_chunk_lod(Vector2i(7, 7)) == 3); // Far corner: coarsest level.
	CHECK(terrain->get_chunk_lod(Vector2i(0, 0)) < terrain->get_chunk_lod(Vector2i(4, 4)));
	CHECK(terrain->get_chunk_lod(Vector2i(4, 4)) <= terrain->get_chunk_lod(Vector2i(7, 7)));
	CHECK(terrain->get_visible_chunk_count() == 64);
	const int collision_near = terrain->get_collision_chunk_count();
	CHECK(collision_near >= 1);
	CHECK(collision_near <= 9); // Only the chunks within 50 m, not the whole terrain.

	// Walk across the terrain: the detail and the collision follow.
	focus->set_global_position(Vector3(120, 30, 120));
	terrain->force_update();
	CHECK(terrain->get_chunk_lod(Vector2i(7, 7)) == 0);
	CHECK(terrain->get_chunk_lod(Vector2i(0, 0)) == 3);
	CHECK(terrain->get_collision_chunk_count() >= 1);
	CHECK(terrain->get_collision_chunk_count() <= 9);

	// A view distance hides far chunks entirely.
	terrain->set_view_distance(100.0);
	terrain->force_update();
	CHECK(terrain->get_visible_chunk_count() < 64);
	CHECK(terrain->get_visible_chunk_count() >= 1);

	// Collision can be switched off.
	terrain->set_collision_enabled(false);
	CHECK(terrain->get_collision_chunk_count() == 0);

	memdelete(focus);
	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Collision shape matches the rendered ground") {
	ChunkedTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
	Node3D *focus = memnew(Node3D);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	SceneTree::get_singleton()->get_root()->add_child(focus);
	terrain->set_focus(terrain->get_path_to(focus));
	terrain->set_collision_distance(1000.0);
	focus->set_global_position(Vector3(0, 10, 0));
	terrain->force_update();
	CHECK(terrain->get_collision_chunk_count() == 4);

	// The physics server must see the terrain: cast a ray straight down at several places.
	PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
	const RID space = SceneTree::get_singleton()->get_root()->get_world_3d()->get_space();
	ps->step(0.016);
	ps->flush_queries();
	PhysicsDirectSpaceState3D *state = ps->space_get_direct_state(space);
	REQUIRE(state != nullptr);
	for (const Vector3 &probe : { Vector3(0, 0, 0), Vector3(-20, 0, 10), Vector3(25, 0, -25), Vector3(10, 0, 31) }) {
		PhysicsServer3DTypes::RayParameters params;
		params.from = Vector3(probe.x, 100, probe.z);
		params.to = Vector3(probe.x, -100, probe.z);
		PhysicsServer3DTypes::RayResult result;
		const bool hit = state->intersect_ray(params, result);
		CHECK(hit);
		if (hit) {
			CHECK(result.position.y == doctest::Approx(terrain->get_height_at(probe)).epsilon(0.02));
		}
	}

	// Switching the terrain off removes it from physics.
	terrain->set_collision_enabled(false);
	ps->step(0.016);
	ps->flush_queries();
	PhysicsServer3DTypes::RayParameters params;
	params.from = Vector3(0, 100, 0);
	params.to = Vector3(0, -100, 0);
	PhysicsServer3DTypes::RayResult result;
	CHECK_FALSE(state->intersect_ray(params, result));

	memdelete(focus);
	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Editing heights and invalid input") {
	ChunkedTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	terrain->force_update();
	const real_t before = terrain->get_height_at(Vector3(0, 0, 0));
	CHECK(before == doctest::Approx(5.0).epsilon(0.01));

	// Raise a plateau in the middle: samples 28..36 get the height 1.0.
	PackedFloat32Array heights = terrain->get_height_data();
	for (int z = 28; z <= 36; z++) {
		for (int x = 28; x <= 36; x++) {
			heights.set(z * 65 + x, 1.0);
		}
	}
	terrain->set_height_data(heights, Vector2i(65, 65));
	terrain->force_update();
	CHECK(terrain->get_height_at(Vector3(0, 0, 0)) == doctest::Approx(10.0).epsilon(0.01));
	CHECK(terrain->get_visible_chunk_count() == 4);

	// A partial update after an in-place change.
	heights.set(5 * 65 + 5, 0.9);
	terrain->set_height_data(heights, Vector2i(65, 65));
	terrain->force_update();
	terrain->update_region(Rect2i(4, 4, 3, 3));
	terrain->force_update();
	CHECK(terrain->get_visible_chunk_count() == 4);

	// Bad data is rejected and leaves the terrain intact.
	ERR_PRINT_OFF;
	terrain->set_height_data(PackedFloat32Array(), Vector2i(65, 65));
	terrain->set_height_data(heights, Vector2i(1, 1));
	terrain->set_size(Vector2(-5, 10));
	ERR_PRINT_ON;
	CHECK(terrain->get_height_dimensions() == Vector2i(65, 65));
	CHECK(terrain->get_size() == Vector2(64, 64));

	// Clearing script data without a heightmap leaves an empty terrain that does not crash.
	terrain->clear_height_data();
	terrain->force_update();
	CHECK(terrain->get_chunk_count() == 0);
	CHECK(terrain->get_height_at(Vector3(0, 0, 0)) == doctest::Approx(terrain->get_global_position().y));
	CHECK_FALSE(terrain->is_over_terrain(Vector3(0, 0, 0)));

	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Sparse paint keeps physics while preserving LOD metadata") {
	ChunkedTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
	PackedColorArray colors;
	colors.resize(65 * 65);
	colors.fill(Color(0.2, 0.3, 0.4, 1.0));
	terrain->set_color_data(colors);
	PackedVector3Array normals;
	normals.resize(65 * 65);
	normals.fill(Vector3(0, 1, 0));
	terrain->set_normal_data(normals);
	Node3D *focus = memnew(Node3D);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	SceneTree::get_singleton()->get_root()->add_child(focus);
	focus->set_global_position(Vector3(-22, 10, -22));
	terrain->set_focus(terrain->get_path_to(focus));
	terrain->set_collision_distance(100.0);
	terrain->force_update();
	const int collision_before = terrain->get_collision_chunk_count();
	REQUIRE(collision_before > 0);

	CHECK(terrain->apply_color_patch(Rect2i(7, 7, 2, 1),
			PackedColorArray({ Color(1, 0, 0), Color(0, 1, 0) })));
	CHECK(terrain->get_last_region_invalidated_chunks() == 1);
	CHECK(terrain->get_collision_chunk_count() == collision_before);
	CHECK(terrain->get_color_data()[7 * 65 + 7] == Color(1, 0, 0));
	CHECK(terrain->get_color_data()[7 * 65 + 8] == Color(0, 1, 0));
	CHECK(terrain->get_color_data()[8 * 65 + 8] == Color(0.2, 0.3, 0.4, 1.0));

	// A height-only patch is refused while the material uses external
	// normals. Supplying matching finite normals lets us edit locally.
	const PackedFloat32Array before = terrain->get_height_data();
	ERR_PRINT_OFF;
	CHECK_FALSE(terrain->apply_color_patch(Rect2i(7, 7, 2, 2), PackedColorArray({ Color(1, 0, 0) })));
	ERR_PRINT_ON;
	CHECK(terrain->get_height_data() == before);
	CHECK(terrain->apply_height_patch(Rect2i(7, 7, 1, 1), PackedFloat32Array({ 0.9f })));
	CHECK(terrain->get_last_region_invalidated_chunks() == 1);
	CHECK(terrain->get_normal_data()[7 * 65 + 7].is_equal_approx(Vector3(0, 1, 0)));
	terrain->force_update();
	CHECK(terrain->get_chunk_count() == 4);
	memdelete(focus);
	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Terrains whose size is not a multiple of the chunk") {
	// 50 samples: 49 quads, chunks of 32 -> 2 chunks per side; the last one is partial.
	ChunkedTerrain3D *terrain = make_terrain(50, 49.0, 10.0);
	Node3D *focus = memnew(Node3D);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	SceneTree::get_singleton()->get_root()->add_child(focus);
	terrain->set_focus(terrain->get_path_to(focus));
	terrain->set_collision_distance(1000.0);
	focus->set_global_position(Vector3(0, 10, 0));
	terrain->force_update();
	CHECK(terrain->get_chunk_grid_size() == Vector2i(2, 2));
	CHECK(terrain->get_visible_chunk_count() == 4);
	CHECK(terrain->get_collision_chunk_count() == 4);
	CHECK(terrain->get_height_at(Vector3(24.5, 0, 0)) == doctest::Approx(10.0).epsilon(0.01));

	memdelete(focus);
	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Custom normals support seam continuity and invalidate on height change") {
	ChunkedTerrain3D *terrain = make_terrain(33, 64.0, 10.0);
	PackedVector3Array normals;
	normals.resize(33 * 33);
	for (int z = 0; z < 33; z++) {
		for (int x = 0; x < 33; x++) {
			normals.set(z * 33 + x, Vector3(-0.4, 1.0, -0.15));
		}
	}
	terrain->set_normal_data(normals);
	CHECK(terrain->get_normal_data().size() == 33 * 33);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	terrain->force_update();
	CHECK(terrain->get_normal_at(Vector3(0, 0, 0)).is_equal_approx(Vector3(-0.4, 1, -0.15).normalized()));
	CHECK(terrain->get_normal_at(Vector3(-32, 0, 0)).is_equal_approx(Vector3(-0.4, 1, -0.15).normalized()));
	terrain->set_height_data(make_ramp(33, 33), Vector2i(33, 33));
	CHECK(terrain->get_normal_data().is_empty());
	terrain->force_update();
	CHECK_FALSE(terrain->get_normal_at(Vector3(0, 0, 0)).is_equal_approx(Vector3(-0.4, 1, -0.15).normalized()));
	terrain->set_normal_data(normals);
	terrain->clear_height_data();
	CHECK(terrain->get_normal_data().is_empty());
	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Authored vertex colors validate and reset on terrain change") {
	ChunkedTerrain3D *terrain = make_terrain(33, 64.0, 10.0);
	PackedColorArray colors;
	colors.resize(33 * 33);
	for (int i = 0; i < colors.size(); i++) {
		colors.set(i, Color(0.2, 0.45, 0.0, 1.0));
	}
	terrain->set_color_data(colors);
	CHECK(terrain->get_color_data().size() == 33 * 33);
	CHECK(terrain->get_color_data()[500].is_equal_approx(colors[500]));
	// A malformed external buffer cannot clobber valid surface shading.
	ERR_PRINT_OFF;
	PackedColorArray invalid_colors;
	invalid_colors.push_back(Color(1, 0, 0));
	terrain->set_color_data(invalid_colors);
	ERR_PRINT_ON;
	CHECK(terrain->get_color_data().size() == 33 * 33);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	terrain->force_update();
	CHECK(terrain->get_visible_chunk_count() > 0);
	terrain->set_height_data(make_ramp(33, 33), Vector2i(33, 33));
	CHECK(terrain->get_color_data().is_empty());
	terrain->set_color_data(colors);
	terrain->clear_height_data();
	CHECK(terrain->get_color_data().is_empty());
	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Pixel error is runtime configurable without replacing height data") {
	ChunkedTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	terrain->set_lod_count(3);
	terrain->force_update();
	CHECK(terrain->get_lod_pixel_error() == doctest::Approx(0.0));
	terrain->set_lod_pixel_error(2.5);
	CHECK(terrain->get_lod_pixel_error() == doctest::Approx(2.5));
	CHECK(terrain->get_chunk_count() == 4);
	terrain->set_lod_pixel_error(-8.0);
	CHECK(terrain->get_lod_pixel_error() == doctest::Approx(0.0));
	terrain->set_lod_pixel_error(Math::INF);
	CHECK(terrain->get_lod_pixel_error() == doctest::Approx(0.0));
	CHECK(terrain->get_height_dimensions() == Vector2i(65, 65));
	memdelete(terrain);
}


TEST_CASE("[SceneTree][ChunkedTerrain3D] Native horizon AO API returns packed sky visibility") {
	PackedFloat32Array heights;
	heights.resize(25 * 25);
	for (int z = 0; z < 25; z++) {
		for (int x = 0; x < 25; x++) {
			const real_t dx = real_t(x - 12);
			const real_t dz = real_t(z - 12);
			heights.set(z * 25 + x, float(real_t(0.3) * (dx * dx + dz * dz)));
		}
	}
	const PackedFloat32Array sky = ChunkedTerrain3D::bake_horizon_visibility(
			heights, Vector2i(25, 25), 2.0, 6);
	REQUIRE(sky.size() == heights.size());
	CHECK(sky[12 * 25 + 12] < real_t(0.95));
	CHECK(sky[12 * 25 + 12] > real_t(0.10));
}


TEST_CASE("[SceneTree][ChunkedTerrain3D] Time-sliced mesh streaming is starvation safe") {
	using TerrainStreamingBudgetPolicy::may_build;
	CHECK(may_build(500000, 0, 42)); // Legacy eager mode.
	CHECK(may_build(500000, 1000, 0)); // Always permit the first mesh.
	CHECK(may_build(999, 1000, 1));
	CHECK_FALSE(may_build(1000, 1000, 1));
	CHECK_FALSE(may_build(4000, 1000, 5));

	ChunkedTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
	CHECK(terrain->get_mesh_build_budget_usec() == 0);
	terrain->set_mesh_build_budget_usec(-10);
	CHECK(terrain->get_mesh_build_budget_usec() == 0);
	terrain->set_mesh_build_budget_usec(30000);
	CHECK(terrain->get_mesh_build_budget_usec() == 20000);
	terrain->set_mesh_build_budget_usec(1);
	CHECK(terrain->get_mesh_build_budget_usec() == 1);

	SceneTree::get_singleton()->get_root()->add_child(terrain);
	CHECK(terrain->get_chunk_count() == 4);
	// First native mesh is allowed even if one 32x32 build exceeds 1 us.
	// Other uncached meshes remain queued, not permanently discarded.
	CHECK(terrain->get_pending_mesh_build_count() > 0);
	CHECK(terrain->get_visible_chunk_count() < 4);
	// Tools and explicit teleports retain their synchronous override.
	terrain->force_update();
	CHECK(terrain->get_pending_mesh_build_count() == 0);
	CHECK(terrain->get_visible_chunk_count() == 4);
	// Disabling the limiter does not rebuild meshes or affect world heights.
	terrain->set_mesh_build_budget_usec(0);
	CHECK(terrain->get_height_dimensions() == Vector2i(65, 65));
	CHECK(terrain->get_chunk_count() == 4);
	memdelete(terrain);
}


TEST_CASE("[SceneTree][ChunkedTerrain3D] Visible terrain holes win the streaming queue") {
	using namespace TerrainStreamingPriorityPolicy;
	LocalVector<Candidate> candidates;
	candidates.push_back({ 4, 4.0f, false }); // Near LOD upgrade.
	candidates.push_back({ 9, 200.0f, true }); // New visible terrain, farther away.
	candidates.push_back({ 2, 5.0f, true }); // New terrain, near camera.
	candidates.push_back({ 1, 5.0f, true }); // Tie uses deterministic index.
	candidates.push_back({ 3, 20.0f, false });
	candidates.sort_custom<Less>();
	CHECK(candidates[0].index == 1);
	CHECK(candidates[1].index == 2);
	CHECK(candidates[2].index == 9);
	CHECK(candidates[3].index == 4);
	CHECK(candidates[4].index == 3);

	// Camera bias is bounded to 35% of distance: forward-facing terrain
	// gets priority without discarding chunks behind the player.
	CHECK(score(100.0f, 1.0f, 1) == doctest::Approx(100.0));
	CHECK(score(100.0f, 1.0f, 2) == doctest::Approx(65.0));
	CHECK(score(100.0f, -1.0f, 2) == doctest::Approx(135.0));
	CHECK(score(-10.0f, 0.5f, 2) == doctest::Approx(0.0));
	CHECK(score(100.0f, 8.0f, 2) == doctest::Approx(65.0));
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Mesh streaming priority stays optional") {
	ChunkedTerrain3D *terrain = make_terrain(33, 64.0, 10.0);
	CHECK(terrain->get_mesh_streaming_priority() == 0);
	terrain->set_mesh_streaming_priority(-10);
	CHECK(terrain->get_mesh_streaming_priority() == 0);
	terrain->set_mesh_streaming_priority(7);
	CHECK(terrain->get_mesh_streaming_priority() == 2);
	terrain->set_mesh_streaming_priority(1);
	CHECK(terrain->get_mesh_streaming_priority() == 1);
	terrain->set_mesh_build_budget_usec(0);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	terrain->force_update();
	// The priority setting only changes construction order when budgeted,
	// never the final geometry, collision, material, or LOD count.
	CHECK(terrain->get_visible_chunk_count() == 1);
	CHECK(terrain->get_height_dimensions() == Vector2i(33, 33));
	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Partial height patches keep far chunks and refresh geometric LOD errors") {
	ChunkedTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	terrain->force_update();
	CHECK(terrain->get_chunk_grid_size() == Vector2i(2, 2));
	CHECK(terrain->get_chunk_count() == 4);
	const real_t before_far = terrain->get_chunk_lod_error(Vector2i(1, 1), 1);
	const real_t before_near = terrain->get_chunk_lod_error(Vector2i(0, 0), 1);
	CHECK(before_near >= 0.0);
	CHECK(terrain->get_chunk_lod_error(Vector2i(-1, 0), 1) == -1.0);
	CHECK(terrain->get_chunk_lod_error(Vector2i(0, 0), -1) == -1.0);
	CHECK(terrain->get_chunk_lod_error(Vector2i(0, 0), 8) == -1.0);

	const PackedFloat32Array brush = { 0.95f };
	CHECK(terrain->apply_height_patch(Rect2i(7, 7, 1, 1), brush));
	CHECK(terrain->get_height_data()[7 * 65 + 7] == doctest::Approx(0.95));
	CHECK(terrain->get_chunk_lod_error(Vector2i(0, 0), 1) > before_near + 1.0);
	CHECK(terrain->get_chunk_lod_error(Vector2i(1, 1), 1) == doctest::Approx(before_far));
	CHECK(terrain->get_chunk_count() == 4); // No full-world mesh/physics rebuild.
	terrain->force_update();
	CHECK(terrain->get_chunk_count() == 4);
	CHECK(terrain->get_collision_chunk_count() > 0);
	const real_t increased = terrain->get_chunk_lod_error(Vector2i(0, 0), 1);
	CHECK(terrain->apply_height_patch(Rect2i(7, 7, 1, 1), brush));
	CHECK(terrain->get_chunk_lod_error(Vector2i(0, 0), 1) == doctest::Approx(increased));
	const PackedFloat32Array original = { 7.0f / 64.0f };
	CHECK(terrain->apply_height_patch(Rect2i(7, 7, 1, 1), original));
	CHECK(terrain->get_chunk_lod_error(Vector2i(0, 0), 1) == doctest::Approx(before_near));
	terrain->force_update();
	CHECK(terrain->get_collision_chunk_count() > 0);
	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Bad late patch samples reject the entire terrain transaction") {
	ChunkedTerrain3D *terrain = make_terrain(65, 64.0, 5.0);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	terrain->force_update();
	const PackedFloat32Array initial = terrain->get_height_data();
	const real_t initial_error = terrain->get_chunk_lod_error(Vector2i(0, 0), 1);
	CHECK_FALSE(terrain->apply_height_patch(Rect2i(0, 0, 0, 1), { 1.0f }));
	CHECK_FALSE(terrain->apply_height_patch(Rect2i(-1, 0, 1, 1), { 1.0f }));
	CHECK_FALSE(terrain->apply_height_patch(Rect2i(64, 64, 2, 2), { 1.0f, 1.0f, 1.0f, 1.0f }));
	CHECK_FALSE(terrain->apply_height_patch(Rect2i(0, 0, 2, 2), { 1.0f }));
	CHECK_FALSE(terrain->apply_height_patch(Rect2i(0, 0, 65, 65), initial));
	const PackedFloat32Array late_nan = { 0.5f, 0.5f, 0.5f, float(Math::NaN) };
	const PackedFloat32Array late_inf = { 0.5f, 0.5f, 0.5f, float(Math::INF) };
	CHECK_FALSE(terrain->apply_height_patch(Rect2i(0, 0, 2, 2), late_nan));
	CHECK_FALSE(terrain->apply_height_patch(Rect2i(0, 0, 2, 2), late_inf));
	CHECK(terrain->get_height_data() == initial);
	CHECK(terrain->get_chunk_lod_error(Vector2i(0, 0), 1) == doctest::Approx(initial_error));

	// A wide but bounded 64x64 patch is legal; an extra row is rejected.
	PackedFloat32Array maximum;
	maximum.resize(4096);
	maximum.fill(0.25f);
	CHECK(terrain->apply_height_patch(Rect2i(0, 0, 64, 64), maximum));
	terrain->force_update();
	CHECK(terrain->get_chunk_count() == 4);
	CHECK(terrain->get_height_data()[0] == doctest::Approx(0.25));
	memdelete(terrain);
}

TEST_CASE("[SceneTree][ChunkedTerrain3D] Partial patch updates custom normals near dirty samples") {
	ChunkedTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
	PackedVector3Array normals;
	normals.resize(65 * 65);
	normals.fill(Vector3.UP);
	terrain->set_normal_data(normals);
	SceneTree::get_singleton()->get_root()->add_child(terrain);
	terrain->force_update();
	const PackedVector3Array originally = terrain->get_normal_data();
	CHECK(terrain->apply_height_patch(Rect2i(7, 7, 1, 1), { 1.0f }));
	const PackedVector3Array changed = terrain->get_normal_data();
	CHECK(changed.size() == originally.size());
	CHECK(changed[7 * 65 + 6] != Vector3.UP);
	CHECK(changed[7 * 65 + 8] != Vector3.UP);
	CHECK(changed[7 * 65 + 7] == Vector3.UP);
	CHECK(changed[20 * 65 + 20] == Vector3.UP);
	memdelete(terrain);
}

} // namespace TestChunkedTerrain3D
