extends RefCounted
## Generic GraphEdit-based editor (addons/cgame_graph_editors): load, edit, undo/redo, JSON
## round trip, and that edited assets still load/execute in the real runtimes.

const GraphEditor = preload("res://addons/cgame_graph_editors/graph_editor.gd")
const Adapters = preload("res://addons/cgame_graph_editors/adapters.gd")
const VisualScript = preload("res://scripts/shared/visual_script_graph.gd")
const PCG = preload("res://scripts/shared/pcg_graph.gd")
const VFX = preload("res://scripts/client/vfx_graph.gd")
const AudioGraph = preload("res://scripts/client/audio_graph.gd")
const StateTree = preload("res://scripts/shared/state_tree.gd")


func run(t) -> void:
	_visual_script(t)
	_pcg(t)
	_vfx(t)
	_audio(t)
	_state_tree(t)
	_misc(t)


func _make(kind: String, asset: Dictionary) -> Control:
	var ed: Control = GraphEditor.new()
	ed.call("load_asset", kind, asset)
	return ed


func _json_round_trip(t, ed: Control, kind: String, file_name: String) -> Dictionary:
	var path: String = "user://%s.json" % file_name
	t.eq(ed.call("save_json", path), OK, kind + " saves json")
	var ed2: Control = GraphEditor.new()
	t.check(bool(ed2.call("load_json", path)), kind + " loads json")
	t.eq(ed2.call("node_count"), ed.call("node_count"), kind + " json keeps nodes")
	t.eq(ed2.call("connection_count"), ed.call("connection_count"), kind + " json keeps connections")
	var asset: Dictionary = ed2.call("to_asset")
	t.eq(JSON.stringify(Adapters.encode_value(asset), "", true), JSON.stringify(Adapters.encode_value(ed.call("to_asset")), "", true), kind + " json round trip is exact")
	ed2.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	t.check(not FileAccess.file_exists(path), kind + " temp json removed")
	return asset


func _visual_script(t) -> void:
	t.current = "graph editor: visual script"
	var asset: Dictionary = {
		"variables": {"hp": 10}, "machines": {},
		"nodes": {
			"ev": {"type": "event", "event": "start", "outputs": []},
			"p": {"type": "print", "in": {"text": "hello"}},
		},
		"exec": [["ev", "out", "p"]], "data": [],
	}
	var ed: Control = _make("visual_script", asset)
	t.eq(ed.call("node_count"), 2, "two nodes")
	t.eq(ed.call("connection_count"), 1, "one exec link")
	t.eq(ed.call("view_node_count"), 2, "GraphEdit shows two nodes")
	t.eq(ed.call("view_connection_count"), 1, "GraphEdit shows one link")
	var pid: String = ed.call("add_node", "print", Vector2(300, 0))
	t.eq(pid, "print_1", "auto id")
	var lit: String = ed.call("add_node", "literal", Vector2(0, 200), {"value": 7})
	t.eq(ed.call("connect_nodes", "p", "out", pid, "@exec"), "", "exec link accepted")
	t.eq(ed.call("connect_nodes", lit, "value", pid, "text"), "", "data link accepted")
	t.check(str(ed.call("connect_nodes", "p", "out", pid, "text")) != "", "exec -> data pin refused")
	t.check(str(ed.call("connect_nodes", "ev", "nope", pid, "@exec")) != "", "unknown pin refused")
	t.eq(ed.call("node_count"), 4, "four nodes after add")
	t.eq(ed.call("connection_count"), 3, "three links after connect")
	t.eq(ed.call("view_connection_count"), 3, "view tracks links")
	t.check((ed.call("validate") as Array).is_empty(), "edited graph validates")
	var out: Dictionary = ed.call("to_asset")
	var rt := VisualScript.new()
	t.check(rt.load_graph(out).is_empty(), "runtime loads edited asset")
	rt.fire("start")
	t.eq(rt.print_log.size(), 2, "both prints ran")
	t.eq(rt.print_log[0], "hello", "first print text")
	t.eq(rt.print_log[1], "7", "literal feeds the new print")

	ed.call("undo")
	t.eq(ed.call("connection_count"), 2, "undo removes the data link")
	ed.call("undo")
	t.eq(ed.call("connection_count"), 1, "undo removes the exec link")
	ed.call("undo")
	ed.call("undo")
	t.eq(ed.call("node_count"), 2, "undo removes added nodes")
	t.check(not bool(ed.call("can_undo")), "undo stack empty")
	ed.call("redo")
	ed.call("redo")
	ed.call("redo")
	ed.call("redo")
	t.eq(ed.call("node_count"), 4, "redo restores nodes")
	t.eq(ed.call("connection_count"), 3, "redo restores links")
	t.eq(ed.call("view_node_count"), 4, "view follows redo")

	ed.call("remove_nodes", [lit])
	t.eq(ed.call("connection_count"), 2, "deleting a node drops its links")
	ed.call("undo")
	t.eq(ed.call("connection_count"), 3, "undo delete restores links")
	t.check(bool(ed.call("set_param", "p", "in", {"text": "bye"})), "param edit")
	ed.call("move_node", "p", Vector2(55, 66))
	t.eq(ed.call("node_position", "p"), Vector2(55, 66), "node moved")
	ed.call("set_node_status", "p", "hits=3")
	t.eq(ed.call("get_node_status", "p"), "hits=3", "status overlay stored")
	var reloaded: Dictionary = _json_round_trip(t, ed, "visual_script", "cg_graph_vs")
	var rt2 := VisualScript.new()
	t.check(rt2.load_graph(reloaded).is_empty(), "json reloaded asset loads")
	ed.free()

	var bad: Control = _make("visual_script", {"nodes": {"x": {"type": "branch"}}, "exec": [["x", "true", "ghost"]]})
	t.check(not (bad.call("validate") as Array).is_empty(), "validate reports runtime errors")
	bad.free()


