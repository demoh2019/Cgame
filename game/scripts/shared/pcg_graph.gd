extends RefCounted
## Procedural content graph runtime (UE5 PCG-style): typed point-data graphs with
## subgraphs, an extension API, a dependency-aware incremental cache, a per-node
## debugger and per-world-partition-cell execution.
##
## Original GDScript implementation. Design inspired by the publicly documented
## concepts of Unreal Engine 5's PCG framework (typed pins, point data with
## attributes, subgraphs, partitioned generation, debug capture). No Unreal code
## was copied. The 64-bit integer mixer in mix64() is the public-domain
## SplitMix64 finaliser (Sebastiano Vigna, CC0 / public domain).
##
## DATA (all plain Dictionaries, tagged by "type"):
##   points   {positions: PackedVector3Array, attrs: {density, scale, rotation_y: PackedFloat32Array,
##             seed: PackedInt64Array, <custom>: PackedFloat32Array}}
##   spline   {points: PackedVector3Array, closed: bool}
##   volume   {aabb: AABB}
##   landscape {height_at: Callable(x, z) -> float, normal_at: Callable(x, z) -> Vector3}
##   mesh_instances  {records: [{mesh_id, transforms: Array[Transform3D]}]}
##   scene_instances {records: [{scene_path, transforms: Array[Transform3D]}]}
##   layer_weights   {layer, positions, weights}
## Node outputs are cached and shared; nodes must never mutate their inputs.
##
## PINS: a pin type string is one of the types above or "any". A trailing "[]"
## on an INPUT pin type makes it multi-input (the node receives an Array).
##
## EXTENSION: register_node(type, input_pins, output_pins, execute). The Callable
## may take (inputs), (inputs, params) or (inputs, params, ctx) and must return a
## Dictionary mapping output pin name -> data. ctx holds node_seed (int),
## has_bounds (bool), bounds (AABB, partition cell) and node_id.

const T_POINTS := "points"
const T_SPLINE := "spline"
const T_VOLUME := "volume"
const T_LANDSCAPE := "landscape"
const T_MESHES := "mesh_instances"
const T_SCENES := "scene_instances"
const T_LAYER := "layer_weights"
const T_ANY := "any"

const _BIG := 1.0e6

var graph_seed: int = 0
var nodes: Dictionary = {}
var edges: Array[Dictionary] = []
## Node ids that actually ran in the last execute()/partition_execute() (cache misses), in order.
var executed_nodes: Array[String] = []
var cache_hits: int = 0
var last_errors: Array[String] = []
var debug_enabled: bool = true
var debug_sample_count: int = 5
var debug_capture_full: bool = false
## node id -> {step, type, executed, usec, inputs, outputs, ...}
var debug: Dictionary = {}
## Same entries in dependency order, for step-by-step stepping.
var debug_steps: Array[Dictionary] = []

var _defs: Dictionary = {}
var _cache: Dictionary = {}
var _last_results: Dictionary = {}


func _init() -> void:
	_reg("surface_sampler", {"volume": T_VOLUME, "landscape": T_LANDSCAPE}, {"out": T_POINTS}, _n_surface_sampler)
	_reg("spline_sampler", {"spline": T_SPLINE, "landscape": T_LANDSCAPE}, {"out": T_POINTS}, _n_spline_sampler)
	_reg("volume_sampler", {"volume": T_VOLUME}, {"out": T_POINTS}, _n_volume_sampler)
	_reg("density_noise", {"in": T_POINTS}, {"out": T_POINTS}, _n_density_noise)
	_reg("density_filter", {"in": T_POINTS}, {"out": T_POINTS}, _n_density_filter)
	_reg("self_pruning", {"in": T_POINTS}, {"out": T_POINTS}, _n_self_pruning)
	_reg("difference", {"in": T_POINTS, "other": T_POINTS + "[]"}, {"out": T_POINTS}, _n_difference)
	_reg("transform_points", {"in": T_POINTS}, {"out": T_POINTS}, _n_transform_points)
	_reg("attribute_set", {"in": T_POINTS}, {"out": T_POINTS}, _n_attribute_set)
	_reg("merge", {"in": T_POINTS + "[]"}, {"out": T_POINTS}, _n_merge)
	_reg("partition_by_attribute", {"in": T_POINTS}, {"below": T_POINTS, "above": T_POINTS}, _n_partition_by_attribute)
	_reg("copy_points", {"source": T_POINTS, "target": T_POINTS}, {"out": T_POINTS}, _n_copy_points)
	_reg("constant_volume", {}, {"out": T_VOLUME}, _n_constant_volume)
	_reg("static_mesh_spawner", {"in": T_POINTS}, {"out": T_MESHES}, _n_static_mesh_spawner)
	_reg("instanced_scene_output", {"in": T_POINTS}, {"out": T_SCENES}, _n_instanced_scene_output)
	_reg("material_layer_output", {"in": T_POINTS}, {"out": T_LAYER}, _n_material_layer_output)


# ---------------------------------------------------------------- data constructors

static func make_points(positions: PackedVector3Array = PackedVector3Array()) -> Dictionary:
	var n: int = positions.size()
	var dens := PackedFloat32Array()
	var scl := PackedFloat32Array()
	var rot := PackedFloat32Array()
	var sd := PackedInt64Array()
	dens.resize(n)
	scl.resize(n)
	rot.resize(n)
	sd.resize(n)
	dens.fill(1.0)
	scl.fill(1.0)
	for i in n:
		sd[i] = mix64(hash(positions[i]))
	return _assemble(positions, dens, scl, rot, sd, {})


static func make_spline(pts: PackedVector3Array, closed: bool = false) -> Dictionary:
	return {"type": T_SPLINE, "points": pts, "closed": closed}


static func make_volume(box: AABB) -> Dictionary:
	return {"type": T_VOLUME, "aabb": box}


## height_at(x, z) -> float; normal_at(x, z) -> Vector3 (derived by finite differences when omitted).
static func make_landscape(height_at: Callable, normal_at: Callable = Callable()) -> Dictionary:
	return {"type": T_LANDSCAPE, "height_at": height_at, "normal_at": normal_at}


static func point_count(d: Variant) -> int:
	if d is Dictionary:
		var dd: Dictionary = d
		var t: String = str(dd.get("type", ""))
		if t == T_POINTS or t == T_LAYER:
			var p: PackedVector3Array = dd["positions"]
			return p.size()
		if t == T_SPLINE:
			var sp: PackedVector3Array = dd["points"]
			return sp.size()
		if t == T_MESHES or t == T_SCENES:
			var total: int = 0
			var recs: Array = dd["records"]
			for r: Dictionary in recs:
				var tr: Array = r["transforms"]
				total += tr.size()
			return total
	return 0


