/**************************************************************************/
/*  pcg_component_3d.h                                                    */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

// Runs a PCGGraph in the scene (Unreal "PCG Component"). Either generates once
// for its own bounds, or streams: the world is cut into square cells around a
// target node and each cell is generated (optionally async) when it comes into
// range and freed when it leaves (runtime PCG, procedural streaming). Points
// become MultiMesh instances per asset and per cluster, with a visibility range
// so far clusters drop out (PCG HLOD integration).

#include "pcg_graph_executor.h"

#include "scene/3d/node_3d.h"
#include "scene/resources/mesh.h"

class PCGComponent3D : public Node3D {
	GDCLASS(PCGComponent3D, Node3D);

	struct Cell {
		Node3D *root = nullptr;
		Ref<PCGPointData> points;
		int64_t job_id = -1;
		bool ready = false;
	};

	Ref<PCGGraph> graph;
	Ref<PCGGraphExecutor> executor;
	int64_t generation_seed = 1337;
	Vector3 extents = Vector3(32, 64, 32);
	Dictionary overrides;
	Callable height_sampler;
	Callable biome_sampler;
	Callable water_sampler;
	Array exclusions;
	Dictionary user_data;
	bool generate_on_ready = false;
	bool async = true;
	bool debug = false;

	bool streaming_enabled = false;
	float cell_size = 64.0;
	int streaming_radius = 2;
	NodePath streaming_target;
	int max_cells_per_frame = 2;

	TypedArray<Mesh> asset_meshes;
	bool cluster_instances = true;
	float visibility_range_end = 0.0; // 0 = always visible.
	bool cast_shadows = true;
	bool align_to_normal = false;

	HashMap<Vector2i, Cell> cells;
	HashMap<int64_t, Vector2i> pending_jobs;
	Dictionary last_profile;

	Ref<PCGContext> _make_context(const AABB &p_bounds, const Vector2i &p_cell) const;
	AABB _cell_bounds(const Vector2i &p_cell) const;
	void _request_cell(const Vector2i &p_cell);
	void _apply_cell(const Vector2i &p_cell, const Dictionary &p_result);
	void _free_cell(const Vector2i &p_cell);
	void _on_job_completed(int64_t p_job_id, const Dictionary &p_result);
	void _update_streaming();
	void _ensure_executor();

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	static Vector2i cell_of(const Vector3 &p_position, float p_cell_size);
	// Instance groups for a point set: {"asset:cluster" -> PackedInt32Array of point indices}.
	static Dictionary group_instances(const Ref<PCGPointData> &p_points, bool p_by_cluster);

	void set_graph(const Ref<PCGGraph> &p_graph);
	Ref<PCGGraph> get_graph() const { return graph; }
	void set_generation_seed(int64_t p_seed);
	int64_t get_generation_seed() const { return generation_seed; }
	void set_extents(const Vector3 &p_extents) { extents = p_extents; }
	Vector3 get_extents() const { return extents; }
	void set_overrides(const Dictionary &p_overrides) { overrides = p_overrides; }
	Dictionary get_overrides() const { return overrides; }
	void set_override(const StringName &p_parameter, const Variant &p_value) { overrides[p_parameter] = p_value; }
	void set_height_sampler(const Callable &p_callable) { height_sampler = p_callable; }
	Callable get_height_sampler() const { return height_sampler; }
	void set_biome_sampler(const Callable &p_callable) { biome_sampler = p_callable; }
	Callable get_biome_sampler() const { return biome_sampler; }
	void set_water_sampler(const Callable &p_callable) { water_sampler = p_callable; }
	Callable get_water_sampler() const { return water_sampler; }
	void set_exclusions(const Array &p_exclusions) { exclusions = p_exclusions; }
	Array get_exclusions() const { return exclusions; }
	void set_user_data(const Dictionary &p_user_data) { user_data = p_user_data; }
	Dictionary get_user_data() const { return user_data; }
	void set_generate_on_ready(bool p_enabled) { generate_on_ready = p_enabled; }
	bool is_generate_on_ready() const { return generate_on_ready; }
	void set_async(bool p_enabled) { async = p_enabled; }
	bool is_async() const { return async; }
	void set_debug(bool p_enabled) { debug = p_enabled; }
	bool is_debug() const { return debug; }
	void set_streaming_enabled(bool p_enabled);
	bool is_streaming_enabled() const { return streaming_enabled; }
	void set_cell_size(float p_size);
	float get_cell_size() const { return cell_size; }
	void set_streaming_radius(int p_radius) { streaming_radius = MAX(0, p_radius); }
	int get_streaming_radius() const { return streaming_radius; }
	void set_streaming_target(const NodePath &p_path) { streaming_target = p_path; }
	NodePath get_streaming_target() const { return streaming_target; }
	void set_max_cells_per_frame(int p_count) { max_cells_per_frame = MAX(1, p_count); }
	int get_max_cells_per_frame() const { return max_cells_per_frame; }
	void set_asset_meshes(const TypedArray<Mesh> &p_meshes) { asset_meshes = p_meshes; }
	TypedArray<Mesh> get_asset_meshes() const { return asset_meshes; }
	void set_cluster_instances(bool p_enabled) { cluster_instances = p_enabled; }
	bool is_cluster_instances() const { return cluster_instances; }
	void set_visibility_range_end(float p_distance) { visibility_range_end = MAX(0.0f, p_distance); }
	float get_visibility_range_end() const { return visibility_range_end; }
	void set_cast_shadows(bool p_enabled) { cast_shadows = p_enabled; }
	bool is_cast_shadows() const { return cast_shadows; }
	void set_align_to_normal(bool p_enabled) { align_to_normal = p_enabled; }
	bool is_align_to_normal() const { return align_to_normal; }
	Ref<PCGGraphExecutor> get_executor();

	// One-shot generation of the component's own bounds (synchronous). Returns the executor result.
	Dictionary generate();
	// Generate one streaming cell now (synchronous); returns its points.
	Ref<PCGPointData> generate_cell(const Vector2i &p_cell);
	void regenerate(); // Drops every cell and the cache, then generates again (interactive editing).
	void clear();
	// Streaming entry point; called every frame while streaming, or manually with a world position.
	void update_streaming_at(const Vector3 &p_position);
	TypedArray<Vector2i> get_loaded_cells() const;
	Ref<PCGPointData> get_cell_points(const Vector2i &p_cell) const;
	Ref<PCGPointData> get_all_points() const;
	int get_pending_cell_count() const { return pending_jobs.size(); }
	Dictionary get_last_profile() const { return last_profile; }
	PackedStringArray get_configuration_warnings() const override;
};
