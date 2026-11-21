/**************************************************************************/
/*  cgame_pcg_graph.h                                                     */
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

#include "core/math/aabb.h"
#include "core/math/rect2.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/variant/callable.h"
#include "core/variant/typed_array.h"

// Procedural content graph runtime (UE5 PCG-style): typed point-data graphs with subgraphs, an
// extension API, a dependency-aware incremental cache, a per-node debugger and per-world-partition-cell
// execution. See doc_classes/CgamePCGGraph.xml for the data model.
class CgamePCGGraph : public RefCounted {
	GDCLASS(CgamePCGGraph, RefCounted);

public:
	enum Builtin {
		BUILTIN_NONE = -1,
		BUILTIN_SURFACE_SAMPLER,
		BUILTIN_SPLINE_SAMPLER,
		BUILTIN_VOLUME_SAMPLER,
		BUILTIN_DENSITY_NOISE,
		BUILTIN_DENSITY_FILTER,
		BUILTIN_SELF_PRUNING,
		BUILTIN_DIFFERENCE,
		BUILTIN_TRANSFORM_POINTS,
		BUILTIN_ATTRIBUTE_SET,
		BUILTIN_MERGE,
		BUILTIN_PARTITION_BY_ATTRIBUTE,
		BUILTIN_COPY_POINTS,
		BUILTIN_CONSTANT_VOLUME,
		BUILTIN_STATIC_MESH_SPAWNER,
		BUILTIN_INSTANCED_SCENE_OUTPUT,
		BUILTIN_MATERIAL_LAYER_OUTPUT,
	};

private:
	struct NodeDef {
		Dictionary in_pins;
		Dictionary out_pins;
		Callable exec;
		Builtin builtin = BUILTIN_NONE;
	};

	struct NodePins {
		Dictionary in;
		Dictionary out;
	};

	struct EvalState {
		Dictionary inputs;
		String scope;
		Dictionary bounds;
		int64_t seed = 0;
		int step = 0;
	};

	int64_t graph_seed = 0;
	Dictionary nodes;
	TypedArray<Dictionary> edges;
	// Node ids that actually ran in the last execute()/partition_execute() (cache misses), in order.
	TypedArray<String> executed_nodes;
	int cache_hits = 0;
	TypedArray<String> last_errors;
	bool debug_enabled = true;
	int debug_sample_count = 5;
	bool debug_capture_full = false;
	// node id -> {step, type, executed, usec, in_counts, outputs, ...}
	Dictionary debug;
	// Same entries in dependency order, for step-by-step stepping.
	TypedArray<Dictionary> debug_steps;

	HashMap<String, NodeDef> defs;
	Dictionary cache;
	Dictionary last_results;

	void _reg(const String &p_type, const Dictionary &p_in, const Dictionary &p_out, const Callable &p_exec, Builtin p_builtin);
	void _register_builtins();
	bool _is_known(const String &p_type) const;
	NodePins _node_pins(const String &p_id) const;
	String _check_edge(const String &p_from_id, const String &p_from_pin, const String &p_to_id, const String &p_to_pin) const;
	bool _has_cycle() const;
	bool _dfs_cycle(const String &p_id, HashMap<String, int> &r_state) const;
	int64_t _params_hash(const Dictionary &p_params) const;

