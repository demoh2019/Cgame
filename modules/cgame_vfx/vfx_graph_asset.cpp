/**************************************************************************/
/*  vfx_graph_asset.cpp                                                   */
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

#include "vfx_graph_asset.h"

#include "vfx_simulation.h"

#include "core/object/class_db.h"
#include "scene/resources/gradient.h"

namespace {

// Parameter kinds: f = number, i = integer, v = Vector3, c = Color, b = bool, s = String.
struct ParamDef {
	const char *name;
	char kind;
};

struct ModuleSchema {
	const char *type;
	const ParamDef *params;
	int count;
};

#define PARAMS(m_name, ...) static const ParamDef m_name[] = { __VA_ARGS__ }
PARAMS(P_RATE, { "rate", 'f' });
PARAMS(P_BURST, { "time", 'f' }, { "count", 'i' });
PARAMS(P_SPHERE, { "radius", 'f' }, { "center", 'v' }, { "surface", 'b' });
PARAMS(P_BOX, { "size", 'v' }, { "center", 'v' });
PARAMS(P_CONE, { "axis", 'v' }, { "angle", 'f' }, { "height", 'f' }, { "center", 'v' });
PARAMS(P_VELOCITY, { "direction", 'v' }, { "spread", 'f' }, { "speed", 'f' }, { "speed_min", 'f' }, { "speed_max", 'f' }, { "radial", 'f' });
PARAMS(P_LIFETIME, { "min", 'f' }, { "max", 'f' });
PARAMS(P_COLOR, { "color", 'c' }, { "color_b", 'c' });
PARAMS(P_SIZE, { "min", 'f' }, { "max", 'f' });
PARAMS(P_ATTRIBUTE, { "attribute", 's' }, { "min", 'f' }, { "max", 'f' });
PARAMS(P_GRAVITY, { "gravity", 'v' });
PARAMS(P_DRAG, { "drag", 'f' });
PARAMS(P_CURL, { "strength", 'f' }, { "frequency", 'f' }, { "scroll", 'v' });
PARAMS(P_VORTEX, { "center", 'v' }, { "axis", 'v' }, { "strength", 'f' }, { "pull", 'f' });
PARAMS(P_ATTRACTOR, { "position", 'v' }, { "strength", 'f' }, { "radius", 'f' });
PARAMS(P_COLOR_LIFE, { "gradient", 'o' });
PARAMS(P_SIZE_LIFE, { "stops", 'a' });
PARAMS(P_COLLIDE, { "normal", 'v' }, { "offset", 'f' }, { "restitution", 'f' }, { "friction", 'f' });
PARAMS(P_KILL, { "normal", 'v' }, { "offset", 'f' });
#undef PARAMS

#define SCHEMA(m_type, m_params) { m_type, m_params, (int)(sizeof(m_params) / sizeof(ParamDef)) }
static const ModuleSchema SCHEMAS[] = {
	SCHEMA("spawn_rate", P_RATE),
	SCHEMA("spawn_burst", P_BURST),
	SCHEMA("initial_position_sphere", P_SPHERE),
	SCHEMA("initial_position_box", P_BOX),
	SCHEMA("initial_position_cone", P_CONE),
	SCHEMA("initial_velocity", P_VELOCITY),
	SCHEMA("lifetime_random", P_LIFETIME),
	SCHEMA("initial_color", P_COLOR),
	SCHEMA("initial_size", P_SIZE),
	SCHEMA("initial_attribute", P_ATTRIBUTE),
	SCHEMA("gravity", P_GRAVITY),
	SCHEMA("drag", P_DRAG),
	SCHEMA("curl_noise", P_CURL),
	SCHEMA("vortex", P_VORTEX),
	SCHEMA("attractor", P_ATTRACTOR),
	SCHEMA("color_over_life", P_COLOR_LIFE),
	SCHEMA("size_over_life", P_SIZE_LIFE),
	SCHEMA("collide_plane", P_COLLIDE),
	SCHEMA("kill_below_plane", P_KILL),
};
#undef SCHEMA

bool _is_number(const Variant &p_v) {
	return p_v.get_type() == Variant::INT || p_v.get_type() == Variant::FLOAT;
}

void _check_value(const Variant &p_value, const ParamDef &p_param, const String &p_where, PackedStringArray &r_errors) {
	bool ok = true;
	switch (p_param.kind) {
		case 'f':
			ok = _is_number(p_value);
			break;
		case 'i':
			ok = p_value.get_type() == Variant::INT || (p_value.get_type() == Variant::FLOAT && Math::floor((double)p_value) == (double)p_value);
			break;
		case 'v':
			ok = p_value.get_type() == Variant::VECTOR3;
			break;
		case 'c':
			ok = p_value.get_type() == Variant::COLOR;
			break;
		case 'b':
			ok = p_value.get_type() == Variant::BOOL;
			break;
		case 's':
			ok = p_value.get_type() == Variant::STRING || p_value.get_type() == Variant::STRING_NAME;
			break;
		case 'o':
			ok = p_value.get_type() == Variant::OBJECT;
			break;
		case 'a':
			ok = p_value.get_type() == Variant::ARRAY;
			break;
		default:
			break;
	}
	if (!ok) {
		r_errors.push_back(vformat("%s: parameter '%s' has the wrong type (%s).", p_where, p_param.name, Variant::get_type_name(p_value.get_type())));
	}
}

void _check_stops(const Dictionary &p_module, bool p_color, const String &p_where, PackedStringArray &r_errors) {
	if (p_color && p_module.has("gradient")) {
		const Ref<Gradient> g = p_module["gradient"];
		if (g.is_null()) {
			r_errors.push_back(vformat("%s: 'gradient' must be a Gradient resource.", p_where));
		}
		return;
	}
	if (!p_module.has("stops")) {
		r_errors.push_back(vformat("%s: needs 'stops' (or a 'gradient' for color_over_life).", p_where));
		return;
	}
	if (p_module["stops"].get_type() != Variant::ARRAY) {
		r_errors.push_back(vformat("%s: 'stops' must be an Array of [offset, value].", p_where));
		return;
	}
	const Array stops = p_module["stops"];
	if (stops.is_empty()) {
		r_errors.push_back(vformat("%s: 'stops' must not be empty.", p_where));
	}
	double previous = -1.0e30;
	for (int i = 0; i < stops.size(); i++) {
		if (stops[i].get_type() != Variant::ARRAY || ((Array)stops[i]).size() != 2) {
			r_errors.push_back(vformat("%s: stop %d must be [offset, value].", p_where, i));
			continue;
		}
		const Array stop = stops[i];
		if (!_is_number(stop[0])) {
			r_errors.push_back(vformat("%s: stop %d offset must be a number.", p_where, i));
			continue;
		}
		if ((double)stop[0] < previous) {
			r_errors.push_back(vformat("%s: stop offsets must be ascending (stop %d).", p_where, i));
		}
		previous = (double)stop[0];
		const bool value_ok = p_color ? stop[1].get_type() == Variant::COLOR : _is_number(stop[1]);
		if (!value_ok) {
			r_errors.push_back(vformat("%s: stop %d value must be a %s.", p_where, i, p_color ? "Color" : "number"));
		}
	}
}

void _check_event_specs(const Variant &p_spec, const Dictionary &p_emitters, const String &p_where, PackedStringArray &r_errors) {
	if (p_spec.get_type() == Variant::NIL) {
		return;
	}
	Array specs;
	if (p_spec.get_type() == Variant::DICTIONARY) {
		specs.push_back(p_spec);
	} else if (p_spec.get_type() == Variant::ARRAY) {
		specs = p_spec;
	} else {
		r_errors.push_back(vformat("%s: event spec must be a Dictionary or an Array of Dictionaries.", p_where));
		return;
	}
	for (int i = 0; i < specs.size(); i++) {
		if (specs[i].get_type() != Variant::DICTIONARY) {
			r_errors.push_back(vformat("%s: event spec %d must be a Dictionary.", p_where, i));
			continue;
		}
		const Dictionary spec = specs[i];
		if (!spec.has("emitter") || (spec["emitter"].get_type() != Variant::STRING && spec["emitter"].get_type() != Variant::STRING_NAME)) {
			r_errors.push_back(vformat("%s: event spec %d needs an 'emitter' name.", p_where, i));
		} else if (!p_emitters.has(String(spec["emitter"]))) {
			r_errors.push_back(vformat("%s: event spec %d routes to unknown emitter '%s'.", p_where, i, String(spec["emitter"])));
		}
		if (spec.has("count") && (!_is_number(spec["count"]) || (double)spec["count"] < 0.0)) {
			r_errors.push_back(vformat("%s: event spec %d 'count' must be >= 0.", p_where, i));
		}
		if (spec.has("inherit_velocity") && (!_is_number(spec["inherit_velocity"]) || (double)spec["inherit_velocity"] < 0.0 || (double)spec["inherit_velocity"] > 1.0)) {
			r_errors.push_back(vformat("%s: event spec %d 'inherit_velocity' must be within 0..1.", p_where, i));
		}
	}
}

void _check_module(const Variant &p_module, int p_index, bool p_spawn_stage, const String &p_emitter, const Dictionary &p_attributes, const Dictionary &p_emitters, PackedStringArray &r_errors) {
	const String stage = p_spawn_stage ? "spawn" : "update";
	const String where = vformat("emitter '%s' %s[%d]", p_emitter, stage, p_index);
	if (p_module.get_type() != Variant::DICTIONARY) {
		r_errors.push_back(vformat("%s: module must be a Dictionary.", where));
		return;
	}
	const Dictionary module = p_module;
	if (!module.has("type")) {
		r_errors.push_back(vformat("%s: missing 'type'.", where));
		return;
	}
	const String type = String(module["type"]);
	const VFXSim::ModuleType mt = VFXSim::module_type_from_name(type);
	if (mt == VFXSim::MODULE_UNKNOWN) {
		r_errors.push_back(vformat("%s: unknown module type '%s'.", where, type));
		return;
	}
	if (VFXSim::is_spawn_stage_module(mt) != p_spawn_stage) {
		r_errors.push_back(vformat("%s: '%s' is a %s-stage module.", where, type, p_spawn_stage ? "update" : "spawn"));
		return;
	}
	const String full = vformat("%s (%s)", where, type);
	for (const ModuleSchema &schema : SCHEMAS) {
		if (type != schema.type) {
			continue;
		}
		for (int i = 0; i < schema.count; i++) {
			const ParamDef &param = schema.params[i];
			if (module.has(param.name) && param.kind != 'o' && param.kind != 'a') {
				_check_value(module[param.name], param, full, r_errors);
			}
		}
	}
	switch (mt) {
		case VFXSim::MODULE_SPAWN_RATE:
			if (module.has("rate") && _is_number(module["rate"]) && (double)module["rate"] < 0.0) {
				r_errors.push_back(vformat("%s: 'rate' must be >= 0.", full));
			}
			break;
		case VFXSim::MODULE_SPAWN_BURST:
			if (module.has("count") && _is_number(module["count"]) && (double)module["count"] < 0.0) {
				r_errors.push_back(vformat("%s: 'count' must be >= 0.", full));
			}
			if (module.has("time") && _is_number(module["time"]) && (double)module["time"] < 0.0) {
				r_errors.push_back(vformat("%s: 'time' must be >= 0.", full));
			}
			break;
		case VFXSim::MODULE_LIFETIME_RANDOM:
			if (module.has("min") && module.has("max") && _is_number(module["min"]) && _is_number(module["max"]) && (double)module["min"] > (double)module["max"]) {
				r_errors.push_back(vformat("%s: 'min' must not exceed 'max'.", full));
			}
			break;
		case VFXSim::MODULE_INITIAL_ATTRIBUTE:
			if (!module.has("attribute") || !p_attributes.has(String(module["attribute"]))) {
				r_errors.push_back(vformat("%s: attribute '%s' is not declared in 'attributes'.", full, module.has("attribute") ? String(module["attribute"]) : String()));
			}
			break;
		case VFXSim::MODULE_COLOR_OVER_LIFE:
			_check_stops(module, true, full, r_errors);
			break;
		case VFXSim::MODULE_SIZE_OVER_LIFE:
			_check_stops(module, false, full, r_errors);
			break;
		case VFXSim::MODULE_COLLIDE_PLANE:
			if (module.has("restitution") && _is_number(module["restitution"]) && (double)module["restitution"] < 0.0) {
				r_errors.push_back(vformat("%s: 'restitution' must be >= 0.", full));
			}
			if (module.has("friction") && _is_number(module["friction"]) && ((double)module["friction"] < 0.0 || (double)module["friction"] > 1.0)) {
				r_errors.push_back(vformat("%s: 'friction' must be within 0..1.", full));
			}
			if (module.has("on_event")) {
				_check_event_specs(module["on_event"], p_emitters, full, r_errors);
			}
			break;
		default:
			break;
	}
}

} // namespace

