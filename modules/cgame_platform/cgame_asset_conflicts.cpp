/**************************************************************************/
/*  cgame_asset_conflicts.cpp                                             */
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

#include "cgame_asset_conflicts.h"

#include "core/crypto/hashing_context.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include "core/variant/variant_utility.h"

// ---------------------------------------------------------------- scanning

Dictionary CgameAssetConflicts::scan(const String &p_dir) {
	Dictionary out;
	_scan_into(p_dir, out);
	return out;
}

void CgameAssetConflicts::_scan_into(const String &p_dir, Dictionary &r_out) {
	Ref<DirAccess> da = DirAccess::open(p_dir);
	if (da.is_null()) {
		return;
	}
	const String base = p_dir.trim_suffix("/");
	for (const String &f : da->get_files()) {
		if (f.begins_with(".")) {
			continue;
		}
		const String p = base + "/" + f;
		r_out[p] = hash_file(p);
	}
	for (const String &d : da->get_directories()) {
		if (d.begins_with(".")) {
			continue;
		}
		_scan_into(base + "/" + d, r_out);
	}
}

Dictionary CgameAssetConflicts::hash_file(const String &p_path) {
	Dictionary d;
	Ref<FileAccess> fa = FileAccess::open(p_path, FileAccess::READ);
	if (fa.is_null()) {
		d["sha256"] = "";
		d["size"] = 0;
		return d;
	}
	Ref<HashingContext> ctx;
	ctx.instantiate();
	ctx->start(HashingContext::HASH_SHA256);
	const uint64_t size = fa->get_length();
	while (fa->get_position() < size) {
		ctx->update(fa->get_buffer(CHUNK));
	}
	const PackedByteArray digest = ctx->finish();
	d["sha256"] = String::hex_encode_buffer(digest.ptr(), digest.size());
	d["size"] = (int64_t)size;
	return d;
}

String CgameAssetConflicts::_entry_hash(const Variant &p_entry) {
	if (p_entry.get_type() == Variant::DICTIONARY) {
		const Dictionary d = p_entry;
		return String(d.get("sha256", ""));
	}
	return "";
}

Array CgameAssetConflicts::changed_paths(const Dictionary &p_a, const Dictionary &p_b) {
	Array out;
	for (const Variant &p : p_a.keys()) {
		if (!p_b.has(p) || _entry_hash(p_a[p]) != _entry_hash(p_b[p])) {
			out.push_back(p);
		}
	}
	for (const Variant &p : p_b.keys()) {
		if (!p_a.has(p)) {
			out.push_back(p);
		}
	}
	out.sort();
	return out;
}

Array CgameAssetConflicts::three_way_binary(const Dictionary &p_base, const Dictionary &p_mine, const Dictionary &p_theirs) {
	Dictionary paths;
	for (const Dictionary &sd : { p_base, p_mine, p_theirs }) {
		for (const Variant &p : sd.keys()) {
			paths[p] = true;
		}
	}
	Array keys = paths.keys();
	keys.sort();
	Array out;
	for (const Variant &p : keys) {
		const String b = _entry_hash(p_base.get(p, Dictionary()));
		const String m = _entry_hash(p_mine.get(p, Dictionary()));
		const String t = _entry_hash(p_theirs.get(p, Dictionary()));
		if (m != b && t != b && m != t) {
			Dictionary c;
			c["kind"] = "binary";
			c["path"] = p;
			c["base"] = b;
			c["mine"] = m;
			c["theirs"] = t;
			out.push_back(c);
		}
	}
	return out;
}

// ---------------------------------------------------------------- text scenes

String CgameAssetConflicts::_attr(const String &p_line, const String &p_key) {
	const String tag = p_key + "=\"";
	const int i = p_line.find(tag);
	if (i < 0) {
		return "";
	}
	const int s = i + tag.length();
	const int e = p_line.find("\"", s);
	return e >= 0 ? p_line.substr(s, e - s) : String();
}