static func landscape_height(ls: Variant, x: float, z: float, fallback: float) -> float:
	if ls is Dictionary:
		var d: Dictionary = ls
		var c: Callable = d.get("height_at", Callable())
		if c.is_valid():
			return float(c.call(x, z))
	return fallback


static func landscape_normal(ls: Variant, x: float, z: float) -> Vector3:
	if ls is Dictionary:
		var d: Dictionary = ls
		var nc: Callable = d.get("normal_at", Callable())
		if nc.is_valid():
			return nc.call(x, z)
		var hc: Callable = d.get("height_at", Callable())
		if hc.is_valid():
			var e: float = 0.5
			var dx: float = float(hc.call(x + e, z)) - float(hc.call(x - e, z))
			var dz: float = float(hc.call(x, z + e)) - float(hc.call(x, z - e))
			return Vector3(-dx, 2.0 * e, -dz).normalized()
	return Vector3.UP


# ---------------------------------------------------------------- hashing / random

static func mix64(x: int) -> int:
	var z: int = x + -7046029254386353131
	z = (z ^ (z >> 30)) * -4658895280553007687
	z = (z ^ (z >> 27)) * -7723592293110705685
	return z ^ (z >> 31)


static func hash3(a: int, b: int, c: int) -> int:
	return mix64(mix64(mix64(a) ^ b) ^ c)


static func rand01(h: int) -> float:
	return float(h & 0xFFFFFF) / 16777216.0


# ---------------------------------------------------------------- graph building

func register_node(type_name: String, input_pins: Dictionary, output_pins: Dictionary, execute_fn: Callable) -> void:
	_reg(type_name, input_pins, output_pins, execute_fn)


func add_node(id: String, type_name: String, params: Dictionary = {}) -> String:
	nodes[id] = {"type": type_name, "params": params.duplicate()}
	return id


func set_param(id: String, key: String, value: Variant) -> void:
	if nodes.has(id):
		var node: Dictionary = nodes[id]
		var params: Dictionary = node["params"]
		params[key] = value


func get_param(id: String, key: String, default_value: Variant = null) -> Variant:
	if nodes.has(id):
		var node: Dictionary = nodes[id]
		var params: Dictionary = node["params"]
		return params.get(key, default_value)
	return default_value


## Adds an edge. Returns "" on success, otherwise the validation error (the edge is not added).
func link(from_id: String, from_pin: String, to_id: String, to_pin: String) -> String:
	var err: String = _check_edge(from_id, from_pin, to_id, to_pin)
	if err != "":
		return err
	var to_pins: Dictionary = _node_pins(to_id)["in"]
	if not _is_multi(str(to_pins[to_pin])):
		for e in edges:
			if e["to"] == to_id and e["to_pin"] == to_pin:
				return "pin %s.%s already connected" % [to_id, to_pin]
	edges.append({"from": from_id, "from_pin": from_pin, "to": to_id, "to_pin": to_pin})
	return ""


## Graph inputs/outputs used when this graph is reused as a subgraph.
func add_graph_input(id: String, pin_name: String, pin_type: String) -> String:
	return add_node(id, "graph_input", {"name": pin_name, "pin_type": pin_type})


func add_graph_output(id: String, pin_name: String, pin_type: String) -> String:
	return add_node(id, "graph_output", {"name": pin_name, "pin_type": pin_type})


func get_io_pins(inputs: bool) -> Dictionary:
	var res: Dictionary = {}
	var want: String = "graph_input" if inputs else "graph_output"
	for id: String in nodes:
		var node: Dictionary = nodes[id]
		if node["type"] == want:
			var params: Dictionary = node["params"]
			res[str(params.get("name", id))] = str(params.get("pin_type", T_ANY))
	return res


static func pins_compatible(from_type: String, to_type: String) -> bool:
	var a: String = _base(from_type)
	var b: String = _base(to_type)
	return a == b or a == T_ANY or b == T_ANY


func validate() -> Array[String]:
	var errs: Array[String] = []
	for id: String in nodes:
		var node: Dictionary = nodes[id]
		var type_name: String = node["type"]
		if not _is_known(type_name):
			errs.append("node %s: unknown type %s" % [id, type_name])
		elif type_name == "subgraph":
			var params: Dictionary = node["params"]
			if not (params.get("graph") is RefCounted):
				errs.append("node %s: subgraph has no graph" % id)
	for e in edges:
		var err: String = _check_edge(str(e["from"]), str(e["from_pin"]), str(e["to"]), str(e["to_pin"]))
		if err != "":
			errs.append(err)
	var counts: Dictionary = {}
	for e in edges:
		var key: String = "%s.%s" % [e["to"], e["to_pin"]]
		counts[key] = int(counts.get(key, 0)) + 1
		if int(counts[key]) == 2 and nodes.has(e["to"]):
			var tp: Dictionary = _node_pins(str(e["to"]))["in"]
			if tp.has(e["to_pin"]) and not _is_multi(str(tp[e["to_pin"]])):
				errs.append("pin %s has several inputs but is not a multi-input pin" % key)
	if _has_cycle():
		errs.append("graph contains a cycle")
	return errs


func clear_cache() -> void:
	_cache.clear()


## Hash of the whole graph definition (nodes, params, edges, nested subgraphs).
func structure_hash() -> int:
	var arr: Array = []
	for id: String in nodes:
		var node: Dictionary = nodes[id]
		var params: Dictionary = node["params"]
		arr.append([id, node["type"], _params_hash(params)])
	for e in edges:
		arr.append([e["from"], e["from_pin"], e["to"], e["to_pin"]])
	arr.append(graph_seed)
	return hash(arr)


# ---------------------------------------------------------------- execution

func execute(inputs: Dictionary = {}) -> Dictionary:
	return run_scoped(inputs, "", {}, graph_seed)


