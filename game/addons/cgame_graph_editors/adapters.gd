@tool
extends RefCounted
## Per-kind adapters for the generic graph editor: node palettes, pin lists, and the
## mapping between each runtime's asset Dictionary and the editor's neutral model.
##
## Supported kinds: visual_script, pcg, vfx, audio, state_tree.
##
## Neutral model (a plain Dictionary so it can be snapshotted for undo):
##   {"nodes": {id: {"type": String, "params": Dictionary, "pos": Vector2, "has_pos": bool}},
##    "conns": [{"from": id, "from_pin": String, "to": id, "to_pin": String}],
##    "meta":  {kind specific top-level asset fields}}
## Pin Dictionary: {"name", "slot" (int, GraphEdit slot type), "multi" (bool: many links
## allowed on this pin), "label", "ptype" (runtime pin type string, PCG only)}.
##
## Original code. The editor UI uses Godot's GraphEdit/GraphNode (Godot Engine, MIT licence).
## The runtimes' formats are read from their sources; the runtimes are not modified.

const VS = preload("res://scripts/shared/visual_script_graph.gd")
const PCG = preload("res://scripts/shared/pcg_graph.gd")
const AG = preload("res://scripts/client/audio_graph.gd")
const VG = preload("res://scripts/client/vfx_graph.gd")
const ST = preload("res://scripts/shared/state_tree.gd")

const KINDS: Array[String] = ["visual_script", "pcg", "vfx", "audio", "state_tree"]
const EXEC_PIN := "@exec"

const AUDIO_IN_TYPES: Array[String] = ["lowpass", "highpass", "bandpass", "smooth", "delay", "gain", "mixer", "clip", "distortion"]
const AUDIO_MOD_KEYS: Array[String] = ["freq", "amp", "cutoff", "q", "gain", "time", "feedback", "rate", "drive", "pw"]

const VFX_SPAWN: Array[String] = [
	"spawn_rate", "spawn_burst", "initial_position_sphere", "initial_position_box", "initial_position_cone",
	"initial_velocity", "lifetime_random", "initial_color", "initial_size", "initial_attribute",
]
const VFX_UPDATE: Array[String] = [
	"gravity", "drag", "curl_noise", "vortex", "attractor", "color_over_life", "size_over_life",
	"collide_plane", "kill_below_plane",
]

static var _pcg_defs_cache: Dictionary = {}


# ---------------------------------------------------------------- generic helpers

static func _p(pin_name: String, slot: int, multi: bool = false, label: String = "", ptype: String = "") -> Dictionary:
	return {"name": pin_name, "slot": slot, "multi": multi, "label": label if label != "" else pin_name, "ptype": ptype}


static func _arr(v: Variant) -> Array:
	if v is Array:
		return v
	return []


static func _dup(v: Variant) -> Variant:
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	return v


static func _dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v
	return {}


static func pin_color(slot: int) -> Color:
	match slot:
		0:
			return Color(0.92, 0.92, 0.92)
		1:
			return Color(0.95, 0.65, 0.25)
		2:
			return Color(0.40, 0.85, 0.50)
	return Color(0.6, 0.7, 0.95)


static func empty_asset(kind: String) -> Dictionary:
	match kind:
		"visual_script":
			return {"variables": {}, "machines": {}, "nodes": {}, "exec": [], "data": []}
		"pcg":
			return {"seed": 0, "nodes": {}, "edges": []}
		"vfx":
			return {"emitters": {}}
		"audio":
			return {"nodes": {}, "connections": [], "output": ""}
		"state_tree":
			return {"name": "", "root": "", "states": {}}
	return {}


static func is_kind(kind: String) -> bool:
	return KINDS.has(kind)


# ---------------------------------------------------------------- JSON codec (keeps int/Vector3/Color exact)

