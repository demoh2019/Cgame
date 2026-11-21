/**************************************************************************/
/*  cgame_pcg_graph.cpp                                                   */
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

#include "cgame_pcg_graph.h"

#include "core/object/class_db.h"

#include "core/math/math_funcs.h"
#include "core/os/os.h"

namespace {
const char *T_POINTS = "points";
const char *T_SPLINE = "spline";
const char *T_VOLUME = "volume";
const char *T_LANDSCAPE = "landscape";
const char *T_MESHES = "mesh_instances";
const char *T_SCENES = "scene_instances";
const char *T_LAYER = "layer_weights";
const char *T_ANY = "any";

int64_t variant_hash(const Variant &p_value) {
	return (int64_t)p_value.hash();
}
} // namespace

CgamePCGGraph::CgamePCGGraph() {
	_register_builtins();
}

// ---------------------------------------------------------------- data constructors

Dictionary CgamePCGGraph::make_points(const PackedVector3Array &p_positions) {
	const int n = p_positions.size();
	PackedFloat32Array dens;
	PackedFloat32Array scl;
	PackedFloat32Array rot;
	PackedInt64Array sd;
	dens.resize(n);
	scl.resize(n);
	rot.resize(n);
	sd.resize(n);
	dens.fill(1.0f);
	scl.fill(1.0f);
	rot.fill(0.0f);
	for (int i = 0; i < n; i++) {
		sd.set(i, mix64(variant_hash(Variant(p_positions[i]))));
	}
	return _assemble(p_positions, dens, scl, rot, sd, Dictionary());
}

Dictionary CgamePCGGraph::make_spline(const PackedVector3Array &p_points, bool p_closed) {
	Dictionary d;
	d["type"] = T_SPLINE;
	d["points"] = p_points;
	d["closed"] = p_closed;
	return d;
}

Dictionary CgamePCGGraph::make_volume(const AABB &p_box) {
	Dictionary d;
	d["type"] = T_VOLUME;
	d["aabb"] = p_box;
	return d;
}

Dictionary CgamePCGGraph::make_landscape(const Callable &p_height_at, const Callable &p_normal_at) {
	Dictionary d;
	d["type"] = T_LANDSCAPE;
	d["height_at"] = p_height_at;
	d["normal_at"] = p_normal_at;
	return d;
}

int64_t CgamePCGGraph::point_count(const Variant &p_data) {
	if (p_data.get_type() != Variant::DICTIONARY) {
		return 0;
	}
	const Dictionary dd = p_data;
	const String t = String(dd.get("type", ""));
	if (t == T_POINTS || t == T_LAYER) {
		const PackedVector3Array p = dd.get("positions", PackedVector3Array());
		return p.size();
	}
	if (t == T_SPLINE) {
		const PackedVector3Array sp = dd.get("points", PackedVector3Array());
		return sp.size();
	}
	if (t == T_MESHES || t == T_SCENES) {
		int64_t total = 0;
		const Array recs = dd.get("records", Array());
		for (int i = 0; i < recs.size(); i++) {
			const Dictionary r = recs[i];
			const Array tr = r.get("transforms", Array());
			total += tr.size();
		}
		return total;
	}
	return 0;
}

double CgamePCGGraph::landscape_height(const Variant &p_landscape, double p_x, double p_z, double p_fallback) {
	if (p_landscape.get_type() == Variant::DICTIONARY) {
		const Dictionary d = p_landscape;
		const Callable c = d.get("height_at", Callable());
		if (c.is_valid()) {
			return (double)c.call(p_x, p_z);
		}
	}
	return p_fallback;
}

Vector3 CgamePCGGraph::landscape_normal(const Variant &p_landscape, double p_x, double p_z) {
	if (p_landscape.get_type() == Variant::DICTIONARY) {
		const Dictionary d = p_landscape;
		const Callable nc = d.get("normal_at", Callable());
		if (nc.is_valid()) {
			return nc.call(p_x, p_z);
		}
		const Callable hc = d.get("height_at", Callable());
		if (hc.is_valid()) {
			const double e = 0.5;
			const double dx = (double)hc.call(p_x + e, p_z) - (double)hc.call(p_x - e, p_z);
			const double dz = (double)hc.call(p_x, p_z + e) - (double)hc.call(p_x, p_z - e);
			return Vector3((real_t)-dx, (real_t)(2.0 * e), (real_t)-dz).normalized();
		}
	}
	return Vector3(0, 1, 0);
}

