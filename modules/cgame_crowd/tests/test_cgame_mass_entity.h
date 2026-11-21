/**************************************************************************/
/*  test_cgame_mass_entity.h                                              */
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

#pragma once

#include "../cgame_mass_entity.h"
#include "core/math/math_funcs.h"
#include "core/object/callable_mp.h"
#include "tests/test_macros.h"

namespace TestCgameMassEntity {

static Vector<String> processor_log;

static void log_a(const Dictionary &p_chunk, int p_count, double p_delta) {
	processor_log.push_back("a");
}

static void log_b(const Dictionary &p_chunk, int p_count, double p_delta) {
	processor_log.push_back("b");
}

static void log_c(const Dictionary &p_chunk, int p_count, double p_delta) {
	processor_log.push_back("c");
}

// A script-style processor that mutates the chunk arrays and relies on write-back.
static void move_script(Dictionary p_chunk, int p_count, double p_delta) {
	PackedVector3Array pos = p_chunk["pos"];
	const PackedVector3Array vel = p_chunk["vel"];
	Vector3 *w = pos.ptrw();
	for (int i = 0; i < p_count; i++) {
		w[i] += vel[i] * (real_t)p_delta;
	}
	p_chunk["pos"] = pos;
}

static Ref<CgameMassEntity> make_world() {
	Ref<CgameMassEntity> w;
	w.instantiate();
	w->define_fragment("pos", Variant::PACKED_VECTOR3_ARRAY);
	w->define_fragment("vel", Variant::PACKED_VECTOR3_ARRAY);
	w->define_fragment("hp", Variant::PACKED_FLOAT32_ARRAY);
	w->define_fragment("tag", Variant::PACKED_INT32_ARRAY);
	return w;
}

static Dictionary frag(const Variant &p_a_key, const Variant &p_a, const Variant &p_b_key = Variant(), const Variant &p_b = Variant()) {
	Dictionary d;
	d[p_a_key] = p_a;
	if (p_b_key.get_type() != Variant::NIL) {
		d[p_b_key] = p_b;
	}
	return d;
}

static PackedStringArray names(const char *p_a, const char *p_b = nullptr, const char *p_c = nullptr) {
	PackedStringArray out;
	out.push_back(p_a);
	if (p_b) {
		out.push_back(p_b);
	}
	if (p_c) {
		out.push_back(p_c);
	}
	return out;
}

TEST_CASE("[CgameMassEntity] lifecycle, generations and swap-remove") {
	Ref<CgameMassEntity> w = make_world();
	const int64_t a = w->create(frag("pos", Vector3(1, 2, 3), "hp", 10.0));
	const int64_t b = w->create(frag("hp", 20.0, "pos", Vector3(4, 5, 6)));
	Dictionary cd;
	cd["pos"] = Vector3();
	cd["vel"] = Vector3(1, 0, 0);
	const int64_t c = w->create(cd);
	CHECK(w->entity_count() == 3);
	CHECK(w->archetype_count() == 2); // Fragment-order independent archetype keys.
	CHECK((w->is_alive(a) && w->is_alive(b) && w->is_alive(c)));
	CHECK(double(w->get_value(b, "hp")) == 20.0);
	CHECK(Vector3(w->get_value(a, "pos")) == Vector3(1, 2, 3));
	w->set_value(a, "hp", 7.5);
	CHECK(double(w->get_value(a, "hp")) == 7.5);
	CHECK(w->get_value(c, "hp").get_type() == Variant::NIL);

	w->destroy(a);
	CHECK_FALSE(w->is_alive(a));
	CHECK(Vector3(w->get_value(b, "pos")) == Vector3(4, 5, 6)); // Swap-remove keeps neighbour data.
	CHECK(w->get_value(a, "hp").get_type() == Variant::NIL);

	Array chunks = w->query(names("hp"));
	REQUIRE(chunks.size() == 1);
	CHECK(int(Dictionary(chunks[0])["_count"]) == 1); // Chunk stays dense.

	const int64_t d = w->create(frag("pos", Vector3(1, 1, 1), "hp", 1.0));
	CHECK(d != a); // Reused slot gets a new generation.
	CHECK_FALSE(w->is_alive(a));
	CHECK(w->is_alive(d));
	w->destroy(a);
	CHECK(w->entity_count() == 3); // Double destroy is a no-op.

	ERR_PRINT_OFF
	CHECK(w->create(frag("nope", 1.0)) == -1); // Undefined fragment.
	CHECK(w->create(frag("hp", Vector3())) == -1); // Wrong value type.
	ERR_PRINT_ON

	CHECK(w->query(names("pos")).size() == 2);
	CHECK(w->query(names("pos", "vel")).size() == 1);
	CHECK(w->query(names("tag")).size() == 0);
}

TEST_CASE("[CgameMassEntity] processors run in dependency order") {
	Ref<CgameMassEntity> w = make_world();
	w->create(frag("pos", Vector3()));
	w->add_processor("c", names("pos"), callable_mp_static(&log_c), names("b"));
	w->add_processor("b", names("pos"), callable_mp_static(&log_b), names("a"));
	w->add_processor("a", names("pos"), callable_mp_static(&log_a));
	const PackedStringArray order = w->processor_order();
	REQUIRE(order.size() == 3);
	CHECK(order[0] == "a");
	CHECK(order[1] == "b");
	CHECK(order[2] == "c");
	processor_log.clear();
	w->run(0.1);
	REQUIRE(processor_log.size() == 3);
	CHECK(processor_log[0] == "a");
	CHECK(processor_log[1] == "b");
	CHECK(processor_log[2] == "c");
	w->remove_processor("b");
	CHECK(w->processor_order().size() == 2);
}

TEST_CASE("[CgameMassEntity] native integrate over 2000 entities and swap-removes") {
	Ref<CgameMassEntity> w = make_world();
	Vector<int64_t> ids;
	for (int i = 0; i < 2000; i++) {
		Dictionary d;
		d["pos"] = Vector3(i, 0, 0);
		d["vel"] = Vector3(1, 0, 2);
		ids.push_back(w->create(d));
	}
	w->add_integrate_processor("move", "pos", "vel");
	for (int s = 0; s < 10; s++) {
		w->run(0.1);
	}
	Vector3 p = w->get_value(ids[1999], "pos");
	CHECK(Math::is_equal_approx(p.x, (real_t)2000.0));
	CHECK(Math::is_equal_approx(p.z, (real_t)2.0));
	for (int i = 0; i < 2000; i += 2) {
		w->destroy(ids[i]);
	}
	CHECK(w->entity_count() == 1000);
	w->run(0.1);
	Vector3 q = w->get_value(ids[1], "pos");
	CHECK(Math::is_equal_approx(q.x, (real_t)(1.0 + 1.1)));
}

TEST_CASE("[CgameMassEntity] script processor writes arrays back") {
	Ref<CgameMassEntity> w = make_world();
	for (int i = 0; i < 50; i++) {
		Dictionary d;
		d["pos"] = Vector3();
		d["vel"] = Vector3(1, 0, 0);
		w->create(d);
		d["hp"] = 1.0;
		w->create(d);
	}
	w->add_processor("move", names("pos", "vel"), callable_mp_static(&move_script), PackedStringArray(), true);
	w->run(1.0);
	int moved = 0;
	const Array chunks = w->query(names("pos"));
	for (int c = 0; c < chunks.size(); c++) {
		const PackedVector3Array pos = Dictionary(chunks[c])["pos"];
		for (int i = 0; i < pos.size(); i++) {
			if (Math::is_equal_approx(pos[i].x, (real_t)1.0)) {
				moved++;
			}
		}
	}
	CHECK(moved == 100);
}

TEST_CASE("[CgameMassEntity] mass create and destroy keeps storage dense and ids valid") {
	Ref<CgameMassEntity> w = make_world();
	Dictionary tmpl;
	tmpl["pos"] = Vector3(1, 2, 3);
	tmpl["hp"] = 5.0;
	const PackedInt64Array first = w->create_many(tmpl, 10000);
	REQUIRE(first.size() == 10000);
	CHECK(w->entity_count() == 10000);
	for (int i = 0; i < first.size(); i += 2) {
		w->destroy(first[i]);
	}
	CHECK(w->entity_count() == 5000);
	const PackedInt64Array second = w->create_many(tmpl, 7000);
	CHECK(w->entity_count() == 12000);
	CHECK(w->archetype_count() == 1);

	// Dense: one chunk whose count equals the entity count; ids list matches.
	const Array chunks = w->query(names("pos", "hp"));
	REQUIRE(chunks.size() == 1);
	CHECK(int(Dictionary(chunks[0])["_count"]) == 12000);
	const PackedInt64Array alive = w->get_entity_ids(names("pos"));
	CHECK(alive.size() == 12000);
	const PackedVector3Array column = w->get_column("pos");
	CHECK(column.size() == 12000);

	HashSet<int64_t> unique;
	bool all_alive = true;
	for (int i = 0; i < alive.size(); i++) {
		unique.insert(alive[i]);
		all_alive = all_alive && w->is_alive(alive[i]);
	}
	CHECK(unique.size() == 12000);
	CHECK(all_alive);
	for (int i = 0; i < first.size(); i += 2) {
		CHECK_FALSE(w->is_alive(first[i])); // Stale ids stay dead after slot reuse.
	}
	for (int i = 1; i < first.size(); i += 2) {
		CHECK(w->is_alive(first[i]));
	}
	for (int i = 0; i < second.size(); i++) {
		CHECK(w->is_alive(second[i]));
	}
	w->clear();
	CHECK(w->entity_count() == 0);
	CHECK_FALSE(w->is_alive(second[0]));
	CHECK(w->query(names("pos")).is_empty());
}

TEST_CASE("[CgameMassEntity] native crowd avoidance processor keeps head-on agents apart") {
	Ref<CgameMassEntity> w = make_world();
	w->define_fragment("pref", Variant::PACKED_VECTOR3_ARRAY);
	const real_t radius = 0.5;
	Dictionary da;
	da["pos"] = Vector3(-5, 0, 0.2);
	da["vel"] = Vector3();
	da["pref"] = Vector3();
	Dictionary db;
	db["pos"] = Vector3(5, 0, -0.2);
	db["vel"] = Vector3();
	db["pref"] = Vector3();
	const int64_t a = w->create(da);
	const int64_t b = w->create(db);
	const Vector3 goal_a(5, 0, 0.2);
	const Vector3 goal_b(-5, 0, -0.2);
	w->add_crowd_avoidance_processor("avoid", "pos", "vel", "pref", radius, 1.5, 3.0, 10.0, 10);
	w->add_integrate_processor("move", "pos", "vel", names("avoid"));
	CHECK(w->processor_order()[0] == "avoid");
	real_t min_d = 1000.0;
	for (int s = 0; s < 200; s++) {
		const Vector3 pa = w->get_value(a, "pos");
		const Vector3 pb = w->get_value(b, "pos");
		w->set_value(a, "pref", (goal_a - pa).limit_length(1.5));
		w->set_value(b, "pref", (goal_b - pb).limit_length(1.5));
		w->run(0.1);
		min_d = MIN(min_d, Vector3(w->get_value(a, "pos")).distance_to(w->get_value(b, "pos")));
	}
	CHECK(min_d >= 2.0 * radius * 0.95);
	CHECK(Vector3(w->get_value(a, "pos")).distance_to(goal_a) < 1.0);
	CHECK(Vector3(w->get_value(b, "pos")).distance_to(goal_b) < 1.0);
	CHECK(Math::is_zero_approx(Vector3(w->get_value(a, "vel")).y)); // Ground plane only.
}

} // namespace TestCgameMassEntity
