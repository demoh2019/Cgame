@tool
extends RefCounted
## EQS-style spatial query graph: generators -> tests (filters + scorers) -> ranked items.
## The asset is a plain Dictionary (serialisable; Callables are supplied via the context).
## Naming follows Unreal's Environment Query System and the engine's native
## modules/environment_query (grid/ring generators, directional dot test, distance scoring).
## Original implementation; response curves are reused from utility_ai.gd.
##
## Asset: {name, generators: [..], tests: [..], combine: "weighted"|"iaus", max_results, min_score}
## Generator: {type: grid|ring|navmesh|actors, ...}
##   grid {half_extents, spacing}  ring {radius, count}  navmesh {radius, count}  actors {actor_type, radius}
## Test: {type: distance|dot|trace|path_length|custom, name, weight, min, max, invert, curve, slope,
##        shift, score: bool, filter_min, filter_max, to: querier|target, axis: facing|to_target,
##        callable: String}
## Context: {querier: Vector3, facing: Vector3, target: Vector3,
##   navmesh_points: Callable(center, radius, count) -> Array[Vector3],
##   actors: [{position, type, id}], trace: Callable(from, to) -> bool (true = clear),
##   path_length: Callable(from, to) -> float (negative/INF = unreachable),
##   custom: {name: Callable(position, context, item) -> float}}

const UtilityAI = preload("res://scripts/shared/utility_ai.gd")

const MAX_ITEMS: int = 65536
const GENERATOR_TYPES: Array[String] = ["grid", "ring", "navmesh", "actors"]
const TEST_TYPES: Array[String] = ["distance", "dot", "trace", "path_length", "custom"]

var _asset: Dictionary = {}
var _ctx: Dictionary = {}
var _items: Array[Dictionary] = []
var _cursor: int = 0
var _done: bool = true
var _steps: int = 0
var _results: Array[Dictionary] = []
var _debug: Dictionary = {}
var _tests: Array[Dictionary] = []
var _stats: Dictionary = {}


# --- asset helpers ---------------------------------------------------------

static func new_asset(asset_name: String = "query") -> Dictionary:
	return {"name": asset_name, "generators": [], "tests": [], "combine": "weighted", "max_results": 0, "min_score": 0.0}


static func make_generator(type: String, params: Dictionary = {}) -> Dictionary:
	var g: Dictionary = {"type": type}
	match type:
		"grid":
			g["half_extents"] = 10.0
			g["spacing"] = 2.0
		"ring":
			g["radius"] = 8.0
			g["count"] = 16
		"navmesh":
			g["radius"] = 10.0
			g["count"] = 32
		"actors":
			g["actor_type"] = ""
			g["radius"] = 30.0
	for k in params:
		g[k] = params[k]
	return g


static func make_test(type: String, params: Dictionary = {}) -> Dictionary:
	var t: Dictionary = {"type": type, "weight": 1.0, "invert": false, "curve": UtilityAI.Response.LINEAR,
			"slope": 1.0, "shift": 0.0, "score": true}
	match type:
		"distance":
			t["min"] = 0.0
			t["max"] = 20.0
			t["to"] = "querier"
		"dot":
			t["min"] = -1.0
			t["max"] = 1.0
			t["axis"] = "facing"
		"trace":
			t["min"] = 0.0
			t["max"] = 1.0
		"path_length":
			t["min"] = 0.0
			t["max"] = 40.0
		_:
			t["min"] = 0.0
			t["max"] = 1.0
	for k in params:
		t[k] = params[k]
	return t


static func add_generator(asset: Dictionary, gen: Dictionary) -> int:
	var arr: Array = asset["generators"]
	arr.append(gen)
	return arr.size() - 1


static func add_test(asset: Dictionary, test: Dictionary) -> int:
	var arr: Array = asset["tests"]
	arr.append(test)
	return arr.size() - 1