// ---------------------------------------------------------------- hashing / random

// SplitMix64 finaliser using the same signed (arithmetic) shifts as the reference script.
int64_t CgamePCGGraph::mix64(int64_t p_x) {
	uint64_t z = (uint64_t)p_x + (uint64_t)(int64_t)-7046029254386353131LL;
	int64_t s = (int64_t)z;
	z = (uint64_t)(s ^ (s >> 30)) * (uint64_t)(int64_t)-4658895280553007687LL;
	s = (int64_t)z;
	z = (uint64_t)(s ^ (s >> 27)) * (uint64_t)(int64_t)-7723592293110705685LL;
	s = (int64_t)z;
	return s ^ (s >> 31);
}

int64_t CgamePCGGraph::hash3(int64_t p_a, int64_t p_b, int64_t p_c) {
	return mix64(mix64(mix64(p_a) ^ p_b) ^ p_c);
}

double CgamePCGGraph::rand01(int64_t p_h) {
	return (double)(p_h & 0xFFFFFF) / 16777216.0;
}

// ---------------------------------------------------------------- pin helpers

String CgamePCGGraph::_base(const String &p_type) {
	return p_type.trim_suffix("[]");
}

bool CgamePCGGraph::_is_multi(const String &p_type) {
	return p_type.ends_with("[]");
}

bool CgamePCGGraph::pins_compatible(const String &p_from_type, const String &p_to_type) {
	const String a = _base(p_from_type);
	const String b = _base(p_to_type);
	return a == b || a == T_ANY || b == T_ANY;
}

void CgamePCGGraph::_reg(const String &p_type, const Dictionary &p_in, const Dictionary &p_out, const Callable &p_exec, Builtin p_builtin) {
	NodeDef def;
	def.in_pins = p_in.duplicate();
	def.out_pins = p_out.duplicate();
	def.exec = p_exec;
	def.builtin = p_builtin;
	defs[p_type] = def;
}

void CgamePCGGraph::register_node(const String &p_type, const Dictionary &p_input_pins, const Dictionary &p_output_pins, const Callable &p_execute) {
	_reg(p_type, p_input_pins, p_output_pins, p_execute, BUILTIN_NONE);
}

bool CgamePCGGraph::_is_known(const String &p_type) const {
	return defs.has(p_type) || p_type == "graph_input" || p_type == "graph_output" || p_type == "subgraph";
}

CgamePCGGraph::NodePins CgamePCGGraph::_node_pins(const String &p_id) const {
	NodePins pins;
	const Dictionary node = nodes[p_id];
	const String type_name = node["type"];
	const Dictionary params = node["params"];
	if (type_name == "graph_input") {
		pins.out["out"] = String(params.get("pin_type", T_ANY));
		return pins;
	}
	if (type_name == "graph_output") {
		const String pt = String(params.get("pin_type", T_ANY));
		pins.in["in"] = pt;
		pins.out["value"] = pt;
		return pins;
	}
	if (type_name == "subgraph") {
		const Variant sub = params.get("graph", Variant());
		if (sub.get_type() == Variant::OBJECT) {
			Object *obj = sub;
			if (CgamePCGGraph *g = Object::cast_to<CgamePCGGraph>(obj)) {
				pins.in = g->get_io_pins(true);
				pins.out = g->get_io_pins(false);
			} else if (RefCounted *rc = Object::cast_to<RefCounted>(obj)) {
				pins.in = rc->call("get_io_pins", true);
				pins.out = rc->call("get_io_pins", false);
			}
		}
		return pins;
	}
	if (const NodeDef *def = defs.getptr(type_name)) {
		pins.in = def->in_pins;
		pins.out = def->out_pins;
	}
	return pins;
}