## Runs the graph for one world-partition cell. Sampling is restricted to the cell
## (grown by `margin` so neighbour-dependent nodes see context) and the outputs are
## cropped to the exact cell, so the union of all cells equals an unpartitioned run.
func partition_execute(grid_cell: Vector2i, cell_size: float, inputs: Dictionary = {}, margin: float = 0.0) -> Dictionary:
	var x0: float = float(grid_cell.x) * cell_size
	var z0: float = float(grid_cell.y) * cell_size
	var bounds: Dictionary = {
		"has_bounds": true,
		"bounds": AABB(Vector3(x0 - margin, -_BIG, z0 - margin), Vector3(cell_size + 2.0 * margin, 2.0 * _BIG, cell_size + 2.0 * margin)),
	}
	var scope: String = "cell:%d,%d:%s|" % [grid_cell.x, grid_cell.y, str(margin)]
	var out: Dictionary = run_scoped(inputs, scope, bounds, graph_seed)
	var rect := Rect2(x0, z0, cell_size, cell_size)
	var cropped: Dictionary = {}
	for k: String in out:
		cropped[k] = _crop(out[k], rect)
	return cropped


func run_scoped(inputs: Dictionary, scope: String, bounds_ctx: Dictionary, seed_value: int) -> Dictionary:
	executed_nodes.clear()
	cache_hits = 0
	debug.clear()
	debug_steps.clear()
	_last_results = {}
	last_errors = validate()
	if not last_errors.is_empty():
		return {}
	var st: Dictionary = {"inputs": inputs, "scope": scope, "bounds": bounds_ctx, "seed": seed_value, "step": 0}
	var targets: Array[String] = []
	for id: String in nodes:
		var node: Dictionary = nodes[id]
		if node["type"] == "graph_output":
			targets.append(id)
	var out: Dictionary = {}
	if targets.is_empty():
		for id: String in nodes:
			_eval(id, st)
		return out
	for id in targets:
		var r: Dictionary = _eval(id, st)
		var node: Dictionary = nodes[id]
		var params: Dictionary = node["params"]
		var outs: Dictionary = r["outputs"]
		out[str(params.get("name", id))] = outs.get("value")
	return out


func node_output(id: String, pin: String = "out") -> Variant:
	if _last_results.has(id):
		var r: Dictionary = _last_results[id]
		var outs: Dictionary = r["outputs"]
		return outs.get(pin)
	return null


func _eval(id: String, st: Dictionary) -> Dictionary:
	if _last_results.has(id):
		return _last_results[id]
	var node: Dictionary = nodes[id]
	var type_name: String = node["type"]
	var params: Dictionary = node["params"]
	var pins: Dictionary = _node_pins(id)
	var in_pins: Dictionary = pins["in"]
	var ins: Dictionary = {}
	var in_hashes: Array = []
	var in_summ: Dictionary = {}
	for pin: String in in_pins:
		var multi: bool = _is_multi(str(in_pins[pin]))
		var vals: Array = []
		for e in edges:
			if e["to"] == id and e["to_pin"] == pin:
				var src: Dictionary = _eval(str(e["from"]), st)
				var souts: Dictionary = src["outputs"]
				var shashes: Dictionary = src["hashes"]
				vals.append(souts.get(e["from_pin"]))
				in_hashes.append([pin, shashes.get(e["from_pin"], 0)])
		if multi:
			ins[pin] = vals
		else:
			ins[pin] = vals[0] if not vals.is_empty() else null
		if debug_enabled:
			in_summ[pin] = point_count(ins[pin]) if not multi else _sum_counts(vals)
	var seed_value: int = int(st["seed"])
	var node_seed: int = mix64(seed_value + mix64(id.hash()) + int(params.get("seed", 0)))
	var bctx: Dictionary = st["bounds"]
	var ctx: Dictionary = {"node_seed": node_seed, "node_id": id, "has_bounds": bctx.get("has_bounds", false), "bounds": bctx.get("bounds", AABB())}
	var extra: int = 0
	var graph_in_data: Variant = null
	if type_name == "graph_input":
		var gin: Dictionary = st["inputs"]
		graph_in_data = gin.get(str(params.get("name", id)))
		extra = hash(graph_in_data)
	var key: int = hash([type_name, _params_hash(params), node_seed, hash(bctx), in_hashes, extra])
	var cache_key: String = "%s%s" % [st["scope"], id]
	var entry: Dictionary = {}
	var executed: bool = false
	var usec: int = 0
	if _cache.has(cache_key) and int((_cache[cache_key] as Dictionary)["key"]) == key:
		entry = _cache[cache_key]
		cache_hits += 1
	else:
		var t0: int = Time.get_ticks_usec()
		var outs: Dictionary = _exec_node(id, type_name, params, ins, ctx, st, graph_in_data)
		usec = Time.get_ticks_usec() - t0
		var hashes: Dictionary = {}
		for pin: String in outs:
			hashes[pin] = hash(outs[pin])
		entry = {"key": key, "outputs": outs, "hashes": hashes}
		_cache[cache_key] = entry
		executed = true
		executed_nodes.append(id)
	_last_results[id] = entry
	if debug_enabled:
		_capture(id, type_name, executed, usec, in_summ, entry, st)
	return entry


func _exec_node(id: String, type_name: String, params: Dictionary, ins: Dictionary, ctx: Dictionary, st: Dictionary, graph_in_data: Variant) -> Dictionary:
	if type_name == "graph_input":
		return {"out": graph_in_data}
	if type_name == "graph_output":
		return {"value": ins.get("in")}
	if type_name == "subgraph":
		var sub: RefCounted = params["graph"]
		var bctx: Dictionary = st["bounds"]
		var res: Dictionary = sub.call("run_scoped", ins, "%s%s/" % [st["scope"], id], bctx, int(ctx["node_seed"]))
		var sub_exec: Array = sub.get("executed_nodes")
		for s in sub_exec:
			executed_nodes.append("%s/%s" % [id, s])
		return res
	var def: Dictionary = _defs[type_name]
	var fn: Callable = def["exec"]
	var argc: int = fn.get_argument_count()
	var raw: Variant
	if argc == 1:
		raw = fn.call(ins)
	elif argc == 2:
		raw = fn.call(ins, params)
	else:
		raw = fn.call(ins, params, ctx)
	if raw is Dictionary:
		return raw
	return {}


func _capture(id: String, type_name: String, executed: bool, usec: int, in_summ: Dictionary, entry: Dictionary, st: Dictionary) -> void:
	var outs: Dictionary = entry["outputs"]
	var out_summ: Dictionary = {}
	for pin: String in outs:
		out_summ[pin] = summarize(outs[pin], debug_sample_count)
	var rec: Dictionary = {
		"id": id, "step": int(st["step"]), "type": type_name, "executed": executed, "usec": usec,
		"in_counts": in_summ, "outputs": out_summ,
	}
	if debug_capture_full:
		rec["full"] = outs
	st["step"] = int(st["step"]) + 1
	debug[id] = rec
	debug_steps.append(rec)


