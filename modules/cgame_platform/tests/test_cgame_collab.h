/**************************************************************************/
/*  test_cgame_collab.h                                                   */
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

#include "../cgame_asset_conflicts.h"
#include "../cgame_scene_crdt.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "tests/signal_watcher.h"
#include "tests/test_macros.h"
#include "tests/test_utils.h"

#include <initializer_list>
#include <utility>

namespace TestCgameCollab {

typedef std::initializer_list<std::pair<const char *, Variant>> Pairs;

static Dictionary D(const Pairs &p_pairs) {
	Dictionary d;
	for (const std::pair<const char *, Variant> &kv : p_pairs) {
		d[String(kv.first)] = kv.second;
	}
	return d;
}

static Array strs(std::initializer_list<const char *> p_values) {
	Array a;
	for (const char *s : p_values) {
		a.push_back(String(s));
	}
	return a;
}

static Dictionary node_args(const String &p_id, const String &p_parent, const String &p_type, const Dictionary &p_props, int p_index = -1) {
	Dictionary d;
	d["id"] = p_id;
	if (!p_parent.is_empty()) {
		d["parent"] = p_parent;
	}
	d["type"] = p_type;
	d["props"] = p_props;
	if (p_index >= 0) {
		d["index"] = p_index;
	}
	return d;
}

static Dictionary named(const char *p_name) {
	return D({ { "name", p_name } });
}

static Dictionary set_args(const String &p_id, const String &p_prop, const Variant &p_value) {
	return D({ { "id", p_id }, { "prop", p_prop }, { "value", p_value } });
}

static Dictionary move_args(const String &p_id, const String &p_parent, int p_index) {
	return D({ { "id", p_id }, { "parent", p_parent }, { "index", p_index } });
}

static Dictionary id_args(const String &p_id) {
	return D({ { "id", p_id } });
}

static Ref<CgameSceneCRDT> make_doc(const String &p_replica) {
	Ref<CgameSceneCRDT> d;
	d.instantiate();
	d->set_replica(p_replica);
	return d;
}

static void sync(const Ref<CgameSceneCRDT> &p_a, const Ref<CgameSceneCRDT> &p_b) {
	p_b->merge_ops(p_a->ops_since(p_b->state_vector()));
	p_a->merge_ops(p_b->ops_since(p_a->state_vector()));
}

static String canon(const Ref<CgameSceneCRDT> &p_doc) {
	return JSON::stringify(p_doc->to_scene_dict(), "", true);
}

static Ref<CgameSceneCRDT> apply_all(const String &p_replica, const Array &p_ops) {
	Ref<CgameSceneCRDT> d = make_doc(p_replica);
	for (int i = 0; i < p_ops.size(); i++) {
		d->apply(p_ops[i]);
	}
	return d;
}

static Dictionary sub(Dictionary &r_dict, const char *p_key) {
	return r_dict[p_key];
}

TEST_CASE("[CgameSceneCRDT] Basics and scene dict") {
	Ref<CgameSceneCRDT> a = make_doc("A");
	a->local_op("add_node", node_args("root", "", "Node3D", named("Root")));
	a->local_op("add_node", node_args("p", "root", "Node3D", D({ { "name", "P" }, { "x", 1 } })));
	a->local_op("add_node", node_args("q", "root", "Node3D", named("Q")));
	a->local_op("add_node", node_args("first", "root", "Node", named("First"), 0));
	CHECK(a->children_of("root") == strs({ "first", "p", "q" }));
	CHECK((int)a->get_prop("p", "x") == 1);
	a->local_op("move_node", move_args("q", "root", 0));
	CHECK(a->children_of("root") == strs({ "q", "first", "p" }));

	const Dictionary sd = a->to_scene_dict();
	CHECK(String(sd["name"]) == "Root");
	CHECK(Array(sd["children"]).size() == 3);
	Ref<CgameSceneCRDT> clone = CgameSceneCRDT::from_packed_scene_dict(sd, "Z");
	CHECK(canon(clone) == canon(a));
	CHECK_FALSE(a->apply(Dictionary(a->ops_since(Dictionary())[0])));
}

TEST_CASE("[CgameSceneCRDT] Idempotency") {
	Ref<CgameSceneCRDT> a = make_doc("A");
	a->local_op("add_node", node_args("root", "", "Node", named("Root")));
	a->local_op("add_node", node_args("k", "root", "Node", named("K")));
	a->local_op("set_prop", set_args("k", "v", 3));
	const Array ops = a->ops_since(Dictionary());
	Ref<CgameSceneCRDT> d1 = apply_all("X", ops);
	const String before = canon(d1);
	for (int i = 0; i < ops.size(); i++) {
		CHECK_FALSE(d1->apply(ops[i]));
	}
	CHECK(canon(d1) == before);
	CHECK(d1->state_vector() == a->state_vector());
}

TEST_CASE("[CgameSceneCRDT] Three replicas converge in three delivery orders") {
	Ref<CgameSceneCRDT> r1 = make_doc("A");
	r1->local_op("add_node", node_args("root", "", "Node", named("Root")));
	r1->local_op("add_node", node_args("a", "root", "Node", D({ { "name", "A" }, { "v", 0 } })));
	r1->local_op("add_node", node_args("b", "root", "Node", named("B")));
	r1->local_op("add_node", node_args("x", "root", "Node", named("X")));
	Ref<CgameSceneCRDT> r2 = make_doc("B");
	Ref<CgameSceneCRDT> r3 = make_doc("C");
	sync(r1, r2);
	sync(r1, r3);
	const int base_count = r1->ops_since(Dictionary()).size();

	// Concurrent edits.
	r1->local_op("set_prop", set_args("a", "v", 11));
	r1->local_op("move_node", move_args("b", "a", 0));
	r1->local_op("add_node", node_args("n1", "root", "Node", named("N1")));
	r2->local_op("set_prop", set_args("a", "v", 22));
	r2->local_op("move_node", move_args("b", "root", 0));
	r2->local_op("add_node", node_args("n2", "root", "Node", named("N2")));
	r2->local_op("remove_node", id_args("x"));
	r3->local_op("set_prop", set_args("x", "v", 5));
	r3->local_op("remove_node", id_args("a"));
	r3->local_op("add_node", node_args("n3", "root", "Node", named("N3")));

	Array all;
	all.append_array(r1->ops_since(Dictionary()));
	all.append_array(r2->ops_since(Dictionary()));
	all.append_array(r3->ops_since(Dictionary()));
	CHECK(all.size() > base_count);

	Ref<CgameSceneCRDT> fwd = apply_all("D", all);
	Array rev_ops = all.duplicate();
	rev_ops.reverse();
	Ref<CgameSceneCRDT> rev = apply_all("E", rev_ops);
	Array rot_ops = all.slice(5);
	rot_ops.append_array(all.slice(0, 5));
	Ref<CgameSceneCRDT> rot = apply_all("F", rot_ops);

	CHECK(canon(rev) == canon(fwd));
	CHECK(canon(rot) == canon(fwd));
	CHECK(fwd->children_of("root") == rev->children_of("root"));
	CHECK_FALSE(fwd->has_node("x")); // Remove wins over a concurrent set_prop (node hidden).
	CHECK((int)fwd->get_prop("x", "v") == 5); // The register still holds the concurrent value.
	CHECK_FALSE(fwd->has_node("a")); // The remove observed the tag of the add.
	CHECK(fwd->has_node("n1"));
	CHECK(fwd->has_node("n2"));
	CHECK(fwd->has_node("n3"));
	CHECK(fwd->parent_of("b") == "root"); // Concurrent move: higher (lamport, replica) wins.

	sync(r1, r2);
	sync(r2, r3);
	sync(r1, r3);
	CHECK(canon(r1) == canon(r2));
	CHECK(canon(r2) == canon(r3));
	CHECK(canon(r3) == canon(fwd));
}

TEST_CASE("[CgameSceneCRDT] LWW registers and add-wins set") {
	Ref<CgameSceneCRDT> l1 = make_doc("A");
	l1->local_op("add_node", node_args("n", "", "Node", named("N")));
	Ref<CgameSceneCRDT> l2 = make_doc("Z");
	sync(l1, l2);
	l1->local_op("set_prop", set_args("n", "k", "from_a"));
	l2->local_op("set_prop", set_args("n", "k", "from_z"));
	sync(l1, l2);
	CHECK(String(l1->get_prop("n", "k")) == "from_z"); // Equal lamport: larger replica id wins.
	CHECK(String(l2->get_prop("n", "k")) == "from_z");
	l1->local_op("set_prop", set_args("n", "k", "later"));
	sync(l1, l2);
	CHECK(String(l2->get_prop("n", "k")) == "later"); // Causally later write wins.

	// Add-wins: A removes while Z re-adds concurrently.
	l1->local_op("remove_node", id_args("n"));
	l2->local_op("add_node", node_args("n", "", "Node", named("N")));
	sync(l1, l2);
	CHECK(l1->has_node("n"));
	CHECK(l2->has_node("n"));
	l1->local_op("remove_node", id_args("n"));
	sync(l1, l2);
	CHECK_FALSE(l1->has_node("n"));
	CHECK_FALSE(l2->has_node("n"));

	SIGNAL_WATCH(l1.ptr(), "op_generated");
	const Dictionary generated = l1->local_op("set_prop", set_args("n", "k", 1));
	Array expected_args;
	expected_args.push_back(generated);
	Array expected;
	expected.push_back(expected_args);
	SIGNAL_CHECK("op_generated", expected);
	SIGNAL_UNWATCH(l1.ptr(), "op_generated");
}

TEST_CASE("[CgameSceneCRDT] Concurrent sibling inserts converge") {
	Ref<CgameSceneCRDT> s1 = make_doc("A");
	s1->local_op("add_node", node_args("root", "", "Node", Dictionary()));
	s1->local_op("add_node", node_args("k1", "root", "Node", Dictionary()));
	Ref<CgameSceneCRDT> s2 = make_doc("B");
	sync(s1, s2);
	s1->local_op("add_node", node_args("ka", "root", "Node", Dictionary(), 1));
	s2->local_op("add_node", node_args("kb", "root", "Node", Dictionary(), 1));
	sync(s1, s2);
	CHECK(s1->children_of("root") == s2->children_of("root"));
	CHECK(s1->children_of("root").size() == 3);
	CHECK(String(s1->children_of("root")[0]) == "k1");
}

TEST_CASE("[CgameSceneCRDT] State vectors and gap handling") {
	Ref<CgameSceneCRDT> v1 = make_doc("A");
	v1->local_op("add_node", node_args("root", "", "Node", Dictionary()));
	v1->local_op("set_prop", set_args("root", "p", 1));
	Ref<CgameSceneCRDT> v2 = make_doc("B");
	sync(v1, v2);
	CHECK((int)v2->state_vector().get("A", 0) == 2);
	v1->local_op("set_prop", set_args("root", "p", 2));
	v1->local_op("set_prop", set_args("root", "q", 3));
	CHECK(v1->ops_since(v2->state_vector()).size() == 2);

	// A gap must not advance the contiguous vector.
	Ref<CgameSceneCRDT> gap = make_doc("G");
	const Array all_v1 = v1->ops_since(Dictionary());
	gap->apply(all_v1[3]);
	CHECK((int)gap->state_vector().get("A", 0) == 0);
	CHECK(gap->merge_ops(all_v1) == 3);
	CHECK((int)gap->state_vector().get("A", 0) == 4);
	CHECK((int)gap->get_prop("root", "q") == 3);
}

TEST_CASE("[CgameSceneCRDT] Presence") {
	Ref<CgameSceneCRDT> pa = make_doc("alice");
	Ref<CgameSceneCRDT> pb = make_doc("bob");
	const Dictionary m1 = pa->local_presence(Vector2(1, 2), strs({ "n1" }), 1000);
	const Dictionary m2 = pa->local_presence(Vector2(3, 4), strs({ "n2" }), 2000);
	pb->apply_presence(m2);
	CHECK_FALSE(pb->apply_presence(m1)); // Stale presence is ignored.
	Dictionary alice = Dictionary(pb->presence())["alice"];
	CHECK(Vector2(alice["cursor"]) == Vector2(3, 4));
	CHECK(Array(alice["selection"]) == strs({ "n2" }));
	pb->local_presence(Vector2(), Array(), 5000);
	CHECK(pb->presence().size() == 2);
	const Array gone = pb->expire_presence(6000, 3000);
	CHECK(gone == strs({ "alice" }));
	pb->remove_presence("bob");
	CHECK(pb->presence().size() == 0);
}

TEST_CASE("[CgameAssetConflicts] Asset scan hashes files with SHA-256") {
	const String dir = TestUtils::get_temp_path("cgame_collab_scan");
	DirAccess::make_dir_recursive_absolute(dir + "/sub");
	{
		Ref<FileAccess> f = FileAccess::open(dir + "/a.txt", FileAccess::WRITE);
		f->store_string("abc");
	}
	{
		Ref<FileAccess> f = FileAccess::open(dir + "/sub/b.bin", FileAccess::WRITE);
		const uint8_t bytes[5] = { 1, 2, 3, 4, 5 };
		f->store_buffer(bytes, 5);
	}
	const Dictionary scan1 = CgameAssetConflicts::scan(dir);
	CHECK(scan1.size() == 2);
	CHECK(String(Dictionary(scan1[dir + "/a.txt"])["sha256"]) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
	CHECK((int)Dictionary(scan1[dir + "/sub/b.bin"])["size"] == 5);
	{
		Ref<FileAccess> f = FileAccess::open(dir + "/a.txt", FileAccess::WRITE);
		f->store_string("abd");
	}
	const Dictionary scan2 = CgameAssetConflicts::scan(dir);
	const Array changed = CgameAssetConflicts::changed_paths(scan1, scan2);
	CHECK(changed.size() == 1);
	CHECK(String(changed[0]) == dir + "/a.txt");
	DirAccess::remove_absolute(dir + "/a.txt");
	DirAccess::remove_absolute(dir + "/sub/b.bin");
	DirAccess::remove_absolute(dir + "/sub");
	DirAccess::remove_absolute(dir);
	CHECK_FALSE(DirAccess::dir_exists_absolute(dir));
}

TEST_CASE("[CgameAssetConflicts] Three-way merge") {
	Dictionary base = D({
			{ "Root", D({ { "_type", "Node3D" }, { "visible", "true" } }) },
			{ "Root/Light", D({ { "_type", "Light3D" }, { "energy", "1.0" }, { "color", "white" } }) },
			{ "Root/Old", D({ { "_type", "Node" }, { "k", "1" } }) },
			{ "Root/Gone", D({ { "_type", "Node" }, { "k", "1" } }) },
	});
	Dictionary mine = base.duplicate(true);
	Dictionary theirs = base.duplicate(true);
	sub(mine, "Root/Light")["energy"] = "2.0";
	sub(theirs, "Root/Light")["color"] = "red";
	mine["Root/Mine"] = D({ { "_type", "Node" }, { "z", "1" } });
	theirs["Root/Theirs"] = D({ { "_type", "Node" } });
	CHECK(CgameAssetConflicts::three_way(base, mine, theirs).size() == 0);

	const Dictionary res = CgameAssetConflicts::merge_scene(base, mine, theirs);
	const Dictionary merged = res["merged"];
	CHECK(String(Dictionary(merged["Root/Light"])["energy"]) == "2.0");
	CHECK(String(Dictionary(merged["Root/Light"])["color"]) == "red");
	CHECK(merged.has("Root/Mine"));
	CHECK(merged.has("Root/Theirs"));

	sub(mine, "Root/Gone").erase("k");
	mine.erase("Root/Old");
	theirs.erase("Root/Gone");
	sub(theirs, "Root/Light")["energy"] = "3.0";
	sub(theirs, "Root/Old")["k"] = "2";
	const Array conf = CgameAssetConflicts::three_way(base, mine, theirs);
	HashMap<String, Dictionary> kinds;
	for (int i = 0; i < conf.size(); i++) {
		const Dictionary cd = conf[i];
		kinds[String(cd["kind"]) + "|" + String(cd["node"])] = cd;
	}
	REQUIRE(kinds.has("property|Root/Light"));
	CHECK(String(kinds["property|Root/Light"]["prop"]) == "energy");
	CHECK(String(kinds["property|Root/Light"]["theirs"]) == "3.0");
	CHECK(kinds.has("delete_edit|Root/Old"));
	CHECK(kinds.has("delete_edit|Root/Gone"));
	CHECK(CgameAssetConflicts::three_way(base, base, theirs).size() == 0); // Delete versus untouched is clean.

	// Delete versus untouched is clean.
	Dictionary only_delete_base = D({ { "N", D({ { "_type", "Node" }, { "k", "1" } }) } });
	Dictionary only_delete_theirs;
	CHECK(CgameAssetConflicts::three_way(only_delete_base, only_delete_base, only_delete_theirs).size() == 0);

	// Identical edits on both sides agree.
	sub(mine, "Root/Light")["energy"] = "3.0";
	int light_conflicts = 0;
	const Array again = CgameAssetConflicts::three_way(base, mine, theirs);
	for (int i = 0; i < again.size(); i++) {
		if (String(Dictionary(again[i])["node"]) == "Root/Light") {
			light_conflicts++;
		}
	}
	CHECK(light_conflicts == 0);

	const Dictionary parsed = CgameAssetConflicts::parse_tscn("[gd_scene]\n[node name=\"Root\" type=\"Node3D\"]\nvisible = true\n[node name=\"L\" type=\"Light3D\" parent=\".\"]\nenergy = 2.0\n");
	CHECK(String(Dictionary(parsed["Root/L"])["energy"]) == "2.0");
	CHECK(String(Dictionary(parsed["Root"])["_type"]) == "Node3D");

	Ref<CgameSceneCRDT> doc = make_doc("A");
	doc->local_op("add_node", node_args("root", "", "Node3D", named("Root")));
	doc->local_op("add_node", node_args("p", "root", "Node3D", D({ { "name", "P" }, { "x", 1 } })));
	const Dictionary flat = CgameAssetConflicts::flatten_scene_dict(doc->to_scene_dict());
	CHECK(flat.has("Root/P"));
	CHECK((int)Dictionary(flat["Root/P"])["x"] == 1);
}

TEST_CASE("[CgameAssetConflicts] Binary conflicts") {
	auto entry = [](const char *p_hash) {
		return D({ { "sha256", p_hash }, { "size", 1 } });
	};
	Dictionary bb = D({ { "a.png", entry("h1") }, { "b.png", entry("h2") }, { "c.png", entry("h3") } });
	Dictionary bm = bb.duplicate(true);
	Dictionary bt = bb.duplicate(true);
	bm["a.png"] = entry("m");
	bt["a.png"] = entry("t");
	bm["b.png"] = entry("only_mine");
	bt["c.png"] = entry("same");
	bm["c.png"] = entry("same");
	const Array bc = CgameAssetConflicts::three_way_binary(bb, bm, bt);
	REQUIRE(bc.size() == 1);
	CHECK(String(Dictionary(bc[0])["path"]) == "a.png");
	CHECK(String(Dictionary(bc[0])["kind"]) == "binary");
}

TEST_CASE("[CgameAssetConflicts] Exclusive locks with expiry") {
	Ref<CgameAssetConflicts> lt;
	lt.instantiate();
	CHECK(lt->lock("res://a.tscn", "alice", 60.0, 100.0));
	CHECK_FALSE(lt->lock("res://a.tscn", "bob", 60.0, 120.0));
	CHECK(lt->owner("res://a.tscn", 120.0) == "alice");
	CHECK(lt->lock("res://a.tscn", "alice", 60.0, 130.0)); // The owner can refresh.
	CHECK(lt->owner("res://a.tscn", 170.0) == "alice");
	CHECK_FALSE(lt->can_edit("res://a.tscn", "bob", 170.0));
	CHECK_FALSE(lt->unlock("res://a.tscn", "bob"));
	CHECK(lt->owner("res://a.tscn", 191.0) == "");
	CHECK(lt->lock("res://a.tscn", "bob", 60.0, 191.0));
	CHECK(lt->unlock("res://a.tscn", "bob"));
	CHECK(lt->owner("res://a.tscn", 192.0) == "");
	lt->lock("res://b.tscn", "alice", 60.0, 0.0);
	CHECK(lt->unlock("res://b.tscn", "admin", true));
	CHECK(lt->active_locks(0.0).size() == 0);
}

TEST_CASE("[CgameAssetConflicts] Override conflicts") {
	Dictionary ov = D({
			{ "Root/Light", D({ { "energy", 5.0 }, { "color", "blue" } }) },
			{ "Root/Removed", D({ { "k", 1 } }) },
			{ "Root/Other", D({ { "k", 2 } }) },
	});
	Dictionary bch = D({
			{ "Root/Light", D({ { "props", D({ { "energy", 3.0 }, { "color", "blue" }, { "shadow", true } }) } }) },
			{ "Root/Removed", D({ { "removed", true } }) },
	});
	const Array oc = CgameAssetConflicts::override_conflicts(ov, bch);
	REQUIRE(oc.size() == 2);
	HashMap<String, Dictionary> kinds;
	for (int i = 0; i < oc.size(); i++) {
		const Dictionary cd = oc[i];
		kinds[String(cd["kind"])] = cd;
	}
	CHECK(String(kinds["override_vs_base"]["prop"]) == "energy");
	CHECK((double)kinds["override_vs_base"]["base_new"] == 3.0);
	CHECK(String(kinds["orphaned_override"]["node"]) == "Root/Removed");
}

} // namespace TestCgameCollab