Dictionary CgameAssetConflicts::parse_tscn(const String &p_text) {
	Dictionary out;
	String cur;
	String root;
	for (const String &raw : p_text.split("\n")) {
		const String line = raw.strip_edges();
		if (line.begins_with("[node ")) {
			const String nm = _attr(line, "name");
			const String par = _attr(line, "parent");
			if (par.is_empty()) {
				cur = nm;
				root = nm;
			} else if (par == ".") {
				cur = root + "/" + nm;
			} else {
				cur = root + "/" + par + "/" + nm;
			}
			Dictionary node;
			node["_type"] = _attr(line, "type");
			out[cur] = node;
		} else if (line.begins_with("[")) {
			cur = "";
		} else if (!cur.is_empty() && line.contains("=") && !line.begins_with(";")) {
			const int eq = line.find("=");
			Dictionary d = out[cur];
			d[line.substr(0, eq).strip_edges()] = line.substr(eq + 1).strip_edges();
		}
	}
	return out;
}

Dictionary CgameAssetConflicts::flatten_scene_dict(const Dictionary &p_dict) {
	Dictionary out;
	_flatten(p_dict, "", out);
	return out;
}

void CgameAssetConflicts::_flatten(const Dictionary &p_dict, const String &p_parent_path, Dictionary &r_out) {
	const String nm = p_dict.get("name", "Node");
	const String path = p_parent_path.is_empty() ? nm : p_parent_path + "/" + nm;
	const Dictionary src = p_dict.get("props", Dictionary());
	Dictionary props = src.duplicate(true);
	props["_type"] = p_dict.get("type", "Node");
	r_out[path] = props;
	const Array kids = p_dict.get("children", Array());
	for (int i = 0; i < kids.size(); i++) {
		_flatten(kids[i], path, r_out);
	}
}

bool CgameAssetConflicts::_same(bool p_a_has, const Variant &p_a, bool p_b_has, const Variant &p_b) {
	if (p_a_has != p_b_has) {
		return false;
	}
	return !p_a_has || VariantUtilityFunctions::var_to_str(p_a) == VariantUtilityFunctions::var_to_str(p_b);
}

bool CgameAssetConflicts::_props_same_keys(const Dictionary &p_a, const Dictionary &p_b) {
	for (const Variant &k : p_a.keys()) {
		if (!p_b.has(k) || VariantUtilityFunctions::var_to_str(p_a[k]) != VariantUtilityFunctions::var_to_str(p_b[k])) {
			return false;
		}
	}
	return true;
}

bool CgameAssetConflicts::_props_equal(const Dictionary &p_a, const Dictionary &p_b) {
	if (p_a.size() != p_b.size()) {
		return VariantUtilityFunctions::var_to_str(p_a) == VariantUtilityFunctions::var_to_str(p_b);
	}
	return _props_same_keys(p_a, p_b);
}

Dictionary CgameAssetConflicts::_merge_props(const String &p_path, const Dictionary &p_base, const Dictionary &p_mine, const Dictionary &p_theirs, Array &r_conflicts, const String &p_kind) {
	Dictionary out;
	Dictionary names;
	for (const Dictionary &sd : { p_base, p_mine, p_theirs }) {
		for (const Variant &k : sd.keys()) {
			names[k] = true;
		}
	}
	Array knames = names.keys();
	knames.sort();
	for (const Variant &k : knames) {
		const bool bh = p_base.has(k);
		const bool mh = p_mine.has(k);
		const bool th = p_theirs.has(k);
		const Variant bv = p_base.get(k, Variant());
		const Variant mv = p_mine.get(k, Variant());
		const Variant tv = p_theirs.get(k, Variant());
		bool pick_h;
		Variant pick_v;
		if (_same(mh, mv, th, tv)) {
			pick_h = mh;
			pick_v = mv;
		} else if (_same(mh, mv, bh, bv)) {
			pick_h = th;
			pick_v = tv;
		} else if (_same(th, tv, bh, bv)) {
			pick_h = mh;
			pick_v = mv;
		} else {
			Dictionary c;
			c["kind"] = p_kind;
			c["node"] = p_path;
			c["prop"] = k;
			c["base"] = bv;
			c["mine"] = mv;
			c["theirs"] = tv;
			r_conflicts.push_back(c);
			pick_h = mh;
			pick_v = mv;
		}
		if (pick_h) {
			out[k] = pick_v;
		}
	}
	return out;
}

