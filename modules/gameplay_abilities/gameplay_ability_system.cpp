/**************************************************************************/
/*  gameplay_ability_system.cpp                                          */                                                     */
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

#include "gameplay_ability_system.h"

#include "core/object/class_db.h"

#include <cmath>

static bool _ability_finite_number(const Variant &p_value, double p_limit) {
	if (p_value.get_type() != Variant::FLOAT && p_value.get_type() != Variant::INT) {
		return false;
	}
	const double value = double(p_value);
	return std::isfinite(value) && value >= 0.0 && value <= p_limit;
}

bool GameplayAbilitySystem::_validate_tag_array(const Variant &p_value) {
	if (p_value.get_type() != Variant::PACKED_STRING_ARRAY) {
		return false;
	}
	const PackedStringArray value = p_value;
	if (value.size() > 128) {
		return false;
	}
	for (int i = 0; i < value.size(); i++) {
		if (value[i].strip_edges().is_empty() || value[i] != value[i].strip_edges()) {
			return false;
		}
	}
	return true;
}

bool GameplayAbilitySystem::_validate_definition(const Dictionary &p_definition) {
	if (!_ability_finite_number(p_definition.get("cost", 0.0), 1000000000.0) ||
			!_ability_finite_number(p_definition.get("cooldown", 0.0), 1000000.0)) {
		return false;
	}
	const char *tag_fields[] = { "required_tags", "blocked_tags" };
	for (const char *field : tag_fields) {
		if (p_definition.has(field) && !_validate_tag_array(p_definition[field])) {
			return false;
		}
	}
	return true;
}

bool GameplayAbilitySystem::register_ability(const String &p_id, const Dictionary &p_definition) {
	if (p_id.strip_edges().is_empty() || p_id != p_id.strip_edges() || !_validate_definition(p_definition)) {
		return false;
	}
	definitions[p_id] = p_definition.duplicate(true);
	return true;
}

void GameplayAbilitySystem::unregister_ability(const String &p_id) {
	definitions.erase(p_id);
	cooldowns.erase(p_id);
}

bool GameplayAbilitySystem::has_ability(const String &p_id) const {
	return definitions.has(p_id);
}

Dictionary GameplayAbilitySystem::get_ability(const String &p_id) const {
	if (!definitions.has(p_id)) {
		return Dictionary();
	}
	const Dictionary definition = definitions[p_id];
	return definition.duplicate(true);
}

bool GameplayAbilitySystem::_has_matching_tag(const String &p_tag) const {
	for (int i = 0; i < tags.size(); i++) {
		if (tags[i] == p_tag || tags[i].begins_with(p_tag + ".")) {
			return true;
		}
	}
	return false;
}

GameplayAbilitySystem::ActivationResult GameplayAbilitySystem::get_activation_result(const String &p_id) const {
	if (!definitions.has(p_id)) {
		return UNKNOWN_ABILITY;
	}
	if (get_remaining_cooldown(p_id) > 0.0) {
		return ON_COOLDOWN;
	}
	const Dictionary definition = definitions[p_id];
	if (resource < double(definition.get("cost", 0.0))) {
		return INSUFFICIENT_RESOURCE;
	}
	const PackedStringArray required = definition.get("required_tags", PackedStringArray());
	for (int i = 0; i < required.size(); i++) {
		if (!_has_matching_tag(required[i])) {
			return MISSING_REQUIRED_TAG;
		}
	}
	const PackedStringArray blocked = definition.get("blocked_tags", PackedStringArray());
	for (int i = 0; i < blocked.size(); i++) {
		if (_has_matching_tag(blocked[i])) {
			return BLOCKED_BY_TAG;
		}
	}
	return ACTIVATED;
}

GameplayAbilitySystem::ActivationResult GameplayAbilitySystem::activate(const String &p_id) {
	const ActivationResult result = get_activation_result(p_id);
	if (result != ACTIVATED) {
		emit_signal(SNAME("activation_failed"), p_id, result);
		return result;
	}
	const Dictionary definition = definitions[p_id];
	const double cost = double(definition.get("cost", 0.0));
	const double duration = double(definition.get("cooldown", 0.0));
	if (cost > 0.0) {
		resource -= cost;
		emit_signal(SNAME("resource_changed"), resource, max_resource);
	}
	if (duration > 0.0) {
		cooldowns[p_id] = duration;
	} else {
		cooldowns.erase(p_id);
	}
	emit_signal(SNAME("ability_activated"), p_id);
	return ACTIVATED;
}