String CgamePCGGraph::_check_edge(const String &p_from_id, const String &p_from_pin, const String &p_to_id, const String &p_to_pin) const {
	if (!nodes.has(p_from_id)) {
		return vformat("edge: unknown node %s", p_from_id);
	}
	if (!nodes.has(p_to_id)) {
		return vformat("edge: unknown node %s", p_to_id);
	}
	const Dictionary fp = _node_pins(p_from_id).out;
	const Dictionary tp = _node_pins(p_to_id).in;
	if (!fp.has(p_from_pin)) {
		return vformat("edge: %s has no output pin %s", p_from_id, p_from_pin);
	}
	if (!tp.has(p_to_pin)) {
		return vformat("edge: %s has no input pin %s", p_to_id, p_to_pin);
	}
	if (!pins_compatible(String(fp[p_from_pin]), String(tp[p_to_pin]))) {
		return vformat("edge: type mismatch %s.%s (%s) -> %s.%s (%s)", p_from_id, p_from_pin, String(fp[p_from_pin]), p_to_id, p_to_pin, _base(String(tp[p_to_pin])));
	}
	return "";
}

// ---------------------------------------------------------------- graph building

String CgamePCGGraph::add_node(const String &p_id, const String &p_type, const Dictionary &p_params) {
	Dictionary node;
	node["type"] = p_type;
	node["params"] = p_params.duplicate();
	nodes[p_id] = node;
	return p_id;
}

void CgamePCGGraph::set_param(const String &p_id, const String &p_key, const Variant &p_value) {
	if (nodes.has(p_id)) {
		const Dictionary node = nodes[p_id];
		Dictionary params = node["params"];
		params[p_key] = p_value;
	}
}

Variant CgamePCGGraph::get_param(const String &p_id, const String &p_key, const Variant &p_default) const {
	if (nodes.has(p_id)) {
		const Dictionary node = nodes[p_id];
		const Dictionary params = node["params"];
		return params.get(p_key, p_default);
	}
	return p_default;
}

// Adds an edge. Returns "" on success, otherwise the validation error (the edge is not added).
String CgamePCGGraph::link(const String &p_from_id, const String &p_from_pin, const String &p_to_id, const String &p_to_pin) {
	const String err = _check_edge(p_from_id, p_from_pin, p_to_id, p_to_pin);
	if (!err.is_empty()) {
		return err;
	}
	const Dictionary to_pins = _node_pins(p_to_id).in;
	if (!_is_multi(String(to_pins[p_to_pin]))) {
		for (int i = 0; i < edges.size(); i++) {
			const Dictionary e = edges[i];
			if (String(e["to"]) == p_to_id && String(e["to_pin"]) == p_to_pin) {
				return vformat("pin %s.%s already connected", p_to_id, p_to_pin);
			}
		}
	}
	Dictionary edge;
	edge["from"] = p_from_id;
	edge["from_pin"] = p_from_pin;
	edge["to"] = p_to_id;
	edge["to_pin"] = p_to_pin;
	edges.push_back(edge);
	return "";
}

// Graph inputs/outputs used when this graph is reused as a subgraph.
String CgamePCGGraph::add_graph_input(const String &p_id, const String &p_pin_name, const String &p_pin_type) {
	Dictionary params;
	params["name"] = p_pin_name;
	params["pin_type"] = p_pin_type;
	return add_node(p_id, "graph_input", params);
}

String CgamePCGGraph::add_graph_output(const String &p_id, const String &p_pin_name, const String &p_pin_type) {
	Dictionary params;
	params["name"] = p_pin_name;
	params["pin_type"] = p_pin_type;
	return add_node(p_id, "graph_output", params);
}

Dictionary CgamePCGGraph::get_io_pins(bool p_inputs) const {
	Dictionary res;
	const String want = p_inputs ? "graph_input" : "graph_output";
	const Array keys = nodes.keys();
	for (int i = 0; i < keys.size(); i++) {
		const String id = keys[i];
		const Dictionary node = nodes[id];
		if (String(node["type"]) == want) {
			const Dictionary params = node["params"];
			res[String(params.get("name", id))] = String(params.get("pin_type", T_ANY));
		}
	}
	return res;
}