PackedStringArray VFXGraphAsset::validate_graph(const Dictionary &p_graph) {
	PackedStringArray errors;
	Dictionary emitters;
	if (p_graph.has("emitters")) {
		if (p_graph["emitters"].get_type() != Variant::DICTIONARY) {
			errors.push_back("'emitters' must be a Dictionary of emitter definitions.");
			return errors;
		}
		emitters = p_graph["emitters"];
	} else {
		emitters["main"] = p_graph;
	}
	if (emitters.is_empty()) {
		errors.push_back("Graph has no emitters.");
		return errors;
	}
	for (const Variant &key : emitters.get_key_list()) {
		const String name = String(key);
		if (emitters[key].get_type() != Variant::DICTIONARY) {
			errors.push_back(vformat("emitter '%s' must be a Dictionary.", name));
			continue;
		}
		const Dictionary def = emitters[key];
		if (def.has("max_particles")) {
			const Variant mp = def["max_particles"];
			if (!_is_number(mp) || (double)mp < 0.0) {
				errors.push_back(vformat("emitter '%s': 'max_particles' must be a non-negative number.", name));
			}
		}
		if (def.has("duration") && (!_is_number(def["duration"]) || (double)def["duration"] < 0.0)) {
			errors.push_back(vformat("emitter '%s': 'duration' must be a non-negative number.", name));
		}
		if (def.has("bounds") && (!_is_number(def["bounds"]) || (double)def["bounds"] <= 0.0)) {
			errors.push_back(vformat("emitter '%s': 'bounds' must be a positive number.", name));
		}
		if (def.has("blend") && String(def["blend"]) != "alpha" && String(def["blend"]) != "add") {
			errors.push_back(vformat("emitter '%s': 'blend' must be \"alpha\" or \"add\".", name));
		}
		Dictionary attributes;
		if (def.has("attributes")) {
			if (def["attributes"].get_type() != Variant::DICTIONARY) {
				errors.push_back(vformat("emitter '%s': 'attributes' must be a Dictionary.", name));
			} else {
				attributes = def["attributes"];
				for (const Variant &akey : attributes.get_key_list()) {
					if (!_is_number(attributes[akey])) {
						errors.push_back(vformat("emitter '%s': attribute '%s' default must be a number.", name, String(akey)));
					}
				}
			}
		}
		for (int stage = 0; stage < 2; stage++) {
			const String stage_name = stage == 0 ? "spawn" : "update";
			if (!def.has(stage_name)) {
				continue;
			}
			if (def[stage_name].get_type() != Variant::ARRAY) {
				errors.push_back(vformat("emitter '%s': '%s' must be an Array of modules.", name, stage_name));
				continue;
			}
			const Array list = def[stage_name];
			for (int i = 0; i < list.size(); i++) {
				_check_module(list[i], i, stage == 0, name, attributes, emitters, errors);
			}
		}
		if (def.has("events")) {
			if (def["events"].get_type() != Variant::DICTIONARY) {
				errors.push_back(vformat("emitter '%s': 'events' must be a Dictionary.", name));
			} else {
				const Dictionary events = def["events"];
				for (const Variant &ekey : events.get_key_list()) {
					const String ev = String(ekey);
					if (ev != "death" && ev != "collision") {
						errors.push_back(vformat("emitter '%s': unknown event '%s' (expected death or collision).", name, ev));
						continue;
					}
					_check_event_specs(events[ekey], emitters, vformat("emitter '%s' event '%s'", name, ev), errors);
				}
			}
		}
	}
	return errors;
}

