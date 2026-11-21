/**************************************************************************/
/*  pcg_component_3d.cpp                                                  */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "pcg_component_3d.h"

#include "pcg_exclusion_volume_3d.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "scene/3d/mesh_instance_3d.h"
#include "scene/3d/multimesh_instance_3d.h"
#include "scene/resources/immediate_mesh.h"
#include "scene/resources/material.h"
#include "scene/resources/multimesh.h"

Vector2i PCGComponent3D::cell_of(const Vector3 &p_position, float p_cell_size) {
	const float size = MAX(1.0f, p_cell_size);
	return Vector2i((int)Math::floor(p_position.x / size), (int)Math::floor(p_position.z / size));
}

Dictionary PCGComponent3D::group_instances(const Ref<PCGPointData> &p_points, bool p_by_cluster) {
	Dictionary groups;
	if (p_points.is_null()) {
		return groups;
	}
	const bool has_asset = p_points->has_attribute("asset");
	const bool has_cluster = p_by_cluster && p_points->has_attribute("cluster");
	for (int i = 0; i < p_points->get_point_count(); i++) {
		const int asset = has_asset ? (int)p_points->get_attribute_value("asset", i) : 0;
		if (asset < 0) {
			continue;
		}
		const int cluster = has_cluster ? (int)p_points->get_attribute_value("cluster", i) : 0;
		const String key = vformat("%d:%d", asset, cluster);
		PackedInt32Array indices = groups.get(key, PackedInt32Array());
		indices.push_back(i);
		groups[key] = indices;
	}
	return groups;
}

void PCGComponent3D::_ensure_executor() {
	if (executor.is_valid()) {
		return;
	}
	executor.instantiate();
	executor->connect(SNAME("job_completed"), callable_mp(this, &PCGComponent3D::_on_job_completed));
}

Ref<PCGGraphExecutor> PCGComponent3D::get_executor() {
	_ensure_executor();
	return executor;
}

Ref<PCGContext> PCGComponent3D::_make_context(const AABB &p_bounds, const Vector2i &p_cell) const {
	Ref<PCGContext> context;
	context.instantiate();
	context->set_seed(generation_seed);
	context->set_bounds(p_bounds);
	context->set_cell(p_cell);
	context->set_overrides(overrides);
	context->set_height_sampler(height_sampler);
	context->set_biome_sampler(biome_sampler);
	context->set_water_sampler(water_sampler);
	Array all_exclusions = exclusions.duplicate();
	if (use_scene_exclusion_volumes && is_inside_tree()) {
		// Only volumes touching this cell, so moving one volume invalidates only nearby cells.
		all_exclusions.append_array(PCGExclusionVolume3D::gather(get_tree(), p_bounds, 1.0));
	}
	context->set_exclusions(all_exclusions);
	context->set_user_data(user_data);
	context->set_debug(debug);
	return context;
}

int64_t PCGComponent3D::compute_cell_cache_key(const Vector2i &p_cell) const {
	uint64_t h = pcg_mix64(0x5043474345ULL, graph.is_valid() ? (uint64_t)graph->compute_fingerprint() : 0);
	h = pcg_mix64(h, (uint64_t)generation_seed);
	h = pcg_mix64(pcg_mix64(h, (uint64_t)(int64_t)p_cell.x), (uint64_t)(int64_t)p_cell.y);
	h = pcg_hash_double(h, streaming_enabled ? cell_size : 0.0);
	h = pcg_hash_double(pcg_hash_double(pcg_hash_double(h, extents.x), extents.y), extents.z);
	h = pcg_mix64(h, (uint64_t)overrides.hash());
	h = pcg_mix64(h, (uint64_t)user_data.hash());
	h = pcg_mix64(h, (uint64_t)exclusions.hash());
	if (use_scene_exclusion_volumes && is_inside_tree()) {
		h = pcg_mix64(h, (uint64_t)PCGExclusionVolume3D::gather(get_tree(), _cell_bounds(p_cell), 1.0).hash());
	}
	return (int64_t)pcg_mix64(h, (uint64_t)cache_version);
}