	Dictionary _eval(const String &p_id, EvalState &r_state);
	Dictionary _exec_node(const String &p_id, const String &p_type, const Dictionary &p_params, const Dictionary &p_ins, const Dictionary &p_ctx, EvalState &r_state, const Variant &p_graph_in_data);
	Dictionary _exec_builtin(Builtin p_builtin, const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	void _capture(const String &p_id, const String &p_type, bool p_executed, int64_t p_usec, const Dictionary &p_in_summ, const Dictionary &p_entry, EvalState &r_state);

	static int64_t _sum_counts(const Array &p_vals);
	static Dictionary _assemble(const PackedVector3Array &p_pos, const PackedFloat32Array &p_dens, const PackedFloat32Array &p_scl, const PackedFloat32Array &p_rot, const PackedInt64Array &p_sd, const Dictionary &p_extras);
	static Dictionary _empty_points();
	static Dictionary _in_pts(const Dictionary &p_inputs, const StringName &p_pin);
	static Dictionary _select(const Dictionary &p_pts, const Vector<int> &p_idx);
	static double _attr_f(const Dictionary &p_attrs, const StringName &p_name, int p_i);
	static Variant _crop(const Variant &p_data, const Rect2 &p_rect);
	static Rect2 _area(const AABB &p_box, const Dictionary &p_ctx, bool p_use_box);
	static bool _in_rect(const Rect2 &p_rect, double p_x, double p_z);
	static Transform3D _point_transform(const Vector3 &p_pos, double p_scale, double p_yaw);
	static String _base(const String &p_type);
	static bool _is_multi(const String &p_type);

	// Built-in nodes.
	Dictionary _n_constant_volume(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_surface_sampler(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_volume_sampler(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_spline_sampler(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_density_noise(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_density_filter(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_self_pruning(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_difference(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_transform_points(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_attribute_set(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_merge(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_partition_by_attribute(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_copy_points(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_static_mesh_spawner(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_instanced_scene_output(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;
	Dictionary _n_material_layer_output(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const;

protected:
	static void _bind_methods();

public:
	static constexpr double BIG = 1.0e6;

	// Property accessors.
	void set_graph_seed(int64_t p_seed) { graph_seed = p_seed; }
	int64_t get_graph_seed() const { return graph_seed; }
	void set_nodes(const Dictionary &p_nodes) { nodes = p_nodes; }
	Dictionary get_nodes() const { return nodes; }
	void set_edges(const TypedArray<Dictionary> &p_edges) { edges = p_edges; }
	TypedArray<Dictionary> get_edges() const { return edges; }
	TypedArray<String> get_executed_nodes() const { return executed_nodes; }
	int get_cache_hits() const { return cache_hits; }
	TypedArray<String> get_last_errors() const { return last_errors; }
	void set_debug_enabled(bool p_enabled) { debug_enabled = p_enabled; }
	bool is_debug_enabled() const { return debug_enabled; }
	void set_debug_sample_count(int p_count) { debug_sample_count = MAX(0, p_count); }
	int get_debug_sample_count() const { return debug_sample_count; }
	void set_debug_capture_full(bool p_full) { debug_capture_full = p_full; }
	bool is_debug_capture_full() const { return debug_capture_full; }
	Dictionary get_debug() const { return debug; }
	TypedArray<Dictionary> get_debug_steps() const { return debug_steps; }

	// Data constructors.
	static Dictionary make_points(const PackedVector3Array &p_positions = PackedVector3Array());
	static Dictionary make_spline(const PackedVector3Array &p_points, bool p_closed = false);
	static Dictionary make_volume(const AABB &p_box);
	static Dictionary make_landscape(const Callable &p_height_at, const Callable &p_normal_at = Callable());
	static int64_t point_count(const Variant &p_data);
	static double landscape_height(const Variant &p_landscape, double p_x, double p_z, double p_fallback);
	static Vector3 landscape_normal(const Variant &p_landscape, double p_x, double p_z);
	static Dictionary summarize(const Variant &p_data, int p_sample_count);

	// Hashing / random.
	static int64_t mix64(int64_t p_x);
	static int64_t hash3(int64_t p_a, int64_t p_b, int64_t p_c);
	static double rand01(int64_t p_h);

	// Graph building.
	void register_node(const String &p_type, const Dictionary &p_input_pins, const Dictionary &p_output_pins, const Callable &p_execute);
	String add_node(const String &p_id, const String &p_type, const Dictionary &p_params = Dictionary());
	void set_param(const String &p_id, const String &p_key, const Variant &p_value);
	Variant get_param(const String &p_id, const String &p_key, const Variant &p_default = Variant()) const;
	String link(const String &p_from_id, const String &p_from_pin, const String &p_to_id, const String &p_to_pin);
	String add_graph_input(const String &p_id, const String &p_pin_name, const String &p_pin_type);
	String add_graph_output(const String &p_id, const String &p_pin_name, const String &p_pin_type);
	Dictionary get_io_pins(bool p_inputs) const;
	static bool pins_compatible(const String &p_from_type, const String &p_to_type);
	TypedArray<String> validate() const;
	void clear_cache();
	int64_t structure_hash() const;

	// Execution.
	Dictionary execute(const Dictionary &p_inputs = Dictionary());
	Dictionary partition_execute(const Vector2i &p_grid_cell, double p_cell_size, const Dictionary &p_inputs = Dictionary(), double p_margin = 0.0);
	Dictionary run_scoped(const Dictionary &p_inputs, const String &p_scope, const Dictionary &p_bounds_ctx, int64_t p_seed);
	Variant node_output(const String &p_id, const String &p_pin = "out") const;

	// Presets (ports of pcg_presets.gd).
	static Ref<CgamePCGGraph> forest_scatter(int64_t p_graph_seed = 1337);
	static Ref<CgamePCGGraph> ruins_debris(int64_t p_graph_seed = 4242);
	static Ref<CgamePCGGraph> cave_rocks(int64_t p_graph_seed = 9001);

	CgamePCGGraph();
};
