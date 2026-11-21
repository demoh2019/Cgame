extends RefCounted
## Asset conflict tooling: content scans, three-way scene merge, binary version conflicts,
## Perforce-style exclusive checkout locks and scene-inheritance override conflicts.
##
## Concepts (no code copied): three-way merge as in diff3 / Git (GPL tools not consulted;
## the algorithm is the textbook base/mine/theirs comparison), Perforce "exclusive open"
## (+l filetype) checkout locks, Unreal Multi-User asset locking. SHA-256 via Godot's
## HashingContext.
##
## Scene dictionary used by three_way(): node path -> {prop name: value}. The reserved
## prop "_type" holds the node type. parse_tscn() and flatten_scene_dict() produce it.

const CHUNK := 65536

var _locks: Dictionary = {}  # path -> {"user": String, "expires": float}


# ---------------------------------------------------------------- scanning

## Recursively hashes every file under `dir` (hidden entries and .godot are skipped).
## Returns {path: {"sha256": String, "size": int}}.
static func scan(dir: String) -> Dictionary:
	var out: Dictionary = {}
	_scan_into(dir, out)
	return out


static func _scan_into(dir: String, out: Dictionary) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	var base := dir.trim_suffix("/")
	for f in da.get_files():
		if f.begins_with("."):
			continue
		var p := base + "/" + f
		out[p] = hash_file(p)
	for d in da.get_directories():
		if d.begins_with("."):
			continue
		_scan_into(base + "/" + d, out)


## {"sha256", "size"} of one file; empty sha256 when unreadable.
static func hash_file(path: String) -> Dictionary:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return {"sha256": "", "size": 0}
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var size := fa.get_length()
	while fa.get_position() < size:
		ctx.update(fa.get_buffer(CHUNK))
	return {"sha256": ctx.finish().hex_encode(), "size": size}


