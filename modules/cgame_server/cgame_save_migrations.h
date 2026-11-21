/**************************************************************************/
/*  cgame_save_migrations.h                                               */
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

#include "cgame_server_macros.h"

#include "core/object/ref_counted.h"
#include "core/variant/callable.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"

// Versioned save-data migrations: a registry of single-step migrations
// {from_version, to_version, migrate: Callable}. migrate() walks the chain from data["version"] to
// the target, never mutating the caller's dictionary and refusing gaps and downgrades.
// verify_roundtrip() proves a sample survives migration and still passes a validator, so every new
// schema bump ships with a fixture.
//
// A migration Callable takes a Dictionary (already a deep copy, free to mutate) and returns the
// upgraded Dictionary WITHOUT touching "version" (the runner stamps it). Steps must be +1 and pure.
//
// Example character-save shape: v1 {version, health, money}; v2 renames money to silver
// (example_v1_to_v2); v3 adds a "focus" meter defaulting to 100.0 (example_v2_to_v3).
class CgameSaveMigrations : public RefCounted {
	GDCLASS(CgameSaveMigrations, RefCounted);

	Dictionary steps;
	String last_error;

protected:
	static void _bind_methods();

public:
	static constexpr int CHARACTER_LATEST = 3;

	CGAME_ACCESSORS(String, last_error)

	static Ref<CgameSaveMigrations> character_registry();
	bool register_step(int p_from_version, int p_to_version, const Callable &p_migrate);
	Dictionary migrate(const Dictionary &p_data, int p_target_version);
	TypedArray<String> verify_roundtrip(const Dictionary &p_data, int p_migrate_to, const Callable &p_validate);

	static Dictionary example_v1_to_v2(const Dictionary &p_data);
	static Dictionary example_v2_to_v3(const Dictionary &p_data);
};