TypedArray<String> CgamePCGGraph::validate() const {
	TypedArray<String> errs;
	const Array keys = nodes.keys();
	for (int i = 0; i < keys.size(); i++) {
		const String id = keys[i];
		const Dictionary node = nodes[id];
		const String type_name = node["type"];
		if (!_is_known(type_name)) {
			errs.push_back(vformat("node %s: unknown type %s", id, type_name));
		} else if (type_name == "subgraph") {
			const Dictionary params = node["params"];
			const Variant g = params.get("graph", Variant());
			if (g.get_type() != Variant::OBJECT || Object::cast_to<RefCounted>((Object *)g) == nullptr) {
				errs.push_back(vformat("node %s: subgraph has no graph", id));
			}
		}
	}
	for (int i = 0; i < edges.size(); i++) {
		const Dictionary e = edges[i];
		const String err = _check_edge(String(e["from"]), String(e["from_pin"]), String(e["to"]), String(e["to_pin"]));
		if (!err.is_empty()) {
			errs.push_back(err);
		}
	}
	HashMap<String, int> counts;
	for (int i = 0; i < edges.size(); i++) {
		const Dictionary e = edges[i];
		const String key = vformat("%s.%s", String(e["to"]), String(e["to_pin"]));
		const int c = counts.has(key) ? counts[key] + 1 : 1;
		counts[key] = c;
		if (c == 2 && nodes.has(e["to"])) {
			const Dictionary tp = _node_pins(String(e["to"])).in;
			if (tp.has(e["to_pin"]) && !_is_multi(String(tp[e["to_pin"]]))) {
				errs.push_back(vformat("pin %s has several inputs but is not a multi-input pin", key));
			}
		}
	}
	if (_has_cycle()) {
		errs.push_back("graph contains a cycle");
	}
	return errs;
}

bool CgamePCGGraph::_has_cycle() const {
	HashMap<String, int> state;
	const Array keys = nodes.keys();
	for (int i = 0; i < keys.size(); i++) {
		if (_dfs_cycle(String(keys[i]), state)) {
			return true;
		}
	}
	return false;
}

bool CgamePCGGraph::_dfs_cycle(const String &p_id, HashMap<String, int> &r_state) const {
	const int s = r_state.has(p_id) ? r_state[p_id] : 0;
	if (s == 1) {
		return true;
	}
	if (s == 2) {
		return false;
	}
	r_state[p_id] = 1;
	for (int i = 0; i < edges.size(); i++) {
		const Dictionary e = edges[i];
		if (String(e["to"]) == p_id && nodes.has(e["from"])) {
			if (_dfs_cycle(String(e["from"]), r_state)) {
				return true;
			}
		}
	}
	r_state[p_id] = 2;
	return false;
}

void CgamePCGGraph::clear_cache() {
	cache.clear();
}

int64_t CgamePCGGraph::_params_hash(const Dictionary &p_params) const {
	Dictionary copy = p_params.duplicate();
	const Variant sub = copy.get("graph", Variant());
	if (sub.get_type() == Variant::OBJECT) {
		Object *obj = sub;
		if (CgamePCGGraph *g = Object::cast_to<CgamePCGGraph>(obj)) {
			copy["graph"] = g->structure_hash();
		} else if (RefCounted *rc = Object::cast_to<RefCounted>(obj)) {
			copy["graph"] = (int64_t)rc->call("structure_hash");
		}
	}
	return variant_hash(copy);
}

// Hash of the whole graph definition (nodes, params, edges, nested subgraphs).
int64_t CgamePCGGraph::structure_hash() const {
	Array arr;
	const Array keys = nodes.keys();
	for (int i = 0; i < keys.size(); i++) {
		const String id = keys[i];
		const Dictionary node = nodes[id];
		const Dictionary params = node["params"];
		Array item;
		item.push_back(id);
		item.push_back(node["type"]);
		item.push_back(_params_hash(params));
		arr.push_back(item);
	}
	for (int i = 0; i < edges.size(); i++) {
		const Dictionary e = edges[i];
		Array item;
		item.push_back(e["from"]);
		item.push_back(e["from_pin"]);
		item.push_back(e["to"]);
		item.push_back(e["to_pin"]);
		arr.push_back(item);
	}
	arr.push_back(graph_seed);
	return variant_hash(arr);
}

// ---------------------------------------------------------------- execution

Dictionary CgamePCGGraph::execute(const Dictionary &p_inputs) {
	return run_scoped(p_inputs, "", Dictionary(), graph_seed);
}