String PCGComponent3D::_cache_path(const Vector2i &p_cell) const {
	return persistent_cache_dir.path_join(String::num_uint64((uint64_t)compute_cell_cache_key(p_cell), 16) + ".pcgcell");
}

Ref<PCGPointData> PCGComponent3D::_load_cached_cell(const Vector2i &p_cell) const {
	if (persistent_cache_dir.is_empty() || graph.is_null()) {
		return Ref<PCGPointData>();
	}
	const String path = _cache_path(p_cell);
	if (!FileAccess::exists(path)) {
		return Ref<PCGPointData>();
	}
	Ref<FileAccess> file = FileAccess::open(path, FileAccess::READ);
	if (file.is_null()) {
		return Ref<PCGPointData>();
	}
	const Variant data = file->get_var(false);
	if (data.get_type() != Variant::DICTIONARY) {
		return Ref<PCGPointData>();
	}
	return PCGPointData::from_dictionary(data);
}

void PCGComponent3D::_save_cached_cell(const Vector2i &p_cell, const Ref<PCGPointData> &p_points) {
	if (persistent_cache_dir.is_empty() || graph.is_null() || p_points.is_null()) {
		return;
	}
	DirAccess::make_dir_recursive_absolute(persistent_cache_dir);
	Ref<FileAccess> file = FileAccess::open(_cache_path(p_cell), FileAccess::WRITE);
	if (file.is_null()) {
		return;
	}
	file->store_var(p_points->to_dictionary(), false);
	cache_saves++;
}

Dictionary PCGComponent3D::get_cache_stats() const {
	Dictionary stats;
	stats["loads"] = cache_loads;
	stats["saves"] = cache_saves;
	return stats;
}

int PCGComponent3D::clear_persistent_cache() {
	if (persistent_cache_dir.is_empty()) {
		return 0;
	}
	Ref<DirAccess> dir = DirAccess::open(persistent_cache_dir);
	if (dir.is_null()) {
		return 0;
	}
	int removed = 0;
	const PackedStringArray files = dir->get_files();
	for (const String &name : files) {
		if (name.ends_with(".pcgcell") && dir->remove(name) == OK) {
			removed++;
		}
	}
	return removed;
}

AABB PCGComponent3D::_cell_bounds(const Vector2i &p_cell) const {
	return AABB(Vector3(p_cell.x * cell_size, -extents.y, p_cell.y * cell_size), Vector3(cell_size, extents.y * 2.0, cell_size));
}

void PCGComponent3D::_request_cell(const Vector2i &p_cell) {
	if (graph.is_null() || cells.has(p_cell)) {
		return;
	}
	_ensure_executor();
	Cell cell;
	cells[p_cell] = cell;
	// Procedural cache on disk: a finished cell loads instead of running the graph.
	Ref<PCGPointData> cached = _load_cached_cell(p_cell);
	if (cached.is_valid()) {
		cache_loads++;
		Dictionary result;
		result["output"] = cached;
		result["from_disk_cache"] = true;
		_apply_cell(p_cell, result);
		return;
	}
	Ref<PCGContext> context = _make_context(_cell_bounds(p_cell), p_cell);
	if (async && is_inside_tree()) {
		if (bake_step > 0.0f) {
			// Scripts' samplers are not thread-safe: read them here, let the worker read the grids.
			const AABB bounds = context->get_bounds();
			context->bake_environment(Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z), bake_step);
		}
		const int64_t job = executor->execute_async(graph, context);
		cells[p_cell].job_id = job;
		pending_jobs[job] = p_cell;
	} else {
		_apply_cell(p_cell, executor->execute(graph, context));
	}
}

void PCGComponent3D::_on_job_completed(int64_t p_job_id, const Dictionary &p_result) {
	if (!pending_jobs.has(p_job_id)) {
		return;
	}
	const Vector2i cell = pending_jobs[p_job_id];
	pending_jobs.erase(p_job_id);
	if (!cells.has(cell) || cells[cell].job_id != p_job_id) {
		return; // The cell left range (or was regenerated) while the job ran.
	}
	_apply_cell(cell, p_result);
}

