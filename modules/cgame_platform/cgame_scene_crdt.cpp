/**************************************************************************/
/*  cgame_scene_crdt.cpp                                                  */
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

#include "cgame_scene_crdt.h"

#include "core/object/class_db.h"
#include "core/templates/sort_array.h"

namespace {

struct ElemDescending {
	// Set by the caller; the comparator is intentionally default-constructible for SortArray.
	const void *elems = nullptr;
	bool (*less)(const void *, const String &, const String &) = nullptr;

	bool operator()(const String &p_a, const String &p_b) const {
		return less(elems, p_a, p_b);
	}
};

} // namespace

bool CgameSceneCRDT::_newer(int64_t p_l1, const String &p_r1, int64_t p_l2, const String &p_r2) {
	// True when (l1, r1) is strictly greater than (l2, r2).
	if (p_l1 != p_l2) {
		return p_l1 > p_l2;
	}
	return p_r2 < p_r1;
}

String CgameSceneCRDT::_elem_id(int64_t p_l, const String &p_r) {
	return itos(p_l) + "@" + p_r;
}

// ---------------------------------------------------------------- apply

bool CgameSceneCRDT::apply(const Dictionary &p_op) {
	const String r = p_op.get("r", "");
	const int64_t seq = p_op.get("seq", 0);
	const int64_t l = p_op.get("l", 0);
	const String oid = r + ":" + itos(seq);
	if (log.has(oid)) {
		return false;
	}
	const Dictionary op = p_op.duplicate(true);
	log.insert(oid, op);
	log_order.push_back(op);
	if (!seen.has(r)) {
		seen.insert(r, HashSet<int64_t>());
		contig.insert(r, 0);
	}
	HashSet<int64_t> &sn = seen[r];
	sn.insert(seq);
	int64_t c = contig[r];
	while (sn.has(c + 1)) {
		c++;
	}
	contig[r] = c;
	clock = MAX(clock, l);

	const String kind = op.get("kind", "");
	const String nid = op.get("id", "");
	if (kind == "add_node") {
		const String tag = _elem_id(l, r);
		Vector<String> &tg = tags[nid];
		if (!tg.has(tag)) {
			tg.push_back(tag);
		}
		_place(tag, nid, op.get("parent", ""), op.get("after", ""), l, r);
		const Dictionary pr = op.get("props", Dictionary());
		for (const Variant &key : pr.keys()) {
			_set_reg(nid, String(key), pr[key], l, r);
		}
		_set_reg(nid, "_type", op.get("type", "Node"), l, r);
	} else if (kind == "remove_node") {
		const Array rtags = op.get("tags", Array());
		for (int i = 0; i < rtags.size(); i++) {
			tombstones.insert(String(rtags[i]));
		}
	} else if (kind == "set_prop") {
		_set_reg(nid, op.get("prop", ""), op.get("value", Variant()), l, r);
	} else if (kind == "move_node") {
		_place(_elem_id(l, r), nid, op.get("parent", ""), op.get("after", ""), l, r);
	}
	return true;
}

void CgameSceneCRDT::_set_reg(const String &p_node, const String &p_prop, const Variant &p_value, int64_t p_l, const String &p_r) {
	HashMap<String, Reg> &regs = props[p_node];
	HashMap<String, Reg>::Iterator it = regs.find(p_prop);
	Reg reg;
	reg.value = p_value;
	reg.l = p_l;
	reg.r = p_r;
	if (it != regs.end()) {
		if (!_newer(p_l, p_r, it->value.l, it->value.r)) {
			return;
		}
		it->value = reg;
		return;
	}
	regs.insert(p_prop, reg);
}

void CgameSceneCRDT::_place(const String &p_elem, const String &p_node, const String &p_parent, const String &p_after, int64_t p_l, const String &p_r) {
	if (elems.has(p_elem)) {
		return;
	}
	Elem e;
	e.node = p_node;
	e.parent = p_parent;
	e.after = p_after;
	e.l = p_l;
	e.r = p_r;
	elems.insert(p_elem, e);
	by_parent[p_parent].push_back(p_elem);
	HashMap<String, String>::Iterator it = best.find(p_node);
	if (it != best.end()) {
		const Elem &cur = elems[it->value];
		if (!_newer(p_l, p_r, cur.l, cur.r)) {
			return;
		}
		it->value = p_elem;
		return;
	}
	best.insert(p_node, p_elem);
}

// ---------------------------------------------------------------- local ops