Dictionary CgameAssetConflicts::merge_scene(const Dictionary &p_base, const Dictionary &p_mine, const Dictionary &p_theirs) {
	Dictionary merged;
	Array conflicts;
	Dictionary paths;
	for (const Dictionary &sd : { p_base, p_mine, p_theirs }) {
		for (const Variant &p : sd.keys()) {
			paths[p] = true;
		}
	}
	Array keys = paths.keys();
	keys.sort();
	for (const Variant &p : keys) {
		const bool in_b = p_base.has(p);
		const bool in_m = p_mine.has(p);
		const bool in_t = p_theirs.has(p);
		const Dictionary b = p_base.get(p, Dictionary());
		const Dictionary m = p_mine.get(p, Dictionary());
		const Dictionary t = p_theirs.get(p, Dictionary());
		if (in_b && !in_m && !in_t) {
			continue;
		}
		if (in_b && (in_m != in_t)) {
			const Dictionary survivor = in_m ? m : t;
			if (_props_equal(survivor, b)) {
				continue; // One side deleted, the other left it alone.
			}
			Dictionary c;
			c["kind"] = "delete_edit";
			c["node"] = p;
			c["prop"] = "";
			c["mine"] = !in_m ? "deleted" : "edited";
			c["theirs"] = !in_t ? "deleted" : "edited";
			conflicts.push_back(c);
			merged[p] = survivor.duplicate(true);
			continue;
		}
		if (!in_b) {
			if (in_m != in_t) {
				merged[p] = (in_m ? m : t).duplicate(true);
				continue;
			}
			merged[p] = _merge_props(p, Dictionary(), m, t, conflicts, "add_add");
			continue;
		}
		merged[p] = _merge_props(p, b, m, t, conflicts, "property");
	}
	Dictionary res;
	res["merged"] = merged;
	res["conflicts"] = conflicts;
	return res;
}

Array CgameAssetConflicts::three_way(const Dictionary &p_base, const Dictionary &p_mine, const Dictionary &p_theirs) {
	return merge_scene(p_base, p_mine, p_theirs)["conflicts"];
}

// ---------------------------------------------------------------- inheritance overrides

Array CgameAssetConflicts::override_conflicts(const Dictionary &p_instance_overrides, const Dictionary &p_base_changes) {
	Array out;
	Array paths = p_instance_overrides.keys();
	paths.sort();
	for (const Variant &p : paths) {
		if (!p_base_changes.has(p)) {
			continue;
		}
		const Dictionary ov = p_instance_overrides[p];
		const Dictionary bc = p_base_changes[p];
		if (bool(bc.get("removed", false))) {
			Dictionary c;
			c["kind"] = "orphaned_override";
			c["node"] = p;
			c["prop"] = "";
			c["override"] = ov.duplicate(true);
			out.push_back(c);
			continue;
		}
		const Dictionary bprops = bc.get("props", Dictionary());
		Array names = ov.keys();
		names.sort();
		for (const Variant &k : names) {
			if (bprops.has(k) && VariantUtilityFunctions::var_to_str(bprops[k]) != VariantUtilityFunctions::var_to_str(ov[k])) {
				Dictionary c;
				c["kind"] = "override_vs_base";
				c["node"] = p;
				c["prop"] = k;
				c["override"] = ov[k];
				c["base_new"] = bprops[k];
				out.push_back(c);
			}
		}
	}
	return out;
}

// ---------------------------------------------------------------- exclusive locks

double CgameAssetConflicts::_now() {
	return OS::get_singleton()->get_unix_time();
}