void PCGComponent3D::_apply_cell(const Vector2i &p_cell, const Dictionary &p_result) {
	if (!cells.has(p_cell)) {
		return;
	}
	last_profile = p_result;
	last_profile.erase("node_outputs");
	if (p_result.has("error")) {
		ERR_PRINT(vformat("PCG generation failed: %s", String(p_result["error"])));
	}
	Ref<PCGPointData> points = p_result.get("output", Variant());
	if (points.is_null()) {
		points.instantiate();
	}
	Cell &cell = cells[p_cell];
	cell.points = points;
	cell.ready = true;
	cell.job_id = -1;
	if (cell.root != nullptr) {
		cell.root->queue_free();
		cell.root = nullptr;
	}
	if ((!asset_meshes.is_empty() || debug_draw) && is_inside_tree()) {
		Node3D *root = memnew(Node3D);
		root->set_name(vformat("PCGCell_%d_%d", p_cell.x, p_cell.y));
		add_child(root, false, INTERNAL_MODE_FRONT);
		cell.root = root;
		_build_cell_visuals(root, points);
	}
	if (!bool(p_result.get("from_disk_cache", false)) && !p_result.has("error")) {
		_save_cached_cell(p_cell, points);
	}
	emit_signal(SNAME("cell_generated"), p_cell, points);
}