Dictionary CgameSceneCRDT::local_op(const String &p_kind, const Dictionary &p_args) {
	clock++;
	seq_counter++;
	Dictionary op;
	op["kind"] = p_kind;
	op["r"] = replica;
	op["seq"] = seq_counter;
	op["l"] = clock;

	const String nid = p_args.get("id", "");
	op["id"] = nid;
	if (p_kind == "add_node") {
		const String parent = p_args.get("parent", "");
		op["parent"] = parent;
		op["after"] = _after_for(parent, p_args.get("index", -1), "");
		op["type"] = p_args.get("type", "Node");
		const Dictionary pr = p_args.get("props", Dictionary());
		op["props"] = pr.duplicate(true);
	} else if (p_kind == "remove_node") {
		Array live;
		HashMap<String, Vector<String>>::ConstIterator it = tags.find(nid);
		if (it != tags.end()) {
			for (const String &tag : it->value) {
				if (!tombstones.has(tag)) {
					live.push_back(tag);
				}
			}
		}
		op["tags"] = live;
	} else if (p_kind == "set_prop") {
		op["prop"] = p_args.get("prop", "");
		op["value"] = p_args.get("value", Variant());
	} else if (p_kind == "move_node") {
		const String np = p_args.get("parent", "");
		op["parent"] = np;
		op["after"] = _after_for(np, p_args.get("index", -1), nid);
	}
	apply(op);
	emit_signal(SNAME("op_generated"), op);
	return op;
}

String CgameSceneCRDT::_after_for(const String &p_parent, int p_index, const String &p_skip_id) const {
	Vector<String> kids;
	for (const String &k : _children(p_parent)) {
		if (k != p_skip_id) {
			kids.push_back(k);
		}
	}
	if (kids.is_empty() || p_index == 0) {
		return "";
	}
	const int i = (p_index < 0 || p_index > kids.size()) ? kids.size() : p_index;
	HashMap<String, String>::ConstIterator it = best.find(kids[i - 1]);
	return it == best.end() ? String() : it->value;
}

// ---------------------------------------------------------------- queries

bool CgameSceneCRDT::has_node(const String &p_node) const {
	HashMap<String, Vector<String>>::ConstIterator it = tags.find(p_node);
	if (it == tags.end()) {
		return false;
	}
	for (const String &tag : it->value) {
		if (!tombstones.has(tag)) {
			return true;
		}
	}
	return false;
}

Variant CgameSceneCRDT::get_prop(const String &p_node, const String &p_prop, const Variant &p_default) const {
	HashMap<String, HashMap<String, Reg>>::ConstIterator it = props.find(p_node);
	if (it == props.end()) {
		return p_default;
	}
	HashMap<String, Reg>::ConstIterator rit = it->value.find(p_prop);
	if (rit == it->value.end()) {
		return p_default;
	}
	return rit->value.value;
}

String CgameSceneCRDT::parent_of(const String &p_node) const {
	HashMap<String, String>::ConstIterator it = best.find(p_node);
	if (it == best.end()) {
		return "";
	}
	return elems[it->value].parent;
}

Vector<String> CgameSceneCRDT::_children(const String &p_parent) const {
	Vector<String> out;
	HashMap<String, Vector<String>>::ConstIterator bp_it = by_parent.find(p_parent);
	if (bp_it == by_parent.end() || bp_it->value.is_empty()) {
		return out;
	}
	const Vector<String> &bp = bp_it->value;
	HashSet<String> members;
	for (const String &eid : bp) {
		members.insert(eid);
	}
	HashMap<String, Vector<String>> groups;
	for (const String &eid : bp) {
		String ref = elems[eid].after;
		if (!ref.is_empty() && !members.has(ref)) {
			ref = "";
		}
		groups[ref].push_back(eid);
	}

	struct Ctx {
		const HashMap<String, Elem> *elems;
	} ctx = { &elems };
	ElemDescending cmp;
	cmp.elems = &ctx;
	cmp.less = [](const void *p_ctx, const String &p_a, const String &p_b) -> bool {
		const Ctx *c = static_cast<const Ctx *>(p_ctx);
		const Elem &ea = (*c->elems)[p_a];
		const Elem &eb = (*c->elems)[p_b];
		return _newer(ea.l, ea.r, eb.l, eb.r);
	};
	SortArray<String, ElemDescending> sorter;
	sorter.compare = cmp;
	for (KeyValue<String, Vector<String>> &kv : groups) {
		if (kv.value.size() > 1) {
			sorter.sort(kv.value.ptrw(), kv.value.size());
		}
	}

	Vector<String> stack;
	HashMap<String, Vector<String>>::Iterator top = groups.find("");
	if (top != groups.end()) {
		for (int i = top->value.size() - 1; i >= 0; i--) {
			stack.push_back(top->value[i]);
		}
	}
	HashSet<String> emitted;
	while (!stack.is_empty()) {
		const String eid = stack[stack.size() - 1];
		stack.resize(stack.size() - 1);
		const Elem &e = elems[eid];
		HashMap<String, String>::ConstIterator b = best.find(e.node);
		if (b != best.end() && b->value == eid && has_node(e.node) && !emitted.has(e.node)) {
			emitted.insert(e.node);
			out.push_back(e.node);
		}
		HashMap<String, Vector<String>>::Iterator sub = groups.find(eid);
		if (sub != groups.end()) {
			for (int i = sub->value.size() - 1; i >= 0; i--) {
				stack.push_back(sub->value[i]);
			}
		}
	}
	return out;
}

