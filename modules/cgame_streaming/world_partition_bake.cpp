/**************************************************************************/
/*  world_partition_bake.cpp                                              */
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

#include "world_partition_bake.h"

#include "core/object/class_db.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/math/math_funcs.h"
#include "core/templates/local_vector.h"

#define DEFAULT_LAYER_KEY "default"

void WorldPartitionBake::set_lookahead_seconds(double p_seconds) {
	lookahead_seconds = p_seconds;
}

double WorldPartitionBake::get_lookahead_seconds() const {
	return lookahead_seconds;
}

void WorldPartitionBake::set_lookahead_samples(int p_samples) {
	lookahead_samples = p_samples;
}

int WorldPartitionBake::get_lookahead_samples() const {
	return lookahead_samples;
}

String WorldPartitionBake::stable_guid(const String &p_seed) {
	String h = p_seed.md5_text();
	return vformat("%s-%s-%s-%s-%s", h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12));
}

AABB WorldPartitionBake::_actor_bounds(const Dictionary &p_actor) {
	if (p_actor.has("bounds")) {
		return p_actor["bounds"];
	}
	Vector3 pos = p_actor.get("position", Vector3());
	return AABB(pos, Vector3());
}

String WorldPartitionBake::_group_of(const PackedStringArray &p_layers) {
	Vector<String> sorted = p_layers;
	sorted.sort();
	return String("+").join(sorted);
}

int WorldPartitionBake::_level_for(double p_extent, double p_cell_size) {
	int level = 0;
	double size = p_cell_size;
	while (p_extent > size && level < MAX_LEVEL) {
		size *= 2.0;
		level++;
	}
	return level;
}

double WorldPartitionBake::_range_for(const PackedStringArray &p_layers, int p_level, double p_cs, const Dictionary &p_ranges) {
	double best = -1.0;
	for (const String &layer : p_layers) {
		if (p_ranges.has(layer)) {
			best = MAX(best, (double)p_ranges[layer]);
		}
	}
	if (best >= 0.0) {
		return best;
	}
	if (p_ranges.has(DEFAULT_LAYER_KEY)) {
		return p_ranges[DEFAULT_LAYER_KEY];
	}
	return p_cs * 2.0 * Math::pow(2.0, (double)p_level);
}

Dictionary WorldPartitionBake::bake(const Array &p_actors, double p_cell_size, const Dictionary &p_loading_range_by_layer) {
	double cs = MAX(p_cell_size, 0.001);
	Dictionary cells;
	Array always_loaded;
	Dictionary layer_members;
	Dictionary actor_info;
	int index = 0;
	for (int ai = 0; ai < p_actors.size(); ai++) {
		Dictionary actor = p_actors[ai];
		String guid = actor.get("guid", "");
		if (guid.is_empty()) {
			Vector3 default_pos = actor.get("position", Vector3());
			guid = stable_guid(vformat("%s|%d", String(Variant(default_pos)), index));
		}
		index++;
		PackedStringArray layers = actor.get("layers", PackedStringArray());
		for (const String &layer : layers) {
			if (!layer_members.has(layer)) {
				layer_members[layer] = Array();
			}
			Array members = layer_members[layer];
			members.push_back(guid);
		}
		AABB bounds = _actor_bounds(actor);
		Vector3 position = actor.get("position", bounds.get_center());
		Dictionary info;
		info["position"] = position;
		info["bounds"] = bounds;
		info["layers"] = layers;
		info["data_hash"] = (int64_t)String(actor.get("data", Dictionary())).hash();
		info["cell"] = "";
		if (!(bool)actor.get("spatially_loaded", true)) {
			always_loaded.push_back(guid);
			actor_info[guid] = info;
			continue;
		}
		Vector3 center = bounds.size != Vector3() ? bounds.get_center() : position;
		int level = _level_for(MAX(bounds.size.x, bounds.size.z), cs);
		double lsize = cs * Math::pow(2.0, (double)level);
		int64_t cx = (int64_t)Math::floor(center.x / lsize);
		int64_t cz = (int64_t)Math::floor(center.z / lsize);
		String group = _group_of(layers);
		String key = vformat("%s|%d|%d|%d", group, level, cx, cz);
		if (!cells.has(key)) {
			Dictionary cell;
			cell["level"] = level;
			cell["x"] = cx;
			cell["z"] = cz;
			cell["group"] = group;
			cell["layers"] = layers;
			cell["bounds"] = bounds;
			cell["actors"] = Array();
			cell["range"] = _range_for(layers, level, cs, p_loading_range_by_layer);
			cells[key] = cell;
		}
		Dictionary cell = cells[key];
		AABB cb = cell["bounds"];
		Array cell_actors = cell["actors"];
		if (cell_actors.is_empty()) {
			cb = bounds;
		} else {
			cb = cb.merge(bounds);
		}
		cell["bounds"] = cb;
		cell_actors.push_back(guid);
		info["cell"] = key;
		actor_info[guid] = info;
	}
	baked = Dictionary();
	baked["cell_size"] = cs;
	baked["cells"] = cells;
	baked["always_loaded"] = always_loaded;
	baked["layers"] = layer_members;
	baked["actors"] = actor_info;
	return baked;
}