static func summarize(d: Variant, sample_n: int) -> Dictionary:
	if not (d is Dictionary):
		return {"type": "null", "count": 0}
	var dd: Dictionary = d
	var t: String = str(dd.get("type", "unknown"))
	var res: Dictionary = {"type": t, "count": point_count(dd)}
	if t == T_POINTS:
		var pos: PackedVector3Array = dd["positions"]
		var attrs: Dictionary = dd["attrs"]
		var dens: PackedFloat32Array = attrs["density"]
		var sc: PackedFloat32Array = attrs["scale"]
		var samples: Array = []
		for i in mini(sample_n, pos.size()):
			samples.append({"index": i, "position": pos[i], "density": dens[i], "scale": sc[i]})
		res["sample"] = samples
		if pos.size() > 0:
			var box := AABB(pos[0], Vector3.ZERO)
			for p in pos:
				box = box.expand(p)
			res["bounds"] = box
	elif t == T_VOLUME:
		res["bounds"] = dd["aabb"]
	return res


func _sum_counts(vals: Array) -> int:
	var total: int = 0
	for v in vals:
		total += point_count(v)
	return total


# ---------------------------------------------------------------- pin / registry helpers

func _reg(type_name: String, input_pins: Dictionary, output_pins: Dictionary, execute_fn: Callable) -> void:
	_defs[type_name] = {"in": input_pins.duplicate(), "out": output_pins.duplicate(), "exec": execute_fn}


func _is_known(type_name: String) -> bool:
	return _defs.has(type_name) or type_name == "graph_input" or type_name == "graph_output" or type_name == "subgraph"


static func _base(t: String) -> String:
	return t.trim_suffix("[]")


static func _is_multi(t: String) -> bool:
	return t.ends_with("[]")


func _node_pins(id: String) -> Dictionary:
	var node: Dictionary = nodes[id]
	var type_name: String = node["type"]
	var params: Dictionary = node["params"]
	if type_name == "graph_input":
		return {"in": {}, "out": {"out": str(params.get("pin_type", T_ANY))}}
	if type_name == "graph_output":
		var pt: String = str(params.get("pin_type", T_ANY))
		return {"in": {"in": pt}, "out": {"value": pt}}
	if type_name == "subgraph":
		var sub: Variant = params.get("graph")
		if sub is RefCounted:
			var s: RefCounted = sub
			return {"in": s.call("get_io_pins", true), "out": s.call("get_io_pins", false)}
		return {"in": {}, "out": {}}
	if _defs.has(type_name):
		var def: Dictionary = _defs[type_name]
		return {"in": def["in"], "out": def["out"]}
	return {"in": {}, "out": {}}


func _check_edge(from_id: String, from_pin: String, to_id: String, to_pin: String) -> String:
	if not nodes.has(from_id):
		return "edge: unknown node %s" % from_id
	if not nodes.has(to_id):
		return "edge: unknown node %s" % to_id
	var fp: Dictionary = _node_pins(from_id)["out"]
	var tp: Dictionary = _node_pins(to_id)["in"]
	if not fp.has(from_pin):
		return "edge: %s has no output pin %s" % [from_id, from_pin]
	if not tp.has(to_pin):
		return "edge: %s has no input pin %s" % [to_id, to_pin]
	if not pins_compatible(str(fp[from_pin]), str(tp[to_pin])):
		return "edge: type mismatch %s.%s (%s) -> %s.%s (%s)" % [from_id, from_pin, fp[from_pin], to_id, to_pin, _base(str(tp[to_pin]))]
	return ""


func _has_cycle() -> bool:
	var state: Dictionary = {}
	for id: String in nodes:
		if _dfs_cycle(id, state):
			return true
	return false


func _dfs_cycle(id: String, state: Dictionary) -> bool:
	var s: int = int(state.get(id, 0))
	if s == 1:
		return true
	if s == 2:
		return false
	state[id] = 1
	for e in edges:
		if e["to"] == id and nodes.has(e["from"]):
			if _dfs_cycle(str(e["from"]), state):
				return true
	state[id] = 2
	return false


func _params_hash(params: Dictionary) -> int:
	var copy: Dictionary = params.duplicate()
	var sub: Variant = copy.get("graph")
	if sub is RefCounted:
		var s: RefCounted = sub
		copy["graph"] = int(s.call("structure_hash"))
	return hash(copy)


# ---------------------------------------------------------------- point data helpers

static func _assemble(pos: PackedVector3Array, dens: PackedFloat32Array, scl: PackedFloat32Array, rot: PackedFloat32Array, sd: PackedInt64Array, extras: Dictionary) -> Dictionary:
	var attrs: Dictionary = {"density": dens, "scale": scl, "rotation_y": rot, "seed": sd}
	for k: String in extras:
		attrs[k] = extras[k]
	return {"type": T_POINTS, "positions": pos, "attrs": attrs}


static func _empty_points() -> Dictionary:
	return _assemble(PackedVector3Array(), PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedInt64Array(), {})


static func _in_pts(inputs: Dictionary, pin: String) -> Dictionary:
	var v: Variant = inputs.get(pin)
	if v is Dictionary:
		var d: Dictionary = v
		if d.get("type") == T_POINTS:
			return d
	return _empty_points()


static func _select(pts: Dictionary, idx: PackedInt32Array) -> Dictionary:
	var pos: PackedVector3Array = pts["positions"]
	var attrs: Dictionary = pts["attrs"]
	var npos := PackedVector3Array()
	npos.resize(idx.size())
	for j in idx.size():
		npos[j] = pos[idx[j]]
	var out_attrs: Dictionary = {}
	for k: String in attrs:
		var src: Variant = attrs[k]
		if src is PackedInt64Array:
			var si: PackedInt64Array = src
			var di := PackedInt64Array()
			di.resize(idx.size())
			for j in idx.size():
				di[j] = si[idx[j]]
			out_attrs[k] = di
		else:
			var sf: PackedFloat32Array = src
			var df := PackedFloat32Array()
			df.resize(idx.size())
			for j in idx.size():
				df[j] = sf[idx[j]]
			out_attrs[k] = df
	return {"type": T_POINTS, "positions": npos, "attrs": out_attrs}


static func _attr_f(attrs: Dictionary, name_key: String, i: int) -> float:
	var v: Variant = attrs.get(name_key)
	if v is PackedFloat32Array:
		var pf: PackedFloat32Array = v
		return pf[i]
	if v is PackedInt64Array:
		var pi: PackedInt64Array = v
		return float(pi[i])
	return 0.0