void PCGComponent3D::_build_cell_visuals(Node3D *p_root, const Ref<PCGPointData> &p_points) {
	const Transform3D to_local = get_global_transform().affine_inverse();
	const Dictionary groups = group_instances(p_points, cluster_instances);
	Array keys = groups.keys();
	keys.sort();
	for (int g = 0; g < keys.size(); g++) {
		const int asset = String(keys[g]).get_slicec(':', 0).to_int();
		const PackedInt32Array indices = groups[keys[g]];
		// Level 0: the real mesh up to visibility_range_end; level 1 (HLOD): the proxy beyond it.
		for (int level = 0; level < 2; level++) {
			const TypedArray<Mesh> &meshes = level == 0 ? asset_meshes : asset_proxy_meshes;
			if (level == 1 && visibility_range_end <= 0.0f) {
				break;
			}
			if (asset < 0 || asset >= meshes.size()) {
				continue;
			}
			Ref<Mesh> mesh = meshes[asset];
			if (mesh.is_null()) {
				continue;
			}
			Ref<MultiMesh> multimesh;
			multimesh.instantiate();
			multimesh->set_transform_format(MultiMesh::TRANSFORM_3D);
			multimesh->set_mesh(mesh);
			multimesh->set_instance_count(indices.size());
			for (int i = 0; i < indices.size(); i++) {
				multimesh->set_instance_transform(i, to_local * p_points->get_point_transform(indices[i], align_to_normal));
			}
			MultiMeshInstance3D *instance = memnew(MultiMeshInstance3D);
			instance->set_name(level == 0 ? String(keys[g]) : String(keys[g]) + "_hlod");
			instance->set_multimesh(multimesh);
			const float margin = MIN(visibility_range_end * 0.1f, 16.0f);
			if (level == 0) {
				instance->set_cast_shadows_setting(cast_shadows ? GeometryInstance3D::SHADOW_CASTING_SETTING_ON : GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
				if (visibility_range_end > 0.0f) {
					instance->set_visibility_range_end(visibility_range_end);
					instance->set_visibility_range_end_margin(margin);
					instance->set_visibility_range_fade_mode(GeometryInstance3D::VISIBILITY_RANGE_FADE_SELF);
				}
			} else {
				// Proxies cast no shadows (distant shadow cascades are coarse anyway) and cross-fade in.
				instance->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
				instance->set_visibility_range_begin(visibility_range_end);
				instance->set_visibility_range_begin_margin(margin);
				if (proxy_range_end > visibility_range_end) {
					instance->set_visibility_range_end(proxy_range_end);
					instance->set_visibility_range_end_margin(MIN(proxy_range_end * 0.1f, 32.0f));
				}
				instance->set_visibility_range_fade_mode(GeometryInstance3D::VISIBILITY_RANGE_FADE_SELF);
			}
			p_root->add_child(instance);
		}
	}
	if (debug_draw && p_points->get_point_count() > 0) {
		// Runtime PCG debugging: a small cross per point, hue by asset index (grey when unassigned).
		Ref<ImmediateMesh> lines;
		lines.instantiate();
		Ref<StandardMaterial3D> material;
		material.instantiate();
		material->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
		material->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
		material->set_flag(BaseMaterial3D::FLAG_DISABLE_DEPTH_TEST, true);
		lines->surface_begin(Mesh::PRIMITIVE_LINES, material);
		const bool has_asset = p_points->has_attribute("asset");
		for (int i = 0; i < p_points->get_point_count(); i++) {
			const int asset = has_asset ? (int)p_points->get_attribute_value("asset", i) : -1;
			const Color color = asset < 0 ? Color(0.7, 0.7, 0.7) : Color::from_hsv(Math::fmod(asset * 0.161803f, 1.0f), 0.85, 1.0);
			const Vector3 p = to_local.xform(p_points->get_position(i));
			const float s = 0.35f * MAX(0.2f, p_points->get_scale(i));
			const Vector3 axes[3] = { Vector3(s, 0, 0), Vector3(0, s * 2.0f, 0), Vector3(0, 0, s) };
			for (int a = 0; a < 3; a++) {
				lines->surface_set_color(color);
				lines->surface_add_vertex(p - (a == 1 ? Vector3() : axes[a]));
				lines->surface_set_color(color);
				lines->surface_add_vertex(p + axes[a]);
			}
		}
		lines->surface_end();
		MeshInstance3D *debug_instance = memnew(MeshInstance3D);
		debug_instance->set_name("PCGDebugPoints");
		debug_instance->set_mesh(lines);
		debug_instance->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
		p_root->add_child(debug_instance);
	}
}

void PCGComponent3D::_free_cell(const Vector2i &p_cell) {
	if (!cells.has(p_cell)) {
		return;
	}
	Cell &cell = cells[p_cell];
	if (cell.job_id >= 0) {
		pending_jobs.erase(cell.job_id); // Result is ignored when it lands.
	}
	if (cell.root != nullptr) {
		cell.root->queue_free();
	}
	cells.erase(p_cell);
	emit_signal(SNAME("cell_unloaded"), p_cell);
}

void PCGComponent3D::update_streaming_at(const Vector3 &p_position) {
	if (graph.is_null()) {
		return;
	}
	const Vector2i center = cell_of(p_position, cell_size);
	// Free cells beyond radius + 1 (hysteresis keeps edge cells from flickering).
	Vector<Vector2i> drop;
	for (const KeyValue<Vector2i, Cell> &E : cells) {
		const Vector2i d = E.key - center;
		if (MAX(Math::abs(d.x), Math::abs(d.y)) > streaming_radius + 1) {
			drop.push_back(E.key);
		}
	}
	for (const Vector2i &c : drop) {
		_free_cell(c);
	}
	// Request missing cells nearest first, a few per frame.
	int requested = 0;
	for (int ring = 0; ring <= streaming_radius && requested < max_cells_per_frame; ring++) {
		for (int dz = -ring; dz <= ring && requested < max_cells_per_frame; dz++) {
			for (int dx = -ring; dx <= ring && requested < max_cells_per_frame; dx++) {
				if (MAX(Math::abs(dx), Math::abs(dz)) != ring) {
					continue;
				}
				const Vector2i c(center.x + dx, center.y + dz);
				if (!cells.has(c)) {
					_request_cell(c);
					requested++;
				}
			}
		}
	}
}

void PCGComponent3D::_update_streaming() {
	Vector3 position = get_global_position();
	if (!streaming_target.is_empty()) {
		Node3D *target = Object::cast_to<Node3D>(get_node_or_null(streaming_target));
		if (target != nullptr) {
			position = target->get_global_position();
		}
	}
	update_streaming_at(position);
}

Dictionary PCGComponent3D::generate() {
	clear();
	if (graph.is_null()) {
		return Dictionary();
	}
	_ensure_executor();
	const Vector3 center = is_inside_tree() ? get_global_position() : Vector3();
	Ref<PCGContext> context = _make_context(AABB(center - extents, extents * 2.0), Vector2i());
	Dictionary result = executor->execute(graph, context);
	Cell cell;
	cells[Vector2i()] = cell;
	_apply_cell(Vector2i(), result);
	return result;
}

Ref<PCGPointData> PCGComponent3D::generate_cell(const Vector2i &p_cell) {
	_free_cell(p_cell);
	const bool was_async = async;
	async = false;
	_request_cell(p_cell);
	async = was_async;
	return get_cell_points(p_cell);
}

void PCGComponent3D::regenerate() {
	clear();
	if (executor.is_valid()) {
		executor->clear_cache();
	}
	if (!streaming_enabled) {
		generate();
	}
}

void PCGComponent3D::clear() {
	Vector<Vector2i> all;
	for (const KeyValue<Vector2i, Cell> &E : cells) {
		all.push_back(E.key);
	}
	for (const Vector2i &c : all) {
		_free_cell(c);
	}
	pending_jobs.clear();
}

TypedArray<Vector2i> PCGComponent3D::get_loaded_cells() const {
	TypedArray<Vector2i> list;
	for (const KeyValue<Vector2i, Cell> &E : cells) {
		if (E.value.ready) {
			list.push_back(E.key);
		}
	}
	return list;
}

Ref<PCGPointData> PCGComponent3D::get_cell_points(const Vector2i &p_cell) const {
	if (!cells.has(p_cell) || cells[p_cell].points.is_null()) {
		return Ref<PCGPointData>();
	}
	return cells[p_cell].points;
}

Ref<PCGPointData> PCGComponent3D::get_all_points() const {
	Ref<PCGPointData> all;
	all.instantiate();
	// Deterministic order regardless of load order.
	Vector<Vector2i> keys;
	for (const KeyValue<Vector2i, Cell> &E : cells) {
		if (E.value.points.is_valid()) {
			keys.push_back(E.key);
		}
	}
	keys.sort();
	for (const Vector2i &k : keys) {
		all->append(cells[k].points);
	}
	return all;
}

void PCGComponent3D::set_graph(const Ref<PCGGraph> &p_graph) {
	graph = p_graph;
	update_configuration_warnings();
}

void PCGComponent3D::set_generation_seed(int64_t p_seed) {
	generation_seed = p_seed;
}

void PCGComponent3D::set_streaming_enabled(bool p_enabled) {
	streaming_enabled = p_enabled;
	set_process(streaming_enabled && is_inside_tree());
}

void PCGComponent3D::set_cell_size(float p_size) {
	cell_size = MAX(1.0f, p_size);
}

PackedStringArray PCGComponent3D::get_configuration_warnings() const {
	PackedStringArray warnings = Node3D::get_configuration_warnings();
	if (graph.is_null()) {
		warnings.push_back(RTR("Assign a PCGGraph to generate content."));
	} else if (graph->has_cycle()) {
		warnings.push_back(RTR("The PCGGraph has a cycle and cannot be evaluated."));
	}
	return warnings;
}

void PCGComponent3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY: {
			set_process(streaming_enabled);
			if (generate_on_ready && !streaming_enabled) {
				generate();
			}
		} break;
		case NOTIFICATION_PROCESS: {
			if (streaming_enabled) {
				_update_streaming();
			}
		} break;
		case NOTIFICATION_EXIT_TREE: {
			clear();
		} break;
	}
}

