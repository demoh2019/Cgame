/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#include "gameplay_attribute_set.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

bool GameplayAttributeSet::_valid_tag(const StringName &p_tag) {
	const String name = p_tag;
	return !name.is_empty() && !name.begins_with(".") && !name.ends_with(".") && !name.contains("..");
}

bool GameplayAttributeSet::_valid_value(double p_value, double p_bound) {
	return Math::is_finite(p_value) && p_value >= -p_bound && p_value <= p_bound;
}

bool GameplayAttributeSet::_valid_modifier(double p_additive, double p_percent) {
	return _valid_value(p_additive, MAX_ADDITIVE) &&
			Math::is_finite(p_percent) && p_percent >= -1.0 && p_percent <= 8.0;
}

int GameplayAttributeSet::_find_attribute(const StringName &p_attribute) const {
	for (int i = 0; i < attributes.size(); ++i) {
		if (attributes[i].name == p_attribute) {
			return i;
		}
	}
	return -1;
}

int GameplayAttributeSet::_find_modifier(const StringName &p_source, const StringName &p_attribute) const {
	for (int i = 0; i < modifiers.size(); ++i) {
		if (modifiers[i].source == p_source && modifiers[i].attribute == p_attribute) {
			return i;
		}
	}
	return -1;
}

bool GameplayAttributeSet::set_base_value(const StringName &p_attribute, double p_value) {
	if (!_valid_tag(p_attribute) || !_valid_value(p_value, MAX_VALUE)) {
		return false;
	}
	const int index = _find_attribute(p_attribute);
	if (index < 0) {
		if (attributes.size() >= MAX_ATTRIBUTES) {
			return false;
		}
		Attribute attr;
		attr.name = p_attribute;
		attr.base = p_value;
		attributes.push_back(attr);
	} else {
		attributes.write[index].base = p_value;
	}
	cached_results.clear();
	return true;
}

bool GameplayAttributeSet::set_bounds(const StringName &p_attribute, double p_minimum, double p_maximum) {
	const int index = _find_attribute(p_attribute);
	if (index < 0 || !_valid_value(p_minimum, MAX_VALUE) ||
			!_valid_value(p_maximum, MAX_VALUE) || p_minimum > p_maximum) {
		return false;
	}
	attributes.write[index].minimum = p_minimum;
	attributes.write[index].maximum = p_maximum;
	cached_results.clear();
	return true;
}

bool GameplayAttributeSet::set_modifier(const StringName &p_source, const StringName &p_attribute, double p_additive, double p_percent) {
	if (!_valid_tag(p_source) || !_valid_tag(p_attribute) ||
			_find_attribute(p_attribute) < 0 || !_valid_modifier(p_additive, p_percent)) {
		return false;
	}
	const int index = _find_modifier(p_source, p_attribute);
	if (index < 0) {
		if (modifiers.size() >= MAX_MODIFIERS) {
			return false;
		}
		Modifier m;
		m.source = p_source;
		m.attribute = p_attribute;
		m.additive = p_additive;
		m.percent = p_percent;
		modifiers.push_back(m);
	} else {
		modifiers.write[index].additive = p_additive;
		modifiers.write[index].percent = p_percent;
	}
	cached_results.clear();
	return true;
}

bool GameplayAttributeSet::remove_modifier(const StringName &p_source, const StringName &p_attribute) {
	const int index = _find_modifier(p_source, p_attribute);
	if (index < 0) {
		return false;
	}
	modifiers.remove_at(index);
	cached_results.clear();
	return true;
}

int GameplayAttributeSet::clear_source(const StringName &p_source) {
	int removed = 0;
	for (int i = modifiers.size() - 1; i >= 0; --i) {
		if (modifiers[i].source == p_source) {
			modifiers.remove_at(i);
			removed++;
		}
	}
	if (removed > 0) {
		cached_results.clear();
	}
	return removed;
}

void GameplayAttributeSet::clear() {
	attributes.clear();
	modifiers.clear();
	cached_results.clear();
}

double GameplayAttributeSet::get_value(const StringName &p_attribute) const {
	if (cached_results.has(p_attribute)) {
		return cached_results[p_attribute];
	}
	const int index = _find_attribute(p_attribute);
	if (index < 0) {
		return 0.0;
	}
	const Attribute &attr = attributes[index];
	double additive = 0.0;
	double percent = 0.0;
	for (const Modifier &modifier : modifiers) {
		if (modifier.attribute == p_attribute) {
			additive += modifier.additive;
			percent += modifier.percent;
		}
	}
	const double result = CLAMP((attr.base + additive) * MAX(0.0, 1.0 + percent), attr.minimum, attr.maximum);
	cached_results[p_attribute] = result;
	return result;
}

