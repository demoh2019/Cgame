/**************************************************************************/
/*  pcg_node.cpp                                                          */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "pcg_node.h"

#include "core/object/class_db.h"

// --- Context -----------------------------------------------------------------------------------------------------

float PCGContext::sample_height(float p_x, float p_z) const {
	if (!height_sampler.is_valid()) {
		return 0.0;
	}
	return float(height_sampler.call(p_x, p_z));
}

String PCGContext::sample_biome(float p_x, float p_z) const {
	if (!biome_sampler.is_valid()) {
		return String();
	}
	return String(biome_sampler.call(p_x, p_z));
}

bool PCGContext::sample_water(float p_x, float p_z) const {
	if (!water_sampler.is_valid()) {
		return false;
	}
	return bool(water_sampler.call(p_x, p_z));
}

Vector3 PCGContext::sample_normal(float p_x, float p_z, float p_step) const {
	if (!height_sampler.is_valid()) {
		return Vector3(0, 1, 0);
	}
	const float hl = sample_height(p_x - p_step, p_z);
	const float hr = sample_height(p_x + p_step, p_z);
	const float hd = sample_height(p_x, p_z - p_step);
	const float hu = sample_height(p_x, p_z + p_step);
	return Vector3(hl - hr, 2.0 * p_step, hd - hu).normalized();
}

bool PCGContext::is_excluded(const Vector3 &p_point, float p_margin) const {
	for (int i = 0; i < exclusions.size(); i++) {
		const Variant &v = exclusions[i];
		if (v.get_type() == Variant::AABB) {
			AABB box = v;
			if (box.grow(p_margin).has_point(p_point)) {
				return true;
			}
		} else if (v.get_type() == Variant::DICTIONARY) {
			Dictionary sphere = v;
			const Vector3 center = sphere.get("center", Vector3());
			const float radius = float(sphere.get("radius", 0.0)) + p_margin;
			// Exclusion spheres are cylinders in practice (settlements, roads): compare on XZ.
			if (Vector2(p_point.x - center.x, p_point.z - center.z).length() <= radius) {
				return true;
			}
		}
	}
	return false;
}

uint64_t PCGContext::compute_environment_hash() const {
	uint64_t h = pcg_mix64((uint64_t)seed, (uint64_t)environment_version);
	h = pcg_hash_double(h, bounds.position.x);
	h = pcg_hash_double(h, bounds.position.y);
	h = pcg_hash_double(h, bounds.position.z);
	h = pcg_hash_double(h, bounds.size.x);
	h = pcg_hash_double(h, bounds.size.y);
	h = pcg_hash_double(h, bounds.size.z);
	h = pcg_mix64(h, (uint64_t)exclusions.hash());
	h = pcg_mix64(h, (uint64_t)user_data.hash());
	h = pcg_mix64(h, height_sampler.is_valid() ? (uint64_t)height_sampler.hash() : 0);
	h = pcg_mix64(h, biome_sampler.is_valid() ? (uint64_t)biome_sampler.hash() : 0);
	h = pcg_mix64(h, water_sampler.is_valid() ? (uint64_t)water_sampler.hash() : 0);
	return h;
}