static func _grid_key(ix: int, iy: int, iz: int) -> int:
	return (ix & 0x1FFFFF) | ((iy & 0x1FFFFF) << 21) | ((iz & 0x1FFFFF) << 42)


static func _cell_of(p: Vector3, cell: float, planar: bool) -> Vector3i:
	return Vector3i(floori(p.x / cell), 0 if planar else floori(p.y / cell), floori(p.z / cell))


static func _grid_add(grid: Dictionary, p: Vector3, idx: int, cell: float, planar: bool) -> void:
	var c: Vector3i = _cell_of(p, cell, planar)
	var k: int = _grid_key(c.x, c.y, c.z)
	var arr: PackedInt32Array = grid.get(k, PackedInt32Array())
	arr.append(idx)
	grid[k] = arr


static func _grid_near(grid: Dictionary, pos: PackedVector3Array, p: Vector3, dist: float, cell: float, planar: bool) -> bool:
	var c: Vector3i = _cell_of(p, cell, planar)
	var d2: float = dist * dist
	var ylo: int = 0 if planar else -1
	var yhi: int = 0 if planar else 1
	for dx in range(-1, 2):
		for dy in range(ylo, yhi + 1):
			for dz in range(-1, 2):
				var k: int = _grid_key(c.x + dx, c.y + dy, c.z + dz)
				if grid.has(k):
					var arr: PackedInt32Array = grid[k]
					for i in arr:
						var q: Vector3 = pos[i]
						var dd: float
						if planar:
							dd = (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
						else:
							dd = q.distance_squared_to(p)
						if dd < d2:
							return true
	return false


static func _in_rect(r: Rect2, x: float, z: float) -> bool:
	return x >= r.position.x and x < r.position.x + r.size.x and z >= r.position.y and z < r.position.y + r.size.y


## Sampling area in xz: the volume (when given) intersected with the partition cell.
static func _area(box: AABB, ctx: Dictionary, use_box: bool) -> Rect2:
	var lo := Vector2(-_BIG, -_BIG)
	var hi := Vector2(_BIG, _BIG)
	if use_box:
		lo = Vector2(box.position.x, box.position.z)
		hi = Vector2(box.end.x, box.end.z)
	if ctx.get("has_bounds", false):
		var b: AABB = ctx["bounds"]
		lo.x = maxf(lo.x, b.position.x)
		lo.y = maxf(lo.y, b.position.z)
		hi.x = minf(hi.x, b.end.x)
		hi.y = minf(hi.y, b.end.z)
	return Rect2(lo, Vector2(maxf(hi.x - lo.x, 0.0), maxf(hi.y - lo.y, 0.0)))


static func _crop(d: Variant, rect: Rect2) -> Variant:
	if not (d is Dictionary):
		return d
	var dd: Dictionary = d
	var t: String = str(dd.get("type", ""))
	if t == T_POINTS:
		var pos: PackedVector3Array = dd["positions"]
		var idx := PackedInt32Array()
		for i in pos.size():
			if _in_rect(rect, pos[i].x, pos[i].z):
				idx.append(i)
		return _select(dd, idx)
	if t == T_LAYER:
		var lp: PackedVector3Array = dd["positions"]
		var lw: PackedFloat32Array = dd["weights"]
		var np := PackedVector3Array()
		var nw := PackedFloat32Array()
		for i in lp.size():
			if _in_rect(rect, lp[i].x, lp[i].z):
				np.append(lp[i])
				nw.append(lw[i])
		return {"type": T_LAYER, "layer": dd["layer"], "positions": np, "weights": nw}
	if t == T_MESHES or t == T_SCENES:
		var recs: Array = dd["records"]
		var out_recs: Array = []
		for r: Dictionary in recs:
			var trs: Array = r["transforms"]
			var kept: Array = []
			for tr: Transform3D in trs:
				if _in_rect(rect, tr.origin.x, tr.origin.z):
					kept.append(tr)
			var nr: Dictionary = r.duplicate()
			nr["transforms"] = kept
			out_recs.append(nr)
		return {"type": t, "records": out_recs}
	return d


static func _fparam(params: Dictionary, key: String, default_value: float) -> float:
	return float(params.get(key, default_value))


# ---------------------------------------------------------------- built-in nodes

func _n_constant_volume(_inputs: Dictionary, params: Dictionary, _ctx: Dictionary) -> Dictionary:
	var c: Vector3 = params.get("center", Vector3.ZERO)
	var s: Vector3 = params.get("size", Vector3(10, 10, 10))
	return {"out": make_volume(AABB(c - s * 0.5, s))}


func _n_surface_sampler(inputs: Dictionary, params: Dictionary, ctx: Dictionary) -> Dictionary:
	var vol: Variant = inputs.get("volume")
	if not (vol is Dictionary):
		return {"out": _empty_points()}
	var vd: Dictionary = vol
	var box: AABB = vd["aabb"]
	var spacing: float = maxf(_fparam(params, "spacing", 2.0), 0.05)
	var jitter: float = clampf(_fparam(params, "jitter", 0.5), 0.0, 1.0)
	var base_density: float = _fparam(params, "density", 1.0)
	var ns: int = int(ctx["node_seed"])
	var area: Rect2 = _area(box, ctx, true)
	var ls: Variant = inputs.get("landscape")
	var pos := PackedVector3Array()
	var dens := PackedFloat32Array()
	var scl := PackedFloat32Array()
	var rot := PackedFloat32Array()
	var sd := PackedInt64Array()
	var slope := PackedFloat32Array()
	if area.size.x > 0.0 and area.size.y > 0.0:
		var ix0: int = floori(area.position.x / spacing) - 1
		var ix1: int = ceili((area.position.x + area.size.x) / spacing) + 1
		var iz0: int = floori(area.position.y / spacing) - 1
		var iz1: int = ceili((area.position.y + area.size.y) / spacing) + 1
		for ix in range(ix0, ix1 + 1):
			for iz in range(iz0, iz1 + 1):
				var h: int = hash3(ns, ix, iz)
				var x: float = (float(ix) + 0.5 + (rand01(mix64(h + 1)) - 0.5) * jitter) * spacing
				var z: float = (float(iz) + 0.5 + (rand01(mix64(h + 2)) - 0.5) * jitter) * spacing
				if not _in_rect(area, x, z):
					continue
				var y: float = landscape_height(ls, x, z, box.position.y)
				pos.append(Vector3(x, y, z))
				dens.append(base_density)
				scl.append(1.0)
				rot.append(0.0)
				sd.append(h)
				slope.append(landscape_normal(ls, x, z).y)
	return {"out": _assemble(pos, dens, scl, rot, sd, {"slope": slope})}


func _n_volume_sampler(inputs: Dictionary, params: Dictionary, ctx: Dictionary) -> Dictionary:
	var vol: Variant = inputs.get("volume")
	if not (vol is Dictionary):
		return {"out": _empty_points()}
	var vd: Dictionary = vol
	var box: AABB = vd["aabb"]
	var spacing: float = maxf(_fparam(params, "spacing", 2.0), 0.05)
	var jitter: float = clampf(_fparam(params, "jitter", 0.5), 0.0, 1.0)
	var ns: int = int(ctx["node_seed"])
	var area: Rect2 = _area(box, ctx, true)
	var pos := PackedVector3Array()
	var dens := PackedFloat32Array()
	var scl := PackedFloat32Array()
	var rot := PackedFloat32Array()
	var sd := PackedInt64Array()
	if area.size.x > 0.0 and area.size.y > 0.0:
		var iy0: int = floori(box.position.y / spacing) - 1
		var iy1: int = ceili(box.end.y / spacing) + 1
		var ix0: int = floori(area.position.x / spacing) - 1
		var ix1: int = ceili((area.position.x + area.size.x) / spacing) + 1
		var iz0: int = floori(area.position.y / spacing) - 1
		var iz1: int = ceili((area.position.y + area.size.y) / spacing) + 1
		for ix in range(ix0, ix1 + 1):
			for iy in range(iy0, iy1 + 1):
				for iz in range(iz0, iz1 + 1):
					var h: int = mix64(hash3(ns, ix, iz) ^ iy)
					var p := Vector3(
						(float(ix) + 0.5 + (rand01(mix64(h + 1)) - 0.5) * jitter) * spacing,
						(float(iy) + 0.5 + (rand01(mix64(h + 2)) - 0.5) * jitter) * spacing,
						(float(iz) + 0.5 + (rand01(mix64(h + 3)) - 0.5) * jitter) * spacing)
					if not _in_rect(area, p.x, p.z) or p.y < box.position.y or p.y >= box.end.y:
						continue
					pos.append(p)
					dens.append(1.0)
					scl.append(1.0)
					rot.append(0.0)
					sd.append(h)
	return {"out": _assemble(pos, dens, scl, rot, sd, {})}


## mode "along": a point every `spacing` metres at `lateral_offset` from the path.
## mode "around": per step, one point on each side at a random distance in [band_inner, band_outer].
func _n_spline_sampler(inputs: Dictionary, params: Dictionary, ctx: Dictionary) -> Dictionary:
	var sp: Variant = inputs.get("spline")
	if not (sp is Dictionary):
		return {"out": _empty_points()}
	var sd_: Dictionary = sp
	var line: PackedVector3Array = sd_["points"]
	if bool(sd_.get("closed", false)) and line.size() > 1:
		line = line.duplicate()
		line.append(line[0])
	var spacing: float = maxf(_fparam(params, "spacing", 2.0), 0.05)
	var mode: String = str(params.get("mode", "along"))
	var lateral: float = _fparam(params, "lateral_offset", 0.0)
	var inner: float = _fparam(params, "band_inner", 1.0)
	var outer: float = _fparam(params, "band_outer", 4.0)
	var ns: int = int(ctx["node_seed"])
	var area: Rect2 = _area(AABB(), ctx, false)
	var ls: Variant = inputs.get("landscape")
	var use_land: bool = ls is Dictionary
	var pos := PackedVector3Array()
	var dens := PackedFloat32Array()
	var scl := PackedFloat32Array()
	var rot := PackedFloat32Array()
	var sd := PackedInt64Array()
	if line.size() >= 2:
		var total: float = 0.0
		var cum := PackedFloat32Array()
		cum.append(0.0)
		for i in range(1, line.size()):
			total += line[i - 1].distance_to(line[i])
			cum.append(total)
		var seg: int = 0
		var steps: int = floori(total / spacing)
		for k in range(0, steps + 1):
			var s: float = float(k) * spacing
			while seg < line.size() - 2 and cum[seg + 1] < s:
				seg += 1
			var seg_len: float = cum[seg + 1] - cum[seg]
			var f: float = 0.0 if seg_len <= 0.0 else (s - cum[seg]) / seg_len
			var p: Vector3 = line[seg].lerp(line[seg + 1], f)
			var tangent := Vector3(line[seg + 1].x - line[seg].x, 0.0, line[seg + 1].z - line[seg].z)
			tangent = tangent.normalized() if tangent.length() > 0.0001 else Vector3.RIGHT
			var side := Vector3(-tangent.z, 0.0, tangent.x)
			var yaw: float = atan2(tangent.x, tangent.z)
			var offs: Array[float] = []
			if mode == "around":
				var h: int = hash3(ns, k, 0)
				offs.append(lerpf(inner, outer, rand01(mix64(h + 1))))
				offs.append(-lerpf(inner, outer, rand01(mix64(h + 2))))
			else:
				offs.append(lateral)
			var side_i: int = 0
			for o in offs:
				var q: Vector3 = p + side * o
				side_i += 1
				if not _in_rect(area, q.x, q.z):
					continue
				if use_land:
					q.y = landscape_height(ls, q.x, q.z, q.y)
				pos.append(q)
				dens.append(1.0)
				scl.append(1.0)
				rot.append(yaw)
				sd.append(hash3(ns, k, side_i))
	return {"out": _assemble(pos, dens, scl, rot, sd, {})}


func _n_density_noise(inputs: Dictionary, params: Dictionary, ctx: Dictionary) -> Dictionary:
	var pts: Dictionary = _in_pts(inputs, "in")
	var pos: PackedVector3Array = pts["positions"]
	var attrs: Dictionary = pts["attrs"]
	var dens: PackedFloat32Array = (attrs["density"] as PackedFloat32Array).duplicate()
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = int(int(ctx["node_seed"]) & 0x7FFFFFFF)
	noise.frequency = _fparam(params, "frequency", 0.05)
	var lo: float = _fparam(params, "min_value", 0.0)
	var hi: float = _fparam(params, "max_value", 1.0)
	var multiply: bool = str(params.get("mode", "set")) == "multiply"
	for i in pos.size():
		var n: float = (noise.get_noise_2d(pos[i].x, pos[i].z) + 1.0) * 0.5
		var v: float = lerpf(lo, hi, clampf(n, 0.0, 1.0))
		dens[i] = dens[i] * v if multiply else v
	var out_attrs: Dictionary = attrs.duplicate()
	out_attrs["density"] = dens
	return {"out": {"type": T_POINTS, "positions": pos, "attrs": out_attrs}}


func _n_density_filter(inputs: Dictionary, params: Dictionary, _ctx: Dictionary) -> Dictionary:
	var pts: Dictionary = _in_pts(inputs, "in")
	var attrs: Dictionary = pts["attrs"]
	var dens: PackedFloat32Array = attrs["density"]
	var lo: float = _fparam(params, "min", 0.0)
	var hi: float = _fparam(params, "max", 1.0)
	var invert: bool = bool(params.get("invert", false))
	var idx := PackedInt32Array()
	for i in dens.size():
		var inside: bool = dens[i] >= lo and dens[i] <= hi
		if inside != invert:
			idx.append(i)
	return {"out": _select(pts, idx)}


## Greedy min-distance pruning; the highest density (then seed) point wins, so the result is
## independent of point order.
func _n_self_pruning(inputs: Dictionary, params: Dictionary, _ctx: Dictionary) -> Dictionary:
	var pts: Dictionary = _in_pts(inputs, "in")
	var pos: PackedVector3Array = pts["positions"]
	var attrs: Dictionary = pts["attrs"]
	var dens: PackedFloat32Array = attrs["density"]
	var seeds: PackedInt64Array = attrs["seed"]
	var dist: float = maxf(_fparam(params, "min_distance", 1.0), 0.001)
	var planar: bool = bool(params.get("planar", false))
	var order: Array = range(pos.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		if dens[a] != dens[b]:
			return dens[a] > dens[b]
		if seeds[a] != seeds[b]:
			return seeds[a] > seeds[b]
		return a < b)
	var grid: Dictionary = {}
	var kept_pos := PackedVector3Array()
	var keep := PackedInt32Array()
	for i: int in order:
		if _grid_near(grid, kept_pos, pos[i], dist, dist, planar):
			continue
		_grid_add(grid, pos[i], kept_pos.size(), dist, planar)
		kept_pos.append(pos[i])
		keep.append(i)
	keep.sort()
	return {"out": _select(pts, keep)}


func _n_difference(inputs: Dictionary, params: Dictionary, _ctx: Dictionary) -> Dictionary:
	var pts: Dictionary = _in_pts(inputs, "in")
	var pos: PackedVector3Array = pts["positions"]
	var dist: float = maxf(_fparam(params, "distance", 1.0), 0.001)
	var planar: bool = bool(params.get("planar", true))
	var others_pos := PackedVector3Array()
	var others: Array = inputs.get("other", [])
	for o in others:
		if o is Dictionary:
			var od: Dictionary = o
			if od.get("type") == T_POINTS:
				others_pos.append_array(od["positions"])
	var grid: Dictionary = {}
	for j in others_pos.size():
		_grid_add(grid, others_pos[j], j, dist, planar)
	var keep := PackedInt32Array()
	for i in pos.size():
		if not _grid_near(grid, others_pos, pos[i], dist, dist, planar):
			keep.append(i)
	return {"out": _select(pts, keep)}


func _n_transform_points(inputs: Dictionary, params: Dictionary, ctx: Dictionary) -> Dictionary:
	var pts: Dictionary = _in_pts(inputs, "in")
	var attrs: Dictionary = pts["attrs"]
	var scl: PackedFloat32Array = (attrs["scale"] as PackedFloat32Array).duplicate()
	var rot: PackedFloat32Array = (attrs["rotation_y"] as PackedFloat32Array).duplicate()
	var seeds: PackedInt64Array = attrs["seed"]
	var smin: float = _fparam(params, "scale_min", 1.0)
	var smax: float = _fparam(params, "scale_max", 1.0)
	var rmin: float = deg_to_rad(_fparam(params, "rot_min_deg", 0.0))
	var rmax: float = deg_to_rad(_fparam(params, "rot_max_deg", 360.0))
	var ns: int = int(ctx["node_seed"])
	for i in scl.size():
		var h: int = mix64(seeds[i] ^ ns)
		scl[i] = scl[i] * lerpf(smin, smax, rand01(mix64(h + 1)))
		rot[i] = rot[i] + lerpf(rmin, rmax, rand01(mix64(h + 2)))
	var out_attrs: Dictionary = attrs.duplicate()
	out_attrs["scale"] = scl
	out_attrs["rotation_y"] = rot
	return {"out": {"type": T_POINTS, "positions": pts["positions"], "attrs": out_attrs}}


## params: name (density/scale/rotation_y/custom), value, op (set/add/mul), source (constant/height).
func _n_attribute_set(inputs: Dictionary, params: Dictionary, _ctx: Dictionary) -> Dictionary:
	var pts: Dictionary = _in_pts(inputs, "in")
	var pos: PackedVector3Array = pts["positions"]
	var attrs: Dictionary = pts["attrs"]
	var attr_name: String = str(params.get("name", "custom"))
	var op: String = str(params.get("op", "set"))
	var from_height: bool = str(params.get("source", "constant")) == "height"
	var value: float = _fparam(params, "value", 0.0)
	var arr := PackedFloat32Array()
	if attrs.has(attr_name) and attrs[attr_name] is PackedFloat32Array:
		arr = (attrs[attr_name] as PackedFloat32Array).duplicate()
	else:
		arr.resize(pos.size())
	for i in pos.size():
		var v: float = value * pos[i].y if from_height else value
		if op == "add":
			arr[i] += v
		elif op == "mul":
			arr[i] *= v
		else:
			arr[i] = v
	var out_attrs: Dictionary = attrs.duplicate()
	out_attrs[attr_name] = arr
	return {"out": {"type": T_POINTS, "positions": pos, "attrs": out_attrs}}


func _n_merge(inputs: Dictionary, _params: Dictionary, _ctx: Dictionary) -> Dictionary:
	var sets: Array = inputs.get("in", [])
	var pos := PackedVector3Array()
	var dens := PackedFloat32Array()
	var scl := PackedFloat32Array()
	var rot := PackedFloat32Array()
	var sd := PackedInt64Array()
	var custom_keys: Array[String] = []
	for s in sets:
		if s is Dictionary and (s as Dictionary).get("type") == T_POINTS:
			var a: Dictionary = (s as Dictionary)["attrs"]
			for k: String in a:
				if not (k in ["density", "scale", "rotation_y", "seed"]) and not custom_keys.has(k):
					custom_keys.append(k)
	var extras: Dictionary = {}
	for k in custom_keys:
		extras[k] = PackedFloat32Array()
	for s in sets:
		if not (s is Dictionary and (s as Dictionary).get("type") == T_POINTS):
			continue
		var d: Dictionary = s
		var p: PackedVector3Array = d["positions"]
		var a: Dictionary = d["attrs"]
		pos.append_array(p)
		dens.append_array(a["density"])
		scl.append_array(a["scale"])
		rot.append_array(a["rotation_y"])
		sd.append_array(a["seed"])
		for k in custom_keys:
			var ea: PackedFloat32Array = extras[k]
			if a.has(k):
				ea.append_array(a[k])
			else:
				var pad := PackedFloat32Array()
				pad.resize(p.size())
				ea.append_array(pad)
			extras[k] = ea
	return {"out": _assemble(pos, dens, scl, rot, sd, extras)}


## Splits points on attribute >= threshold ("above") versus < threshold ("below").
func _n_partition_by_attribute(inputs: Dictionary, params: Dictionary, _ctx: Dictionary) -> Dictionary:
	var pts: Dictionary = _in_pts(inputs, "in")
	var attrs: Dictionary = pts["attrs"]
	var pos: PackedVector3Array = pts["positions"]
	var attr_name: String = str(params.get("attribute", "density"))
	var thr: float = _fparam(params, "threshold", 0.5)
	var lo := PackedInt32Array()
	var hi := PackedInt32Array()
	for i in pos.size():
		if _attr_f(attrs, attr_name, i) >= thr:
			hi.append(i)
		else:
			lo.append(i)
	return {"below": _select(pts, lo), "above": _select(pts, hi)}


## Instances every source point onto every target point (target scale/yaw applied).
func _n_copy_points(inputs: Dictionary, _params: Dictionary, _ctx: Dictionary) -> Dictionary:
	var src: Dictionary = _in_pts(inputs, "source")
	var tgt: Dictionary = _in_pts(inputs, "target")
	var sp: PackedVector3Array = src["positions"]
	var sa: Dictionary = src["attrs"]
	var tp: PackedVector3Array = tgt["positions"]
	var ta: Dictionary = tgt["attrs"]
	var pos := PackedVector3Array()
	var dens := PackedFloat32Array()
	var scl := PackedFloat32Array()
	var rot := PackedFloat32Array()
	var sd := PackedInt64Array()
	for t in tp.size():
		var t_scale: float = _attr_f(ta, "scale", t)
		var t_rot: float = _attr_f(ta, "rotation_y", t)
		var basis := Basis(Vector3.UP, t_rot)
		for s in sp.size():
			pos.append(tp[t] + basis * (sp[s] * t_scale))
			dens.append(_attr_f(ta, "density", t) * _attr_f(sa, "density", s))
			scl.append(t_scale * _attr_f(sa, "scale", s))
			rot.append(t_rot + _attr_f(sa, "rotation_y", s))
			sd.append(hash3(int(_attr_f(ta, "seed", t)), int(_attr_f(sa, "seed", s)), 7))
	return {"out": _assemble(pos, dens, scl, rot, sd, {})}


func _point_transform(pos: Vector3, scale_v: float, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_v), pos)