## Paths whose hash differs between two scans (added, removed or modified).
static func changed_paths(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for p in a:
		if not b.has(p) or _entry_hash(a[p]) != _entry_hash(b[p]):
			out.append(p)
	for p in b:
		if not a.has(p):
			out.append(p)
	out.sort()
	return out


static func _entry_hash(e: Variant) -> String:
	if e is Dictionary:
		var d: Dictionary = e
		return str(d.get("sha256", ""))
	return ""


## Binary version conflicts from three scans: both sides changed the file differently.
## Returns [{"kind": "binary", "path", "base", "mine", "theirs"}] (hashes, "" if absent).
static func three_way_binary(base: Dictionary, mine: Dictionary, theirs: Dictionary) -> Array:
	var paths: Dictionary = {}
	for s in [base, mine, theirs]:
		var sd: Dictionary = s
		for p in sd:
			paths[p] = true
	var keys: Array = paths.keys()
	keys.sort()
	var out: Array = []
	for p in keys:
		var b := _entry_hash(base.get(p, {}))
		var m := _entry_hash(mine.get(p, {}))
		var t := _entry_hash(theirs.get(p, {}))
		if m != b and t != b and m != t:
			out.append({"kind": "binary", "path": p, "base": b, "mine": m, "theirs": t})
	return out


# ---------------------------------------------------------------- text scenes

## Minimal .tscn-like parser: "[node name=.. type=.. parent=..]" headers followed by
## "key = value" lines (values kept as raw strings). Returns node path -> {prop: value}.
static func parse_tscn(text: String) -> Dictionary:
	var out: Dictionary = {}
	var cur := ""
	var root := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("[node "):
			var nm := _attr(line, "name")
			var par := _attr(line, "parent")
			if par == "":
				cur = nm
				root = nm
			elif par == ".":
				cur = root + "/" + nm
			else:
				cur = root + "/" + par + "/" + nm
			out[cur] = {"_type": _attr(line, "type")}
		elif line.begins_with("["):
			cur = ""
		elif cur != "" and "=" in line and not line.begins_with(";"):
			var eq := line.find("=")
			var d: Dictionary = out[cur]
			d[line.substr(0, eq).strip_edges()] = line.substr(eq + 1).strip_edges()
	return out


static func _attr(line: String, key: String) -> String:
	var tag := key + "=\""
	var i := line.find(tag)
	if i < 0:
		return ""
	var s := i + tag.length()
	var e := line.find("\"", s)
	return line.substr(s, e - s) if e >= 0 else ""


## Flattens a nested scene dict ({name, type, props, children}) to path -> props.
static func flatten_scene_dict(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	_flatten(d, "", out)
	return out


static func _flatten(d: Dictionary, parent_path: String, out: Dictionary) -> void:
	var nm: String = d.get("name", "Node")
	var path := nm if parent_path == "" else parent_path + "/" + nm
	var props: Dictionary = d.get("props", {}).duplicate(true)
	props["_type"] = d.get("type", "Node")
	out[path] = props
	var kids: Array = d.get("children", [])
	for k in kids:
		_flatten(k, path, out)


static func _same(ah: bool, av: Variant, bh: bool, bv: Variant) -> bool:
	if ah != bh:
		return false
	return not ah or var_to_str(av) == var_to_str(bv)


## Three-way property-level merge. Returns {"merged": Dictionary, "conflicts": Array}.
## A property changed on one side only is taken; changed on both sides to different values
## is a conflict (merged keeps "mine"). Conflict kinds: property, add_add, delete_edit.
static func merge_scene(base: Dictionary, mine: Dictionary, theirs: Dictionary) -> Dictionary:
	var merged: Dictionary = {}
	var conflicts: Array = []
	var paths: Dictionary = {}
	for s in [base, mine, theirs]:
		var sd: Dictionary = s
		for p in sd:
			paths[p] = true
	var keys: Array = paths.keys()
	keys.sort()
	for p in keys:
		var in_b := base.has(p)
		var in_m := mine.has(p)
		var in_t := theirs.has(p)
		var b: Dictionary = base.get(p, {})
		var m: Dictionary = mine.get(p, {})
		var t: Dictionary = theirs.get(p, {})
		if in_b and not in_m and not in_t:
			continue
		if in_b and (in_m != in_t):
			var survivor: Dictionary = m if in_m else t
			if _props_equal(survivor, b):
				continue  # one side deleted, the other left it alone
			conflicts.append({"kind": "delete_edit", "node": p, "prop": "", "mine": "deleted" if not in_m else "edited", "theirs": "deleted" if not in_t else "edited"})
			merged[p] = survivor.duplicate(true)
			continue
		if not in_b:
			if in_m != in_t:
				merged[p] = (m if in_m else t).duplicate(true)
				continue
			merged[p] = _merge_props(p, {}, m, t, conflicts, "add_add")
			continue
		merged[p] = _merge_props(p, b, m, t, conflicts, "property")
	return {"merged": merged, "conflicts": conflicts}


## Conflicts only (see merge_scene).
static func three_way(base: Dictionary, mine: Dictionary, theirs: Dictionary) -> Array:
	return merge_scene(base, mine, theirs)["conflicts"]


static func _props_equal(a: Dictionary, b: Dictionary) -> bool:
	return var_to_str(a) == var_to_str(b) if a.size() != b.size() else _props_same_keys(a, b)


static func _props_same_keys(a: Dictionary, b: Dictionary) -> bool:
	for k in a:
		if not b.has(k) or var_to_str(a[k]) != var_to_str(b[k]):
			return false
	return true


static func _merge_props(path: String, b: Dictionary, m: Dictionary, t: Dictionary, conflicts: Array, kind: String) -> Dictionary:
	var out: Dictionary = {}
	var names: Dictionary = {}
	for s in [b, m, t]:
		var sd: Dictionary = s
		for k in sd:
			names[k] = true
	var knames: Array = names.keys()
	knames.sort()
	for k in knames:
		var bh := b.has(k)
		var mh := m.has(k)
		var th := t.has(k)
		var bv: Variant = b.get(k)
		var mv: Variant = m.get(k)
		var tv: Variant = t.get(k)
		var pick_h: bool
		var pick_v: Variant
		if _same(mh, mv, th, tv):
			pick_h = mh
			pick_v = mv
		elif _same(mh, mv, bh, bv):
			pick_h = th
			pick_v = tv
		elif _same(th, tv, bh, bv):
			pick_h = mh
			pick_v = mv
		else:
			conflicts.append({"kind": kind, "node": path, "prop": k, "base": bv, "mine": mv, "theirs": tv})
			pick_h = mh
			pick_v = mv
		if pick_h:
			out[k] = pick_v
	return out


# ---------------------------------------------------------------- inheritance overrides

## Conflicts between instance overrides and upstream (base scene) changes.
## instance_overrides: node path -> {prop: value}.
## base_changes: node path -> {"removed": bool, "props": {prop: new value}}.
## Kinds: orphaned_override (node removed upstream), override_vs_base (upstream changed a
## property that the instance overrides to a different value).
static func override_conflicts(instance_overrides: Dictionary, base_changes: Dictionary) -> Array:
	var out: Array = []
	var paths: Array = instance_overrides.keys()
	paths.sort()
	for p in paths:
		if not base_changes.has(p):
			continue
		var ov: Dictionary = instance_overrides[p]
		var bc: Dictionary = base_changes[p]
		if bc.get("removed", false):
			out.append({"kind": "orphaned_override", "node": p, "prop": "", "override": ov.duplicate(true)})
			continue
		var bprops: Dictionary = bc.get("props", {})
		var names: Array = ov.keys()
		names.sort()
		for k in names:
			if bprops.has(k) and var_to_str(bprops[k]) != var_to_str(ov[k]):
				out.append({"kind": "override_vs_base", "node": p, "prop": k, "override": ov[k], "base_new": bprops[k]})
	return out


# ---------------------------------------------------------------- exclusive locks

static func _now() -> float:
	return Time.get_unix_time_from_system()


## Takes (or refreshes) an exclusive lock. False if another user holds an unexpired lock.
## now < 0 uses the wall clock (pass a fixed value in tests).
func lock(path: String, user: String, ttl_sec: float = 300.0, now: float = -1.0) -> bool:
	var t := _now() if now < 0.0 else now
	var cur: String = owner(path, t)
	if cur != "" and cur != user:
		return false
	_locks[path] = {"user": user, "expires": t + ttl_sec}
	return true


## Releases a lock held by `user` (or any lock when force). Returns whether one was released.
func unlock(path: String, user: String, force: bool = false) -> bool:
	if not _locks.has(path):
		return false
	var e: Dictionary = _locks[path]
	if e["user"] != user and not force:
		return false
	_locks.erase(path)
	return true


## Current owner or "" when free or expired.
func owner(path: String, now: float = -1.0) -> String:
	if not _locks.has(path):
		return ""
	var t := _now() if now < 0.0 else now
	var e: Dictionary = _locks[path]
	if float(e["expires"]) <= t:
		_locks.erase(path)
		return ""
	return str(e["user"])


## Whether `user` may edit path (free, or held by them).
func can_edit(path: String, user: String, now: float = -1.0) -> bool:
	var o := owner(path, now)
	return o == "" or o == user


## path -> owner for all unexpired locks.
func active_locks(now: float = -1.0) -> Dictionary:
	var out: Dictionary = {}
	for p in _locks.keys():
		var o := owner(str(p), now)
		if o != "":
			out[p] = o
	return out