double GameplayAttributeSet::get_base_value(const StringName &p_attribute) const {
	const int index = _find_attribute(p_attribute);
	return index < 0 ? 0.0 : attributes[index].base;
}

Dictionary GameplayAttributeSet::get_snapshot() const {
	Dictionary result;
	Dictionary attrs;
	for (const Attribute &attr : attributes) {
		Dictionary value;
		value["base"] = attr.base;
		value["min"] = attr.minimum;
		value["max"] = attr.maximum;
		attrs[attr.name] = value;
	}
	Array mods;
	for (const Modifier &modifier : modifiers) {
		Dictionary value;
		value["source"] = modifier.source;
		value["attribute"] = modifier.attribute;
		value["additive"] = modifier.additive;
		value["percent"] = modifier.percent;
		mods.push_back(value);
	}
	result["attributes"] = attrs;
	result["modifiers"] = mods;
	return result;
}

bool GameplayAttributeSet::_parse_snapshot(const Dictionary &p_snapshot, Vector<Attribute> &r_attributes, Vector<Modifier> &r_modifiers) const {
	if (!p_snapshot.has("attributes") || !p_snapshot.has("modifiers")) {
		return false;
	}
	const Variant raw_attrs = p_snapshot["attributes"];
	const Variant raw_mods = p_snapshot["modifiers"];
	if (raw_attrs.get_type() != Variant::DICTIONARY || raw_mods.get_type() != Variant::ARRAY) {
		return false;
	}
	const Dictionary attr_dict = raw_attrs;
	const Array mod_array = raw_mods;
	if (attr_dict.size() > MAX_ATTRIBUTES || mod_array.size() > MAX_MODIFIERS) {
		return false;
	}
	Vector<Attribute> parsed_attrs;
	for (const Variant &key : attr_dict) {
		if (key.get_type() != Variant::STRING && key.get_type() != Variant::STRING_NAME) {
			return false;
		}
		const StringName name = key;
		if (!_valid_tag(name)) {
			return false;
		}
		for (const Attribute &existing : parsed_attrs) {
			if (existing.name == name) {
				return false;
			}
		}
		const Variant raw_entry = attr_dict[key];
		if (raw_entry.get_type() != Variant::DICTIONARY) {
			return false;
		}
		const Dictionary entry = raw_entry;
		if (!entry.has("base") || !entry.has("min") || !entry.has("max")) {
			return false;
		}
		const Variant raw_base = entry["base"], raw_min = entry["min"], raw_max = entry["max"];
		if ((raw_base.get_type() != Variant::INT && raw_base.get_type() != Variant::FLOAT) ||
				(raw_min.get_type() != Variant::INT && raw_min.get_type() != Variant::FLOAT) ||
				(raw_max.get_type() != Variant::INT && raw_max.get_type() != Variant::FLOAT)) {
			return false;
		}
		Attribute parsed;
		parsed.name = name;
		parsed.base = double(raw_base);
		parsed.minimum = double(raw_min);
		parsed.maximum = double(raw_max);
		if (!_valid_value(parsed.base, MAX_VALUE) || !_valid_value(parsed.minimum, MAX_VALUE) ||
				!_valid_value(parsed.maximum, MAX_VALUE) || parsed.minimum > parsed.maximum) {
			return false;
		}
		parsed_attrs.push_back(parsed);
	}
	Vector<Modifier> parsed_mods;
	for (const Variant &item : mod_array) {
		if (item.get_type() != Variant::DICTIONARY) {
			return false;
		}
		const Dictionary entry = item;
		if (!entry.has("source") || !entry.has("attribute") || !entry.has("additive") || !entry.has("percent")) {
			return false;
		}
		const Variant raw_src = entry["source"], raw_attr = entry["attribute"];
		const Variant raw_add = entry["additive"], raw_pct = entry["percent"];
		if ((raw_src.get_type() != Variant::STRING && raw_src.get_type() != Variant::STRING_NAME) ||
				(raw_attr.get_type() != Variant::STRING && raw_attr.get_type() != Variant::STRING_NAME) ||
				(raw_add.get_type() != Variant::INT && raw_add.get_type() != Variant::FLOAT) ||
				(raw_pct.get_type() != Variant::INT && raw_pct.get_type() != Variant::FLOAT)) {
			return false;
		}
		Modifier m;
		m.source = raw_src;
		m.attribute = raw_attr;
		m.additive = double(raw_add);
		m.percent = double(raw_pct);
		if (!_valid_tag(m.source) || !_valid_tag(m.attribute) || !_valid_modifier(m.additive, m.percent)) {
			return false;
		}
		bool found_attribute = false;
		for (const Attribute &attr : parsed_attrs) {
			if (attr.name == m.attribute) {
				found_attribute = true;
				break;
			}
		}
		if (!found_attribute) {
			return false;
		}
		for (const Modifier &existing : parsed_mods) {
			if (existing.source == m.source && existing.attribute == m.attribute) {
				return false;
			}
		}
		parsed_mods.push_back(m);
	}
	r_attributes = parsed_attrs;
	r_modifiers = parsed_mods;
	return true;
}