## params: mesh_id, or meshes: [{id, weight}] chosen per point by seed. Output records {mesh_id, transforms}.
func _n_static_mesh_spawner(inputs: Dictionary, params: Dictionary, ctx: Dictionary) -> Dictionary:
	var pts: Dictionary = _in_pts(inputs, "in")
	var pos: PackedVector3Array = pts["positions"]
	var attrs: Dictionary = pts["attrs"]
	var ns: int = int(ctx["node_seed"])
	var meshes: Array = params.get("meshes", [])
	if meshes.is_empty():
		meshes = [{"id": str(params.get("mesh_id", "mesh")), "weight": 1.0}]
	var total_w: float = 0.0
	for m: Dictionary in meshes:
		total_w += float(m.get("weight", 1.0))
	var buckets: Dictionary = {}
	var order: Array[String] = []
	for m: Dictionary in meshes:
		var mid: String = str(m["id"])
		if not buckets.has(mid):
			buckets[mid] = []
			order.append(mid)
	for i in pos.size():
		var roll: float = rand01(mix64(int(_attr_f(attrs, "seed", i)) ^ ns)) * total_w
		var chosen: String = order[0]
		var acc: float = 0.0
		for m: Dictionary in meshes:
			acc += float(m.get("weight", 1.0))
			if roll < acc:
				chosen = str(m["id"])
				break
		var list: Array = buckets[chosen]
		list.append(_point_transform(pos[i], _attr_f(attrs, "scale", i), _attr_f(attrs, "rotation_y", i)))
	var records: Array = []
	for mid in order:
		records.append({"mesh_id": mid, "transforms": buckets[mid]})
	return {"out": {"type": T_MESHES, "records": records}}