Array CgameSceneCRDT::children_of(const String &p_parent) const {
	Array out;
	for (const String &s : _children(p_parent)) {
		out.push_back(s);
	}
	return out;
}

Array CgameSceneCRDT::all_node_ids() const {
	Array out;
	HashSet<String> visited;
	Vector<String> stack;
	const Vector<String> roots = _children("");
	for (int i = roots.size() - 1; i >= 0; i--) {
		stack.push_back(roots[i]);
	}
	while (!stack.is_empty()) {
		const String nid = stack[stack.size() - 1];
		stack.resize(stack.size() - 1);
		if (visited.has(nid)) {
			continue;
		}
		visited.insert(nid);
		out.push_back(nid);
		const Vector<String> kids = _children(nid);
		for (int i = kids.size() - 1; i >= 0; i--) {
			stack.push_back(kids[i]);
		}
	}
	return out;
}

// ---------------------------------------------------------------- sync

Dictionary CgameSceneCRDT::state_vector() const {
	Dictionary d;
	for (const KeyValue<String, int64_t> &kv : contig) {
		d[kv.key] = kv.value;
	}
	return d;
}

Array CgameSceneCRDT::ops_since(const Dictionary &p_vector) const {
	Array out;
	for (const Dictionary &op : log_order) {
		const int64_t seq = op.get("seq", 0);
		const int64_t known = p_vector.get(op.get("r", ""), 0);
		if (seq > known) {
			out.push_back(op);
		}
	}
	return out;
}

int CgameSceneCRDT::merge_ops(const Array &p_ops) {
	int n = 0;
	for (int i = 0; i < p_ops.size(); i++) {
		if (apply(p_ops[i])) {
			n++;
		}
	}
	return n;
}

// ---------------------------------------------------------------- scene dict

Dictionary CgameSceneCRDT::to_scene_dict() const {
	const Vector<String> roots = _children("");
	if (roots.is_empty()) {
		return Dictionary();
	}
	HashSet<String> visiting;
	return _node_dict(roots[0], visiting);
}

Dictionary CgameSceneCRDT::_node_dict(const String &p_node, HashSet<String> &r_visiting) const {
	r_visiting.insert(p_node);
	Dictionary pr;
	HashMap<String, HashMap<String, Reg>>::ConstIterator it = props.find(p_node);
	if (it != props.end()) {
		for (const KeyValue<String, Reg> &kv : it->value) {
			if (kv.key == "_type" || kv.key == "name") {
				continue;
			}
			pr[kv.key] = kv.value.value;
		}
	}
	Array kids;
	for (const String &k : _children(p_node)) {
		if (!r_visiting.has(k)) {
			kids.push_back(_node_dict(k, r_visiting));
		}
	}
	Dictionary d;
	d["id"] = p_node;
	d["type"] = get_prop(p_node, "_type", "Node");
	d["name"] = get_prop(p_node, "name", p_node);
	d["props"] = pr;
	d["children"] = kids;
	return d;
}

void CgameSceneCRDT::load_scene_dict(const Dictionary &p_dict) {
	_load_node(p_dict, "", "");
}

void CgameSceneCRDT::_load_node(const Dictionary &p_dict, const String &p_parent, const String &p_path) {
	const String nm = p_dict.get("name", "Node");
	String nid;
	if (p_dict.has("id")) {
		nid = p_dict["id"];
	} else {
		nid = p_path.is_empty() ? nm : p_path + "/" + nm;
	}
	const Dictionary src_props = p_dict.get("props", Dictionary());
	Dictionary pr = src_props.duplicate(true);
	pr["name"] = nm;
	Dictionary args;
	args["id"] = nid;
	args["parent"] = p_parent;
	args["type"] = p_dict.get("type", "Node");
	args["props"] = pr;
	local_op("add_node", args);
	const Array kids = p_dict.get("children", Array());
	for (int i = 0; i < kids.size(); i++) {
		_load_node(kids[i], nid, nid);
	}
}

Ref<CgameSceneCRDT> CgameSceneCRDT::from_packed_scene_dict(const Dictionary &p_dict, const String &p_replica) {
	Ref<CgameSceneCRDT> doc;
	doc.instantiate();
	doc->set_replica(p_replica);
	doc->load_scene_dict(p_dict);
	return doc;
}

// ---------------------------------------------------------------- presence