void VFXGraphAsset::set_graph(const Dictionary &p_graph) {
	graph = p_graph.duplicate(true);
	emit_changed();
}

Dictionary VFXGraphAsset::get_system() const {
	if (graph.has("emitters")) {
		return graph;
	}
	Dictionary emitters;
	emitters["main"] = graph;
	Dictionary system;
	system["emitters"] = emitters;
	return system;
}

PackedStringArray VFXGraphAsset::get_emitter_names() const {
	PackedStringArray names;
	const Dictionary system = get_system();
	if (system["emitters"].get_type() != Variant::DICTIONARY) {
		return names;
	}
	const Dictionary emitters = system["emitters"];
	for (const Variant &key : emitters.get_key_list()) {
		names.push_back(String(key));
	}
	return names;
}

bool VFXGraphAsset::has_emitter(const String &p_name) const {
	return get_emitter_names().has(p_name);
}

Dictionary VFXGraphAsset::get_emitter(const String &p_name) const {
	const Dictionary system = get_system();
	if (system["emitters"].get_type() != Variant::DICTIONARY) {
		return Dictionary();
	}
	const Dictionary emitters = system["emitters"];
	if (emitters.has(p_name) && emitters[p_name].get_type() == Variant::DICTIONARY) {
		return emitters[p_name];
	}
	return Dictionary();
}