void PCGComponent3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_graph", "graph"), &PCGComponent3D::set_graph);
	ClassDB::bind_method(D_METHOD("get_graph"), &PCGComponent3D::get_graph);
	ClassDB::bind_method(D_METHOD("set_generation_seed", "seed"), &PCGComponent3D::set_generation_seed);
	ClassDB::bind_method(D_METHOD("get_generation_seed"), &PCGComponent3D::get_generation_seed);
	ClassDB::bind_method(D_METHOD("set_extents", "extents"), &PCGComponent3D::set_extents);
	ClassDB::bind_method(D_METHOD("get_extents"), &PCGComponent3D::get_extents);
	ClassDB::bind_method(D_METHOD("set_overrides", "overrides"), &PCGComponent3D::set_overrides);
	ClassDB::bind_method(D_METHOD("get_overrides"), &PCGComponent3D::get_overrides);
	ClassDB::bind_method(D_METHOD("set_override", "parameter", "value"), &PCGComponent3D::set_override);
	ClassDB::bind_method(D_METHOD("set_height_sampler", "callable"), &PCGComponent3D::set_height_sampler);
	ClassDB::bind_method(D_METHOD("get_height_sampler"), &PCGComponent3D::get_height_sampler);
	ClassDB::bind_method(D_METHOD("set_biome_sampler", "callable"), &PCGComponent3D::set_biome_sampler);
	ClassDB::bind_method(D_METHOD("get_biome_sampler"), &PCGComponent3D::get_biome_sampler);
	ClassDB::bind_method(D_METHOD("set_water_sampler", "callable"), &PCGComponent3D::set_water_sampler);
	ClassDB::bind_method(D_METHOD("get_water_sampler"), &PCGComponent3D::get_water_sampler);
	ClassDB::bind_method(D_METHOD("set_exclusions", "exclusions"), &PCGComponent3D::set_exclusions);
	ClassDB::bind_method(D_METHOD("get_exclusions"), &PCGComponent3D::get_exclusions);
	ClassDB::bind_method(D_METHOD("set_user_data", "user_data"), &PCGComponent3D::set_user_data);
	ClassDB::bind_method(D_METHOD("get_user_data"), &PCGComponent3D::get_user_data);
	ClassDB::bind_method(D_METHOD("set_generate_on_ready", "enabled"), &PCGComponent3D::set_generate_on_ready);
	ClassDB::bind_method(D_METHOD("is_generate_on_ready"), &PCGComponent3D::is_generate_on_ready);
	ClassDB::bind_method(D_METHOD("set_async", "enabled"), &PCGComponent3D::set_async);
	ClassDB::bind_method(D_METHOD("is_async"), &PCGComponent3D::is_async);
	ClassDB::bind_method(D_METHOD("set_debug", "enabled"), &PCGComponent3D::set_debug);
	ClassDB::bind_method(D_METHOD("is_debug"), &PCGComponent3D::is_debug);
	ClassDB::bind_method(D_METHOD("set_streaming_enabled", "enabled"), &PCGComponent3D::set_streaming_enabled);
	ClassDB::bind_method(D_METHOD("is_streaming_enabled"), &PCGComponent3D::is_streaming_enabled);
	ClassDB::bind_method(D_METHOD("set_cell_size", "size"), &PCGComponent3D::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &PCGComponent3D::get_cell_size);
	ClassDB::bind_method(D_METHOD("set_streaming_radius", "radius"), &PCGComponent3D::set_streaming_radius);
	ClassDB::bind_method(D_METHOD("get_streaming_radius"), &PCGComponent3D::get_streaming_radius);
	ClassDB::bind_method(D_METHOD("set_streaming_target", "path"), &PCGComponent3D::set_streaming_target);
	ClassDB::bind_method(D_METHOD("get_streaming_target"), &PCGComponent3D::get_streaming_target);
	ClassDB::bind_method(D_METHOD("set_max_cells_per_frame", "count"), &PCGComponent3D::set_max_cells_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_cells_per_frame"), &PCGComponent3D::get_max_cells_per_frame);
	ClassDB::bind_method(D_METHOD("set_asset_meshes", "meshes"), &PCGComponent3D::set_asset_meshes);
	ClassDB::bind_method(D_METHOD("get_asset_meshes"), &PCGComponent3D::get_asset_meshes);
	ClassDB::bind_method(D_METHOD("set_cluster_instances", "enabled"), &PCGComponent3D::set_cluster_instances);
	ClassDB::bind_method(D_METHOD("is_cluster_instances"), &PCGComponent3D::is_cluster_instances);
	ClassDB::bind_method(D_METHOD("set_visibility_range_end", "distance"), &PCGComponent3D::set_visibility_range_end);
	ClassDB::bind_method(D_METHOD("get_visibility_range_end"), &PCGComponent3D::get_visibility_range_end);
	ClassDB::bind_method(D_METHOD("set_cast_shadows", "enabled"), &PCGComponent3D::set_cast_shadows);
	ClassDB::bind_method(D_METHOD("is_cast_shadows"), &PCGComponent3D::is_cast_shadows);
	ClassDB::bind_method(D_METHOD("set_align_to_normal", "enabled"), &PCGComponent3D::set_align_to_normal);
	ClassDB::bind_method(D_METHOD("is_align_to_normal"), &PCGComponent3D::is_align_to_normal);
	ClassDB::bind_method(D_METHOD("get_executor"), &PCGComponent3D::get_executor);
	ClassDB::bind_method(D_METHOD("set_bake_step", "step"), &PCGComponent3D::set_bake_step);
	ClassDB::bind_method(D_METHOD("get_bake_step"), &PCGComponent3D::get_bake_step);
	ClassDB::bind_method(D_METHOD("set_use_scene_exclusion_volumes", "enabled"), &PCGComponent3D::set_use_scene_exclusion_volumes);
	ClassDB::bind_method(D_METHOD("is_use_scene_exclusion_volumes"), &PCGComponent3D::is_use_scene_exclusion_volumes);
	ClassDB::bind_method(D_METHOD("set_persistent_cache_dir", "dir"), &PCGComponent3D::set_persistent_cache_dir);
	ClassDB::bind_method(D_METHOD("get_persistent_cache_dir"), &PCGComponent3D::get_persistent_cache_dir);
	ClassDB::bind_method(D_METHOD("set_cache_version", "version"), &PCGComponent3D::set_cache_version);
	ClassDB::bind_method(D_METHOD("get_cache_version"), &PCGComponent3D::get_cache_version);
	ClassDB::bind_method(D_METHOD("set_asset_proxy_meshes", "meshes"), &PCGComponent3D::set_asset_proxy_meshes);
	ClassDB::bind_method(D_METHOD("get_asset_proxy_meshes"), &PCGComponent3D::get_asset_proxy_meshes);
	ClassDB::bind_method(D_METHOD("set_proxy_range_end", "distance"), &PCGComponent3D::set_proxy_range_end);
	ClassDB::bind_method(D_METHOD("get_proxy_range_end"), &PCGComponent3D::get_proxy_range_end);
	ClassDB::bind_method(D_METHOD("set_debug_draw", "enabled"), &PCGComponent3D::set_debug_draw);
	ClassDB::bind_method(D_METHOD("is_debug_draw"), &PCGComponent3D::is_debug_draw);
	ClassDB::bind_method(D_METHOD("get_cache_stats"), &PCGComponent3D::get_cache_stats);
	ClassDB::bind_method(D_METHOD("clear_persistent_cache"), &PCGComponent3D::clear_persistent_cache);
	ClassDB::bind_method(D_METHOD("compute_cell_cache_key", "cell"), &PCGComponent3D::compute_cell_cache_key);
	ClassDB::bind_method(D_METHOD("generate"), &PCGComponent3D::generate);
	ClassDB::bind_method(D_METHOD("generate_cell", "cell"), &PCGComponent3D::generate_cell);
	ClassDB::bind_method(D_METHOD("regenerate"), &PCGComponent3D::regenerate);
	ClassDB::bind_method(D_METHOD("clear"), &PCGComponent3D::clear);
	ClassDB::bind_method(D_METHOD("update_streaming_at", "position"), &PCGComponent3D::update_streaming_at);
	ClassDB::bind_method(D_METHOD("get_loaded_cells"), &PCGComponent3D::get_loaded_cells);
	ClassDB::bind_method(D_METHOD("get_cell_points", "cell"), &PCGComponent3D::get_cell_points);
	ClassDB::bind_method(D_METHOD("get_all_points"), &PCGComponent3D::get_all_points);
	ClassDB::bind_method(D_METHOD("get_pending_cell_count"), &PCGComponent3D::get_pending_cell_count);
	ClassDB::bind_method(D_METHOD("get_last_profile"), &PCGComponent3D::get_last_profile);
	ClassDB::bind_static_method("PCGComponent3D", D_METHOD("cell_of", "position", "cell_size"), &PCGComponent3D::cell_of);
	ClassDB::bind_static_method("PCGComponent3D", D_METHOD("group_instances", "points", "by_cluster"), &PCGComponent3D::group_instances);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "graph", PROPERTY_HINT_RESOURCE_TYPE, "PCGGraph"), "set_graph", "get_graph");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "generation_seed"), "set_generation_seed", "get_generation_seed");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "extents"), "set_extents", "get_extents");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "overrides"), "set_overrides", "get_overrides");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "generate_on_ready"), "set_generate_on_ready", "is_generate_on_ready");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "async"), "set_async", "is_async");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "debug"), "set_debug", "is_debug");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "debug_draw"), "set_debug_draw", "is_debug_draw");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "bake_step", PROPERTY_HINT_RANGE, "0,16,0.25,suffix:m"), "set_bake_step", "get_bake_step");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_scene_exclusion_volumes"), "set_use_scene_exclusion_volumes", "is_use_scene_exclusion_volumes");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "persistent_cache_dir", PROPERTY_HINT_DIR), "set_persistent_cache_dir", "get_persistent_cache_dir");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "cache_version"), "set_cache_version", "get_cache_version");
	ADD_GROUP("Streaming", "");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "streaming_enabled"), "set_streaming_enabled", "is_streaming_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "1,1024,1,or_greater"), "set_cell_size", "get_cell_size");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "streaming_radius", PROPERTY_HINT_RANGE, "0,16,1"), "set_streaming_radius", "get_streaming_radius");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "streaming_target", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "Node3D"), "set_streaming_target", "get_streaming_target");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_cells_per_frame", PROPERTY_HINT_RANGE, "1,64,1"), "set_max_cells_per_frame", "get_max_cells_per_frame");
	ADD_GROUP("Instances", "");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "asset_meshes", PROPERTY_HINT_ARRAY_TYPE, "Mesh"), "set_asset_meshes", "get_asset_meshes");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "cluster_instances"), "set_cluster_instances", "is_cluster_instances");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "visibility_range_end", PROPERTY_HINT_RANGE, "0,4096,1,or_greater,suffix:m"), "set_visibility_range_end", "get_visibility_range_end");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "cast_shadows"), "set_cast_shadows", "is_cast_shadows");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "align_to_normal"), "set_align_to_normal", "is_align_to_normal");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "asset_proxy_meshes", PROPERTY_HINT_ARRAY_TYPE, "Mesh"), "set_asset_proxy_meshes", "get_asset_proxy_meshes");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "proxy_range_end", PROPERTY_HINT_RANGE, "0,8192,1,or_greater,suffix:m"), "set_proxy_range_end", "get_proxy_range_end");

	ADD_SIGNAL(MethodInfo("cell_generated", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::OBJECT, "points", PROPERTY_HINT_RESOURCE_TYPE, "PCGPointData")));
	ADD_SIGNAL(MethodInfo("cell_unloaded", PropertyInfo(Variant::VECTOR2I, "cell")));
}