// Branch matching is exact or dot-delimited, never string-prefix matching.
bool GameplayAttributeSet::_source_in_branch(const StringName &p_source, const StringName &p_branch) {
	const String source = p_source;
	const String branch = p_branch;
	return source == branch || (source.length() > branch.length() &&
			source.begins_with(branch) && source[branch.length()] == '.');
}

bool GameplayAttributeSet::replace_snapshot(const Dictionary &p_snapshot) {
	Vector<Attribute> parsed_attrs;
	Vector<Modifier> parsed_mods;
	if (!_parse_snapshot(p_snapshot, parsed_attrs, parsed_mods)) {
		return false;
	}
	attributes = parsed_attrs;
	modifiers = parsed_mods;
	cached_results.clear();
	return true;
}

bool GameplayAttributeSet::replace_snapshot_branch(const StringName &p_branch, const Dictionary &p_snapshot) {
	if (!_valid_tag(p_branch)) {
		return false;
	}
	Vector<Attribute> parsed_attrs;
	Vector<Modifier> parsed_mods;
	if (!_parse_snapshot(p_snapshot, parsed_attrs, parsed_mods)) {
		return false;
	}
	// Do not permit a supposedly scoped authoritative snapshot to replace
	// any source outside its namespace.
	for (const Modifier &modifier : parsed_mods) {
		if (!_source_in_branch(modifier.source, p_branch)) {
			return false;
		}
	}

	// Retain independently owned modifiers (e.g. Local.Visual) and reject a
	// snapshot that removes an attribute still used by an outside source.
	for (const Modifier &modifier : modifiers) {
		if (_source_in_branch(modifier.source, p_branch)) {
			continue;
		}
		bool found_attribute = false;
		for (const Attribute &attr : parsed_attrs) {
			if (attr.name == modifier.attribute) {
				found_attribute = true;
				break;
			}
		}
		if (!found_attribute || parsed_mods.size() >= MAX_MODIFIERS) {
			return false; // Entire transaction is unchanged on failure.
		}
		parsed_mods.push_back(modifier);
	}
	attributes = parsed_attrs;
	modifiers = parsed_mods;
	cached_results.clear();
	return true;
}

void GameplayAttributeSet::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_base_value", "attribute", "value"), &GameplayAttributeSet::set_base_value);
	ClassDB::bind_method(D_METHOD("set_bounds", "attribute", "minimum", "maximum"), &GameplayAttributeSet::set_bounds);
	ClassDB::bind_method(D_METHOD("set_modifier", "source", "attribute", "additive", "percent"), &GameplayAttributeSet::set_modifier, DEFVAL(0.0), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("remove_modifier", "source", "attribute"), &GameplayAttributeSet::remove_modifier);
	ClassDB::bind_method(D_METHOD("clear_source", "source"), &GameplayAttributeSet::clear_source);
	ClassDB::bind_method(D_METHOD("clear"), &GameplayAttributeSet::clear);
	ClassDB::bind_method(D_METHOD("get_value", "attribute"), &GameplayAttributeSet::get_value);
	ClassDB::bind_method(D_METHOD("get_base_value", "attribute"), &GameplayAttributeSet::get_base_value);
	ClassDB::bind_method(D_METHOD("has_attribute", "attribute"), &GameplayAttributeSet::has_attribute);
	ClassDB::bind_method(D_METHOD("get_attribute_count"), &GameplayAttributeSet::get_attribute_count);
	ClassDB::bind_method(D_METHOD("get_modifier_count"), &GameplayAttributeSet::get_modifier_count);
	ClassDB::bind_method(D_METHOD("get_snapshot"), &GameplayAttributeSet::get_snapshot);
	ClassDB::bind_method(D_METHOD("replace_snapshot", "snapshot"), &GameplayAttributeSet::replace_snapshot);
	ClassDB::bind_method(D_METHOD("replace_snapshot_branch", "branch", "snapshot"), &GameplayAttributeSet::replace_snapshot_branch);
}