double GameplayAbilitySystem::get_remaining_cooldown(const String &p_id) const {
	return cooldowns.has(p_id) ? double(cooldowns[p_id]) : 0.0;
}

void GameplayAbilitySystem::tick(double p_delta) {
	if (!std::isfinite(p_delta) || p_delta <= 0.0) {
		return;
	}
	const Array ids = cooldowns.keys();
	for (const Variant &key : ids) {
		if (!cooldowns.has(key)) {
			continue; // A cooldown_finished listener may remove another ability.
		}
		const double remaining = double(cooldowns[key]) - p_delta;
		if (remaining <= 0.0) {
			cooldowns.erase(key);
			emit_signal(SNAME("cooldown_finished"), key);
		} else {
			cooldowns[key] = remaining;
		}
	}
}

bool GameplayAbilitySystem::add_tag(const String &p_tag) {
	if (p_tag.strip_edges().is_empty() || p_tag != p_tag.strip_edges() || tags.has(p_tag)) {
		return false;
	}
	tags.push_back(p_tag);
	emit_signal(SNAME("tags_changed"), get_tags());
	return true;
}

void GameplayAbilitySystem::remove_tag(const String &p_tag) {
	const int index = tags.find(p_tag);
	if (index >= 0) {
		tags.remove_at(index);
		emit_signal(SNAME("tags_changed"), get_tags());
	}
}

bool GameplayAbilitySystem::has_tag(const String &p_tag) const {
	return _has_matching_tag(p_tag);
}

PackedStringArray GameplayAbilitySystem::get_tags() const {
	return tags;
}

bool GameplayAbilitySystem::set_max_resource(double p_value) {
	if (!std::isfinite(p_value) || p_value < 0.0 || p_value > 1000000000.0) {
		return false;
	}
	max_resource = p_value;
	if (resource > max_resource) {
		resource = max_resource;
	}
	emit_signal(SNAME("resource_changed"), resource, max_resource);
	return true;
}

double GameplayAbilitySystem::get_max_resource() const {
	return max_resource;
}

bool GameplayAbilitySystem::set_resource(double p_value) {
	if (!std::isfinite(p_value) || p_value < 0.0) {
		return false;
	}
	resource = MIN(p_value, max_resource);
	emit_signal(SNAME("resource_changed"), resource, max_resource);
	return true;
}

double GameplayAbilitySystem::get_resource() const {
	return resource;
}

Dictionary GameplayAbilitySystem::save_state() const {
	Dictionary state;
	state["version"] = 1;
	state["max_resource"] = max_resource;
	state["resource"] = resource;
	state["tags"] = get_tags();
	state["cooldowns"] = cooldowns.duplicate(true);
	return state;
}

bool GameplayAbilitySystem::load_state(const Dictionary &p_state) {
	if (!p_state.has("version") || p_state["version"].get_type() != Variant::INT ||
			int(p_state["version"]) != 1 ||
			!p_state.has("max_resource") || !_ability_finite_number(p_state["max_resource"], 1000000000.0) ||
			!p_state.has("resource") || !_ability_finite_number(p_state["resource"], 1000000000.0) ||
			double(p_state["resource"]) > double(p_state["max_resource"]) ||
			!p_state.has("tags") || !_validate_tag_array(p_state["tags"]) ||
			!p_state.has("cooldowns") || p_state["cooldowns"].get_type() != Variant::DICTIONARY) {
		return false;
	}
	const PackedStringArray proposed_tags = p_state["tags"];
	for (int i = 0; i < proposed_tags.size(); i++) {
		for (int j = i + 1; j < proposed_tags.size(); j++) {
			if (proposed_tags[i] == proposed_tags[j]) {
				return false;
			}
		}
	}
	const Dictionary proposed_cooldowns = p_state["cooldowns"];
	const Array keys = proposed_cooldowns.keys();
	if (keys.size() > definitions.size()) {
		return false;
	}
	Dictionary next_cooldowns;
	for (const Variant &key : keys) {
		if (key.get_type() != Variant::STRING || !definitions.has(key) ||
				!_ability_finite_number(proposed_cooldowns[key], 1000000.0)) {
			return false;
		}
		const double value = double(proposed_cooldowns[key]);
		if (value > 0.0) {
			next_cooldowns[key] = value;
		}
	}
	max_resource = double(p_state["max_resource"]);
	resource = double(p_state["resource"]);
	tags = proposed_tags;
	cooldowns = next_cooldowns;
	emit_signal(SNAME("resource_changed"), resource, max_resource);
	emit_signal(SNAME("tags_changed"), get_tags());
	return true;
}

