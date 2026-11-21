/**************************************************************************/
/*  pcg_node.h                                                            */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

// PCGContext: what a graph evaluation knows about the world (seed, bounds,
// height/biome/water samplers, exclusion volumes, parameter overrides).
// PCGNode: one step of a graph. C++ nodes override execute(); scripts override
// _execute(inputs, context, seed). Every node sees a deterministic per-node seed
// derived from the world seed, its id and its seed offset, never from the
// streaming cell, so tiles generate seamlessly in any order (seed-based,
// deterministic generation).

#include "pcg_data.h"

#include "core/io/resource.h"
#include "core/object/gdvirtual.gen.h"

class PCGContext : public RefCounted {
	GDCLASS(PCGContext, RefCounted);

	int64_t seed = 1337;
	AABB bounds = AABB(Vector3(-32, -64, -32), Vector3(64, 128, 64));
	Vector2i cell;
	Dictionary overrides; // Graph parameter name -> value (PCG overrides).
	Callable height_sampler; // (x: float, z: float) -> float
	Callable biome_sampler; // (x: float, z: float) -> String
	Callable water_sampler; // (x: float, z: float) -> bool
	Array exclusions; // AABB, or {"center": Vector3, "radius": float} spheres (exclusion volumes).
	Dictionary user_data; // Spline/point sources injected by the game.
	bool debug = false;
	int64_t environment_version = 0; // Bump when samplers change meaning, to invalidate caches.

	// Baked environment grids (thread-safe sampling for async graphs). Cell centres at origin + (i, j) * step.
	Vector2 grid_origin;
	float grid_step = 0.0; // 0 = no baked grids.
	Vector2i grid_size;
	PackedFloat32Array height_grid;
	PackedByteArray water_grid;
	PackedInt32Array biome_grid; // Index into biome_names.
	PackedStringArray biome_names;

	bool _grid_index(float p_x, float p_z, int &r_i, int &r_j) const;

protected:
	static void _bind_methods();

public:
	void set_seed(int64_t p_seed) { seed = p_seed; }
	int64_t get_seed() const { return seed; }
	void set_bounds(const AABB &p_bounds) { bounds = p_bounds; }
	AABB get_bounds() const { return bounds; }
	void set_cell(const Vector2i &p_cell) { cell = p_cell; }
	Vector2i get_cell() const { return cell; }
	void set_overrides(const Dictionary &p_overrides) { overrides = p_overrides; }
	Dictionary get_overrides() const { return overrides; }
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
	void set_debug(bool p_debug) { debug = p_debug; }
	bool is_debug() const { return debug; }
	void set_environment_version(int64_t p_version) { environment_version = p_version; }
	int64_t get_environment_version() const { return environment_version; }

	// Samples the height/water/biome samplers over `p_area` every `p_step` metres (call on the main thread),
	// after which sampling inside the area reads only the grids and is safe on worker threads.
	// The area is grown by two steps so normals at the edge still sample inside.
	void bake_environment(const Rect2 &p_area, float p_step);
	void clear_baked_environment();
	// Full copy, baked grids included (the executor layers parameter overrides on a copy).
	Ref<PCGContext> duplicate_context() const;
	bool has_baked_environment() const { return grid_step > 0.0 && !height_grid.is_empty(); }
	Rect2 get_baked_area() const;

	float sample_height(float p_x, float p_z) const;
	String sample_biome(float p_x, float p_z) const;
	bool sample_water(float p_x, float p_z) const;
	// Surface normal from central differences of the height sampler.
	Vector3 sample_normal(float p_x, float p_z, float p_step = 0.5) const;
	bool is_excluded(const Vector3 &p_point, float p_margin = 0.0) const;
	uint64_t compute_environment_hash() const;
};

class PCGNode : public Resource {
	GDCLASS(PCGNode, Resource);

	int node_id = -1;
	String title;
	Vector2 graph_position;
	bool enabled = true;
	int64_t seed_offset = 0;
	bool debug_output = false;
	Dictionary parameter_bindings; // property -> graph parameter name.

protected:
	static void _bind_methods();

	GDVIRTUAL3RC(Ref<PCGData>, _execute, Array, Ref<PCGContext>, int64_t)
	GDVIRTUAL0RC(int, _get_input_count)
	GDVIRTUAL0RC(String, _get_category)

public:
	void set_node_id(int p_id) { node_id = p_id; }
	int get_node_id() const { return node_id; }
	void set_title(const String &p_title) { title = p_title; }
	String get_title() const;
	void set_graph_position(const Vector2 &p_position) { graph_position = p_position; }
	Vector2 get_graph_position() const { return graph_position; }
	void set_enabled(bool p_enabled);
	bool is_enabled() const { return enabled; }
	void set_seed_offset(int64_t p_offset);
	int64_t get_seed_offset() const { return seed_offset; }
	void set_debug_output(bool p_debug) { debug_output = p_debug; }
	bool is_debug_output() const { return debug_output; }
	void set_parameter_bindings(const Dictionary &p_bindings);
	Dictionary get_parameter_bindings() const { return parameter_bindings; }
	void bind_parameter(const StringName &p_property, const StringName &p_parameter);

	virtual int get_input_count() const;
	virtual String get_category() const;
	// Property value with graph-parameter overrides applied (PCG overrides).
	Variant resolve(const StringName &p_property, const Ref<PCGContext> &p_context) const;
	// Hash of every stored parameter (and the override values bound to them).
	uint64_t compute_param_hash(const Ref<PCGContext> &p_context) const;
	// Nodes that read the context samplers or bounds must say so; their cache key then includes the environment.
	virtual bool uses_environment() const { return get_input_count() == 0; }

	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const;
	Ref<PCGData> execute_script(const Array &p_inputs, const Ref<PCGContext> &p_context, int64_t p_seed) const;

	// First input as points (empty set when missing or of another type).
	static Ref<PCGPointData> points_input(const Vector<Ref<PCGData>> &p_inputs, int p_index);
};