void PCGContext::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_seed", "seed"), &PCGContext::set_seed);
	ClassDB::bind_method(D_METHOD("get_seed"), &PCGContext::get_seed);
	ClassDB::bind_method(D_METHOD("set_bounds", "bounds"), &PCGContext::set_bounds);
	ClassDB::bind_method(D_METHOD("get_bounds"), &PCGContext::get_bounds);
	ClassDB::bind_method(D_METHOD("set_cell", "cell"), &PCGContext::set_cell);
	ClassDB::bind_method(D_METHOD("get_cell"), &PCGContext::get_cell);
	ClassDB::bind_method(D_METHOD("set_overrides", "overrides"), &PCGContext::set_overrides);
	ClassDB::bind_method(D_METHOD("get_overrides"), &PCGContext::get_overrides);
	ClassDB::bind_method(D_METHOD("set_height_sampler", "callable"), &PCGContext::set_height_sampler);
	ClassDB::bind_method(D_METHOD("get_height_sampler"), &PCGContext::get_height_sampler);
	ClassDB::bind_method(D_METHOD("set_biome_sampler", "callable"), &PCGContext::set_biome_sampler);
	ClassDB::bind_method(D_METHOD("get_biome_sampler"), &PCGContext::get_biome_sampler);
	ClassDB::bind_method(D_METHOD("set_water_sampler", "callable"), &PCGContext::set_water_sampler);
	ClassDB::bind_method(D_METHOD("get_water_sampler"), &PCGContext::get_water_sampler);
	ClassDB::bind_method(D_METHOD("set_exclusions", "exclusions"), &PCGContext::set_exclusions);
	ClassDB::bind_method(D_METHOD("get_exclusions"), &PCGContext::get_exclusions);
	ClassDB::bind_method(D_METHOD("set_user_data", "user_data"), &PCGContext::set_user_data);
	ClassDB::bind_method(D_METHOD("get_user_data"), &PCGContext::get_user_data);
	ClassDB::bind_method(D_METHOD("set_debug", "debug"), &PCGContext::set_debug);
	ClassDB::bind_method(D_METHOD("is_debug"), &PCGContext::is_debug);
	ClassDB::bind_method(D_METHOD("set_environment_version", "version"), &PCGContext::set_environment_version);
	ClassDB::bind_method(D_METHOD("get_environment_version"), &PCGContext::get_environment_version);
	ClassDB::bind_method(D_METHOD("sample_height", "x", "z"), &PCGContext::sample_height);
	ClassDB::bind_method(D_METHOD("sample_biome", "x", "z"), &PCGContext::sample_biome);
	ClassDB::bind_method(D_METHOD("sample_water", "x", "z"), &PCGContext::sample_water);
	ClassDB::bind_method(D_METHOD("sample_normal", "x", "z", "step"), &PCGContext::sample_normal, DEFVAL(0.5));
	ClassDB::bind_method(D_METHOD("is_excluded", "point", "margin"), &PCGContext::is_excluded, DEFVAL(0.0));

	ADD_PROPERTY(PropertyInfo(Variant::INT, "seed"), "set_seed", "get_seed");
	ADD_PROPERTY(PropertyInfo(Variant::AABB, "bounds"), "set_bounds", "get_bounds");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "cell"), "set_cell", "get_cell");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "overrides"), "set_overrides", "get_overrides");
	ADD_PROPERTY(PropertyInfo(Variant::CALLABLE, "height_sampler"), "set_height_sampler", "get_height_sampler");
	ADD_PROPERTY(PropertyInfo(Variant::CALLABLE, "biome_sampler"), "set_biome_sampler", "get_biome_sampler");
	ADD_PROPERTY(PropertyInfo(Variant::CALLABLE, "water_sampler"), "set_water_sampler", "get_water_sampler");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "exclusions"), "set_exclusions", "get_exclusions");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "user_data"), "set_user_data", "get_user_data");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "debug"), "set_debug", "is_debug");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "environment_version"), "set_environment_version", "get_environment_version");
}

// --- Node --------------------------------------------------------------------------------------------------------

String PCGNode::get_title() const {
	if (!title.is_empty()) {
		return title;
	}
	return String(get_class()).trim_prefix("PCG").trim_suffix("Node");
}

void PCGNode::set_enabled(bool p_enabled) {
	enabled = p_enabled;
	emit_changed();
}

void PCGNode::set_seed_offset(int64_t p_offset) {
	seed_offset = p_offset;
	emit_changed();
}

void PCGNode::set_parameter_bindings(const Dictionary &p_bindings) {
	parameter_bindings = p_bindings;
	emit_changed();
}

void PCGNode::bind_parameter(const StringName &p_property, const StringName &p_parameter) {
	if (p_parameter == StringName()) {
		parameter_bindings.erase(p_property);
	} else {
		parameter_bindings[p_property] = p_parameter;
	}
	emit_changed();
}

int PCGNode::get_input_count() const {
	int count = 1;
	if (GDVIRTUAL_CALL(_get_input_count, count)) {
		return count;
	}
	return 1;
}

String PCGNode::get_category() const {
	String category;
	if (GDVIRTUAL_CALL(_get_category, category)) {
		return category;
	}
	return "Custom";
}

Variant PCGNode::resolve(const StringName &p_property, const Ref<PCGContext> &p_context) const {
	if (p_context.is_valid() && parameter_bindings.has(p_property)) {
		const Dictionary overrides = p_context->get_overrides();
		const Variant parameter = parameter_bindings[p_property];
		if (overrides.has(parameter)) {
			return overrides[parameter];
		}
	}
	return get(p_property);
}