func _pcg(t) -> void:
	t.current = "graph editor: pcg"
	var asset: Dictionary = {
		"seed": 3,
		"nodes": {
			"vol": {"type": "constant_volume", "params": {"center": Vector3.ZERO, "size": Vector3(10, 10, 10)}},
			"samp": {"type": "volume_sampler", "params": {"spacing": 2.0}},
		},
		"edges": [{"from": "vol", "from_pin": "out", "to": "samp", "to_pin": "volume"}],
	}
	var ed: Control = _make("pcg", asset)
	t.eq(ed.call("node_count"), 2, "two nodes")
	t.eq(ed.call("connection_count"), 1, "one edge")
	var flt: String = ed.call("add_node", "density_filter", Vector2(400, 0))
	t.check(str(ed.call("connect_nodes", "vol", "out", flt, "in")) != "", "volume -> points refused")
	t.eq(ed.call("connect_nodes", "samp", "out", flt, "in"), "", "points -> points accepted")
	t.eq(ed.call("connection_count"), 2, "two edges")
	t.check((ed.call("validate") as Array).is_empty(), "pcg validates")
	var out: Dictionary = ed.call("to_asset")
	var g: RefCounted = Adapters.build_pcg(out)
	g.call("execute", {})
	var pts: Variant = g.call("node_output", flt, "out")
	t.check(PCG.point_count(pts) > 0, "edited pcg graph produces points")
	ed.call("undo")
	t.eq(ed.call("connection_count"), 1, "undo edge")
	ed.call("undo")
	t.eq(ed.call("node_count"), 2, "undo node")
	ed.call("redo")
	ed.call("redo")
	t.eq(ed.call("connection_count"), 2, "redo edge")
	var reloaded: Dictionary = _json_round_trip(t, ed, "pcg", "cg_graph_pcg")
	var params: Dictionary = (reloaded["nodes"] as Dictionary)["vol"]["params"]
	t.eq(params["size"], Vector3(10, 10, 10), "Vector3 params survive json")
	ed.free()