// Runs the graph for one world-partition cell. Sampling is restricted to the cell (grown by
// p_margin so neighbour-dependent nodes see context) and the outputs are cropped to the exact
// cell, so the union of all cells equals an unpartitioned run.
Dictionary CgamePCGGraph::partition_execute(const Vector2i &p_grid_cell, double p_cell_size, const Dictionary &p_inputs, double p_margin) {
	const double x0 = (double)p_grid_cell.x * p_cell_size;
	const double z0 = (double)p_grid_cell.y * p_cell_size;
	Dictionary bounds;
	bounds["has_bounds"] = true;
	bounds["bounds"] = AABB(Vector3((real_t)(x0 - p_margin), (real_t)-BIG, (real_t)(z0 - p_margin)), Vector3((real_t)(p_cell_size + 2.0 * p_margin), (real_t)(2.0 * BIG), (real_t)(p_cell_size + 2.0 * p_margin)));
	const String scope = vformat("cell:%d,%d:%s|", p_grid_cell.x, p_grid_cell.y, String::num(p_margin));
	const Dictionary out = run_scoped(p_inputs, scope, bounds, graph_seed);
	const Rect2 rect((real_t)x0, (real_t)z0, (real_t)p_cell_size, (real_t)p_cell_size);
	Dictionary cropped;
	const Array keys = out.keys();
	for (int i = 0; i < keys.size(); i++) {
		cropped[keys[i]] = _crop(out[keys[i]], rect);
	}
	return cropped;
}

Dictionary CgamePCGGraph::run_scoped(const Dictionary &p_inputs, const String &p_scope, const Dictionary &p_bounds_ctx, int64_t p_seed) {
	executed_nodes.clear();
	cache_hits = 0;
	debug.clear();
	debug_steps.clear();
	last_results = Dictionary();
	last_errors = validate();
	if (!last_errors.is_empty()) {
		return Dictionary();
	}
	EvalState st;
	st.inputs = p_inputs;
	st.scope = p_scope;
	st.bounds = p_bounds_ctx;
	st.seed = p_seed;
	st.step = 0;
	Vector<String> targets;
	const Array keys = nodes.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Dictionary node = nodes[keys[i]];
		if (String(node["type"]) == "graph_output") {
			targets.push_back(String(keys[i]));
		}
	}
	Dictionary out;
	if (targets.is_empty()) {
		for (int i = 0; i < keys.size(); i++) {
			_eval(String(keys[i]), st);
		}
		return out;
	}
	for (const String &id : targets) {
		const Dictionary r = _eval(id, st);
		const Dictionary node = nodes[id];
		const Dictionary params = node["params"];
		const Dictionary outs = r["outputs"];
		out[String(params.get("name", id))] = outs.get("value", Variant());
	}
	return out;
}

Variant CgamePCGGraph::node_output(const String &p_id, const String &p_pin) const {
	if (last_results.has(p_id)) {
		const Dictionary r = last_results[p_id];
		const Dictionary outs = r["outputs"];
		return outs.get(p_pin, Variant());
	}
	return Variant();
}

int64_t CgamePCGGraph::_sum_counts(const Array &p_vals) {
	int64_t total = 0;
	for (int i = 0; i < p_vals.size(); i++) {
		total += point_count(p_vals[i]);
	}
	return total;
}

