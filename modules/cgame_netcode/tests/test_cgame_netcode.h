/**************************************************************************/
/*  test_cgame_netcode.h                                                  */
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

#include "../cgame_bit_stream.h"
#include "../cgame_net_schema.h"
#include "../cgame_replication_graph.h"
#include "../cgame_snapshot_delta.h"

#include "tests/test_macros.h"

namespace TestCgameNetcode {

TEST_CASE("[CgameNetcode] Bit writer/reader integer round trip") {
	Ref<CgameBitWriter> w;
	w.instantiate();
	w->write_bits(5, 3);
	w->write_bool(true);
	w->write_bits(0xABCDE, 20);
	w->write_bits(-1, 64);
	w->write_varint(0);
	w->write_varint(300);
	w->write_varint(int64_t(1) << 40);
	w->write_signed_varint(-1);
	w->write_signed_varint(-123456789);
	w->write_signed_varint(42);
	w->write_float32(1.5);
	w->write_string("héllo");
	CHECK(w->get_bit_count() > 0);

	Ref<CgameBitReader> r = CgameBitReader::create(w->get_bytes());
	CHECK(r->read_bits(3) == 5);
	CHECK(r->read_bool());
	CHECK(r->read_bits(20) == 0xABCDE);
	CHECK(r->read_bits(64) == -1);
	CHECK(r->read_varint() == 0);
	CHECK(r->read_varint() == 300);
	CHECK(r->read_varint() == (int64_t(1) << 40));
	CHECK(r->read_signed_varint() == -1);
	CHECK(r->read_signed_varint() == -123456789);
	CHECK(r->read_signed_varint() == 42);
	CHECK(r->read_float32() == 1.5);
	CHECK(r->read_string() == "héllo");
	CHECK(!r->is_overflowed());
	r->read_bits(64);
	CHECK(r->is_overflowed());
}

TEST_CASE("[CgameNetcode] Bit layout is LSB-first") {
	Ref<CgameBitWriter> w;
	w.instantiate();
	w->write_bits(1, 1);
	w->write_bits(0, 1);
	w->write_bits(1, 1);
	PackedByteArray b = w->get_bytes();
	CHECK(b.size() == 1);
	CHECK(b[0] == 0b101);
	CHECK(w->get_bit_count() == 3);
	w->align_to_byte();
	CHECK(w->get_bit_count() == 8);
}

TEST_CASE("[CgameNetcode] Quantized float error bound") {
	const double mn = -100.0, mx = 100.0;
	const int bits = 12;
	const double max_err = (mx - mn) / double((1 << bits) - 1) * 0.5 + 1e-9;
	Ref<CgameBitWriter> w;
	w.instantiate();
	for (int i = 0; i <= 200; i++) {
		w->write_float(-100.0 + i * 0.997, mn, mx, bits);
	}
	Ref<CgameBitReader> r = CgameBitReader::create(w->get_bytes());
	for (int i = 0; i <= 200; i++) {
		double expected = CLAMP(-100.0 + i * 0.997, mn, mx);
		CHECK(Math::abs(r->read_float(mn, mx, bits) - expected) <= max_err);
	}
}

TEST_CASE("[CgameNetcode] Angle wraps and stays within half a quantum") {
	const int bits = 10;
	const double quantum = Math::TAU / double(1 << bits);
	const double samples[] = { 0.0, 1.0, 3.14159, 6.2, -1.0, 7.5 };
	for (double a : samples) {
		Ref<CgameBitWriter> w;
		w.instantiate();
		w->write_angle(a, bits);
		Ref<CgameBitReader> r = CgameBitReader::create(w->get_bytes());
		double got = r->read_angle(bits);
		double d = Math::abs(Math::fposmod(got - a + Math::PI, Math::TAU) - Math::PI);
		CHECK(d <= quantum * 0.5 + 1e-9);
	}
}

TEST_CASE("[CgameNetcode] Vector3 and smallest-three quaternion round trip") {
	Ref<CgameBitWriter> w;
	w.instantiate();
	Vector3 v(12.5, -3.25, 99.0);
	w->write_vector3(v, -128.0, 128.0, 16);
	LocalVector<Quaternion> quats;
	quats.push_back(Quaternion());
	quats.push_back(Quaternion(Vector3(0, 1, 0), 1.2f));
	quats.push_back(Quaternion(Vector3(1, 2, 3).normalized(), 2.9f));
	quats.push_back(Quaternion(Vector3(0, 0, 1), -2.0f));
	for (const Quaternion &q : quats) {
		w->write_quaternion(q, 10);
	}
	CHECK(w->get_bit_count() == 48 + 4 * (2 + 30));

	Ref<CgameBitReader> r = CgameBitReader::create(w->get_bytes());
	Vector3 got = r->read_vector3(-128.0, 128.0, 16);
	CHECK(got.distance_to(v) < 0.01);
	for (const Quaternion &q : quats) {
		Quaternion g = r->read_quaternion(10);
		// q and -q are the same rotation.
		CHECK(Math::abs(g.dot(q)) > 0.9995);
	}
}

static Dictionary _make_schema() {
	Array fields;
	fields.push_back(CgameNetSchema::make_field("hp", "int", 8, 0, 255, "on_change"));
	fields.push_back(CgameNetSchema::make_field("pos", "vec3", 16, -512, 512, "on_change"));
	fields.push_back(CgameNetSchema::make_field("rot", "quat", 12, -1, 1, "on_change"));
	fields.push_back(CgameNetSchema::make_field("alive", "bool", 1, 0, 0, "always"));
	fields.push_back(CgameNetSchema::make_field("name", "string", 8, 0, 0, "initial_only"));
	fields.push_back(CgameNetSchema::make_field("ammo", "int", 6, 0, 63, "owner_only"));
	fields.push_back(CgameNetSchema::make_field("speed", "float", 10, 0, 20, "on_change"));
	Dictionary s;
	s["fields"] = fields;
	return s;
}

TEST_CASE("[CgameNetcode] Schema round trip, hash and versioning") {
	Ref<CgameNetSchema> schema;
	schema.instantiate();
	CHECK(schema->set_schema(_make_schema()));
	CHECK(schema->get_field_count() == 7);

	Dictionary state;
	state["hp"] = 77;
	state["pos"] = Vector3(10, 20, -30);
	state["rot"] = Quaternion(Vector3(0, 1, 0), 0.5f);
	state["alive"] = true;
	state["name"] = "Ünit";
	state["ammo"] = 12;
	state["speed"] = 7.5;

	PackedByteArray bytes = schema->serialize(state, Dictionary(), true);
	Dictionary out = schema->deserialize(bytes, Dictionary());
	CHECK(int(out["hp"]) == 77);
	CHECK(Vector3(out["pos"]).distance_to(Vector3(10, 20, -30)) < 0.05);
	CHECK(Math::abs(Quaternion(out["rot"]).dot(Quaternion(Vector3(0, 1, 0), 0.5f))) > 0.999);
	CHECK(bool(out["alive"]));
	CHECK(String(out["name"]) == "Ünit");
	CHECK(int(out["ammo"]) == 12);
	CHECK(Math::abs(double(out["speed"]) - 7.5) < 0.02);

	// Non-owners do not receive owner_only fields.
	Dictionary nonowner = schema->deserialize(schema->serialize(state, Dictionary(), false), Dictionary());
	CHECK(!nonowner.has("ammo"));
	CHECK(nonowner.has("hp"));

	Ref<CgameNetSchema> other;
	other.instantiate();
	Dictionary changed = _make_schema();
	Array f = changed["fields"];
	f.push_back(CgameNetSchema::make_field("extra", "bool", 1));
	CHECK(other->set_schema(changed));
	CHECK(other->get_schema_hash() != schema->get_schema_hash());
	CHECK(schema->get_schema_hash() <= 0xFFFFFFFFLL);

	PackedByteArray ver = schema->serialize_versioned(state, Dictionary(), true);
	CHECK(bool(schema->deserialize_versioned(ver, Dictionary())["ok"]));
	CHECK(!bool(other->deserialize_versioned(ver, Dictionary())["ok"]));
	CHECK(!bool(schema->deserialize_versioned(PackedByteArray(), Dictionary())["ok"]));
}

TEST_CASE("[CgameNetcode] Schema rejects invalid definitions") {
	Ref<CgameNetSchema> schema;
	schema.instantiate();
	Dictionary bad;
	Array fields;
	fields.push_back(CgameNetSchema::make_field("x", "blob", 8));
	bad["fields"] = fields;
	ERR_PRINT_OFF;
	CHECK(!schema->set_schema(bad));
	CHECK(!schema->set_schema(Dictionary()));
	ERR_PRINT_ON;
	CHECK(schema->get_field_count() == 0);
}

TEST_CASE("[CgameNetcode] Schema delta against baseline sends only changed fields") {
	Ref<CgameNetSchema> schema;
	schema.instantiate();
	CHECK(schema->set_schema(_make_schema()));

	Dictionary base;
	base["hp"] = 77;
	base["pos"] = Vector3(10, 20, -30);
	base["rot"] = Quaternion();
	base["alive"] = true;
	base["name"] = "Unit";
	base["ammo"] = 12;
	base["speed"] = 7.5;
	PackedByteArray full = schema->serialize(base, Dictionary(), true);
	Dictionary baseline = schema->deserialize(full, Dictionary());

	Dictionary next = baseline.duplicate();
	next["hp"] = 70;
	PackedByteArray delta = schema->serialize(next, baseline, true);
	CHECK(delta.size() < full.size());
	// 7 mask bits + 8 bits hp + 1 bit "always" alive = 16 bits.
	CHECK(delta.size() == 2);

	Dictionary applied = schema->deserialize(delta, baseline);
	CHECK(int(applied["hp"]) == 70);
	CHECK(Vector3(applied["pos"]) == Vector3(baseline["pos"]));

	// No change: 7 mask bits + the always-sent bool = 8 bits = 1 byte.
	PackedByteArray none = schema->serialize(baseline, baseline, true);
	CHECK(none.size() == 1);
}

TEST_CASE("[CgameNetcode] Replication graph relevance") {
	Ref<CgameReplicationGraph> g;
	g.instantiate();
	g->set_cell_size(32.0);
	g->set_class_config("unit", 1.0, 0.0, 10);
	g->add_entity(1, "unit", Vector3(5, 0, 5));
	g->add_entity(2, "unit", Vector3(500, 0, 500));
	g->add_entity(3, "unit", Vector3(1000, 0, 1000), -1, true);
	g->add_entity(4, "unit", Vector3(900, 0, 900), 7, false, true);
	CHECK(g->get_entity_count() == 4);

	Dictionary conn;
	conn["id"] = 7;
	conn["position"] = Vector3(0, 0, 0);
	conn["view_radius"] = 50.0;
	Array res = g->gather_for(conn);
	HashSet<int64_t> ids;
	for (int i = 0; i < res.size(); i++) {
		ids.insert(int64_t(Dictionary(res[i])["id"]));
	}
	CHECK(ids.has(1));
	CHECK(!ids.has(2));
	CHECK(ids.has(3)); // always relevant
	CHECK(ids.has(4)); // owner-only for this connection

	Dictionary other = conn.duplicate();
	other["id"] = 8;
	Array res2 = g->gather_for(other);
	bool has4 = false;
	for (int i = 0; i < res2.size(); i++) {
		has4 = has4 || int64_t(Dictionary(res2[i])["id"]) == 4;
	}
	CHECK(!has4);

	// Moving an entity across cells keeps the grid consistent.
	g->set_position(2, Vector3(1, 0, 1));
	Dictionary c3 = conn.duplicate();
	c3["id"] = 9;
	CHECK(g->gather_for(c3).size() >= 3);
	g->remove_entity(2);
	CHECK(!g->has_entity(2));
}

TEST_CASE("[CgameNetcode] Replication graph frequency, dormancy and wake") {
	Ref<CgameReplicationGraph> g;
	g.instantiate();
	g->set_class_config("slow", 1.0, 1.0, 10);
	g->add_entity(1, "slow", Vector3());
	Dictionary conn;
	conn["id"] = 1;
	conn["position"] = Vector3();
	CHECK(g->gather_for(conn).size() == 1);
	CHECK(g->gather_for(conn).size() == 0); // within interval
	g->advance(1.5);
	CHECK(g->gather_for(conn).size() == 1);

	g->set_dormant(1, true);
	g->advance(5.0);
	CHECK(g->gather_for(conn).size() == 0);
	g->wake(1);
	Array woken = g->gather_for(conn);
	CHECK(woken.size() == 1);
	CHECK(double(Dictionary(woken[0])["priority"]) >= 1000.0);
	CHECK(g->gather_for(conn).size() == 0);
}

TEST_CASE("[CgameNetcode] Replication graph bandwidth budget and starvation") {
	Ref<CgameReplicationGraph> g;
	g.instantiate();
	g->set_class_config("hi", 10.0, 0.0, 40);
	g->set_class_config("lo", 1.0, 0.0, 40);
	g->add_entity(1, "hi", Vector3());
	g->add_entity(2, "lo", Vector3());
	Dictionary conn;
	conn["id"] = 1;
	conn["position"] = Vector3();
	conn["bandwidth_bytes"] = 40;

	// Budget fits one entity per tick: the high priority one wins first.
	Array first = g->gather_for(conn);
	CHECK(first.size() == 1);
	CHECK(int64_t(Dictionary(first[0])["id"]) == 1);

	// The skipped low priority entity accumulates starvation until it overtakes.
	int64_t low_sent_at = -1;
	for (int tick = 1; tick < 30 && low_sent_at < 0; tick++) {
		Array r = g->gather_for(conn);
		CHECK(r.size() == 1);
		if (int64_t(Dictionary(r[0])["id"]) == 2) {
			low_sent_at = tick;
		}
	}
	CHECK(low_sent_at > 0);
}

TEST_CASE("[CgameNetcode] Replication graph scales to thousands of entities") {
	Ref<CgameReplicationGraph> g;
	g.instantiate();
	g->set_cell_size(64.0);
	g->set_class_config("npc", 1.0, 0.0, 8);
	for (int i = 0; i < 5000; i++) {
		g->add_entity(i, "npc", Vector3((i % 100) * 20.0, 0, (i / 100) * 20.0));
	}
	Dictionary conn;
	conn["id"] = 1;
	conn["position"] = Vector3(1000, 0, 500);
	conn["view_radius"] = 100.0;
	Array res = g->gather_for(conn);
	CHECK(res.size() > 0);
	CHECK(res.size() < 200);
}

TEST_CASE("[CgameNetcode] Snapshot delta round trip") {
	Dictionary base;
	Dictionary e1;
	e1["hp"] = 10;
	e1["pos"] = Vector3(1, 2, 3);
	e1["tag"] = "a";
	Dictionary e2;
	e2["hp"] = 5;
	base[1] = e1;
	base[2] = e2;

	Dictionary cur = base.duplicate(true);
	Dictionary c1 = cur[1];
	c1["hp"] = 9;
	c1.erase("tag");
	Dictionary e3;
	e3["hp"] = 100;
	cur[3] = e3;
	cur.erase(2);

	Dictionary delta = CgameSnapshotDelta::diff(base, cur);
	CHECK(!CgameSnapshotDelta::is_empty(delta));
	CHECK(Dictionary(delta["changed"]).has(1));
	CHECK(Dictionary(delta["added"]).has(3));
	CHECK(PackedInt64Array(delta["removed"]).size() == 1);
	CHECK(delta.has("dropped"));

	Dictionary rebuilt = CgameSnapshotDelta::apply(base, delta);
	CHECK(rebuilt.recursive_equal(cur, 0));
	// Baseline is untouched.
	CHECK(int(Dictionary(base[1])["hp"]) == 10);
	CHECK(Dictionary(base[1]).has("tag"));
}

TEST_CASE("[CgameNetcode] Snapshot delta tolerances and empty delta") {
	Dictionary base;
	Dictionary e;
	e["x"] = 1.0;
	e["pos"] = Vector3(0, 0, 0);
	base[1] = e;
	Dictionary cur = base.duplicate(true);
	Dictionary ce = cur[1];
	ce["x"] = 1.004;
	ce["pos"] = Vector3(0.003, 0, 0);

	Dictionary tol;
	tol["x"] = 0.01;
	tol["pos"] = 0.01;
	CHECK(CgameSnapshotDelta::is_empty(CgameSnapshotDelta::diff(base, cur, tol)));
	CHECK(!CgameSnapshotDelta::is_empty(CgameSnapshotDelta::diff(base, cur)));
}

TEST_CASE("[CgameNetcode] Snapshot retirement preserves surviving order and isolation") {
	Dictionary base;
	Dictionary current;
	for (int id = 0; id < 120; id++) {
		Dictionary entity;
		Array items;
		items.push_back(id);
		entity["items"] = items;
		base[id] = entity;
		if (id % 10 == 0) {
			current[id] = entity.duplicate(true);
		}
	}
	Dictionary added;
	added["hp"] = 50;
	current[500] = added;
	const Dictionary delta = CgameSnapshotDelta::diff(base, current);
	Dictionary rebuilt = CgameSnapshotDelta::apply(base, delta);
	CHECK(rebuilt.recursive_equal(current, 0));
	CHECK(rebuilt.keys() == current.keys());
	Dictionary survivor = rebuilt[0];
	Array items = survivor["items"];
	items.push_back(999);
	CHECK(Array(Dictionary(base[0])["items"]).size() == 1);
	Dictionary new_entity = rebuilt[500];
	new_entity["hp"] = 1;
	CHECK(int(Dictionary(Dictionary(delta["added"])[500])["hp"]) == 50);
}

} // namespace TestCgameNetcode