static func encode_value(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_FLOAT, TYPE_STRING:
			return v
		TYPE_INT:
			return {"$int": v}
		TYPE_STRING_NAME:
			return str(v)
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			var d: Dictionary = v
			for k in d:
				out[str(k)] = encode_value(d[k])
			return out
		TYPE_ARRAY:
			var arr_out: Array = []
			var a: Array = v
			for x in a:
				arr_out.append(encode_value(x))
			return arr_out
	return {"$var": var_to_str(v)}


static func decode_value(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = v
		if d.size() == 1 and d.has("$int"):
			return int(d["$int"])
		if d.size() == 1 and d.has("$var"):
			return str_to_var(str(d["$var"]))
		var out: Dictionary = {}
		for k in d:
			out[k] = decode_value(d[k])
		return out
	if v is Array:
		var arr_out: Array = []
		var a: Array = v
		for x in a:
			arr_out.append(decode_value(x))
		return arr_out
	return v


## Text shown in a parameter field. Strings that would be misparsed are quoted.
static func value_to_text(v: Variant) -> String:
	if v is String:
		var s: String = v
		if s == "" or _parses_as_variant(s):
			return var_to_str(s)
		return s
	return var_to_str(v)


static func _parses_as_variant(s: String) -> bool:
	var first: String = s.substr(0, 1)
	if "0123456789-+.[{(\"&".contains(first):
		return true
	return s in ["true", "false", "null", "inf", "nan"] or s.contains("(")


## Parses a parameter field: Godot variant syntax when valid, otherwise a plain string.
static func text_to_value(t: String) -> Variant:
	var s: String = t.strip_edges()
	if _parses_as_variant(s):
		var v: Variant = str_to_var(s)
		if v != null or s == "null":
			return v
	return s


# ---------------------------------------------------------------- palette / defaults / titles

static func palette(kind: String) -> Array[String]:
	var out: Array[String] = []
	match kind:
		"visual_script":
			out.append_array(VS.NODE_TYPES)
		"pcg":
			for k in _pcg_defs():
				out.append(str(k))
			out.append_array(["graph_input", "graph_output"])
		"vfx":
			out.append("emitter")
			out.append_array(VFX_SPAWN)
			out.append_array(VFX_UPDATE)
		"audio":
			for k in AG.DEFAULTS:
				out.append(str(k))
		"state_tree":
			out.append_array(["state", "transition", "end_succeeded", "end_failed"])
	return out


static func default_params(kind: String, type: String) -> Dictionary:
	match kind:
		"visual_script":
			return _vs_defaults(type)
		"pcg":
			return _pcg_defaults(type)
		"vfx":
			return _vfx_defaults(type)
		"audio":
			var d: Dictionary = _dict(AG.DEFAULTS.get(type, {}))
			return d.duplicate(true)
		"state_tree":
			if type == "state":
				return {"conditions": [], "tasks": [], "link": ""}
			if type == "transition":
				return {"trigger": "on_completed", "event": "", "condition": [], "priority": 0}
	return {}


static func node_title(_kind: String, type: String, id: String) -> String:
	if type == id or type == "state" or type == "emitter":
		return id
	return "%s - %s" % [type, id]


static func new_id(type: String, nodes: Dictionary) -> String:
	var n: int = 1
	while nodes.has("%s_%d" % [type, n]):
		n += 1
	return "%s_%d" % [type, n]


## Called after a node was added to the model (kind specific bookkeeping).
static func on_node_added(kind: String, model: Dictionary, id: String) -> void:
	var meta: Dictionary = model["meta"]
	var nodes: Dictionary = model["nodes"]
	var n: Dictionary = nodes[id]
	if kind == "audio" and str(meta.get("output", "")) == "":
		meta["output"] = id
	elif kind == "state_tree" and str(n["type"]) == "state" and str(meta.get("root", "")) == "":
		meta["root"] = id


static func on_node_removed(kind: String, model: Dictionary, id: String) -> void:
	var meta: Dictionary = model["meta"]
	if kind == "audio" and str(meta.get("output", "")) == id:
		meta["output"] = ""
	elif kind == "state_tree" and str(meta.get("root", "")) == id:
		meta["root"] = ""


## Name of the meta field a node can be marked as (audio output, state tree root), or "".
static func entry_field(kind: String) -> String:
	if kind == "audio":
		return "output"
	if kind == "state_tree":
		return "root"
	return ""


# ---------------------------------------------------------------- pins

static func pins(kind: String, type: String, params: Dictionary) -> Dictionary:
	var ins: Array[Dictionary] = []
	var outs: Array[Dictionary] = []
	match kind:
		"visual_script":
			_vs_pins(type, params, ins, outs)
		"pcg":
			_pcg_pins(type, params, ins, outs)
		"vfx":
			_vfx_pins(type, ins, outs)
		"audio":
			_audio_pins(type, ins, outs)
		"state_tree":
			_st_pins(type, ins, outs)
	return {"in": ins, "out": outs}


static func compatible(kind: String, from_pin: Dictionary, to_pin: Dictionary) -> bool:
	if kind == "pcg":
		return PCG.pins_compatible(str(from_pin.get("ptype", "any")), str(to_pin.get("ptype", "any")))
	return int(from_pin["slot"]) == int(to_pin["slot"])


static func _vs_pins(type: String, params: Dictionary, ins: Array[Dictionary], outs: Array[Dictionary]) -> void:
	if type != "event" and not VS.PURE_TYPES.has(type):
		ins.append(_p(EXEC_PIN, 0, true, "exec"))
	match type:
		"event":
			outs.append(_p("out", 0, true, "exec"))
			for o in _arr(params.get("outputs", [])):
				outs.append(_p(str(o), 1, true))
		"branch":
			ins.append(_p("cond", 1))
			outs.append(_p("true", 0, true))
			outs.append(_p("false", 0, true))
		"sequence":
			for i in clampi(int(params.get("count", 2)), 1, 64):
				outs.append(_p(str(i), 0, true, "then %d" % i))
		"for_loop":
			ins.append_array([_p("first", 1), _p("last", 1), _p("max_iter", 1)])
			outs.append_array([_p("body", 0, true), _p("done", 0, true), _p("index", 1, true)])
		"while":
			ins.append_array([_p("cond", 1), _p("max_iter", 1)])
			outs.append_array([_p("body", 0, true), _p("done", 0, true)])
		"set_var":
			ins.append(_p("value", 1))
			outs.append(_p("out", 0, true))
		"get_var", "literal":
			outs.append(_p("value", 1, true))
		"math":
			ins.append_array([_p("a", 1), _p("b", 1), _p("c", 1)])
			outs.append(_p("result", 1, true))
		"call", "emit_rpc":
			for i in clampi(int(params.get("args", 0)), 0, 16):
				ins.append(_p("arg%d" % i, 1))
			outs.append(_p("out", 0, true))
			if type == "call":
				outs.append(_p("result", 1, true))
		"delay":
			ins.append(_p("seconds", 1))
			outs.append(_p("out", 0, true))
		"print":
			ins.append(_p("text", 1))
			outs.append(_p("out", 0, true))
		"state_enter":
			outs.append(_p("out", 0, true))
		"state_transition":
			outs.append_array([_p("out", 0, true), _p("blocked", 0, true)])
		"get_state":
			outs.append(_p("state", 1, true))


static func _vs_defaults(type: String) -> Dictionary:
	match type:
		"event":
			return {"event": "on_start", "outputs": []}
		"sequence":
			return {"count": 2}
		"for_loop", "while":
			return {"max_iter": 1000}
		"set_var", "get_var":
			return {"var": ""}
		"literal":
			return {"value": 0, "value_type": "int"}
		"math":
			return {"op": "add", "cmp": "==", "in": {"a": 0, "b": 0}}
		"call":
			return {"fn": "", "args": 0}
		"delay":
			return {"in": {"seconds": 1.0}}
		"print":
			return {"in": {"text": ""}}
		"emit_rpc":
			return {"rpc": "", "args": 0}
		"state_enter":
			return {"machine": "", "state": ""}
		"state_transition":
			return {"machine": "", "from": "*", "to": ""}
		"get_state":
			return {"machine": ""}
	return {}


static func _pcg_defs() -> Dictionary:
	if _pcg_defs_cache.is_empty():
		var g: RefCounted = PCG.new()
		var d: Dictionary = g.get("_defs")
		_pcg_defs_cache = d
	return _pcg_defs_cache


static func _pcg_pins(type: String, params: Dictionary, ins: Array[Dictionary], outs: Array[Dictionary]) -> void:
	if type == "graph_input":
		outs.append(_p("out", 0, true, "out", str(params.get("pin_type", "any"))))
		return
	if type == "graph_output":
		var pt: String = str(params.get("pin_type", "any"))
		ins.append(_p("in", 0, false, "in: %s" % pt, pt))
		outs.append(_p("value", 0, true, "value", pt))
		return
	var defs: Dictionary = _pcg_defs()
	if not defs.has(type):
		return
	var def: Dictionary = defs[type]
	var din: Dictionary = def["in"]
	var dout: Dictionary = def["out"]
	for k in din:
		var t: String = str(din[k])
		ins.append(_p(str(k), 0, t.ends_with("[]"), "%s: %s" % [k, t], t))
	for k in dout:
		var t2: String = str(dout[k])
		outs.append(_p(str(k), 0, true, "%s: %s" % [k, t2], t2))


static func _pcg_defaults(type: String) -> Dictionary:
	match type:
		"surface_sampler":
			return {"spacing": 2.0, "jitter": 0.5, "density": 1.0}
		"volume_sampler":
			return {"spacing": 2.0, "jitter": 0.5}
		"spline_sampler":
			return {"spacing": 2.0, "mode": "along"}
		"density_noise":
			return {"frequency": 0.05, "min_value": 0.0, "max_value": 1.0, "mode": "set"}
		"density_filter":
			return {"min": 0.0, "max": 1.0, "invert": false}
		"self_pruning":
			return {"min_distance": 1.0, "planar": false}
		"difference":
			return {"distance": 1.0, "planar": true}
		"transform_points":
			return {"scale_min": 1.0, "scale_max": 1.0, "rot_min_deg": 0.0, "rot_max_deg": 360.0}
		"attribute_set":
			return {"name": "custom", "op": "set", "source": "constant", "value": 0.0}
		"partition_by_attribute":
			return {"attribute": "density", "threshold": 0.5}
		"constant_volume":
			return {"center": Vector3.ZERO, "size": Vector3(10, 10, 10)}
		"static_mesh_spawner":
			return {"mesh_id": "mesh"}
		"instanced_scene_output":
			return {"scene_path": ""}
		"material_layer_output":
			return {"attribute": "density", "strength": 1.0, "layer": "layer"}
		"graph_input", "graph_output":
			return {"name": "pin", "pin_type": "any"}
	return {}


static func _audio_pins(type: String, ins: Array[Dictionary], outs: Array[Dictionary]) -> void:
	if AUDIO_IN_TYPES.has(type):
		ins.append(_p("in", 0, true))
	var defs: Dictionary = _dict(AG.DEFAULTS.get(type, {}))
	for k in defs:
		ins.append(_p(str(k), 0, true))
	for k in defs:
		if AUDIO_MOD_KEYS.has(str(k)):
			ins.append(_p("%s_mod" % k, 0, true))
	outs.append(_p("out", 0, true))


static func _vfx_stage(type: String) -> int:
	if VFX_SPAWN.has(type):
		return 1
	if VFX_UPDATE.has(type):
		return 2
	return 0


static func _vfx_pins(type: String, ins: Array[Dictionary], outs: Array[Dictionary]) -> void:
	if type == "emitter":
		outs.append(_p("spawn", 1, false, "spawn"))
		outs.append(_p("update", 2, false, "update"))
		return
	var stage: int = _vfx_stage(type)
	if stage > 0:
		ins.append(_p("in", stage, false, "in"))
		outs.append(_p("next", stage, false, "next"))


static func _vfx_defaults(type: String) -> Dictionary:
	match type:
		"emitter":
			return {"max_particles": 1000, "duration": 0.0, "attributes": {}, "events": {}}
		"spawn_rate":
			return {"rate": 10.0}
		"spawn_burst":
			return {"time": 0.0, "count": 10}
		"initial_position_sphere":
			return {"radius": 1.0, "center": Vector3.ZERO, "surface": false}
		"initial_position_box":
			return {"size": Vector3.ONE, "center": Vector3.ZERO}
		"initial_position_cone":
			return {"axis": Vector3.UP, "angle": 30.0, "height": 1.0, "center": Vector3.ZERO}
		"initial_velocity":
			return {"direction": Vector3.UP, "speed_min": 1.0, "speed_max": 1.0, "spread": 0.0, "radial": 0.0}
		"lifetime_random":
			return {"min": 1.0, "max": 1.0}
		"initial_color":
			return {"color": Color.WHITE}
		"initial_size":
			return {"min": 1.0, "max": 1.0}
		"initial_attribute":
			return {"attribute": "", "min": 0.0, "max": 0.0}
		"gravity":
			return {"gravity": Vector3(0.0, -9.81, 0.0)}
		"drag":
			return {"drag": 1.0}
		"curl_noise":
			return {"strength": 1.0, "frequency": 0.5, "scroll": Vector3.ZERO}
		"vortex":
			return {"center": Vector3.ZERO, "axis": Vector3.UP, "strength": 1.0, "pull": 0.0}
		"attractor":
			return {"position": Vector3.ZERO, "strength": 5.0, "radius": 0.0}
		"color_over_life":
			return {"stops": [[0.0, Color.WHITE], [1.0, Color(1, 1, 1, 0)]]}
		"size_over_life":
			return {"stops": [[0.0, 1.0], [1.0, 0.0]]}
		"collide_plane":
			return {"normal": Vector3.UP, "offset": 0.0, "restitution": 0.5, "friction": 0.0}
		"kill_below_plane":
			return {"normal": Vector3.UP, "offset": 0.0}
	return {}


static func _st_pins(type: String, ins: Array[Dictionary], outs: Array[Dictionary]) -> void:
	match type:
		"state":
			ins.append(_p("parent", 0, false, "parent"))
			ins.append(_p("target", 2, true, "target"))
			outs.append(_p("children", 0, true, "children"))
			outs.append(_p("transitions", 1, true, "transitions"))
		"transition":
			ins.append(_p("from", 1, false, "from"))
			outs.append(_p("target", 2, false, "target"))
		"end_succeeded", "end_failed":
			ins.append(_p("target", 2, true, "target"))


# ---------------------------------------------------------------- model helpers

static func _new_model() -> Dictionary:
	return {"nodes": {}, "conns": [], "meta": {}}


static func _add(model: Dictionary, id: String, type: String, params: Dictionary) -> void:
	var nodes: Dictionary = model["nodes"]
	nodes[id] = {"type": type, "params": params, "pos": Vector2.ZERO, "has_pos": false}


static func _conn(model: Dictionary, from_id: String, from_pin: String, to_id: String, to_pin: String) -> void:
	var conns: Array = model["conns"]
	conns.append({"from": from_id, "from_pin": from_pin, "to": to_id, "to_pin": to_pin})


static func _apply_positions(model: Dictionary, asset: Dictionary) -> void:
	var ed: Dictionary = _dict(asset.get("editor", {}))
	var posd: Dictionary = _dict(ed.get("positions", {}))
	var nodes: Dictionary = model["nodes"]
	for id in nodes:
		var key: String = str(id)
		if posd.has(key):
			var xy: Array = _arr(posd[key])
			if xy.size() == 2:
				var n: Dictionary = nodes[id]
				n["pos"] = Vector2(float(xy[0]), float(xy[1]))
				n["has_pos"] = true
	_auto_layout(model)


## Longest-path column layout for nodes that have no stored position.
static func _auto_layout(model: Dictionary) -> void:
	var nodes: Dictionary = model["nodes"]
	var conns: Array = model["conns"]
	var depth: Dictionary = {}
	for id in nodes:
		depth[id] = 0
	for _i in nodes.size():
		var changed: bool = false
		for c_v in conns:
			var c: Dictionary = c_v
			if depth.has(c["from"]) and depth.has(c["to"]):
				var nd: int = int(depth[c["from"]]) + 1
				if nd > int(depth[c["to"]]) and nd <= nodes.size():
					depth[c["to"]] = nd
					changed = true
		if not changed:
			break
	var rows: Dictionary = {}
	for id in nodes:
		var n: Dictionary = nodes[id]
		if bool(n["has_pos"]):
			continue
		var col: int = int(depth[id])
		var row: int = int(rows.get(col, 0))
		rows[col] = row + 1
		n["pos"] = Vector2(40.0 + col * 320.0, 40.0 + row * 220.0)
		n["has_pos"] = true


static func _positions_into(asset: Dictionary, model: Dictionary, ids: Dictionary) -> void:
	## ids: model id -> asset id (nodes missing from the map are not stored).
	var posd: Dictionary = {}
	var nodes: Dictionary = model["nodes"]
	for id in ids:
		if nodes.has(id):
			var n: Dictionary = nodes[id]
			var p: Vector2 = n["pos"]
			posd[str(ids[id])] = [p.x, p.y]
	asset["editor"] = {"positions": posd}


static func _identity_ids(model: Dictionary) -> Dictionary:
	var m: Dictionary = {}
	var nodes: Dictionary = model["nodes"]
	for id in nodes:
		m[id] = id
	return m


static func _without_type(src: Dictionary) -> Dictionary:
	var p: Dictionary = src.duplicate(true)
	p.erase("type")
	return p


# ---------------------------------------------------------------- asset -> model

static func load_model(kind: String, asset: Dictionary) -> Dictionary:
	var model: Dictionary = _new_model()
	match kind:
		"visual_script":
			_load_vs(asset, model)
		"pcg":
			_load_pcg(asset, model)
		"vfx":
			_load_vfx(asset, model)
		"audio":
			_load_audio(asset, model)
		"state_tree":
			_load_st(asset, model)
	_apply_positions(model, asset)
	return model


static func _load_vs(asset: Dictionary, model: Dictionary) -> void:
	var meta: Dictionary = model["meta"]
	meta["variables"] = _dict(asset.get("variables", {})).duplicate(true)
	meta["machines"] = _dict(asset.get("machines", {})).duplicate(true)
	var nodes: Dictionary = _dict(asset.get("nodes", {}))
	for id in nodes:
		var nd: Dictionary = _dict(nodes[id])
		_add(model, str(id), str(nd.get("type", "")), _without_type(nd))
	for e_v in _arr(asset.get("exec", [])):
		var e: Array = _arr(e_v)
		if e.size() == 3:
			_conn(model, str(e[0]), str(e[1]), str(e[2]), EXEC_PIN)
	for d_v in _arr(asset.get("data", [])):
		var d: Array = _arr(d_v)
		if d.size() == 4:
			_conn(model, str(d[0]), str(d[1]), str(d[2]), str(d[3]))


static func _store_vs(model: Dictionary) -> Dictionary:
	var meta: Dictionary = model["meta"]
	var nodes_out: Dictionary = {}
	var nodes: Dictionary = model["nodes"]
	for id in nodes:
		var n: Dictionary = nodes[id]
		var d: Dictionary = {"type": n["type"]}
		d.merge(_dict(n["params"]).duplicate(true), false)
		nodes_out[id] = d
	var exec_out: Array = []
	var data_out: Array = []
	for c_v in model["conns"]:
		var c: Dictionary = c_v
		if str(c["to_pin"]) == EXEC_PIN:
			exec_out.append([c["from"], c["from_pin"], c["to"]])
		else:
			data_out.append([c["from"], c["from_pin"], c["to"], c["to_pin"]])
	var asset: Dictionary = {
		"variables": _dict(meta.get("variables", {})).duplicate(true),
		"machines": _dict(meta.get("machines", {})).duplicate(true),
		"nodes": nodes_out, "exec": exec_out, "data": data_out,
	}
	_positions_into(asset, model, _identity_ids(model))
	return asset


static func _load_pcg(asset: Dictionary, model: Dictionary) -> void:
	var meta: Dictionary = model["meta"]
	meta["seed"] = int(asset.get("seed", 0))
	var nodes: Dictionary = _dict(asset.get("nodes", {}))
	for id in nodes:
		var nd: Dictionary = _dict(nodes[id])
		_add(model, str(id), str(nd.get("type", "")), _dict(nd.get("params", {})).duplicate(true))
	for e_v in _arr(asset.get("edges", [])):
		var e: Dictionary = _dict(e_v)
		_conn(model, str(e.get("from", "")), str(e.get("from_pin", "")), str(e.get("to", "")), str(e.get("to_pin", "")))


static func _store_pcg(model: Dictionary) -> Dictionary:
	var meta: Dictionary = model["meta"]
	var nodes_out: Dictionary = {}
	var nodes: Dictionary = model["nodes"]
	for id in nodes:
		var n: Dictionary = nodes[id]
		nodes_out[id] = {"type": n["type"], "params": _dict(n["params"]).duplicate(true)}
	var edges: Array = []
	for c_v in model["conns"]:
		var c: Dictionary = c_v
		edges.append({"from": c["from"], "from_pin": c["from_pin"], "to": c["to"], "to_pin": c["to_pin"]})
	var asset: Dictionary = {"seed": int(meta.get("seed", 0)), "nodes": nodes_out, "edges": edges}
	_positions_into(asset, model, _identity_ids(model))
	return asset


## Builds the runtime graph object from a PCG asset (edges are appended raw so validate() sees problems).
static func build_pcg(asset: Dictionary) -> RefCounted:
	var g: RefCounted = PCG.new()
	g.set("graph_seed", int(asset.get("seed", 0)))
	var nodes: Dictionary = _dict(asset.get("nodes", {}))
	for id in nodes:
		var nd: Dictionary = _dict(nodes[id])
		g.call("add_node", str(id), str(nd.get("type", "")), _dict(nd.get("params", {})))
	var edges: Array = g.get("edges")
	for e_v in _arr(asset.get("edges", [])):
		var e: Dictionary = _dict(e_v)
		edges.append({"from": str(e.get("from", "")), "from_pin": str(e.get("from_pin", "")),
				"to": str(e.get("to", "")), "to_pin": str(e.get("to_pin", ""))})
	return g


static func _load_audio(asset: Dictionary, model: Dictionary) -> void:
	var meta: Dictionary = model["meta"]
	meta["output"] = str(asset.get("output", ""))
	var nodes: Dictionary = _dict(asset.get("nodes", {}))
	for id in nodes:
		var nd: Dictionary = _dict(nodes[id])
		_add(model, str(id), str(nd.get("type", "")), _without_type(nd))
	for c_v in _arr(asset.get("connections", [])):
		var c: Array = _arr(c_v)
		if c.size() == 3:
			_conn(model, str(c[0]), "out", str(c[1]), str(c[2]))


static func _store_audio(model: Dictionary) -> Dictionary:
	var meta: Dictionary = model["meta"]
	var nodes_out: Dictionary = {}
	var nodes: Dictionary = model["nodes"]
	for id in nodes:
		var n: Dictionary = nodes[id]
		var d: Dictionary = {"type": n["type"]}
		d.merge(_dict(n["params"]).duplicate(true), false)
		nodes_out[id] = d
	var conns: Array = []
	for c_v in model["conns"]:
		var c: Dictionary = c_v
		conns.append([c["from"], c["to"], c["to_pin"]])
	var asset: Dictionary = {"nodes": nodes_out, "connections": conns, "output": str(meta.get("output", ""))}
	_positions_into(asset, model, _identity_ids(model))
	return asset


static func _vfx_emitters(asset: Dictionary) -> Dictionary:
	var ems: Dictionary = _dict(asset.get("emitters", {}))
	if ems.is_empty() and (asset.has("spawn") or asset.has("update")):
		return {"emitter": asset}
	return ems


static func _load_vfx(asset: Dictionary, model: Dictionary) -> void:
	var ems: Dictionary = _vfx_emitters(asset)
	for name_v in ems:
		var ename: String = str(name_v)
		var em: Dictionary = _dict(ems[name_v])
		var ep: Dictionary = {
			"max_particles": int(em.get("max_particles", 1000)),
			"duration": float(em.get("duration", 0.0)),
			"attributes": _dict(em.get("attributes", {})).duplicate(true),
			"events": _dict(em.get("events", {})).duplicate(true),
		}
		_add(model, ename, "emitter", ep)
		for stage in ["spawn", "update"]:
			var prev: String = ename
			var prev_pin: String = stage
			var lst: Array = _arr(em.get(stage, []))
			for i in lst.size():
				var m: Dictionary = _dict(lst[i])
				var mid: String = "%s.%s.%d" % [ename, stage, i]
				_add(model, mid, str(m.get("type", "")), _without_type(m))
				_conn(model, prev, prev_pin, mid, "in")
				prev = mid
				prev_pin = "next"


static func _vfx_chain(model: Dictionary, emitter_id: String, stage: String, ids: Dictionary) -> Array:
	var out: Array = []
	var conns: Array = model["conns"]
	var nodes: Dictionary = model["nodes"]
	var cur: String = emitter_id
	var pin: String = stage
	var seen: Dictionary = {}
	var idx: int = 0
	while true:
		var nxt: String = ""
		for c_v in conns:
			var c: Dictionary = c_v
			if c["from"] == cur and c["from_pin"] == pin:
				nxt = str(c["to"])
				break
		if nxt == "" or seen.has(nxt) or not nodes.has(nxt):
			break
		seen[nxt] = true
		var n: Dictionary = nodes[nxt]
		var m: Dictionary = {"type": n["type"]}
		m.merge(_dict(n["params"]).duplicate(true), false)
		out.append(m)
		ids[nxt] = "%s.%s.%d" % [emitter_id, stage, idx]
		idx += 1
		cur = nxt
		pin = "next"
	return out


static func _store_vfx(model: Dictionary) -> Dictionary:
	var ems: Dictionary = {}
	var ids: Dictionary = {}
	var nodes: Dictionary = model["nodes"]
	for id in nodes:
		var n: Dictionary = nodes[id]
		if str(n["type"]) != "emitter":
			continue
		var p: Dictionary = _dict(n["params"])
		var em: Dictionary = {
			"max_particles": int(p.get("max_particles", 1000)),
			"duration": float(p.get("duration", 0.0)),
			"spawn": _vfx_chain(model, str(id), "spawn", ids),
			"update": _vfx_chain(model, str(id), "update", ids),
		}
		var attrs: Dictionary = _dict(p.get("attributes", {}))
		if not attrs.is_empty():
			em["attributes"] = attrs.duplicate(true)
		var evs: Dictionary = _dict(p.get("events", {}))
		if not evs.is_empty():
			em["events"] = evs.duplicate(true)
		ems[str(id)] = em
		ids[id] = str(id)
	var asset: Dictionary = {"emitters": ems}
	_positions_into(asset, model, ids)
	return asset


static func _load_st(asset: Dictionary, model: Dictionary) -> void:
	var meta: Dictionary = model["meta"]
	meta["name"] = str(asset.get("name", ""))
	meta["root"] = str(asset.get("root", ""))
	meta["evaluators"] = _arr(asset.get("evaluators", [])).duplicate(true)
	var states: Dictionary = _dict(asset.get("states", {}))
	for sid in states:
		var s: Dictionary = _dict(states[sid])
		var p: Dictionary = {"conditions": _arr(s.get("conditions", [])).duplicate(true),
				"tasks": _arr(s.get("tasks", [])).duplicate(true), "link": str(s.get("link", ""))}
		_add(model, str(sid), "state", p)
	var nodes: Dictionary = model["nodes"]
	for sid in states:
		var sk: String = str(sid)
		var s2: Dictionary = _dict(states[sid])
		for c in _arr(s2.get("children", [])):
			if nodes.has(str(c)):
				_conn(model, sk, "children", str(c), "parent")
		var trs: Array = _arr(s2.get("transitions", []))
		for i in trs.size():
			var tr: Dictionary = _dict(trs[i])
			var tid: String = "%s#t%d" % [sk, i]
			_add(model, tid, "transition", {"trigger": str(tr.get("trigger", "on_completed")), "event": str(tr.get("event", "")),
					"condition": _dup(tr.get("condition", [])),
					"priority": int(tr.get("priority", 0))})
			_conn(model, sk, "transitions", tid, "from")
			var target: String = str(tr.get("target", ""))
			if target == ST.END_SUCCEEDED or target == ST.END_FAILED:
				if not nodes.has(target):
					_add(model, target, "end_succeeded" if target == ST.END_SUCCEEDED else "end_failed", {})
				_conn(model, tid, "target", target, "target")
			elif nodes.has(target):
				_conn(model, tid, "target", target, "target")


static func _store_st(model: Dictionary) -> Dictionary:
	var meta: Dictionary = model["meta"]
	var nodes: Dictionary = model["nodes"]
	var conns: Array = model["conns"]
	var states: Dictionary = {}
	var has_parent: Dictionary = {}
	for id in nodes:
		var n: Dictionary = nodes[id]
		if str(n["type"]) != "state":
			continue
		var p: Dictionary = _dict(n["params"])
		var s: Dictionary = {"children": [], "conditions": p.get("conditions", []), "tasks": p.get("tasks", []), "transitions": []}
		if str(p.get("link", "")) != "":
			s["link"] = str(p["link"])
		states[str(id)] = s
	for c_v in conns:
		var c: Dictionary = c_v
		var from_id: String = str(c["from"])
		var to_id: String = str(c["to"])
		if not states.has(from_id):
			continue
		var s2: Dictionary = states[from_id]
		if str(c["from_pin"]) == "children" and states.has(to_id):
			var kids: Array = s2["children"]
			kids.append(to_id)
			has_parent[to_id] = true
		elif str(c["from_pin"]) == "transitions" and nodes.has(to_id):
			var tn: Dictionary = nodes[to_id]
			if str(tn["type"]) != "transition":
				continue
			var tp: Dictionary = _dict(tn["params"])
			var trs: Array = s2["transitions"]
			trs.append({"trigger": str(tp.get("trigger", "on_completed")), "event": str(tp.get("event", "")),
					"condition": tp.get("condition", []), "target": _st_target(model, to_id), "priority": int(tp.get("priority", 0))})
	var root: String = str(meta.get("root", ""))
	if not states.has(root):
		root = ""
		for sid in states:
			if not has_parent.has(sid):
				root = str(sid)
				break
	var asset: Dictionary = {"name": str(meta.get("name", "")), "root": root, "states": states}
	var evs: Array = _arr(meta.get("evaluators", []))
	if not evs.is_empty():
		asset["evaluators"] = evs.duplicate(true)
	_positions_into(asset, model, _identity_ids(model))
	return asset


static func _st_target(model: Dictionary, transition_id: String) -> String:
	var nodes: Dictionary = model["nodes"]
	for c_v in model["conns"]:
		var c: Dictionary = c_v
		if c["from"] == transition_id and c["from_pin"] == "target" and nodes.has(c["to"]):
			var tn: Dictionary = nodes[c["to"]]
			match str(tn["type"]):
				"state":
					return str(c["to"])
				"end_succeeded":
					return ST.END_SUCCEEDED
				"end_failed":
					return ST.END_FAILED
	return ""


static func store_model(kind: String, model: Dictionary) -> Dictionary:
	match kind:
		"visual_script":
			return _store_vs(model)
		"pcg":
			return _store_pcg(model)
		"vfx":
			return _store_vfx(model)
		"audio":
			return _store_audio(model)
		"state_tree":
			return _store_st(model)
	return {}


# ---------------------------------------------------------------- validation

## Editor-level problems the asset format cannot express (orphans that would be dropped).
static func validate_model(kind: String, model: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var nodes: Dictionary = model["nodes"]
	var conns: Array = model["conns"]
	if kind == "vfx":
		var ids: Dictionary = {}
		_vfx_chain_mark(model, ids)
		for id in nodes:
			var n2: Dictionary = nodes[id]
			if str(n2["type"]) != "emitter" and not ids.has(id):
				errs.append("module %s is not attached to an emitter chain" % id)
	elif kind == "state_tree":
		for id in nodes:
			var n3: Dictionary = nodes[id]
			if str(n3["type"]) != "transition":
				continue
			var owned: bool = false
			for c_v in conns:
				var c: Dictionary = c_v
				if c["to"] == id and c["from_pin"] == "transitions":
					owned = true
			if not owned:
				errs.append("transition %s has no source state" % id)
	return errs


static func _vfx_chain_mark(model: Dictionary, ids: Dictionary) -> void:
	var nodes: Dictionary = model["nodes"]
	for id in nodes:
		var n: Dictionary = nodes[id]
		if str(n["type"]) == "emitter":
			_vfx_chain(model, str(id), "spawn", ids)
			_vfx_chain(model, str(id), "update", ids)


## Delegates to the real runtime. `setup` (optional Callable taking the runtime instance) lets the
## host register functions/tasks/conditions; unless `strict`, unknown names are stubbed so only
## structural problems are reported.
static func validate_asset(kind: String, asset: Dictionary, setup: Callable = Callable(), strict: bool = false) -> Array[String]:
	match kind:
		"visual_script":
			var rt: RefCounted = VS.new()
			if setup.is_valid():
				setup.call(rt)
			if not strict:
				var stub := func() -> Variant: return null
				for n_v in _dict(asset.get("nodes", {})).values():
					var n: Dictionary = _dict(n_v)
					if str(n.get("type", "")) == "call":
						var fname: String = str(n.get("fn", ""))
						if fname != "" and not bool(rt.call("has_function", fname)):
							rt.call("register_function", fname, stub, -1)
			var res: Array[String] = rt.call("validate", asset)
			return res
		"pcg":
			var g: RefCounted = build_pcg(asset)
			if setup.is_valid():
				setup.call(g)
			var pres: Array[String] = g.call("validate")
			return pres
		"audio":
			return AG.validate(asset)
		"vfx":
			return _validate_vfx(asset)
		"state_tree":
			return _validate_st(asset, setup, strict)
	var bad: Array[String] = ["unknown graph kind '%s'" % kind]
	return bad


static func _validate_vfx(asset: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var ems: Dictionary = _vfx_emitters(asset)
	if ems.is_empty():
		errs.append("system has no emitters")
	for name_v in ems:
		var em: Dictionary = _dict(ems[name_v])
		if int(em.get("max_particles", 1000)) < 1:
			errs.append("emitter %s: max_particles must be >= 1" % name_v)
		for stage in ["spawn", "update"]:
			var allowed: Array[String] = VFX_SPAWN if stage == "spawn" else VFX_UPDATE
			for m_v in _arr(em.get(stage, [])):
				var m: Dictionary = _dict(m_v)
				var mt: String = str(m.get("type", ""))
				if not allowed.has(mt):
					errs.append("emitter %s: '%s' is not a %s module" % [name_v, mt, stage])
					continue
				var defs: Dictionary = _vfx_defaults(mt)
				for k in m:
					if str(k) == "type" or not defs.has(k):
						continue
					if not _same_kind(defs[k], m[k]):
						errs.append("emitter %s: %s.%s has the wrong value type" % [name_v, mt, k])
	return errs


static func _same_kind(a: Variant, b: Variant) -> bool:
	var an: bool = typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var bn: bool = typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	return (an and bn) or typeof(a) == typeof(b)


static func _validate_st(asset: Dictionary, setup: Callable, strict: bool) -> Array[String]:
	var rt: RefCounted = ST.new()
	if setup.is_valid():
		setup.call(rt)
	if not strict:
		var tasks: Dictionary = rt.get("_tasks")
		var conds: Dictionary = rt.get("_conditions")
		var evals: Dictionary = rt.get("_evaluators")
		var subs: Dictionary = rt.get("_subtrees")
		var cond_stub := func(_c: Dictionary, _a: Dictionary) -> bool: return true
		var eval_stub := func(_c: Dictionary, _dt: float, _a: Dictionary) -> Variant: return null
		for e in _arr(asset.get("evaluators", [])):
			var en: String = _fn_name(e)
			if en != "" and not evals.has(en):
				rt.call("register_evaluator", en, eval_stub)
		var states: Dictionary = _dict(asset.get("states", {}))
		for sid in states:
			var s: Dictionary = _dict(states[sid])
			for t in _arr(s.get("tasks", [])):
				var tn: String = _fn_name(t)
				if tn != "" and not tasks.has(tn):
					rt.call("register_task", tn)
			_stub_conds(rt, conds, s.get("conditions", []), cond_stub)
			for tr_v in _arr(s.get("transitions", [])):
				_stub_conds(rt, conds, _dict(tr_v).get("condition", []), cond_stub)
			var link: String = str(s.get("link", ""))
			if link != "" and not subs.has(link):
				rt.call("register_subtree", link, {"root": "r", "states": {"r": {}}})
	var res: Array[String] = rt.call("validate", asset)
	return res


static func _fn_name(v: Variant) -> String:
	if v is Dictionary:
		return str(_dict(v).get("fn", ""))
	return str(v)


static func _stub_conds(rt: RefCounted, known: Dictionary, cond: Variant, stub: Callable) -> void:
	if cond is Array:
		for c in _arr(cond):
			_stub_conds(rt, known, c, stub)
	elif cond is String or cond is StringName:
		if str(cond) != "" and not known.has(str(cond)):
			rt.call("register_condition", str(cond), stub)
	elif cond is Dictionary:
		var d: Dictionary = cond
		if d.has("fn") and not known.has(str(d["fn"])):
			rt.call("register_condition", str(d["fn"]), stub)