Dictionary CgamePCGGraph::_eval(const String &p_id, EvalState &r_state) {
	if (last_results.has(p_id)) {
		return last_results[p_id];
	}
	const Dictionary node = nodes[p_id];
	const String type_name = node["type"];
	const Dictionary params = node["params"];
	const NodePins pins = _node_pins(p_id);
	const Dictionary in_pins = pins.in;
	Dictionary ins;
	Array in_hashes;
	Dictionary in_summ;
	const Array pin_keys = in_pins.keys();
	for (int pi = 0; pi < pin_keys.size(); pi++) {
		const String pin = pin_keys[pi];
		const bool multi = _is_multi(String(in_pins[pin]));
		Array vals;
		for (int ei = 0; ei < edges.size(); ei++) {
			const Dictionary e = edges[ei];
			if (String(e["to"]) == p_id && String(e["to_pin"]) == pin) {
				const Dictionary src = _eval(String(e["from"]), r_state);
				const Dictionary souts = src["outputs"];
				const Dictionary shashes = src["hashes"];
				vals.push_back(souts.get(e["from_pin"], Variant()));
				Array h;
				h.push_back(pin);
				h.push_back(shashes.get(e["from_pin"], 0));
				in_hashes.push_back(h);
			}
		}
		if (multi) {
			ins[pin] = vals;
		} else {
			ins[pin] = vals.is_empty() ? Variant() : vals[0];
		}
		if (debug_enabled) {
			in_summ[pin] = multi ? _sum_counts(vals) : point_count(ins[pin]);
		}
	}
	const int64_t seed_value = r_state.seed;
	const int64_t node_seed = mix64(seed_value + mix64((int64_t)p_id.hash()) + (int64_t)params.get("seed", 0));
	const Dictionary bctx = r_state.bounds;
	Dictionary ctx;
	ctx["node_seed"] = node_seed;
	ctx["node_id"] = p_id;
	ctx["has_bounds"] = bctx.get("has_bounds", false);
	ctx["bounds"] = bctx.get("bounds", AABB());
	int64_t extra = 0;
	Variant graph_in_data;
	if (type_name == "graph_input") {
		graph_in_data = r_state.inputs.get(String(params.get("name", p_id)), Variant());
		extra = variant_hash(graph_in_data);
	}
	Array key_arr;
	key_arr.push_back(type_name);
	key_arr.push_back(_params_hash(params));
	key_arr.push_back(node_seed);
	key_arr.push_back(variant_hash(bctx));
	key_arr.push_back(in_hashes);
	key_arr.push_back(extra);
	const int64_t key = variant_hash(key_arr);
	const String cache_key = r_state.scope + p_id;
	Dictionary entry;
	bool executed = false;
	int64_t usec = 0;
	bool hit = false;
	if (cache.has(cache_key)) {
		const Dictionary cached = cache[cache_key];
		if ((int64_t)cached["key"] == key) {
			entry = cached;
			cache_hits++;
			hit = true;
		}
	}
	if (!hit) {
		const uint64_t t0 = OS::get_singleton()->get_ticks_usec();
		const Dictionary outs = _exec_node(p_id, type_name, params, ins, ctx, r_state, graph_in_data);
		usec = (int64_t)(OS::get_singleton()->get_ticks_usec() - t0);
		Dictionary hashes;
		const Array out_keys = outs.keys();
		for (int i = 0; i < out_keys.size(); i++) {
			hashes[out_keys[i]] = variant_hash(outs[out_keys[i]]);
		}
		entry["key"] = key;
		entry["outputs"] = outs;
		entry["hashes"] = hashes;
		cache[cache_key] = entry;
		executed = true;
		executed_nodes.push_back(p_id);
	}
	last_results[p_id] = entry;
	if (debug_enabled) {
		_capture(p_id, type_name, executed, usec, in_summ, entry, r_state);
	}
	return entry;
}

Dictionary CgamePCGGraph::_exec_node(const String &p_id, const String &p_type, const Dictionary &p_params, const Dictionary &p_ins, const Dictionary &p_ctx, EvalState &r_state, const Variant &p_graph_in_data) {
	if (p_type == "graph_input") {
		Dictionary d;
		d["out"] = p_graph_in_data;
		return d;
	}
	if (p_type == "graph_output") {
		Dictionary d;
		d["value"] = p_ins.get("in", Variant());
		return d;
	}
	if (p_type == "subgraph") {
		const Variant sub = p_params.get("graph", Variant());
		Object *obj = sub;
		const String sub_scope = vformat("%s%s/", r_state.scope, p_id);
		const int64_t sub_seed = p_ctx["node_seed"];
		Dictionary res;
		Array sub_exec;
		if (CgamePCGGraph *g = Object::cast_to<CgamePCGGraph>(obj)) {
			res = g->run_scoped(p_ins, sub_scope, r_state.bounds, sub_seed);
			sub_exec = g->get_executed_nodes();
		} else if (RefCounted *rc = Object::cast_to<RefCounted>(obj)) {
			res = rc->call("run_scoped", p_ins, sub_scope, r_state.bounds, sub_seed);
			sub_exec = rc->get("executed_nodes");
		}
		for (int i = 0; i < sub_exec.size(); i++) {
			executed_nodes.push_back(vformat("%s/%s", p_id, String(sub_exec[i])));
		}
		return res;
	}
	const NodeDef *def = defs.getptr(p_type);
	ERR_FAIL_NULL_V(def, Dictionary());
	if (def->builtin != BUILTIN_NONE) {
		return _exec_builtin(def->builtin, p_ins, p_params, p_ctx);
	}
	const Callable fn = def->exec;
	if (!fn.is_valid()) {
		return Dictionary();
	}
	const int argc = fn.get_argument_count();
	Variant ins_v = p_ins;
	Variant params_v = p_params;
	Variant ctx_v = p_ctx;
	const Variant *args[3] = { &ins_v, &params_v, &ctx_v };
	Variant raw;
	Callable::CallError ce;
	fn.callp(args, argc == 1 ? 1 : (argc == 2 ? 2 : 3), raw, ce);
	if (ce.error != Callable::CallError::CALL_OK) {
		ERR_PRINT(vformat("CgamePCGGraph: custom node '%s' failed to execute.", p_type));
		return Dictionary();
	}
	if (raw.get_type() == Variant::DICTIONARY) {
		return raw;
	}
	return Dictionary();
}