bool CgameAssetConflicts::lock(const String &p_path, const String &p_user, double p_ttl_sec, double p_now) {
	const double t = p_now < 0.0 ? _now() : p_now;
	const String cur = owner(p_path, t);
	if (!cur.is_empty() && cur != p_user) {
		return false;
	}
	Lock l;
	l.user = p_user;
	l.expires = t + p_ttl_sec;
	locks[p_path] = l;
	return true;
}

bool CgameAssetConflicts::unlock(const String &p_path, const String &p_user, bool p_force) {
	HashMap<String, Lock>::Iterator it = locks.find(p_path);
	if (it == locks.end()) {
		return false;
	}
	if (it->value.user != p_user && !p_force) {
		return false;
	}
	locks.remove(it);
	return true;
}

String CgameAssetConflicts::owner(const String &p_path, double p_now) {
	HashMap<String, Lock>::Iterator it = locks.find(p_path);
	if (it == locks.end()) {
		return "";
	}
	const double t = p_now < 0.0 ? _now() : p_now;
	if (it->value.expires <= t) {
		locks.remove(it);
		return "";
	}
	return it->value.user;
}

bool CgameAssetConflicts::can_edit(const String &p_path, const String &p_user, double p_now) {
	const String o = owner(p_path, p_now);
	return o.is_empty() || o == p_user;
}

Dictionary CgameAssetConflicts::active_locks(double p_now) {
	Vector<String> paths;
	for (const KeyValue<String, Lock> &kv : locks) {
		paths.push_back(kv.key);
	}
	Dictionary out;
	for (const String &p : paths) {
		const String o = owner(p, p_now);
		if (!o.is_empty()) {
			out[p] = o;
		}
	}
	return out;
}

void CgameAssetConflicts::_bind_methods() {
	ClassDB::bind_static_method("CgameAssetConflicts", D_METHOD("scan", "dir"), &CgameAssetConflicts::scan);
	ClassDB::bind_static_method("CgameAssetConflicts", D_METHOD("hash_file", "path"), &CgameAssetConflicts::hash_file);
	ClassDB::bind_static_method("CgameAssetConflicts", D_METHOD("changed_paths", "a", "b"), &CgameAssetConflicts::changed_paths);
	ClassDB::bind_static_method("CgameAssetConflicts", D_METHOD("three_way_binary", "base", "mine", "theirs"), &CgameAssetConflicts::three_way_binary);
	ClassDB::bind_static_method("CgameAssetConflicts", D_METHOD("parse_tscn", "text"), &CgameAssetConflicts::parse_tscn);
	ClassDB::bind_static_method("CgameAssetConflicts", D_METHOD("flatten_scene_dict", "scene"), &CgameAssetConflicts::flatten_scene_dict);
	ClassDB::bind_static_method("CgameAssetConflicts", D_METHOD("merge_scene", "base", "mine", "theirs"), &CgameAssetConflicts::merge_scene);
	ClassDB::bind_static_method("CgameAssetConflicts", D_METHOD("three_way", "base", "mine", "theirs"), &CgameAssetConflicts::three_way);
	ClassDB::bind_static_method("CgameAssetConflicts", D_METHOD("override_conflicts", "instance_overrides", "base_changes"), &CgameAssetConflicts::override_conflicts);

	ClassDB::bind_method(D_METHOD("lock", "path", "user", "ttl_sec", "now"), &CgameAssetConflicts::lock, DEFVAL(300.0), DEFVAL(-1.0));
	ClassDB::bind_method(D_METHOD("unlock", "path", "user", "force"), &CgameAssetConflicts::unlock, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("owner", "path", "now"), &CgameAssetConflicts::owner, DEFVAL(-1.0));
	ClassDB::bind_method(D_METHOD("can_edit", "path", "user", "now"), &CgameAssetConflicts::can_edit, DEFVAL(-1.0));
	ClassDB::bind_method(D_METHOD("active_locks", "now"), &CgameAssetConflicts::active_locks, DEFVAL(-1.0));

	BIND_CONSTANT(CHUNK);
}