void GameplayAbilitySystem::_bind_methods() {
	ClassDB::bind_method(D_METHOD("register_ability", "id", "definition"), &GameplayAbilitySystem::register_ability);
	ClassDB::bind_method(D_METHOD("unregister_ability", "id"), &GameplayAbilitySystem::unregister_ability);
	ClassDB::bind_method(D_METHOD("has_ability", "id"), &GameplayAbilitySystem::has_ability);
	ClassDB::bind_method(D_METHOD("get_ability", "id"), &GameplayAbilitySystem::get_ability);
	ClassDB::bind_method(D_METHOD("get_activation_result", "id"), &GameplayAbilitySystem::get_activation_result);
	ClassDB::bind_method(D_METHOD("activate", "id"), &GameplayAbilitySystem::activate);
	ClassDB::bind_method(D_METHOD("get_remaining_cooldown", "id"), &GameplayAbilitySystem::get_remaining_cooldown);
	ClassDB::bind_method(D_METHOD("tick", "delta"), &GameplayAbilitySystem::tick);
	ClassDB::bind_method(D_METHOD("add_tag", "tag"), &GameplayAbilitySystem::add_tag);
	ClassDB::bind_method(D_METHOD("remove_tag", "tag"), &GameplayAbilitySystem::remove_tag);
	ClassDB::bind_method(D_METHOD("has_tag", "tag"), &GameplayAbilitySystem::has_tag);
	ClassDB::bind_method(D_METHOD("get_tags"), &GameplayAbilitySystem::get_tags);
	ClassDB::bind_method(D_METHOD("set_max_resource", "value"), &GameplayAbilitySystem::set_max_resource);
	ClassDB::bind_method(D_METHOD("get_max_resource"), &GameplayAbilitySystem::get_max_resource);
	ClassDB::bind_method(D_METHOD("set_resource", "value"), &GameplayAbilitySystem::set_resource);
	ClassDB::bind_method(D_METHOD("get_resource"), &GameplayAbilitySystem::get_resource);
	ClassDB::bind_method(D_METHOD("save_state"), &GameplayAbilitySystem::save_state);
	ClassDB::bind_method(D_METHOD("load_state", "state"), &GameplayAbilitySystem::load_state);

	ADD_SIGNAL(MethodInfo("ability_activated", PropertyInfo(Variant::STRING, "id")));
	ADD_SIGNAL(MethodInfo("activation_failed", PropertyInfo(Variant::STRING, "id"), PropertyInfo(Variant::INT, "result")));
	ADD_SIGNAL(MethodInfo("cooldown_finished", PropertyInfo(Variant::STRING, "id")));
	ADD_SIGNAL(MethodInfo("resource_changed", PropertyInfo(Variant::FLOAT, "resource"), PropertyInfo(Variant::FLOAT, "maximum")));
	ADD_SIGNAL(MethodInfo("tags_changed", PropertyInfo(Variant::PACKED_STRING_ARRAY, "tags")));

	BIND_ENUM_CONSTANT(ACTIVATED);
	BIND_ENUM_CONSTANT(UNKNOWN_ABILITY);
	BIND_ENUM_CONSTANT(ON_COOLDOWN);
	BIND_ENUM_CONSTANT(INSUFFICIENT_RESOURCE);
	BIND_ENUM_CONSTANT(MISSING_REQUIRED_TAG);
	BIND_ENUM_CONSTANT(BLOCKED_BY_TAG);
}