int VFXGraphAsset::get_emitter_count() const {
	return get_emitter_names().size();
}

int VFXGraphAsset::get_total_max_particles() const {
	int total = 0;
	for (const String &name : get_emitter_names()) {
		const Dictionary def = get_emitter(name);
		total += def.has("max_particles") && (def["max_particles"].get_type() == Variant::INT || def["max_particles"].get_type() == Variant::FLOAT) ? MAX((int)def["max_particles"], 0) : 1000;
	}
	return total;
}

bool VFXGraphAsset::has_particles() const {
	return get_total_max_particles() > 0;
}

PackedStringArray VFXGraphAsset::validate() const {
	return validate_graph(graph);
}

Ref<VFXGraphAsset> VFXGraphAsset::create_from_dictionary(const Dictionary &p_graph) {
	Ref<VFXGraphAsset> asset;
	asset.instantiate();
	asset->set_graph(p_graph);
	return asset;
}

PackedStringArray VFXGraphAsset::get_module_names() {
	PackedStringArray names;
	for (const ModuleSchema &schema : SCHEMAS) {
		names.push_back(schema.type);
	}
	return names;
}

void VFXGraphAsset::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_graph", "graph"), &VFXGraphAsset::set_graph);
	ClassDB::bind_method(D_METHOD("get_graph"), &VFXGraphAsset::get_graph);
	ClassDB::bind_method(D_METHOD("get_system"), &VFXGraphAsset::get_system);
	ClassDB::bind_method(D_METHOD("get_emitter_names"), &VFXGraphAsset::get_emitter_names);
	ClassDB::bind_method(D_METHOD("has_emitter", "name"), &VFXGraphAsset::has_emitter);
	ClassDB::bind_method(D_METHOD("get_emitter", "name"), &VFXGraphAsset::get_emitter);
	ClassDB::bind_method(D_METHOD("get_emitter_count"), &VFXGraphAsset::get_emitter_count);
	ClassDB::bind_method(D_METHOD("get_total_max_particles"), &VFXGraphAsset::get_total_max_particles);
	ClassDB::bind_method(D_METHOD("has_particles"), &VFXGraphAsset::has_particles);
	ClassDB::bind_method(D_METHOD("validate"), &VFXGraphAsset::validate);
	ClassDB::bind_method(D_METHOD("is_valid"), &VFXGraphAsset::is_valid);
	ClassDB::bind_static_method("VFXGraphAsset", D_METHOD("validate_graph", "graph"), &VFXGraphAsset::validate_graph);
	ClassDB::bind_static_method("VFXGraphAsset", D_METHOD("create_from_dictionary", "graph"), &VFXGraphAsset::create_from_dictionary);
	ClassDB::bind_static_method("VFXGraphAsset", D_METHOD("get_module_names"), &VFXGraphAsset::get_module_names);

	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "graph"), "set_graph", "get_graph");
}