Dictionary WorldPartitionBake::get_baked() const {
	return baked;
}

Array WorldPartitionBake::hlod_clusters(const Dictionary &p_cells, int p_cluster_cells) const {
	int n = MAX(p_cluster_cells, 1);
	Dictionary by_key;
	Array keys = p_cells.keys();
	keys.sort();
	for (int i = 0; i < keys.size(); i++) {
		String cell_key = keys[i];
		Dictionary cell = p_cells[cell_key];
		int64_t cx = cell["x"];
		int64_t cz = cell["z"];
		int64_t level = cell["level"];
		String key = vformat("%s|%d|%d|%d", String(cell["group"]), level,
				(int64_t)Math::floor((double)cx / (double)n), (int64_t)Math::floor((double)cz / (double)n));
		if (!by_key.has(key)) {
			Dictionary c;
			c["key"] = key;
			c["level"] = level;
			c["group"] = cell["group"];
			c["bounds"] = cell["bounds"];
			c["cells"] = Array();
			c["actors"] = Array();
			by_key[key] = c;
		}
		Dictionary cluster = by_key[key];
		AABB cb = cluster["bounds"];
		Array cluster_cells = cluster["cells"];
		AABB cell_bounds = cell["bounds"];
		if (cluster_cells.is_empty()) {
			cb = cell_bounds;
		} else {
			cb = cb.merge(cell_bounds);
		}
		cluster["bounds"] = cb;
		cluster_cells.push_back(cell_key);
		Array cluster_actors = cluster["actors"];
		cluster_actors.append_array(cell["actors"]);
	}
	Array out;
	Array ckeys = by_key.keys();
	ckeys.sort();
	for (int i = 0; i < ckeys.size(); i++) {
		out.push_back(by_key[ckeys[i]]);
	}
	return out;
}

Dictionary WorldPartitionBake::_actor_to_json(const Dictionary &p_actor) {
	Vector3 pos = p_actor.get("position", Vector3());
	AABB b = _actor_bounds(p_actor);
	Array pos_arr;
	pos_arr.push_back(pos.x);
	pos_arr.push_back(pos.y);
	pos_arr.push_back(pos.z);
	Array bounds_arr;
	bounds_arr.push_back(b.position.x);
	bounds_arr.push_back(b.position.y);
	bounds_arr.push_back(b.position.z);
	bounds_arr.push_back(b.size.x);
	bounds_arr.push_back(b.size.y);
	bounds_arr.push_back(b.size.z);
	PackedStringArray layers = p_actor.get("layers", PackedStringArray());
	Array layers_arr;
	for (const String &l : layers) {
		layers_arr.push_back(l);
	}
	Dictionary d;
	d["guid"] = p_actor.get("guid", "");
	d["position"] = pos_arr;
	d["bounds"] = bounds_arr;
	d["layers"] = layers_arr;
	d["spatially_loaded"] = (bool)p_actor.get("spatially_loaded", true);
	d["data"] = p_actor.get("data", Dictionary());
	return d;
}