static func validate(asset: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var gens: Array = asset.get("generators", [])
	var tests: Array = asset.get("tests", [])
	if gens.is_empty():
		errs.append("query has no generators")
	for i in gens.size():
		var g: Dictionary = gens[i]
		if not GENERATOR_TYPES.has(String(g.get("type", ""))):
			errs.append("generator %d: unknown type '%s'" % [i, g.get("type", "")])
	for i in tests.size():
		var t: Dictionary = tests[i]
		if not TEST_TYPES.has(String(t.get("type", ""))):
			errs.append("test %d: unknown type '%s'" % [i, t.get("type", "")])
		elif float(t.get("max", 1.0)) <= float(t.get("min", 0.0)) and bool(t.get("score", true)):
			errs.append("test %d: max must be greater than min" % i)
	return errs


# --- execution -------------------------------------------------------------

func run(asset: Dictionary, context: Dictionary) -> Array[Dictionary]:
	start(asset, context)
	step(MAX_ITEMS * 2)
	return _results


## Generates all items (cheap) and prepares tests. Returns the generated item count.
func start(asset: Dictionary, context: Dictionary) -> int:
	_asset = asset
	_ctx = context
	_items = []
	_results = []
	_cursor = 0
	_steps = 0
	_stats = {}
	_tests = []
	var tests: Array = asset.get("tests", [])
	var used: Dictionary = {}
	for i in tests.size():
		var t: Dictionary = (tests[i] as Dictionary).duplicate()
		var tn: String = String(t.get("name", "%s_%d" % [t.get("type", "test"), i]))
		while used.has(tn):
			tn += "_"
		used[tn] = true
		t["name"] = tn
		_tests.append(t)
		_stats[tn] = {"evaluated": 0, "filtered": 0, "min": INF, "max": -INF, "sum": 0.0}
	var gen_debug: Array[Dictionary] = []
	for g_v in asset.get("generators", []):
		var g: Dictionary = g_v
		var before: int = _items.size()
		_generate(g, context)
		gen_debug.append({"type": String(g.get("type", "")), "count": _items.size() - before})
	_debug = {"name": String(asset.get("name", "")), "generated": _items.size(), "generators": gen_debug,
			"evaluated": 0, "passed": 0, "steps": 0, "filtered_by": {}, "tests": {}}
	_done = false
	if _items.is_empty():
		_finish()
	return _items.size()


## Evaluates up to `budget_items` items; returns true once the query has finished.
func step(budget_items: int) -> bool:
	if _done:
		return true
	_steps += 1
	var end: int = mini(_cursor + maxi(budget_items, 1), _items.size())
	while _cursor < end:
		_evaluate(_items[_cursor])
		_cursor += 1
	if _cursor >= _items.size():
		_finish()
	return _done


func is_done() -> bool:
	return _done


func progress() -> float:
	return 1.0 if _items.is_empty() else float(_cursor) / float(_items.size())


func results() -> Array[Dictionary]:
	return _results


## {generated, evaluated, passed, steps, filtered_by: {test: n}, tests: {name: {evaluated, filtered, min, max, mean}}}
func debug() -> Dictionary:
	return _debug


# --- internals -------------------------------------------------------------

func _add_item(pos: Vector3, actor: Variant = null) -> void:
	if _items.size() >= MAX_ITEMS:
		return
	var it: Dictionary = {"position": pos, "index": _items.size(), "score": 0.0, "passed": true, "tests": {}}
	if actor != null:
		it["actor"] = actor
	_items.append(it)


func _generate(g: Dictionary, ctx: Dictionary) -> void:
	var origin: Vector3 = ctx.get("querier", Vector3.ZERO)
	match String(g.get("type", "")):
		"grid":
			var half: float = maxf(float(g.get("half_extents", 10.0)), 0.0)
			var spacing: float = maxf(float(g.get("spacing", 2.0)), 0.01)
			var n: int = int(floorf(2.0 * half / spacing + 0.0001)) + 1
			if n * n > MAX_ITEMS:
				return
			for ix in n:
				for iz in n:
					_add_item(origin + Vector3(-half + float(ix) * spacing, 0.0, -half + float(iz) * spacing))
		"ring":
			var radius: float = float(g.get("radius", 8.0))
			var cnt: int = clampi(int(g.get("count", 16)), 0, 4096)
			for i in cnt:
				var a: float = TAU * float(i) / float(cnt)
				_add_item(origin + Vector3(cos(a), 0.0, sin(a)) * radius)
		"navmesh":
			var fn: Callable = ctx.get("navmesh_points", Callable())
			if fn.is_valid():
				var pts: Array = fn.call(origin, float(g.get("radius", 10.0)), int(g.get("count", 32)))
				for p in pts:
					_add_item(p)
		"actors":
			var want: String = String(g.get("actor_type", ""))
			var radius2: float = float(g.get("radius", 30.0))
			for a_v in ctx.get("actors", []):
				var a: Dictionary = a_v
				if want != "" and String(a.get("type", "")) != want:
					continue
				var p: Vector3 = a.get("position", Vector3.ZERO)
				if p.distance_to(origin) <= radius2:
					_add_item(p, a.get("id", a.get("type", "")))


func _raw(t: Dictionary, it: Dictionary) -> float:
	var pos: Vector3 = it["position"]
	var origin: Vector3 = _ctx.get("querier", Vector3.ZERO)
	var target: Vector3 = _ctx.get("target", origin)
	match String(t.get("type", "")):
		"distance":
			var ref: Vector3 = target if String(t.get("to", "querier")) == "target" else origin
			return pos.distance_to(ref)
		"dot":
			var axis: Vector3 = _ctx.get("facing", Vector3(0, 0, -1))
			if String(t.get("axis", "facing")) == "to_target":
				axis = target - origin
			var dir: Vector3 = pos - origin
			if axis.length_squared() < 1e-12 or dir.length_squared() < 1e-12:
				return 0.0
			return axis.normalized().dot(dir.normalized())
		"trace":
			var tr: Callable = _ctx.get("trace", Callable())
			if not tr.is_valid():
				return 1.0
			return 1.0 if bool(tr.call(origin, pos)) else 0.0
		"path_length":
			var pl: Callable = _ctx.get("path_length", Callable())
			if not pl.is_valid():
				return pos.distance_to(origin)
			var plen: float = float(pl.call(origin, pos))
			return INF if plen < 0.0 else plen
		_:
			var fn: Callable = t.get("fn", Callable())
			if not fn.is_valid():
				var custom: Dictionary = _ctx.get("custom", {})
				fn = custom.get(String(t.get("callable", "")), Callable())
			if not fn.is_valid():
				return 0.0
			return float(fn.call(pos, _ctx, it))


func _normalise(t: Dictionary, raw: float) -> float:
	var lo: float = float(t.get("min", 0.0))
	var hi: float = float(t.get("max", 1.0))
	var x: float = 1.0 if is_inf(raw) else clampf((raw - lo) / maxf(hi - lo, 0.000001), 0.0, 1.0)
	if bool(t.get("invert", false)):
		x = 1.0 - x
	return UtilityAI.curve(int(t.get("curve", UtilityAI.Response.LINEAR)), x, float(t.get("slope", 1.0)), float(t.get("shift", 0.0)))


func _evaluate(it: Dictionary) -> void:
	var weighted: float = 0.0
	var weight_sum: float = 0.0
	var scores: PackedFloat32Array = PackedFloat32Array()
	var tests_out: Dictionary = it["tests"]
	var dbg_filtered: Dictionary = _debug["filtered_by"]
	for t in _tests:
		var tn: String = String(t["name"])
		var raw: float = _raw(t, it)
		var st: Dictionary = _stats[tn]
		st["evaluated"] = int(st["evaluated"]) + 1
		if not is_inf(raw):
			st["min"] = minf(float(st["min"]), raw)
			st["max"] = maxf(float(st["max"]), raw)
			st["sum"] = float(st["sum"]) + raw
		var failed: bool = (t.has("filter_min") and raw < float(t["filter_min"])) \
				or (t.has("filter_max") and raw > float(t["filter_max"]))
		if failed:
			st["filtered"] = int(st["filtered"]) + 1
			dbg_filtered[tn] = int(dbg_filtered.get(tn, 0)) + 1
			it["passed"] = false
			tests_out[tn] = {"raw": raw, "score": 0.0, "filtered": true}
			break
		var s: float = _normalise(t, raw)
		tests_out[tn] = {"raw": raw, "score": s}
		if bool(t.get("score", true)):
			var w: float = maxf(float(t.get("weight", 1.0)), 0.0)
			weighted += w * s
			weight_sum += w
			scores.append(s)
	_debug["evaluated"] = int(_debug["evaluated"]) + 1
	if not bool(it["passed"]):
		return
	if scores.is_empty():
		it["score"] = 1.0
	elif String(_asset.get("combine", "weighted")) == "iaus":
		it["score"] = UtilityAI.combine(scores)
	else:
		it["score"] = weighted / weight_sum if weight_sum > 0.0 else 0.0
	_debug["passed"] = int(_debug["passed"]) + 1


func _finish() -> void:
	_done = true
	var min_score: float = float(_asset.get("min_score", 0.0))
	var out: Array[Dictionary] = []
	for it in _items:
		if bool(it["passed"]) and float(it["score"]) >= min_score:
			out.append(it)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: float = a["score"]
		var sb: float = b["score"]
		if sa != sb:
			return sa > sb
		return int(a["index"]) < int(b["index"]))
	var cap: int = int(_asset.get("max_results", 0))
	if cap > 0 and out.size() > cap:
		out.resize(cap)
	_results = out
	var tdbg: Dictionary = {}
	for tn in _stats:
		var st: Dictionary = _stats[tn]
		var ev: int = int(st["evaluated"])
		tdbg[tn] = {"evaluated": ev, "filtered": int(st["filtered"]),
				"min": float(st["min"]) if ev > 0 else 0.0, "max": float(st["max"]) if ev > 0 else 0.0,
				"mean": float(st["sum"]) / float(ev) if ev > 0 else 0.0}
	_debug["tests"] = tdbg
	_debug["steps"] = _steps
