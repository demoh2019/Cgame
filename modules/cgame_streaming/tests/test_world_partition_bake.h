/**************************************************************************/
/*  test_world_partition_bake.h                                           */
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

#pragma once

#include "../world_partition_bake.h"

#include "core/io/dir_access.h"
#include "core/variant/array.h"
#include "tests/test_macros.h"
#include "tests/test_utils.h"

namespace TestWorldPartitionBake {

static Dictionary make_actor(const String &p_guid, const Vector3 &p_pos, float p_size, const PackedStringArray &p_layers = PackedStringArray(), bool p_loaded = true) {
	Dictionary a;
	a["guid"] = p_guid;
	a["position"] = p_pos;
	a["bounds"] = AABB(p_pos - Vector3(1, 1, 1) * p_size * 0.5f, Vector3(1, 1, 1) * p_size);
	a["layers"] = p_layers;
	a["spatially_loaded"] = p_loaded;
	Dictionary data;
	data["name"] = p_guid;
	a["data"] = data;
	return a;
}

static Array make_actors() {
	PackedStringArray night;
	night.push_back("Night");
	Array a;
	a.push_back(make_actor("a", Vector3(5, 0, 5), 2.0));
	a.push_back(make_actor("b", Vector3(40, 0, 5), 2.0));
	a.push_back(make_actor("c", Vector3(100, 0, 5), 2.0));
	a.push_back(make_actor("big", Vector3(20, 0, 20), 50.0));
	a.push_back(make_actor("sky", Vector3(0, 100, 0), 2.0, PackedStringArray(), false));
	a.push_back(make_actor("night", Vector3(6, 0, 6), 2.0, night));
	return a;
}

static Dictionary make_ranges() {
	Dictionary r;
	r["default"] = 40.0;
	r["Night"] = 40.0;
	return r;
}

static bool cell_has_actor(const Dictionary &p_cells, const String &p_key, const String &p_guid) {
	if (!p_cells.has(p_key)) {
		return false;
	}
	Array members = Dictionary(p_cells[p_key])["actors"];
	return members.has(p_guid);
}

TEST_CASE("[WorldPartitionBake] Cell assignment and levels") {
	Ref<WorldPartitionBake> wp;
	wp.instantiate();
	Dictionary result = wp->bake(make_actors(), 32.0, make_ranges());
	Dictionary cells = result["cells"];

	String a_cell, big_cell;
	Array keys = cells.keys();
	for (int i = 0; i < keys.size(); i++) {
		String key = keys[i];
		Array members = Dictionary(cells[key])["actors"];
		if (members.has("a")) {
			a_cell = key;
		}
		if (members.has("big")) {
			big_cell = key;
		}
	}
	CHECK(a_cell == "|0|0|0");
	CHECK(cell_has_actor(cells, "|0|1|0", "b"));
	CHECK(cell_has_actor(cells, "|0|3|0", "c"));
	CHECK((int)Dictionary(cells[big_cell])["level"] > 0);
	CHECK((int)Dictionary(cells[a_cell])["level"] == 0);
	AABB cb = Dictionary(cells[a_cell])["bounds"];
	CHECK(cb.encloses(AABB(Vector3(4, -1, 4), Vector3(2, 2, 2))));
}

TEST_CASE("[WorldPartitionBake] Always loaded actors and data layers") {
	Ref<WorldPartitionBake> wp;
	wp.instantiate();
	Dictionary result = wp->bake(make_actors(), 32.0, make_ranges());
	Dictionary cells = result["cells"];
	Array always = result["always_loaded"];
	CHECK(always.size() == 1);
	CHECK(String(always[0]) == "sky");
	Array ckeys = cells.keys();
	for (int i = 0; i < ckeys.size(); i++) {
		CHECK_FALSE(cell_has_actor(cells, ckeys[i], "sky"));
	}
	Dictionary layers = result["layers"];
	Array night_members = layers["Night"];
	CHECK(night_members.size() == 1);
	CHECK(String(night_members[0]) == "night");

	PackedStringArray night;
	night.push_back("Night");
	Array day_only = wp->cells_to_load(Vector3(5, 0, 5), Vector3(), PackedStringArray());
	Array with_night = wp->cells_to_load(Vector3(5, 0, 5), Vector3(), night);
	CHECK_FALSE(day_only.has("Night|0|0|0"));
	CHECK(with_night.has("Night|0|0|0"));
	CHECK(day_only.has("|0|0|0"));
}

TEST_CASE("[WorldPartitionBake] GUID stability") {
	Ref<WorldPartitionBake> wp;
	wp.instantiate();
	CHECK(WorldPartitionBake::stable_guid("tree@12,4") == WorldPartitionBake::stable_guid("tree@12,4"));
	CHECK(WorldPartitionBake::stable_guid("x") != WorldPartitionBake::stable_guid("y"));
	CHECK(WorldPartitionBake::stable_guid("x").length() == 36);

	Array unnamed;
	Dictionary u;
	u["position"] = Vector3(1, 0, 1);
	u["spatially_loaded"] = true;
	unnamed.push_back(u);
	Dictionary r1 = wp->bake(unnamed, 32.0, make_ranges());
	Dictionary r2 = wp->bake(unnamed, 32.0, make_ranges());
	CHECK(Dictionary(r1["actors"]).keys() == Dictionary(r2["actors"]).keys());
}

TEST_CASE("[WorldPartitionBake] HLOD clusters") {
	Ref<WorldPartitionBake> wp;
	wp.instantiate();
	Dictionary result = wp->bake(make_actors(), 32.0, make_ranges());
	Dictionary cells = result["cells"];
	Array clusters = wp->hlod_clusters(cells, 2);
	CHECK(clusters.size() > 0);
	CHECK(clusters.size() < cells.size());
	bool contained = true;
	int total_actors = 0;
	Dictionary actor_info = result["actors"];
	for (int i = 0; i < clusters.size(); i++) {
		Dictionary cl = clusters[i];
		AABB cbounds = cl["bounds"];
		Array members = cl["actors"];
		for (int k = 0; k < members.size(); k++) {
			AABB b = Dictionary(actor_info[members[k]])["bounds"];
			if (!cbounds.encloses(b)) {
				contained = false;
			}
			total_actors++;
		}
	}
	CHECK(contained);
	CHECK(total_actors == 5);
}

TEST_CASE("[WorldPartitionBake] One file per actor round trip") {
	Ref<WorldPartitionBake> wp;
	wp.instantiate();
	String dir = TestUtils::get_temp_path("wp_ofpa_test");
	Array actors = make_actors();
	CHECK(wp->split_one_file_per_actor(actors, dir) == 6);
	Array loaded = wp->load_actors(dir);
	CHECK(loaded.size() == 6);
	bool found_big = false;
	for (int i = 0; i < loaded.size(); i++) {
		Dictionary ld = loaded[i];
		if (String(ld["guid"]) == "big") {
			found_big = true;
			AABB lb = ld["bounds"];
			CHECK(Math::is_equal_approx(lb.size.x, 50.0f));
			CHECK(String(Dictionary(ld["data"])["name"]) == "big");
		}
	}
	CHECK(found_big);
	Ref<DirAccess> d = DirAccess::open(dir);
	if (d.is_valid()) {
		for (const String &f : d->get_files()) {
			d->remove(f);
		}
	}
	DirAccess::remove_absolute(dir);
}

TEST_CASE("[WorldPartitionBake] Incremental diff") {
	Ref<WorldPartitionBake> wp;
	wp.instantiate();
	Array newer = make_actors();
	newer.remove_at(2);
	newer[0] = make_actor("a", Vector3(70, 0, 5), 2.0);
	newer.push_back(make_actor("fresh", Vector3(10, 0, 10), 2.0));
	Dictionary old_bake = wp->bake(make_actors(), 32.0, make_ranges());
	Dictionary new_bake = wp->bake(newer, 32.0, make_ranges());
	Dictionary diff = wp->diff_bakes(old_bake, new_bake);
	Array moved = diff["moved"];
	Array added = diff["added"];
	Array removed = diff["removed"];
	CHECK(moved.size() == 1);
	CHECK(String(moved[0]) == "a");
	CHECK(added.size() == 1);
	CHECK(String(added[0]) == "fresh");
	CHECK(removed.size() == 1);
	CHECK(String(removed[0]) == "c");
	Array dirty = diff["dirty_cells"];
	CHECK(dirty.has("|0|0|0"));
}

TEST_CASE("[WorldPartitionBake] Predictive streaming") {
	Ref<WorldPartitionBake> wp;
	wp.instantiate();
	wp->bake(make_actors(), 32.0, make_ranges());
	Array still = wp->cells_to_load(Vector3(5, 0, 5), Vector3(), PackedStringArray());
	Array moving = wp->cells_to_load(Vector3(5, 0, 5), Vector3(60, 0, 0), PackedStringArray());
	CHECK_FALSE(still.has("|0|3|0"));
	CHECK(moving.has("|0|3|0"));
	// Nearest first.
	CHECK(String(still[0]) == "|0|0|0");
}

} //namespace TestWorldPartitionBake
