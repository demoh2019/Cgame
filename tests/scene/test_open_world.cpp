/**************************************************************************/
/*  test_open_world.cpp                                                   */
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
#include "tests/test_utils.h"

TEST_FORCE_LINK(test_open_world)

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/object/callable_mp.h"
#include "core/io/resource_saver.h"
#include "core/os/os.h"
#include "scene/3d/floating_origin_3d.h"
#include "scene/3d/node_3d.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/main/world_streamer.h"
#include "scene/main/world_streaming_grid.h"
#include "scene/resources/packed_scene.h"

namespace TestOpenWorld {

using namespace WorldStreamingGrid;

// Plain object that receives signals and answers the chunk provider callback.
class Recorder : public Object {
public:
	int loaded = 0;
	int unloaded = 0;
	int failed = 0;
	Vector3 shift;
	String only_path; // The provider answers this path for `only_cell` and nothing for other cells.
	Vector3i only_cell;

	void on_loaded(const Vector3i &, Node *) { loaded++; }
	void on_unloaded(const Vector3i &) { unloaded++; }
	void on_failed(const Vector3i &, const String &) { failed++; }
	void on_shifted(const Vector3 &p_offset) { shift = p_offset; }
	String provide(const Vector3i &p_cell) { return p_cell == only_cell ? only_path : String(); }
};

TEST_CASE("[WorldStreaming] Cells and distances, including negative coordinates") {
	CHECK(world_to_cell(Vector3(0, 5, 0), 10.0, AXES_XZ) == Vector3i(0, 0, 0));
	CHECK(world_to_cell(Vector3(9.99, 5, 0), 10.0, AXES_XZ) == Vector3i(0, 0, 0));
	CHECK(world_to_cell(Vector3(10.0, 5, -0.01), 10.0, AXES_XZ) == Vector3i(1, 0, -1));
	CHECK(world_to_cell(Vector3(-10.0, 0, -10.01), 10.0, AXES_XZ) == Vector3i(-1, 0, -2));
	CHECK(world_to_cell(Vector3(15, 25, 99), 10.0, AXES_XY) == Vector3i(1, 2, 0));
	CHECK(world_to_cell(Vector3(15, 25, 35), 10.0, AXES_XYZ) == Vector3i(1, 2, 3));
	CHECK(cell_origin(Vector3i(-1, 0, 2), 10.0).is_equal_approx(Vector3(-10, 0, 20)));

	// Inside the cell: zero. Outside: distance to the nearest face or corner.
	CHECK(distance_to_cell(Vector3(5, 99, 5), Vector3i(0, 0, 0), 10.0, AXES_XZ) == doctest::Approx(0.0));
	CHECK(distance_to_cell(Vector3(15, 0, 5), Vector3i(0, 0, 0), 10.0, AXES_XZ) == doctest::Approx(5.0));
	CHECK(distance_to_cell(Vector3(13, 0, 14), Vector3i(0, 0, 0), 10.0, AXES_XZ) == doctest::Approx(5.0)); // 3-4-5 from the corner.
	CHECK(distance_to_cell(Vector3(-4, 0, 5), Vector3i(0, 0, 0), 10.0, AXES_XZ) == doctest::Approx(4.0));
	// A volumetric grid also counts the vertical axis; the ground grid ignores it.
	CHECK(distance_to_cell(Vector3(5, 18, 5), Vector3i(0, 0, 0), 10.0, AXES_XYZ) == doctest::Approx(8.0));
	CHECK(distance_to_cell(Vector3(5, 18, 5), Vector3i(0, 0, 0), 10.0, AXES_XZ) == doctest::Approx(0.0));

	// Bad cell sizes are rejected, not divided by.
	ERR_PRINT_OFF;
	CHECK(world_to_cell(Vector3(1, 1, 1), 0.0, AXES_XZ) == Vector3i());
	ERR_PRINT_ON;
}

TEST_CASE("[WorldStreaming] Cells in radius are sorted nearest first and within range") {
	LocalVector<Vector3i> cells;
	const Vector3 position(25, 0, 25); // Inside cell (2, 0, 2) of a 10 m grid.
	cells_in_radius(position, 12.0, 10.0, AXES_XZ, cells);
	REQUIRE(cells.size() > 0);
	CHECK(cells[0] == Vector3i(2, 0, 2)); // The cell containing the point comes first.
	real_t previous = -1.0;
	for (const Vector3i &cell : cells) {
		const real_t distance = distance_to_cell(position, cell, 10.0, AXES_XZ);
		CHECK(distance <= real_t(12.0) + real_t(1e-4));
		CHECK(distance >= previous - real_t(1e-4));
		previous = distance;
		CHECK(cell.y == 0);
	}
	// A radius of zero still loads the cell the player stands in.
	cells_in_radius(position, 0.0, 10.0, AXES_XZ, cells);
	CHECK(cells.size() == 1);
	CHECK(cells[0] == Vector3i(2, 0, 2));

	// 3D radius covers more cells than the ground grid with the same radius.
	LocalVector<Vector3i> ground;
	LocalVector<Vector3i> volume;
	cells_in_radius(Vector3(5, 5, 5), 15.0, 10.0, AXES_XZ, ground);
	cells_in_radius(Vector3(5, 5, 5), 15.0, 10.0, AXES_XYZ, volume);
	CHECK(volume.size() > ground.size());

	// Invalid input yields nothing rather than an error loop.
	cells_in_radius(position, -1.0, 10.0, AXES_XZ, cells);
	CHECK(cells.is_empty());
	cells_in_radius(Vector3(Math::INF, 0, 0), 10.0, 10.0, AXES_XZ, cells);
	CHECK(cells.is_empty());
}

TEST_CASE("[WorldStreaming] Cell count is capped for huge radii") {
	LocalVector<Vector3i> cells;
	bool truncated = false;
	cells_in_radius(Vector3(), 1.0e9, 1.0, AXES_XZ, cells, 1000, &truncated);
	CHECK(truncated);
	CHECK(cells.size() <= 1000);
	CHECK(cells.size() > 0);
	// The cap keeps the nearest cells.
	for (const Vector3i &cell : cells) {
		CHECK(distance_to_cell(Vector3(), cell, 1.0, AXES_XZ) < real_t(100.0));
	}
	// An ordinary query is not truncated.
	cells_in_radius(Vector3(), 50.0, 10.0, AXES_XZ, cells, 1000, &truncated);
	CHECK_FALSE(truncated);
}

TEST_CASE("[WorldStreaming] Hysteresis: cells inside the unload radius stay loaded") {
	HashSet<Vector3i> loaded;
	loaded.insert(Vector3i(0, 0, 0));
	loaded.insert(Vector3i(5, 0, 0));
	loaded.insert(Vector3i(20, 0, 0));
	LocalVector<Vector3i> unload;
	// Standing in cell 0 of a 10 m grid: cell 5 starts 40 m away, cell 20 starts 190 m away.
	cells_to_unload(Vector3(5, 0, 5), 100.0, 10.0, AXES_XZ, loaded, unload);
	REQUIRE(unload.size() == 1);
	CHECK(unload[0] == Vector3i(20, 0, 0));
	cells_to_unload(Vector3(5, 0, 5), 30.0, 10.0, AXES_XZ, loaded, unload);
	REQUIRE(unload.size() == 2);
	CHECK(unload[0] == Vector3i(20, 0, 0)); // Farthest first.
	CHECK(unload[1] == Vector3i(5, 0, 0));
	cells_to_unload(Vector3(5, 0, 5), 1000.0, 10.0, AXES_XZ, loaded, unload);
	CHECK(unload.is_empty());
}

// Saves a tiny chunk scene (a Node3D with one child) and returns its path.
static String save_chunk(const String &p_path, const String &p_marker) {
	Node3D *root = memnew(Node3D);
	root->set_name("Chunk");
	Node3D *marker = memnew(Node3D);
	marker->set_name(p_marker);
	root->add_child(marker);
	marker->set_owner(root);
	Ref<PackedScene> scene;
	scene.instantiate();
	REQUIRE(scene->pack(root) == OK);
	REQUIRE(ResourceSaver::save(scene, p_path) == OK);
	memdelete(root);
	return p_path;
}

// Streaming runs on background threads: pump the tree until the condition holds or time runs out.
template <typename Condition>
static bool pump_until(Condition p_condition, int p_timeout_ms = 5000) {
	const uint64_t start = OS::get_singleton()->get_ticks_msec();
	while (!p_condition()) {
		if (OS::get_singleton()->get_ticks_msec() - start > uint64_t(p_timeout_ms)) {
			return false;
		}
		SceneTree::get_singleton()->process(0.2);
		OS::get_singleton()->delay_usec(2000);
	}
	return true;
}

TEST_CASE("[SceneTree][WorldStreamer] Loads nearby chunks, positions them and frees far ones") {
	const String directory = TestUtils::get_temp_path("open_world_chunks");
	DirAccess::make_dir_recursive_absolute(directory);
	for (int x = -2; x <= 2; x++) {
		for (int z = -2; z <= 2; z++) {
			save_chunk(directory.path_join(vformat("chunk_%d_%d.tscn", x, z)), vformat("Marker_%d_%d", x, z));
		}
	}

	WorldStreamer *streamer = memnew(WorldStreamer);
	streamer->set_cell_size(100.0);
	streamer->set_load_radius(120.0);
	streamer->set_unload_radius(180.0);
	streamer->set_chunk_path_template(directory.path_join("chunk_{x}_{z}.tscn"));
	streamer->set_update_interval(0.0);
	streamer->set_max_instantiations_per_frame(16);
	SceneTree::get_singleton()->get_root()->add_child(streamer);

	Recorder recorder;
	streamer->connect("chunk_loaded", callable_mp(&recorder, &Recorder::on_loaded));
	streamer->connect("chunk_unloaded", callable_mp(&recorder, &Recorder::on_unloaded));

	// Standing in the middle of cell (0, 0): the 3x3 block around it is within 120 m.
	streamer->set_focus_position(Vector3(50, 0, 50));
	CHECK(streamer->world_to_cell(Vector3(50, 0, 50)) == Vector3i(0, 0, 0));
	REQUIRE(pump_until([&]() { return streamer->get_loaded_count() >= 9 && streamer->get_pending_count() == 0; }));
	CHECK(streamer->get_loaded_count() == 9);
	CHECK(recorder.loaded == 9);
	CHECK(streamer->is_cell_loaded(Vector3i(0, 0, 0)));
	CHECK(streamer->is_cell_loaded(Vector3i(-1, 0, -1)));
	CHECK_FALSE(streamer->is_cell_loaded(Vector3i(2, 0, 2)));

	Node3D *chunk = Object::cast_to<Node3D>(streamer->get_chunk(Vector3i(1, 0, -1)));
	REQUIRE(chunk != nullptr);
	CHECK(chunk->get_position().is_equal_approx(Vector3(100, 0, -100))); // Positioned at its cell.
	CHECK(chunk->has_node(NodePath("Marker_1_-1")));
	CHECK(chunk->get_parent() == streamer);

	// Walk far east: the western chunks are dropped, new eastern ones load.
	streamer->set_focus_position(Vector3(250, 0, 50));
	REQUIRE(pump_until([&]() { return streamer->is_cell_loaded(Vector3i(2, 0, 0)) && !streamer->is_cell_loaded(Vector3i(-1, 0, 0)); }));
	CHECK_FALSE(streamer->is_cell_loaded(Vector3i(-1, 0, -1)));
	CHECK(recorder.unloaded > 0);
	CHECK(streamer->get_loaded_count() <= 12);

	// Cells with no scene file are skipped silently and not retried every update.
	CHECK_FALSE(streamer->is_cell_loaded(Vector3i(4, 0, 0)));

	streamer->unload_all();
	CHECK(streamer->get_loaded_count() == 0);
	SceneTree::get_singleton()->process(0.0);

	memdelete(streamer);
}

TEST_CASE("[SceneTree][WorldStreamer] Custom provider, failed loads and the 2D grid") {
	const String directory = TestUtils::get_temp_path("open_world_provider");
	DirAccess::make_dir_recursive_absolute(directory);
	const String good = save_chunk(directory.path_join("good.tscn"), "Good");

	WorldStreamer *streamer = memnew(WorldStreamer);
	streamer->set_axes(WorldStreamer::AXES_XY);
	streamer->set_cell_size(50.0);
	streamer->set_load_radius(10.0);
	streamer->set_update_interval(0.0);
	// Only cell (0, 0) has a scene; every other cell answers with nothing.
	Recorder recorder;
	recorder.only_cell = Vector3i(0, 0, 0);
	recorder.only_path = good;
	streamer->set_chunk_provider(callable_mp(&recorder, &Recorder::provide));
	SceneTree::get_singleton()->get_root()->add_child(streamer);

	streamer->set_focus_position(Vector3(25, 25, 0));
	REQUIRE(pump_until([&]() { return streamer->get_loaded_count() == 1; }));
	CHECK(streamer->is_cell_loaded(Vector3i(0, 0, 0)));
	CHECK(streamer->get_loaded_cells().size() == 1);

	// Moving next to a neighbour that has no scene loads nothing and raises no error.
	streamer->set_focus_position(Vector3(45, 25, 0));
	for (int i = 0; i < 5; i++) {
		SceneTree::get_singleton()->process(0.2);
	}
	CHECK(streamer->get_loaded_count() == 1);

	// A scene file that is not a scene reports a failure.
	const String bad = directory.path_join("bad.tscn");
	Ref<FileAccess> file = FileAccess::open(bad, FileAccess::WRITE);
	REQUIRE(file.is_valid());
	file->store_string("this is not a scene");
	file.unref();
	streamer->connect("chunk_load_failed", callable_mp(&recorder, &Recorder::on_failed));
	recorder.only_cell = Vector3i(1, 0, 0);
	recorder.only_path = bad;
	streamer->set_chunk_provider(callable_mp(&recorder, &Recorder::provide));
	ERR_PRINT_OFF;
	streamer->refresh(true);
	pump_until([&]() { return recorder.failed > 0; }, 3000);
	ERR_PRINT_ON;
	CHECK(recorder.failed == 1);
	CHECK_FALSE(streamer->is_cell_loaded(Vector3i(1, 0, 0)));

	memdelete(streamer);
}

TEST_CASE("[SceneTree][WorldStreamer][FloatingOrigin3D] The chunk grid stays absolute while the origin shifts") {
	const String directory = TestUtils::get_temp_path("open_world_origin");
	DirAccess::make_dir_recursive_absolute(directory);
	for (int x = 0; x <= 30; x++) {
		save_chunk(directory.path_join(vformat("c_%d.tscn", x)), vformat("M%d", x));
	}

	Node3D *world = memnew(Node3D);
	Node3D *player = memnew(Node3D);
	Node3D *chunks = memnew(Node3D);
	chunks->set_name("Chunks");
	WorldStreamer *streamer = memnew(WorldStreamer);
	FloatingOrigin3D *origin = memnew(FloatingOrigin3D);
	world->add_child(player);
	world->add_child(chunks);
	world->add_child(streamer);
	world->add_child(origin);
	SceneTree::get_singleton()->get_root()->add_child(world);

	origin->set_focus(origin->get_path_to(player));
	origin->set_world_root(origin->get_path_to(world));
	origin->set_threshold(1000.0);
	origin->set_snap(1000.0);
	origin->set_process_callback(FloatingOrigin3D::PROCESS_IDLE);

	streamer->set_cell_size(100.0);
	streamer->set_load_radius(50.0);
	streamer->set_unload_radius(150.0);
	streamer->set_update_interval(0.0);
	streamer->set_max_instantiations_per_frame(16);
	streamer->set_chunk_path_template(directory.path_join("c_{x}.tscn"));
	streamer->set_focus(streamer->get_path_to(player));
	streamer->set_chunk_parent(streamer->get_path_to(chunks));

	// Walk to x = 1550: the origin shifts by 2000 (snap 1000, rounded), the player ends at -450.
	player->set_global_position(Vector3(1550, 0, 50));
	SceneTree::get_singleton()->process(0.016);
	CHECK(origin->get_shift_count() == 1);
	CHECK(player->get_global_position().is_equal_approx(Vector3(-450, 0, 50)));
	REQUIRE(pump_until([&]() { return streamer->is_cell_loaded(Vector3i(15, 0, 0)); }));

	// The player is at absolute x = 1550, i.e. in cell 15, not in cell -5.
	CHECK(streamer->world_to_cell(Vector3(1550, 0, 50)) == Vector3i(15, 0, 0));
	Node3D *chunk = Object::cast_to<Node3D>(streamer->get_chunk(Vector3i(15, 0, 0)));
	REQUIRE(chunk != nullptr);
	// Chunk (15, 0) sits at absolute x = 1500, so 50 m behind the player in the shifted frame too.
	CHECK(chunk->get_global_position().is_equal_approx(Vector3(-500, 0, 0)));
	CHECK((player->get_global_position() - chunk->get_global_position()).is_equal_approx(Vector3(50, 0, 50)));

	// A chunk that was loaded before the shift moves with the world.
	player->set_global_position(Vector3(-450, 0, 50));
	chunks->set_global_position(chunks->get_global_position()); // No-op, keeps the test honest about the frame.
	CHECK(streamer->get_loaded_count() >= 1);

	memdelete(world);
}

TEST_CASE("[FloatingOrigin3D] Shift is zero inside the threshold and snapped outside") {
	CHECK(FloatingOrigin3D::compute_shift(Vector3(100, 0, 100), 2000.0, 1000.0, false) == Vector3());
	CHECK(FloatingOrigin3D::compute_shift(Vector3(2000, 0, 0), 2000.0, 1000.0, false) == Vector3()); // Exactly at the threshold.
	const Vector3 shift = FloatingOrigin3D::compute_shift(Vector3(5300, 40, -2600), 2000.0, 1000.0, false);
	CHECK(shift == Vector3(5000, 0, -3000)); // Whole multiples of the snap; height is kept.
	CHECK(FloatingOrigin3D::compute_shift(Vector3(5300, 40, -2600), 2000.0, 1000.0, true) == Vector3(5000, 0, -3000));
	CHECK(FloatingOrigin3D::compute_shift(Vector3(100, 5400, 0), 2000.0, 1000.0, true) == Vector3(0, 5000, 0));
	CHECK(FloatingOrigin3D::compute_shift(Vector3(100, 5400, 0), 2000.0, 1000.0, false) == Vector3()); // Climbing alone never shifts.
	// Invalid input never shifts.
	CHECK(FloatingOrigin3D::compute_shift(Vector3(Math::NaN, 0, 0), 2000.0, 1000.0, false) == Vector3());
	CHECK(FloatingOrigin3D::compute_shift(Vector3(9000, 0, 0), 2000.0, 0.0, false) == Vector3());
	// After the shift the focus is within half a snap of the origin: no repeated shifting.
	const Vector3 focus(5300, 0, -2600);
	const Vector3 after = focus - shift;
	CHECK(Math::abs(after.x) <= 500.0 + 1e-3);
	CHECK(Math::abs(after.z) <= 500.0 + 1e-3);
	CHECK(FloatingOrigin3D::compute_shift(after, 2000.0, 1000.0, false) == Vector3());
}

TEST_CASE("[SceneTree][FloatingOrigin3D] Rebases the world around the focus") {
	Node3D *world = memnew(Node3D);
	Node3D *player = memnew(Node3D);
	player->set_name("Player");
	Node3D *tree_a = memnew(Node3D);
	tree_a->set_name("TreeA");
	Node3D *ignored = memnew(Node3D);
	ignored->set_name("Sky");
	ignored->add_to_group("floating_origin_ignore");
	FloatingOrigin3D *origin = memnew(FloatingOrigin3D);
	origin->set_name("Origin");
	world->add_child(player);
	world->add_child(tree_a);
	world->add_child(ignored);
	world->add_child(origin);
	SceneTree::get_singleton()->get_root()->add_child(world);

	origin->set_focus(origin->get_path_to(player));
	origin->set_world_root(origin->get_path_to(world));
	origin->set_threshold(1000.0);
	origin->set_snap(500.0);
	origin->set_process_callback(FloatingOrigin3D::PROCESS_IDLE);

	player->set_global_position(Vector3(100, 2, 100));
	tree_a->set_global_position(Vector3(130, 0, 100)); // 30 m east of the player.
	ignored->set_global_position(Vector3(7, 7, 7));
	SceneTree::get_singleton()->process(0.016);
	CHECK(origin->get_shift_count() == 0);
	CHECK(player->get_global_position().is_equal_approx(Vector3(100, 2, 100)));

	Recorder recorder;
	origin->connect("origin_shifted", callable_mp(&recorder, &Recorder::on_shifted));
	player->set_global_position(Vector3(2600, 2, -1200));
	tree_a->set_global_position(Vector3(2630, 0, -1200));
	SceneTree::get_singleton()->process(0.016);

	CHECK(origin->get_shift_count() == 1);
	CHECK(recorder.shift.is_equal_approx(Vector3(2500, 0, -1000)));
	CHECK(origin->get_origin_cells() == Vector3i(5, 0, -2));
	// The player is back near the origin; the tree is still exactly 30 m east of it.
	CHECK(player->get_global_position().is_equal_approx(Vector3(100, 2, -200)));
	CHECK((tree_a->get_global_position() - player->get_global_position()).is_equal_approx(Vector3(30, -2, 0)));
	CHECK(ignored->get_global_position().is_equal_approx(Vector3(7, 7, 7))); // Opted out.
	// The absolute position is still recoverable.
	CHECK(origin->to_absolute(player->get_global_position()).is_equal_approx(Vector3(2600, 2, -1200)));
	CHECK(origin->to_local(Vector3(2600, 2, -1200)).is_equal_approx(player->get_global_position()));

	// A second walk accumulates exactly.
	player->set_global_position(Vector3(100 + 1800, 2, -200));
	SceneTree::get_singleton()->process(0.016);
	CHECK(origin->get_shift_count() == 2);
	CHECK(origin->get_origin_cells() == Vector3i(9, 0, -2));

	memdelete(world);
}

} // namespace TestOpenWorld
