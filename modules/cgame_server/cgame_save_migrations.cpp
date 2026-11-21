/**************************************************************************/
/*  cgame_save_migrations.cpp                                             */
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

#include "cgame_save_migrations.h"

#include "core/object/callable_mp.h"

// Registry preloaded with the two example character migrations.
Ref<CgameSaveMigrations> CgameSaveMigrations::character_registry() {
	Ref<CgameSaveMigrations> reg;
	reg.instantiate();
	reg->register_step(1, 2, callable_mp_static(&CgameSaveMigrations::example_v1_to_v2));
	reg->register_step(2, 3, callable_mp_static(&CgameSaveMigrations::example_v2_to_v3));
	return reg;
}

// Returns false (and sets last_error) for non-forward steps or a duplicate from_version.
bool CgameSaveMigrations::register_step(int p_from_version, int p_to_version, const Callable &p_migrate) {
	if (p_to_version != p_from_version + 1) {
		last_error = vformat("migration %d->%d must advance exactly one version", p_from_version, p_to_version);
		return false;
	}
	if (steps.has(p_from_version)) {
		last_error = vformat("migration from %d already registered", p_from_version);
		return false;
	}
	if (!p_migrate.is_valid()) {
		last_error = vformat("migration %d->%d has an invalid callable", p_from_version, p_to_version);
		return false;
	}
	Dictionary step;
	step["to"] = p_to_version;
	step["migrate"] = p_migrate;
	steps[p_from_version] = step;
	return true;
}

// Returns the migrated deep copy, or an empty Dictionary with last_error set (gap, downgrade, bad
// version, step failure).
Dictionary CgameSaveMigrations::migrate(const Dictionary &p_data, int p_target_version) {
	last_error = "";
	if (!p_data.has("version") || (p_data["version"].get_type() != Variant::INT && p_data["version"].get_type() != Variant::FLOAT)) {
		last_error = "save has no numeric version";
		return Dictionary();
	}
	int version = int(p_data["version"]);
	if (version > p_target_version) {
		last_error = vformat("refusing downgrade from v%d to v%d", version, p_target_version);
		return Dictionary();
	}
	Dictionary current = p_data.duplicate(true);
	while (version < p_target_version) {
		if (!steps.has(version)) {
			last_error = vformat("no migration from v%d (gap before v%d)", version, p_target_version);
			return Dictionary();
		}
		Dictionary step = steps[version];
		Callable migrate_fn = step["migrate"];
		const Variant result = migrate_fn.call(current.duplicate(true));
		if (result.get_type() != Variant::DICTIONARY) {
			last_error = vformat("migration v%d->v%d returned a non-Dictionary", version, int(step["to"]));
			return Dictionary();
		}
		current = result;
		version = int(step["to"]);
		current["version"] = version;
	}
	return current;
}

// Returns problems (empty = ok): migration failure, input mutated, wrong final version, validator
// rejection, or a second migrate() call that is not a no-op.
TypedArray<String> CgameSaveMigrations::verify_roundtrip(const Dictionary &p_data, int p_migrate_to, const Callable &p_validate) {
	TypedArray<String> problems;
	Dictionary before = p_data.duplicate(true);
	Dictionary out = migrate(p_data, p_migrate_to);
	if (out.is_empty()) {
		problems.push_back("migration failed: " + last_error);
		return problems;
	}
	if (!p_data.recursive_equal(before, 0)) {
		problems.push_back("migration mutated its input");
	}
	if (int(out.get("version", -1)) != p_migrate_to) {
		problems.push_back(vformat("result version is %s, expected %d", String(out.get("version", Variant())), p_migrate_to));
	}
	if (p_validate.is_valid()) {
		const Variant verdict = p_validate.call(out);
		if (verdict.get_type() == Variant::BOOL && !bool(verdict)) {
			problems.push_back("validator rejected migrated data");
		} else if (verdict.get_type() == Variant::STRING && !String(verdict).is_empty()) {
			problems.push_back("validator: " + String(verdict));
		} else if (verdict.get_type() == Variant::ARRAY) {
			Array items = verdict;
			for (int i = 0; i < items.size(); i++) {
				problems.push_back("validator: " + String(items[i]));
			}
		}
	}
	Dictionary again = migrate(out, p_migrate_to);
	if (!again.recursive_equal(out, 0)) {
		problems.push_back("migrating an up-to-date save changed it");
	}
	return problems;
}

// v1 -> v2: "money" is renamed "silver" (value preserved; an existing "silver" wins).
Dictionary CgameSaveMigrations::example_v1_to_v2(const Dictionary &p_data) {
	Dictionary data = p_data;
	if (data.has("money")) {
		if (!data.has("silver")) {
			data["silver"] = data["money"];
		}
		data.erase("money");
	}
	return data;
}

// v2 -> v3: adds the "focus" meter, defaulting to a full 100.0 when absent.
Dictionary CgameSaveMigrations::example_v2_to_v3(const Dictionary &p_data) {
	Dictionary data = p_data;
	if (!data.has("focus")) {
		data["focus"] = 100.0;
	}
	return data;
}

void CgameSaveMigrations::_bind_methods() {
	CGAME_BIND_PROPERTY(CgameSaveMigrations, Variant::STRING, last_error)

	ClassDB::bind_static_method("CgameSaveMigrations", D_METHOD("character_registry"), &CgameSaveMigrations::character_registry);
	ClassDB::bind_method(D_METHOD("register", "from_version", "to_version", "migrate_fn"), &CgameSaveMigrations::register_step);
	ClassDB::bind_method(D_METHOD("migrate", "data", "target_version"), &CgameSaveMigrations::migrate);
	ClassDB::bind_method(D_METHOD("verify_roundtrip", "data", "migrate_to", "validate"), &CgameSaveMigrations::verify_roundtrip, DEFVAL(Callable()));
	ClassDB::bind_static_method("CgameSaveMigrations", D_METHOD("example_v1_to_v2", "data"), &CgameSaveMigrations::example_v1_to_v2);
	ClassDB::bind_static_method("CgameSaveMigrations", D_METHOD("example_v2_to_v3", "data"), &CgameSaveMigrations::example_v2_to_v3);

	BIND_CONSTANT(CHARACTER_LATEST);
}
