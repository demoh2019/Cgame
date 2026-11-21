extends RefCounted
## Scene CRDT convergence, sync, presence, asset scans, three-way merge, locks, overrides.

const SceneCRDT = preload("res://scripts/tools/scene_crdt.gd")
const AssetConflicts = preload("res://scripts/tools/asset_conflicts.gd")


func _doc(r: String) -> RefCounted:
	return SceneCRDT.new(r)


func _sync(a: RefCounted, b: RefCounted) -> void:
	b.merge_ops(a.ops_since(b.state_vector()))
	a.merge_ops(b.ops_since(a.state_vector()))


func _canon(d: RefCounted) -> String:
	return JSON.stringify(d.to_scene_dict(), "", true)


func _apply_all(r: String, ops: Array) -> RefCounted:
	var d := _doc(r)
	for op in ops:
		d.apply(op)
	return d


func run(t) -> void:
	t.current = "crdt basics and scene dict"
	var a := _doc("A")
	a.local_op("add_node", {"id": "root", "type": "Node3D", "props": {"name": "Root"}})
	a.local_op("add_node", {"id": "p", "parent": "root", "type": "Node3D", "props": {"name": "P", "x": 1}})
	a.local_op("add_node", {"id": "q", "parent": "root", "type": "Node3D", "props": {"name": "Q"}})
	a.local_op("add_node", {"id": "first", "parent": "root", "index": 0, "type": "Node", "props": {"name": "First"}})
	t.eq(a.children_of("root"), ["first", "p", "q"], "index 0 inserts first, others append")
	t.eq(a.get_prop("p", "x"), 1, "prop readable")
	a.local_op("move_node", {"id": "q", "parent": "root", "index": 0})
	t.eq(a.children_of("root"), ["q", "first", "p"], "move within parent reorders")
	var sd: Dictionary = a.to_scene_dict()
	t.eq(sd["name"], "Root", "scene dict root name")
	t.eq((sd["children"] as Array).size(), 3, "scene dict children")
	var clone: RefCounted = SceneCRDT.from_packed_scene_dict(sd, "Z")
	t.eq(_canon(clone), _canon(a), "scene dict round-trips through from_packed_scene_dict")
	t.check(a.apply(a.ops_since({})[0]) == false, "re-applying a known op is a no-op")

	t.current = "idempotency"
	var ops: Array = a.ops_since({})
	var d1 := _apply_all("X", ops)
	var before := _canon(d1)
	for op in ops:
		d1.apply(op)
	t.eq(_canon(d1), before, "applying every op twice changes nothing")
	t.eq(d1.state_vector(), a.state_vector(), "state vectors match")

	t.current = "three replicas converge"
	var r1 := _doc("A")
	r1.local_op("add_node", {"id": "root", "type": "Node", "props": {"name": "Root"}})
	r1.local_op("add_node", {"id": "a", "parent": "root", "type": "Node", "props": {"name": "A", "v": 0}})
	r1.local_op("add_node", {"id": "b", "parent": "root", "type": "Node", "props": {"name": "B"}})
	r1.local_op("add_node", {"id": "x", "parent": "root", "type": "Node", "props": {"name": "X"}})
	var r2 := _doc("B")
	var r3 := _doc("C")
	_sync(r1, r2)
	_sync(r1, r3)
	var base_count: int = r1.ops_since({}).size()
	# Concurrent edits.
	r1.local_op("set_prop", {"id": "a", "prop": "v", "value": 11})
	r1.local_op("move_node", {"id": "b", "parent": "a", "index": 0})
	r1.local_op("add_node", {"id": "n1", "parent": "root", "type": "Node", "props": {"name": "N1"}})
	r2.local_op("set_prop", {"id": "a", "prop": "v", "value": 22})
	r2.local_op("move_node", {"id": "b", "parent": "root", "index": 0})
	r2.local_op("add_node", {"id": "n2", "parent": "root", "type": "Node", "props": {"name": "N2"}})
	r2.local_op("remove_node", {"id": "x"})
	r3.local_op("set_prop", {"id": "x", "prop": "v", "value": 5})
	r3.local_op("remove_node", {"id": "a"})
	r3.local_op("add_node", {"id": "n3", "parent": "root", "type": "Node", "props": {"name": "N3"}})
	var all: Array = []
	for r in [r1, r2, r3]:
		var rd: RefCounted = r
		all.append_array(rd.ops_since({}))
	t.check(all.size() > base_count, "concurrent ops generated")
	var fwd := _apply_all("D", all)
	var rev_ops: Array = all.duplicate()
	rev_ops.reverse()
	var rev := _apply_all("E", rev_ops)
	var rot_ops: Array = all.slice(5) + all.slice(0, 5)
	var rot := _apply_all("F", rot_ops)
	t.eq(_canon(rev), _canon(fwd), "reverse order converges")
	t.eq(_canon(rot), _canon(fwd), "rotated order converges")
	t.eq(fwd.children_of("root"), rev.children_of("root"), "sibling order converges")
	t.check(not fwd.has_node("x"), "remove wins over concurrent set_prop (node hidden)")
	t.eq(fwd.get_prop("x", "v"), 5, "register still holds the concurrent value")
	t.check(not fwd.has_node("a"), "remove of a observed tag removes node a")
	t.check(fwd.has_node("n1") and fwd.has_node("n2") and fwd.has_node("n3"), "all concurrent adds survive")
	t.eq(fwd.parent_of("b"), "root", "concurrent move: higher (lamport, replica) wins")
	_sync(r1, r2)
	_sync(r2, r3)
	_sync(r1, r3)
	t.eq(_canon(r1), _canon(r2), "pairwise sync converges r1 r2")
	t.eq(_canon(r2), _canon(r3), "pairwise sync converges r2 r3")
	t.eq(_canon(r3), _canon(fwd), "synced replicas equal order-shuffled replica")

	t.current = "lww and add-wins"
	var l1 := _doc("A")
	l1.local_op("add_node", {"id": "n", "type": "Node", "props": {"name": "N"}})
	var l2 := _doc("Z")
	_sync(l1, l2)
	l1.local_op("set_prop", {"id": "n", "prop": "k", "value": "from_a"})
	l2.local_op("set_prop", {"id": "n", "prop": "k", "value": "from_z"})
	_sync(l1, l2)
	t.eq(l1.get_prop("n", "k"), "from_z", "equal lamport: larger replica id wins")
	t.eq(l2.get_prop("n", "k"), "from_z", "both replicas agree")
	l1.local_op("set_prop", {"id": "n", "prop": "k", "value": "later"})
	_sync(l1, l2)
	t.eq(l2.get_prop("n", "k"), "later", "causally later write wins regardless of replica id")
	# add-wins: A removes, Z re-adds concurrently.
	l1.local_op("remove_node", {"id": "n"})
	l2.local_op("add_node", {"id": "n", "type": "Node", "props": {"name": "N"}})
	_sync(l1, l2)
	t.check(l1.has_node("n") and l2.has_node("n"), "concurrent add beats remove")
	l1.local_op("remove_node", {"id": "n"})
	_sync(l1, l2)
	t.check(not l1.has_node("n") and not l2.has_node("n"), "remove after observing all adds deletes")
	var evl := [0]
	l1.op_generated.connect(func(_o: Dictionary) -> void: evl[0] += 1)
	l1.local_op("set_prop", {"id": "n", "prop": "k", "value": 1})
	t.eq(evl[0], 1, "op_generated signal fires")

	t.current = "concurrent sibling inserts"
	var s1 := _doc("A")
	s1.local_op("add_node", {"id": "root", "type": "Node"})
	s1.local_op("add_node", {"id": "k1", "parent": "root", "type": "Node"})
	var s2 := _doc("B")
	_sync(s1, s2)
	s1.local_op("add_node", {"id": "ka", "parent": "root", "index": 1, "type": "Node"})
	s2.local_op("add_node", {"id": "kb", "parent": "root", "index": 1, "type": "Node"})
	_sync(s1, s2)
	t.eq(s1.children_of("root"), s2.children_of("root"), "same slot inserts converge to one order")
	t.eq(s1.children_of("root").size(), 3, "no insert lost")
	t.eq(s1.children_of("root")[0], "k1", "k1 stays first")

	t.current = "state vector sync"
	var v1 := _doc("A")
	v1.local_op("add_node", {"id": "root", "type": "Node"})
	v1.local_op("set_prop", {"id": "root", "prop": "p", "value": 1})
	var v2 := _doc("B")
	_sync(v1, v2)
	t.eq(v2.state_vector().get("A", 0), 2, "vector counts A's ops")
	v1.local_op("set_prop", {"id": "root", "prop": "p", "value": 2})
	v1.local_op("set_prop", {"id": "root", "prop": "q", "value": 3})
	var missing: Array = v1.ops_since(v2.state_vector())
	t.eq(missing.size(), 2, "ops_since returns only the missing ops")
	# A gap must not advance the contiguous vector.
	var gap := _doc("G")
	var all_v1: Array = v1.ops_since({})
	gap.apply(all_v1[3])
	t.eq(gap.state_vector().get("A", 0), 0, "vector stays at 0 while seq 1..3 are missing")
	gap.merge_ops(all_v1)
	t.eq(gap.state_vector().get("A", 0), 4, "vector advances once gap is filled")
	t.eq(gap.get_prop("root", "q"), 3, "gap-filled doc has latest state")

	t.current = "presence"
	var pa := _doc("alice")
	var pb := _doc("bob")
	var m1: Dictionary = pa.local_presence(Vector2(1, 2), ["n1"], 1000)
	var m2: Dictionary = pa.local_presence(Vector2(3, 4), ["n2"], 2000)
	pb.apply_presence(m2)
	t.check(pb.apply_presence(m1) == false, "stale presence ignored")
	t.eq(pb.presence()["alice"]["cursor"], Vector2(3, 4), "latest cursor kept")
	t.eq(pb.presence()["alice"]["selection"], ["n2"], "selection kept")
	pb.local_presence(Vector2.ZERO, [], 5000)
	t.eq(pb.presence().size(), 2, "two users present")
	var gone: Array = pb.expire_presence(6000, 3000)
	t.eq(gone, ["alice"], "idle user expired")
	pb.remove_presence("bob")
	t.eq(pb.presence().size(), 0, "presence removal")

	t.current = "asset scan"
	var dir := "user://collab_scan_test"
	DirAccess.make_dir_recursive_absolute(dir + "/sub")
	var f := FileAccess.open(dir + "/a.txt", FileAccess.WRITE)
	f.store_string("abc")
	f.close()
	f = FileAccess.open(dir + "/sub/b.bin", FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1, 2, 3, 4, 5]))
	f.close()
	var scan1: Dictionary = AssetConflicts.scan(dir)
	t.eq(scan1.size(), 2, "scan finds nested files")
	t.eq(scan1[dir + "/a.txt"]["sha256"], "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 of abc")
	t.eq(scan1[dir + "/sub/b.bin"]["size"], 5, "size recorded")
	f = FileAccess.open(dir + "/a.txt", FileAccess.WRITE)
	f.store_string("abd")
	f.close()
	var scan2: Dictionary = AssetConflicts.scan(dir)
	t.eq(AssetConflicts.changed_paths(scan1, scan2), [dir + "/a.txt"], "changed_paths reports the edited file")
	DirAccess.remove_absolute(dir + "/a.txt")
	DirAccess.remove_absolute(dir + "/sub/b.bin")
	DirAccess.remove_absolute(dir + "/sub")
	DirAccess.remove_absolute(dir)
	t.check(not DirAccess.dir_exists_absolute(dir), "scan fixtures cleaned up")

	t.current = "three-way merge"
	var base := {
		"Root": {"_type": "Node3D", "visible": "true"},
		"Root/Light": {"_type": "Light3D", "energy": "1.0", "color": "white"},
		"Root/Old": {"_type": "Node", "k": "1"},
		"Root/Gone": {"_type": "Node", "k": "1"},
	}
	var mine: Dictionary = base.duplicate(true)
	var theirs: Dictionary = base.duplicate(true)
	mine["Root/Light"]["energy"] = "2.0"
	theirs["Root/Light"]["color"] = "red"
	mine["Root/Mine"] = {"_type": "Node", "z": "1"}
	theirs["Root/Theirs"] = {"_type": "Node"}
	t.eq(AssetConflicts.three_way(base, mine, theirs).size(), 0, "disjoint property edits do not conflict")
	var res: Dictionary = AssetConflicts.merge_scene(base, mine, theirs)
	var merged: Dictionary = res["merged"]
	t.eq(merged["Root/Light"]["energy"], "2.0", "merge keeps my energy")
	t.eq(merged["Root/Light"]["color"], "red", "merge takes their color")
	t.check(merged.has("Root/Mine") and merged.has("Root/Theirs"), "both added nodes merged")
	mine["Root/Gone"].erase("k")
	mine.erase("Root/Old")
	theirs.erase("Root/Gone")
	theirs["Root/Light"]["energy"] = "3.0"
	theirs["Root/Old"]["k"] = "2"
	var conf: Array = AssetConflicts.three_way(base, mine, theirs)
	var kinds: Dictionary = {}
	for c in conf:
		var cd: Dictionary = c
		kinds["%s|%s" % [cd["kind"], cd["node"]]] = cd
	t.check(kinds.has("property|Root/Light"), "same property changed differently conflicts")
	t.eq(kinds["property|Root/Light"]["prop"], "energy", "conflict names the property")
	t.eq(kinds["property|Root/Light"]["theirs"], "3.0", "conflict carries their value")
	t.check(kinds.has("delete_edit|Root/Old"), "delete vs edit conflicts")
	t.check(kinds.has("delete_edit|Root/Gone"), "their delete vs my edit conflicts")
	t.eq(AssetConflicts.three_way(base, base, theirs).size(), 0, "delete vs untouched is clean")
	mine["Root/Light"]["energy"] = "3.0"
	t.eq(AssetConflicts.three_way(base, mine, theirs).filter(func(x: Dictionary) -> bool: return x["node"] == "Root/Light").size(), 0, "identical edits on both sides agree")
	var parsed: Dictionary = AssetConflicts.parse_tscn("[gd_scene]\n[node name=\"Root\" type=\"Node3D\"]\nvisible = true\n[node name=\"L\" type=\"Light3D\" parent=\".\"]\nenergy = 2.0\n")
	t.eq(parsed["Root/L"]["energy"], "2.0", "parse_tscn reads props")
	t.eq(parsed["Root"]["_type"], "Node3D", "parse_tscn reads type")
	var flat: Dictionary = AssetConflicts.flatten_scene_dict(sd)
	t.check(flat.has("Root/P") and flat["Root/P"]["x"] == 1, "flatten_scene_dict builds path props")

	t.current = "binary conflicts"
	var bb := {"a.png": {"sha256": "h1", "size": 1}, "b.png": {"sha256": "h2", "size": 1}, "c.png": {"sha256": "h3", "size": 1}}
	var bm: Dictionary = bb.duplicate(true)
	var bt: Dictionary = bb.duplicate(true)
	bm["a.png"] = {"sha256": "m", "size": 1}
	bt["a.png"] = {"sha256": "t", "size": 1}
	bm["b.png"] = {"sha256": "only_mine", "size": 1}
	bt["c.png"] = {"sha256": "same", "size": 1}
	bm["c.png"] = {"sha256": "same", "size": 1}
	var bc: Array = AssetConflicts.three_way_binary(bb, bm, bt)
	t.eq(bc.size(), 1, "only the file changed on both sides conflicts")
	t.eq(bc[0]["path"], "a.png", "conflicting path reported")
	t.eq(bc[0]["kind"], "binary", "binary kind")

	t.current = "exclusive locks"
	var lt: RefCounted = AssetConflicts.new()
	t.check(lt.lock("res://a.tscn", "alice", 60.0, 100.0), "free lock granted")
	t.check(not lt.lock("res://a.tscn", "bob", 60.0, 120.0), "second user denied while held")
	t.eq(lt.owner("res://a.tscn", 120.0), "alice", "owner reported")
	t.check(lt.lock("res://a.tscn", "alice", 60.0, 130.0), "owner can refresh")
	t.eq(lt.owner("res://a.tscn", 170.0), "alice", "refresh extended expiry")
	t.check(not lt.can_edit("res://a.tscn", "bob", 170.0), "bob cannot edit")
	t.check(not lt.unlock("res://a.tscn", "bob"), "non-owner cannot unlock")
	t.eq(lt.owner("res://a.tscn", 191.0), "", "lock expires")
	t.check(lt.lock("res://a.tscn", "bob", 60.0, 191.0), "expired lock can be taken")
	t.check(lt.unlock("res://a.tscn", "bob"), "owner unlocks")
	t.eq(lt.owner("res://a.tscn", 192.0), "", "unlocked is free")
	lt.lock("res://b.tscn", "alice", 60.0, 0.0)
	t.check(lt.unlock("res://b.tscn", "admin", true), "force unlock")
	t.eq(lt.active_locks(0.0).size(), 0, "no active locks left")

	t.current = "override conflicts"
	var ov := {"Root/Light": {"energy": 5.0, "color": "blue"}, "Root/Removed": {"k": 1}, "Root/Other": {"k": 2}}
	var bch := {"Root/Light": {"props": {"energy": 3.0, "color": "blue", "shadow": true}}, "Root/Removed": {"removed": true}}
	var oc: Array = AssetConflicts.override_conflicts(ov, bch)
	t.eq(oc.size(), 2, "one orphaned and one shadowed override")
	var okinds: Dictionary = {}
	for c in oc:
		var cd: Dictionary = c
		okinds[cd["kind"]] = cd
	t.eq(okinds["override_vs_base"]["prop"], "energy", "override vs base names the property")
	t.eq(okinds["override_vs_base"]["base_new"], 3.0, "carries new base value")
	t.eq(okinds["orphaned_override"]["node"], "Root/Removed", "orphaned override on removed node")