void CgamePCGGraph::_capture(const String &p_id, const String &p_type, bool p_executed, int64_t p_usec, const Dictionary &p_in_summ, const Dictionary &p_entry, EvalState &r_state) {
	const Dictionary outs = p_entry["outputs"];
	Dictionary out_summ;
	const Array out_keys = outs.keys();
	for (int i = 0; i < out_keys.size(); i++) {
		out_summ[out_keys[i]] = summarize(outs[out_keys[i]], debug_sample_count);
	}
	Dictionary rec;
	rec["id"] = p_id;
	rec["step"] = r_state.step;
	rec["type"] = p_type;
	rec["executed"] = p_executed;
	rec["usec"] = p_usec;
	rec["in_counts"] = p_in_summ;
	rec["outputs"] = out_summ;
	if (debug_capture_full) {
		rec["full"] = outs;
	}
	r_state.step++;
	debug[p_id] = rec;
	debug_steps.push_back(rec);
}

Dictionary CgamePCGGraph::summarize(const Variant &p_data, int p_sample_count) {
	Dictionary res;
	if (p_data.get_type() != Variant::DICTIONARY) {
		res["type"] = "null";
		res["count"] = 0;
		return res;
	}
	const Dictionary dd = p_data;
	const String t = String(dd.get("type", "unknown"));
	res["type"] = t;
	res["count"] = point_count(dd);
	if (t == T_POINTS) {
		const PackedVector3Array pos = dd["positions"];
		const Dictionary attrs = dd["attrs"];
		const PackedFloat32Array dens = attrs["density"];
		const PackedFloat32Array sc = attrs["scale"];
		Array samples;
		for (int i = 0; i < MIN(p_sample_count, (int)pos.size()); i++) {
			Dictionary s;
			s["index"] = i;
			s["position"] = pos[i];
			s["density"] = dens[i];
			s["scale"] = sc[i];
			samples.push_back(s);
		}
		res["sample"] = samples;
		if (pos.size() > 0) {
			AABB box(pos[0], Vector3());
			for (int i = 0; i < pos.size(); i++) {
				box.expand_to(pos[i]);
			}
			res["bounds"] = box;
		}
	} else if (t == T_VOLUME) {
		res["bounds"] = dd["aabb"];
	}
	return res;
}

// ---------------------------------------------------------------- bindings