func _vfx(t) -> void:
	t.current = "graph editor: vfx"
	var asset: Dictionary = {"emitters": {"fx": {
		"max_particles": 100, "duration": 0.0,
		"spawn": [{"type": "spawn_rate", "rate": 50.0}, {"type": "lifetime_random", "min": 1.0, "max": 1.0}],
		"update": [{"type": "gravity", "gravity": Vector3(0, -9, 0)}],
	}}}
	var ed: Control = _make("vfx", asset)
	t.eq(ed.call("node_count"), 4, "emitter + three modules")
	t.eq(ed.call("connection_count"), 3, "chain links")
	var drag: String = ed.call("add_node", "drag", Vector2(500, 200))
	t.eq(ed.call("connect_nodes", "fx.update.0", "next", drag, "in"), "", "module appended to update chain")
	var sz: String = ed.call("add_node", "initial_size")
	t.check(str(ed.call("connect_nodes", "fx", "update", sz, "in")) != "", "spawn module refused in update chain")
	t.check(not (ed.call("validate") as Array).is_empty(), "detached module is reported")
	ed.call("remove_nodes", [sz])
	t.check((ed.call("validate") as Array).is_empty(), "attached graph validates")
	var out: Dictionary = ed.call("to_asset")
	var update: Array = ((out["emitters"] as Dictionary)["fx"] as Dictionary)["update"]
	t.eq(update.size(), 2, "update chain has two modules")
	t.eq((update[1] as Dictionary)["type"], "drag", "chain order kept")
	var sys: Dictionary = VFX.create_system(out, 1)
	for i in 10:
		VFX.tick(sys, 0.1)
	t.check(VFX.particle_count(sys, "fx") > 0, "edited emitter spawns particles")
	ed.call("undo")
	ed.call("undo")
	ed.call("undo")
	ed.call("undo")
	t.eq(ed.call("node_count"), 4, "undo back to loaded state")
	t.eq(ed.call("connection_count"), 3, "undo restores links")
	ed.call("redo")
	ed.call("redo")
	t.eq(ed.call("node_count"), 5, "redo")
	t.eq(ed.call("connection_count"), 4, "redo link")
	var reloaded: Dictionary = _json_round_trip(t, ed, "vfx", "cg_graph_vfx")
	t.check(not VFX.create_system(reloaded, 2).is_empty(), "json reloaded vfx asset builds")
	ed.free()


func _audio(t) -> void:
	t.current = "graph editor: audio"
	var asset: Dictionary = {
		"nodes": {"osc": {"type": "sine", "freq": 440.0}, "g": {"type": "gain", "gain": 0.5}},
		"connections": [["osc", "g", "in"]], "output": "g",
	}
	var ed: Control = _make("audio", asset)
	t.eq(ed.call("node_count"), 2, "two nodes")
	t.eq(ed.call("connection_count"), 1, "one connection")
	t.eq(ed.call("get_entry"), "g", "output node known")
	var lp: String = ed.call("add_node", "lowpass", Vector2(600, 0), {"cutoff": 800.0})
	t.eq(ed.call("connect_nodes", "g", "out", lp, "in"), "", "gain -> lowpass")
	t.check(bool(ed.call("set_entry", lp)), "lowpass is the output")
	t.check(bool(ed.call("set_param", "osc", "freq", 220.0)), "param edit")
	t.check((ed.call("validate") as Array).is_empty(), "audio validates")
	var out: Dictionary = ed.call("to_asset")
	t.eq((out["connections"] as Array).size(), 2, "two connections")
	t.eq(out["output"], lp, "output stored")
	t.near(float((out["nodes"] as Dictionary)["osc"]["freq"]), 220.0, 0.001, "freq stored")
	var samples: PackedFloat32Array = AudioGraph.render(out, 0.05)
	t.check(samples.size() > 0, "edited audio graph renders")
	var peak: float = 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
	t.check(peak > 0.01, "rendered audio is not silent")
	ed.call("undo")
	ed.call("undo")
	ed.call("undo")
	ed.call("undo")
	t.eq(ed.call("get_entry"), "g", "undo restores output")
	t.eq(ed.call("node_count"), 2, "undo removes lowpass")
	t.near(float(ed.call("node_params", "osc")["freq"]), 440.0, 0.001, "undo restores freq")
	ed.call("redo")
	ed.call("redo")
	ed.call("redo")
	ed.call("redo")
	t.eq(ed.call("get_entry"), lp, "redo output")
	var reloaded: Dictionary = _json_round_trip(t, ed, "audio", "cg_graph_audio")
	t.check(AudioGraph.render(reloaded, 0.02).size() > 0, "json reloaded audio renders")
	# A cycle without a delay must be reported by the real validator.
	ed.call("connect_nodes", lp, "out", "osc", "freq_mod")
	t.check(not (ed.call("validate") as Array).is_empty(), "cycle reported")
	ed.free()