Dictionary WorldPartitionBake::_actor_from_json(const Dictionary &p_json) {
	Array p = p_json.get("position", Array());
	Array b = p_json.get("bounds", Array());
	while (p.size() < 3) {
		p.push_back(0);
	}
	while (b.size() < 6) {
		b.push_back(0);
	}
	Dictionary a;
	a["guid"] = String(p_json.get("guid", ""));
	a["position"] = Vector3((float)(double)p[0], (float)(double)p[1], (float)(double)p[2]);
	a["bounds"] = AABB(Vector3((float)(double)b[0], (float)(double)b[1], (float)(double)b[2]),
			Vector3((float)(double)b[3], (float)(double)b[4], (float)(double)b[5]));
	a["layers"] = PackedStringArray(p_json.get("layers", Array()));
	a["spatially_loaded"] = (bool)p_json.get("spatially_loaded", true);
	a["data"] = p_json.get("data", Dictionary());
	return a;
}

int WorldPartitionBake::split_one_file_per_actor(const Array &p_actors, const String &p_dir_path) const {
	DirAccess::make_dir_recursive_absolute(p_dir_path);
	int written = 0;
	for (int i = 0; i < p_actors.size(); i++) {
		Dictionary actor = p_actors[i];
		String guid = actor.get("guid", "");
		if (guid.is_empty()) {
			continue;
		}
		String final_path = p_dir_path.path_join(guid + ".json");
		String tmp_path = final_path + ".tmp";
		{
			Ref<FileAccess> f = FileAccess::open(tmp_path, FileAccess::WRITE);
			if (f.is_null()) {
				continue;
			}
			f->store_string(JSON::stringify(_actor_to_json(actor)));
		}
		Error err = DirAccess::rename_absolute(tmp_path, final_path);
		if (err != OK) {
			DirAccess::remove_absolute(final_path);
			err = DirAccess::rename_absolute(tmp_path, final_path);
		}
		if (err == OK) {
			written++;
		}
	}
	return written;
}

Array WorldPartitionBake::load_actors(const String &p_dir_path) const {
	Array out;
	Ref<DirAccess> dir = DirAccess::open(p_dir_path);
	if (dir.is_null()) {
		return out;
	}
	Vector<String> names;
	for (const String &fname : dir->get_files()) {
		if (fname.ends_with(".json")) {
			names.push_back(fname);
		}
	}
	names.sort();
	for (const String &fname : names) {
		String text = FileAccess::get_file_as_string(p_dir_path.path_join(fname));
		Variant parsed = JSON::parse_string(text);
		if (parsed.get_type() == Variant::DICTIONARY) {
			out.push_back(_actor_from_json(parsed));
		}
	}
	return out;
}

Dictionary WorldPartitionBake::diff_bakes(const Dictionary &p_old_bake, const Dictionary &p_new_bake) const {
	Dictionary old_actors = p_old_bake.get("actors", Dictionary());
	Dictionary new_actors = p_new_bake.get("actors", Dictionary());
	Array added, removed, moved, changed;
	Dictionary dirty;
	Array new_keys = new_actors.keys();
	for (int i = 0; i < new_keys.size(); i++) {
		String guid = new_keys[i];
		Dictionary n = new_actors[guid];
		if (!old_actors.has(guid)) {
			added.push_back(guid);
			dirty[String(n["cell"])] = true;
			continue;
		}
		Dictionary o = old_actors[guid];
		Vector3 op = o["position"];
		Vector3 np = n["position"];
		AABB ob = o["bounds"];
		AABB nb = n["bounds"];
		if (!op.is_equal_approx(np) || !ob.is_equal_approx(nb) || String(o["cell"]) != String(n["cell"])) {
			moved.push_back(guid);
			dirty[String(o["cell"])] = true;
			dirty[String(n["cell"])] = true;
		} else if ((int64_t)o["data_hash"] != (int64_t)n["data_hash"]) {
			changed.push_back(guid);
			dirty[String(n["cell"])] = true;
		}
	}
	Array old_keys = old_actors.keys();
	for (int i = 0; i < old_keys.size(); i++) {
		String guid = old_keys[i];
		if (!new_actors.has(guid)) {
			removed.push_back(guid);
			dirty[String(Dictionary(old_actors[guid])["cell"])] = true;
		}
	}
	dirty.erase("");
	added.sort();
	removed.sort();
	moved.sort();
	changed.sort();
	Array dirty_cells = dirty.keys();
	dirty_cells.sort();
	Dictionary out;
	out["added"] = added;
	out["removed"] = removed;
	out["moved"] = moved;
	out["changed"] = changed;
	out["dirty_cells"] = dirty_cells;
	return out;
}

