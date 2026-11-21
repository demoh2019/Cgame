/**************************************************************************/
/*  test_ai_threat_table_2d.h                                                    */
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

#include "../ai_threat_table_2d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestAIThreatTable2D {

TEST_CASE("[AIThreatTable2D] Bounded record and deterministic lowest-hate eviction") {
	Ref<AIThreatTable2D> table;
	table.instantiate();
	Dictionary first;
	for (int id = 1; id <= 5; ++id) {
		CHECK(table->record(first, id, double(id)));
	}
	CHECK(first.size() == 5);
	CHECK_FALSE(table->record(first, 77, 0.5));
	CHECK(table->record(first, 77, 30.0));
	CHECK_FALSE(first.has(1));
	CHECK(first.size() == 5);

	Dictionary reverse;
	for (int id = 5; id >= 1; --id) {
		CHECK(table->record(reverse, id, 10.0));
	}
	CHECK(table->record(reverse, 77, 11.0));
	CHECK_FALSE(reverse.has(1)); // equal-hate eviction always lowest peer ID
	CHECK(reverse.has(2));
}

TEST_CASE("[AIThreatTable2D] Threat caps, decay and malformed samples") {
	Ref<AIThreatTable2D> table;
	table.instantiate();
	Dictionary entries;
	CHECK_FALSE(table->record(entries, -1, 10.0));
	CHECK_FALSE(table->record(entries, 0, 10.0));
	CHECK_FALSE(table->record(entries, 1, NaN));
	CHECK_FALSE(table->record(entries, 1, INF));
	CHECK_FALSE(table->record(entries, 1, -10.0));
	CHECK(entries.is_empty());
	CHECK(table->record(entries, 1, 50000.0));
	CHECK(table->record(entries, 1, 50000.0));
	CHECK(double(entries[1]) == 10000.0);
	table->decay(entries, NaN);
	CHECK(double(entries[1]) == 10000.0);
	table->decay(entries, 1.0);
	CHECK(double(entries[1]) == 9999.25);
	entries[2] = NaN;
	table->decay(entries, 0.1);
	CHECK_FALSE(entries.has(2));
	table->decay(entries, 20000.0);
	CHECK(entries.is_empty());
}

TEST_CASE("[AIThreatTable2D] Pick respects leash, safe zones and switch margin") {
	Ref<AIThreatTable2D> table;
	table.instantiate();
	Dictionary entries;
	entries[1] = 10.0;
	entries[2] = 12.0;
	Dictionary players;
	Dictionary a;
	a["position"] = Vector3(3, 0, 0);
	a["alive"] = true;
	a["safe"] = false;
	Dictionary b;
	b["position"] = Vector3(9, 0, 0);
	b["alive"] = true;
	b["safe"] = false;
	players[1] = a;
	players[2] = b;
	CHECK(table->pick(entries, players, Vector2(), 30.0) == 2);
	CHECK(table->pick(entries, players, Vector2(), 30.0, 1) == 1);
	entries[2] = 15.0;
	CHECK(table->pick(entries, players, Vector2(), 30.0, 1) == 2);
	b["safe"] = true;
	players[2] = b;
	CHECK(table->pick(entries, players, Vector2(), 30.0) == 1);
	CHECK_FALSE(entries.has(2));
	a["position"] = Vector3(500, 0, 0);
	players[1] = a;
	CHECK(table->pick(entries, players, Vector2(), 30.0) == -1);
	CHECK(entries.is_empty());
}

TEST_CASE("[AIThreatTable2D] Ties are deterministic regardless of source Dictionary order") {
	Ref<AIThreatTable2D> table;
	table.instantiate();
	Dictionary forward;
	forward[1] = 5.0;
	forward[2] = 5.0;
	Dictionary reverse;
	reverse[2] = 5.0;
	reverse[1] = 5.0;
	Dictionary players;
	for (int64_t id = 1; id <= 2; ++id) {
		Dictionary info;
		info["position"] = Vector3(id, 0, 0);
		info["alive"] = true;
		info["safe"] = false;
		players[id] = info;
	}
	CHECK(table->pick(forward, players, Vector2(), 30.0) == 1);
	CHECK(table->pick(reverse, players, Vector2(), 30.0) == 1);
	CHECK(table->pick(forward, players, Vector2(), 30.0, 2) == 2); // switch hysteresis
}

TEST_CASE("[AIThreatTable2D] Invalid targets are pruned, invalid origin changes nothing") {
	Ref<AIThreatTable2D> table;
	table.instantiate();
	Dictionary entries;
	entries[1] = 8.0;
	entries[2] = 9.0;
	entries[3] = 7.0;
	Dictionary players;
	Dictionary dead;
	dead["alive"] = false;
	dead["safe"] = false;
	dead["position"] = Vector3(0, 0, 0);
	players[1] = dead;
	Dictionary invalid;
	invalid["alive"] = true;
	invalid["safe"] = false;
	invalid["position"] = Vector3(INF, 0, 0);
	players[2] = invalid;
	CHECK(table->pick(entries, players, Vector2(NaN, 0), 100.0) == -1);
	CHECK(entries.size() == 3);
	CHECK(table->pick(entries, players, Vector2(), 100.0) == -1);
	CHECK(entries.is_empty());
}

} // namespace TestAIThreatTable2D