void CgamePCGGraph::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_graph_seed", "seed"), &CgamePCGGraph::set_graph_seed);
	ClassDB::bind_method(D_METHOD("get_graph_seed"), &CgamePCGGraph::get_graph_seed);
	ClassDB::bind_method(D_METHOD("set_nodes", "nodes"), &CgamePCGGraph::set_nodes);
	ClassDB::bind_method(D_METHOD("get_nodes"), &CgamePCGGraph::get_nodes);
	ClassDB::bind_method(D_METHOD("set_edges", "edges"), &CgamePCGGraph::set_edges);
	ClassDB::bind_method(D_METHOD("get_edges"), &CgamePCGGraph::get_edges);
	ClassDB::bind_method(D_METHOD("get_executed_nodes"), &CgamePCGGraph::get_executed_nodes);
	ClassDB::bind_method(D_METHOD("get_cache_hits"), &CgamePCGGraph::get_cache_hits);
	ClassDB::bind_method(D_METHOD("get_last_errors"), &CgamePCGGraph::get_last_errors);
	ClassDB::bind_method(D_METHOD("set_debug_enabled", "enabled"), &CgamePCGGraph::set_debug_enabled);
	ClassDB::bind_method(D_METHOD("is_debug_enabled"), &CgamePCGGraph::is_debug_enabled);
	ClassDB::bind_method(D_METHOD("set_debug_sample_count", "count"), &CgamePCGGraph::set_debug_sample_count);
	ClassDB::bind_method(D_METHOD("get_debug_sample_count"), &CgamePCGGraph::get_debug_sample_count);
	ClassDB::bind_method(D_METHOD("set_debug_capture_full", "full"), &CgamePCGGraph::set_debug_capture_full);
	ClassDB::bind_method(D_METHOD("is_debug_capture_full"), &CgamePCGGraph::is_debug_capture_full);
	ClassDB::bind_method(D_METHOD("get_debug"), &CgamePCGGraph::get_debug);
	ClassDB::bind_method(D_METHOD("get_debug_steps"), &CgamePCGGraph::get_debug_steps);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "graph_seed"), "set_graph_seed", "get_graph_seed");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "nodes", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "set_nodes", "get_nodes");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "edges", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "set_edges", "get_edges");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "debug_enabled"), "set_debug_enabled", "is_debug_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "debug_sample_count", PROPERTY_HINT_RANGE, "0,64,1,or_greater"), "set_debug_sample_count", "get_debug_sample_count");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "debug_capture_full"), "set_debug_capture_full", "is_debug_capture_full");

	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("make_points", "positions"), &CgamePCGGraph::make_points, DEFVAL(PackedVector3Array()));
	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("make_spline", "points", "closed"), &CgamePCGGraph::make_spline, DEFVAL(false));
	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("make_volume", "box"), &CgamePCGGraph::make_volume);
	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("make_landscape", "height_at", "normal_at"), &CgamePCGGraph::make_landscape, DEFVAL(Callable()));
	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("point_count", "data"), &CgamePCGGraph::point_count);
	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("landscape_height", "landscape", "x", "z", "fallback"), &CgamePCGGraph::landscape_height);
	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("landscape_normal", "landscape", "x", "z"), &CgamePCGGraph::landscape_normal);
	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("summarize", "data", "sample_count"), &CgamePCGGraph::summarize);
	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("mix64", "x"), &CgamePCGGraph::mix64);
	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("hash3", "a", "b", "c"), &CgamePCGGraph::hash3);
	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("rand01", "h"), &CgamePCGGraph::rand01);
	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("pins_compatible", "from_type", "to_type"), &CgamePCGGraph::pins_compatible);

	ClassDB::bind_method(D_METHOD("register_node", "type_name", "input_pins", "output_pins", "execute"), &CgamePCGGraph::register_node);
	ClassDB::bind_method(D_METHOD("add_node", "id", "type_name", "params"), &CgamePCGGraph::add_node, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("set_param", "id", "key", "value"), &CgamePCGGraph::set_param);
	ClassDB::bind_method(D_METHOD("get_param", "id", "key", "default_value"), &CgamePCGGraph::get_param, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("link", "from_id", "from_pin", "to_id", "to_pin"), &CgamePCGGraph::link);
	ClassDB::bind_method(D_METHOD("add_graph_input", "id", "pin_name", "pin_type"), &CgamePCGGraph::add_graph_input);
	ClassDB::bind_method(D_METHOD("add_graph_output", "id", "pin_name", "pin_type"), &CgamePCGGraph::add_graph_output);
	ClassDB::bind_method(D_METHOD("get_io_pins", "inputs"), &CgamePCGGraph::get_io_pins);
	ClassDB::bind_method(D_METHOD("validate"), &CgamePCGGraph::validate);
	ClassDB::bind_method(D_METHOD("clear_cache"), &CgamePCGGraph::clear_cache);
	ClassDB::bind_method(D_METHOD("structure_hash"), &CgamePCGGraph::structure_hash);

	ClassDB::bind_method(D_METHOD("execute", "inputs"), &CgamePCGGraph::execute, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("partition_execute", "grid_cell", "cell_size", "inputs", "margin"), &CgamePCGGraph::partition_execute, DEFVAL(Dictionary()), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("run_scoped", "inputs", "scope", "bounds_ctx", "seed_value"), &CgamePCGGraph::run_scoped);
	ClassDB::bind_method(D_METHOD("node_output", "id", "pin"), &CgamePCGGraph::node_output, DEFVAL("out"));

	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("forest_scatter", "graph_seed"), &CgamePCGGraph::forest_scatter, DEFVAL(1337));
	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("ruins_debris", "graph_seed"), &CgamePCGGraph::ruins_debris, DEFVAL(4242));
	ClassDB::bind_static_method("CgamePCGGraph", D_METHOD("cave_rocks", "graph_seed"), &CgamePCGGraph::cave_rocks, DEFVAL(9001));
}