double WorldPartitionBake::_dist_to_cell(const Vector3 &p_point, const AABB &p_bounds) {
	double dx = MAX(MAX((double)p_bounds.position.x - p_point.x, (double)p_point.x - (p_bounds.position.x + p_bounds.size.x)), 0.0);
	double dz = MAX(MAX((double)p_bounds.position.z - p_point.z, (double)p_point.z - (p_bounds.position.z + p_bounds.size.z)), 0.0);
	return Math::sqrt(dx * dx + dz * dz);
}

namespace {
struct ScoredCell {
	double dist;
	String key;
};

struct ScoredCellLess {
	bool operator()(const ScoredCell &p_a, const ScoredCell &p_b) const {
		if (p_a.dist == p_b.dist) {
			return p_a.key < p_b.key;
		}
		return p_a.dist < p_b.dist;
	}
};
} //namespace

Array WorldPartitionBake::cells_to_load(const Vector3 &p_source_pos, const Vector3 &p_velocity, const PackedStringArray &p_layers_enabled) const {
	Dictionary cells = baked.get("cells", Dictionary());
	LocalVector<Vector3> samples;
	samples.push_back(p_source_pos);
	int count = MAX(lookahead_samples, 1);
	if (p_velocity.length_squared() > 0.000001) {
		for (int i = 1; i <= count; i++) {
			samples.push_back(p_source_pos + p_velocity * (float)(lookahead_seconds * (double)i / (double)count));
		}
	}
	LocalVector<ScoredCell> scored;
	Array keys = cells.keys();
	for (int ki = 0; ki < keys.size(); ki++) {
		String key = keys[ki];
		Dictionary cell = cells[key];
		PackedStringArray layers = cell["layers"];
		if (!layers.is_empty()) {
			bool enabled = false;
			for (const String &layer : layers) {
				if (p_layers_enabled.has(layer)) {
					enabled = true;
					break;
				}
			}
			if (!enabled) {
				continue;
			}
		}
		double best = Math::INF;
		AABB b = cell["bounds"];
		for (const Vector3 &s : samples) {
			best = MIN(best, _dist_to_cell(s, b));
		}
		if (best <= (double)cell["range"]) {
			scored.push_back({ best, key });
		}
	}
	scored.sort_custom<ScoredCellLess>();
	Array out;
	for (const ScoredCell &s : scored) {
		out.push_back(s.key);
	}
	return out;
}

void WorldPartitionBake::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_lookahead_seconds", "seconds"), &WorldPartitionBake::set_lookahead_seconds);
	ClassDB::bind_method(D_METHOD("get_lookahead_seconds"), &WorldPartitionBake::get_lookahead_seconds);
	ClassDB::bind_method(D_METHOD("set_lookahead_samples", "samples"), &WorldPartitionBake::set_lookahead_samples);
	ClassDB::bind_method(D_METHOD("get_lookahead_samples"), &WorldPartitionBake::get_lookahead_samples);

	ClassDB::bind_static_method("WorldPartitionBake", D_METHOD("stable_guid", "seed"), &WorldPartitionBake::stable_guid);
	ClassDB::bind_method(D_METHOD("bake", "actors", "cell_size", "loading_range_by_layer"), &WorldPartitionBake::bake);
	ClassDB::bind_method(D_METHOD("get_baked"), &WorldPartitionBake::get_baked);
	ClassDB::bind_method(D_METHOD("hlod_clusters", "cells", "cluster_cells"), &WorldPartitionBake::hlod_clusters);
	ClassDB::bind_method(D_METHOD("split_one_file_per_actor", "actors", "dir_path"), &WorldPartitionBake::split_one_file_per_actor);
	ClassDB::bind_method(D_METHOD("load_actors", "dir_path"), &WorldPartitionBake::load_actors);
	ClassDB::bind_method(D_METHOD("diff_bakes", "old_bake", "new_bake"), &WorldPartitionBake::diff_bakes);
	ClassDB::bind_method(D_METHOD("cells_to_load", "source_pos", "velocity", "layers_enabled"), &WorldPartitionBake::cells_to_load);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lookahead_seconds", PROPERTY_HINT_RANGE, "0,60,0.01,or_greater,suffix:s"), "set_lookahead_seconds", "get_lookahead_seconds");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "lookahead_samples", PROPERTY_HINT_RANGE, "1,32,1,or_greater"), "set_lookahead_samples", "get_lookahead_samples");

	BIND_CONSTANT(MAX_LEVEL);
}