func _state_tree(t) -> void:
	t.current = "graph editor: state tree"
	var asset: Dictionary = {"name": "t", "root": "root", "states": {
		"root": {"children": ["a", "b"]},
		"a": {"tasks": ["wait"], "transitions": [{"trigger": "on_completed", "target": "b"}]},
		"b": {},
	}}
	var ed: Control = _make("state_tree", asset)
	t.eq(ed.call("node_count"), 4, "three states and one transition")
	t.eq(ed.call("connection_count"), 4, "children + transition links")
	t.eq(ed.call("get_entry"), "root", "root known")
	var tr: String = ed.call("add_node", "transition", Vector2(300, 300), {"trigger": "on_event", "event": "stop"})
	var end: String = ed.call("add_node", "end_succeeded", Vector2(600, 300))
	t.eq(ed.call("connect_nodes", "b", "transitions", tr, "from"), "", "state -> transition")
	t.eq(ed.call("connect_nodes", tr, "target", end, "target"), "", "transition -> end")
	t.check(str(ed.call("connect_nodes", "b", "children", "root", "parent")) == "", "hierarchy link accepted (runtime rejects cycles)")
	t.check(not (ed.call("validate") as Array).is_empty(), "hierarchy cycle reported by runtime")
	ed.call("undo")
	t.check((ed.call("validate") as Array).is_empty(), "state tree validates with stubbed names")
	ed.set("strict_names", true)
	t.check(not (ed.call("validate") as Array).is_empty(), "strict mode reports unregistered task")
	ed.set("strict_names", false)
	var out: Dictionary = ed.call("to_asset")
	var b: Dictionary = (out["states"] as Dictionary)["b"]
	var trs: Array = b["transitions"]
	t.eq(trs.size(), 1, "transition exported")
	t.eq((trs[0] as Dictionary)["target"], "$succeeded", "end node becomes $succeeded")
	t.eq((trs[0] as Dictionary)["event"], "stop", "event name kept")
	var rt := StateTree.new()
	rt.register_task("wait")
	t.check(rt.set_asset(out), "runtime accepts edited tree")
	t.check(rt.start({}), "tree starts")
	t.eq(rt.active_path, ["root", "a"] as Array[String], "first child active")
	ed.call("undo")
	ed.call("undo")
	ed.call("undo")
	ed.call("undo")
	t.eq(ed.call("node_count"), 4, "undo to loaded state")
	t.eq(ed.call("connection_count"), 4, "undo links")
	var reloaded: Dictionary = _json_round_trip(t, ed, "state_tree", "cg_graph_st")
	var rt2 := StateTree.new()
	rt2.register_task("wait")
	t.check(rt2.set_asset(reloaded), "json reloaded tree installs")
	ed.free()


func _misc(t) -> void:
	t.current = "graph editor: misc"
	var ed: Control = GraphEditor.new()
	t.check(not bool(ed.call("load_asset", "bogus", {})), "unknown kind rejected")
	t.eq(ed.call("add_node", "sine"), "", "no node without a loaded graph")
	var vals: Array = [5, 5.0, "x", "5", Vector3(1, 2, 3), Color.RED, [1, 2.5], {"a": 1}]
	for v in vals:
		var back: Variant = Adapters.decode_value(JSON.parse_string(JSON.stringify(Adapters.encode_value(v))))
		t.check(typeof(back) == typeof(v) and hash(back) == hash(v), "codec keeps %s" % var_to_str(v))
		var txt: Variant = Adapters.text_to_value(Adapters.value_to_text(v))
		t.check(typeof(txt) == typeof(v) and hash(txt) == hash(v), "param text keeps %s" % var_to_str(v))
	ed.free()