Dictionary CgameSceneCRDT::local_presence(const Variant &p_cursor, const Array &p_selection, int64_t p_time_msec) {
	presence_l++;
	Dictionary msg;
	msg["kind"] = "presence";
	msg["user"] = replica;
	msg["l"] = presence_l;
	msg["cursor"] = p_cursor;
	msg["selection"] = p_selection.duplicate();
	msg["t"] = p_time_msec;
	apply_presence(msg);
	return msg;
}

bool CgameSceneCRDT::apply_presence(const Dictionary &p_message) {
	const String user = p_message.get("user", "");
	const int64_t l = p_message.get("l", 0);
	HashMap<String, Presence>::Iterator it = presence_map.find(user);
	if (it != presence_map.end() && it->value.l >= l) {
		return false;
	}
	Presence p;
	p.l = l;
	p.cursor = p_message.get("cursor", Variant());
	p.selection = p_message.get("selection", Array());
	p.t = p_message.get("t", 0);
	if (it != presence_map.end()) {
		it->value = p;
	} else {
		presence_map.insert(user, p);
	}
	return true;
}

Dictionary CgameSceneCRDT::presence() const {
	Dictionary out;
	for (const KeyValue<String, Presence> &kv : presence_map) {
		Dictionary d;
		d["l"] = kv.value.l;
		d["cursor"] = kv.value.cursor;
		d["selection"] = kv.value.selection.duplicate(true);
		d["t"] = kv.value.t;
		out[kv.key] = d;
	}
	return out;
}

void CgameSceneCRDT::remove_presence(const String &p_user) {
	presence_map.erase(p_user);
}

Array CgameSceneCRDT::expire_presence(int64_t p_now_msec, int64_t p_ttl_msec) {
	Array gone;
	for (const KeyValue<String, Presence> &kv : presence_map) {
		if (p_now_msec - kv.value.t > p_ttl_msec) {
			gone.push_back(kv.key);
		}
	}
	for (int i = 0; i < gone.size(); i++) {
		presence_map.erase(String(gone[i]));
	}
	return gone;
}

void CgameSceneCRDT::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_replica", "replica"), &CgameSceneCRDT::set_replica);
	ClassDB::bind_method(D_METHOD("get_replica"), &CgameSceneCRDT::get_replica);
	ClassDB::bind_method(D_METHOD("set_clock", "clock"), &CgameSceneCRDT::set_clock);
	ClassDB::bind_method(D_METHOD("get_clock"), &CgameSceneCRDT::get_clock);

	ClassDB::bind_method(D_METHOD("apply", "op"), &CgameSceneCRDT::apply);
	ClassDB::bind_method(D_METHOD("local_op", "kind", "args"), &CgameSceneCRDT::local_op);
	ClassDB::bind_method(D_METHOD("has_node", "node_id"), &CgameSceneCRDT::has_node);
	ClassDB::bind_method(D_METHOD("get_prop", "node_id", "prop", "default"), &CgameSceneCRDT::get_prop, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("parent_of", "node_id"), &CgameSceneCRDT::parent_of);
	ClassDB::bind_method(D_METHOD("children_of", "parent"), &CgameSceneCRDT::children_of);
	ClassDB::bind_method(D_METHOD("all_node_ids"), &CgameSceneCRDT::all_node_ids);

	ClassDB::bind_method(D_METHOD("state_vector"), &CgameSceneCRDT::state_vector);
	ClassDB::bind_method(D_METHOD("ops_since", "vector"), &CgameSceneCRDT::ops_since);
	ClassDB::bind_method(D_METHOD("merge_ops", "ops"), &CgameSceneCRDT::merge_ops);

	ClassDB::bind_method(D_METHOD("to_scene_dict"), &CgameSceneCRDT::to_scene_dict);
	ClassDB::bind_method(D_METHOD("load_scene_dict", "scene"), &CgameSceneCRDT::load_scene_dict);
	ClassDB::bind_static_method("CgameSceneCRDT", D_METHOD("from_packed_scene_dict", "scene", "replica"), &CgameSceneCRDT::from_packed_scene_dict, DEFVAL("local"));

	ClassDB::bind_method(D_METHOD("local_presence", "cursor", "selection", "time_msec"), &CgameSceneCRDT::local_presence, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("apply_presence", "message"), &CgameSceneCRDT::apply_presence);
	ClassDB::bind_method(D_METHOD("presence"), &CgameSceneCRDT::presence);
	ClassDB::bind_method(D_METHOD("remove_presence", "user"), &CgameSceneCRDT::remove_presence);
	ClassDB::bind_method(D_METHOD("expire_presence", "now_msec", "ttl_msec"), &CgameSceneCRDT::expire_presence);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "replica"), "set_replica", "get_replica");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "clock"), "set_clock", "get_clock");

	ADD_SIGNAL(MethodInfo("op_generated", PropertyInfo(Variant::DICTIONARY, "op")));
}
