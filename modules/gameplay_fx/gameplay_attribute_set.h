/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/string/string_name.h"
#include "core/templates/vector.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

// Compact numerical attribute aggregator inspired by Unreal GAS AttributeSets.
// Numeric properties are authoritative only when owned by the server; clients
// may use an instance to calculate presentation from replicated snapshots.
class GameplayAttributeSet : public RefCounted {
	GDCLASS(GameplayAttributeSet, RefCounted);

public:
	static constexpr int MAX_ATTRIBUTES = 64;
	static constexpr int MAX_MODIFIERS = 256;
	static constexpr double MAX_VALUE = 1000000000.0;
	static constexpr double MAX_ADDITIVE = 1000000.0;

private:
	struct Attribute {
		StringName name;
		double base = 0.0;
		double minimum = -MAX_VALUE;
		double maximum = MAX_VALUE;
	};
	struct Modifier {
		StringName source;
		StringName attribute;
		double additive = 0.0;
		double percent = 0.0;
	};
	Vector<Attribute> attributes;
	Vector<Modifier> modifiers;
	mutable Dictionary cached_results;

	int _find_attribute(const StringName &p_attribute) const;
	int _find_modifier(const StringName &p_source, const StringName &p_attribute) const;
	static bool _valid_tag(const StringName &p_tag);
	static bool _valid_value(double p_value, double p_bound);
	static bool _valid_modifier(double p_additive, double p_percent);

protected:
	static void _bind_methods();

public:
	// Modifiers combine as clamp((base + sum(additive)) * max(0, 1 + sum(percent))).
	// Evaluation does not depend on insertion order. Identical queries are cached.
	bool set_base_value(const StringName &p_attribute, double p_value);
	bool set_bounds(const StringName &p_attribute, double p_minimum, double p_maximum);
	bool set_modifier(const StringName &p_source, const StringName &p_attribute, double p_additive = 0.0, double p_percent = 0.0);
	bool remove_modifier(const StringName &p_source, const StringName &p_attribute);
	int clear_source(const StringName &p_source);
	void clear();
	double get_value(const StringName &p_attribute) const;
	double get_base_value(const StringName &p_attribute) const;
	bool has_attribute(const StringName &p_attribute) const { return _find_attribute(p_attribute) >= 0; }
	int get_attribute_count() const { return attributes.size(); }
	int get_modifier_count() const { return modifiers.size(); }
	// Complete transaction: invalid attributes/modifiers never partially apply.
	bool replace_snapshot(const Dictionary &p_snapshot);
	Dictionary get_snapshot() const;
};