uint64_t PCGNode::compute_param_hash(const Ref<PCGContext> &p_context) const {
	uint64_t h = pcg_mix64((uint64_t)String(get_class()).hash(), (uint64_t)seed_offset);
	h = pcg_mix64(h, enabled ? 1 : 0);
	List<PropertyInfo> properties;
	get_property_list(&properties);
	for (const PropertyInfo &info : properties) {
		if (!(info.usage & PROPERTY_USAGE_STORAGE)) {
			continue;
		}
		if (info.name == "graph_position" || info.name == "title" || info.name == "debug_output" || info.name == "resource_name" || info.name == "resource_path" || info.name == "resource_local_to_scene" || info.name == "script") {
			continue;
		}
		h = pcg_mix64(h, (uint64_t)info.name.hash());
		h = pcg_mix64(h, (uint64_t)resolve(info.name, p_context).hash());
	}
	return h;
}

Ref<PCGData> PCGNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Array inputs;
	for (const Ref<PCGData> &data : p_inputs) {
		inputs.push_back(data);
	}
	return execute_script(inputs, p_context, (int64_t)p_seed);
}

Ref<PCGData> PCGNode::execute_script(const Array &p_inputs, const Ref<PCGContext> &p_context, int64_t p_seed) const {
	Ref<PCGData> result;
	if (GDVIRTUAL_CALL(_execute, p_inputs, p_context, p_seed, result)) {
		return result;
	}
	// A plain PCGNode passes its first input through.
	if (!p_inputs.is_empty()) {
		return p_inputs[0];
	}
	return Ref<PCGData>(memnew(PCGPointData));
}

Ref<PCGPointData> PCGNode::points_input(const Vector<Ref<PCGData>> &p_inputs, int p_index) {
	if (p_index >= 0 && p_index < p_inputs.size()) {
		Ref<PCGPointData> points = p_inputs[p_index];
		if (points.is_valid()) {
			return points;
		}
	}
	Ref<PCGPointData> empty;
	empty.instantiate();
	return empty;
}

void PCGNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_node_id", "id"), &PCGNode::set_node_id);
	ClassDB::bind_method(D_METHOD("get_node_id"), &PCGNode::get_node_id);
	ClassDB::bind_method(D_METHOD("set_title", "title"), &PCGNode::set_title);
	ClassDB::bind_method(D_METHOD("get_title"), &PCGNode::get_title);
	ClassDB::bind_method(D_METHOD("set_graph_position", "position"), &PCGNode::set_graph_position);
	ClassDB::bind_method(D_METHOD("get_graph_position"), &PCGNode::get_graph_position);
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &PCGNode::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &PCGNode::is_enabled);
	ClassDB::bind_method(D_METHOD("set_seed_offset", "offset"), &PCGNode::set_seed_offset);
	ClassDB::bind_method(D_METHOD("get_seed_offset"), &PCGNode::get_seed_offset);
	ClassDB::bind_method(D_METHOD("set_debug_output", "debug"), &PCGNode::set_debug_output);
	ClassDB::bind_method(D_METHOD("is_debug_output"), &PCGNode::is_debug_output);
	ClassDB::bind_method(D_METHOD("set_parameter_bindings", "bindings"), &PCGNode::set_parameter_bindings);
	ClassDB::bind_method(D_METHOD("get_parameter_bindings"), &PCGNode::get_parameter_bindings);
	ClassDB::bind_method(D_METHOD("bind_parameter", "property", "parameter"), &PCGNode::bind_parameter);
	ClassDB::bind_method(D_METHOD("get_input_count"), &PCGNode::get_input_count);
	ClassDB::bind_method(D_METHOD("get_category"), &PCGNode::get_category);
	ClassDB::bind_method(D_METHOD("resolve", "property", "context"), &PCGNode::resolve);
	ClassDB::bind_method(D_METHOD("execute", "inputs", "context", "seed"), &PCGNode::execute_script);

	GDVIRTUAL_BIND(_execute, "inputs", "context", "seed");
	GDVIRTUAL_BIND(_get_input_count);
	GDVIRTUAL_BIND(_get_category);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "node_id", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_node_id", "get_node_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "title"), "set_title", "get_title");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "graph_position", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_graph_position", "get_graph_position");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "seed_offset"), "set_seed_offset", "get_seed_offset");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "debug_output"), "set_debug_output", "is_debug_output");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "parameter_bindings"), "set_parameter_bindings", "get_parameter_bindings");
}
