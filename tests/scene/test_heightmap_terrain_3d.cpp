/**************************************************************************/
/*  test_heightmap_terrain_3d.cpp                                         */
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

TEST_FORCE_LINK(test_heightmap_terrain_3d)

#include "scene/3d/heightmap_terrain_3d.h"
#include "scene/3d/node_3d.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/resources/3d/world_3d.h"
#include "servers/physics_3d/physics_server_3d.h"

namespace TestHeightmapTerrain3D {

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

static HeightmapTerrain3D *make_terrain(int p_samples, real_t p_size, real_t p_height_scale) {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_height_data(make_ramp(p_samples, p_samples), Vector2i(p_samples, p_samples));
	terrain->set_size(Vector2(p_size, p_size));
	terrain->set_height_scale(p_height_scale);
	terrain->set_chunk_quads(32);
	terrain->set_update_interval(0.0);
	return terrain;
}

TEST_CASE("[SceneTree][HeightmapTerrain3D] Heights and normals follow the field") {
	HeightmapTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
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

TEST_CASE("[SceneTree][HeightmapTerrain3D] The node's transform moves the terrain") {
	HeightmapTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
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

TEST_CASE("[SceneTree][HeightmapTerrain3D] Detail drops with distance and collision stays near the focus") {
	HeightmapTerrain3D *terrain = make_terrain(257, 256.0, 20.0);
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

TEST_CASE("[SceneTree][HeightmapTerrain3D] Collision shape matches the rendered ground") {
	HeightmapTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
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

TEST_CASE("[SceneTree][HeightmapTerrain3D] Editing heights and invalid input") {
	HeightmapTerrain3D *terrain = make_terrain(65, 64.0, 10.0);
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

TEST_CASE("[SceneTree][HeightmapTerrain3D] Terrains whose size is not a multiple of the chunk") {
	// 50 samples: 49 quads, chunks of 32 -> 2 chunks per side; the last one is partial.
	HeightmapTerrain3D *terrain = make_terrain(50, 49.0, 10.0);
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

} // namespace TestHeightmapTerrain3D