func _n_instanced_scene_output(inputs: Dictionary, params: Dictionary, _ctx: Dictionary) -> Dictionary:
	var pts: Dictionary = _in_pts(inputs, "in")
	var pos: PackedVector3Array = pts["positions"]
	var attrs: Dictionary = pts["attrs"]
	var trs: Array = []
	for i in pos.size():
		trs.append(_point_transform(pos[i], _attr_f(attrs, "scale", i), _attr_f(attrs, "rotation_y", i)))
	return {"out": {"type": T_SCENES, "records": [{"scene_path": str(params.get("scene_path", "")), "transforms": trs}]}}


## Writes one weight per point to a named material/paint layer (weight = attribute * strength).
func _n_material_layer_output(inputs: Dictionary, params: Dictionary, _ctx: Dictionary) -> Dictionary:
	var pts: Dictionary = _in_pts(inputs, "in")
	var pos: PackedVector3Array = pts["positions"]
	var attrs: Dictionary = pts["attrs"]
	var src: String = str(params.get("attribute", "density"))
	var strength: float = _fparam(params, "strength", 1.0)
	var w := PackedFloat32Array()
	w.resize(pos.size())
	for i in pos.size():
		w[i] = clampf(_attr_f(attrs, src, i) * strength, 0.0, 1.0)
	return {"out": {"type": T_LAYER, "layer": str(params.get("layer", "layer")), "positions": pos, "weights": w}}
