extends RefCounted
## Safe default function library for visual-script call nodes (Albion After gameplay hooks).
## Original code; the whitelist idea (scripts only reach host-registered callables, never
## arbitrary Object.call) is a standard sandboxing pattern. No third-party code ported.
##
## Every function takes Variant arguments and validates them, so a bad graph yields a
## recorded error and a neutral return value instead of a script error.

const FUNCTION_NAMES: Array[String] = ["random_range", "distance", "format", "spawn_effect", "clamp01", "lerp_f"]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## spawn_effect requests: {"effect": String, "position": Variant}. The host consumes these.
var effects: Array[Dictionary] = []
var errors: Array[String] = []


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value


## Registers the default functions on a graph. Returns registration errors (empty on success).
func install(graph: RefCounted) -> Array[String]:
	var errs: Array[String] = []
	var table: Array = [
		["random_range", random_range, 2],
		["distance", distance, 2],
		["format", format, 2],
		["spawn_effect", spawn_effect, 2],
		["clamp01", clamp01, 1],
		["lerp_f", lerp_f, 3],
	]
	for row in table:
		var r: Array = row
		var e: String = register_host(graph, str(r[0]), r[1], int(r[2]))
		if not e.is_empty():
			errs.append(e)
	return errs


## Registers a host function with name and argument-count checking. Returns "" or an error.
static func register_host(graph: RefCounted, fn_name: String, callable: Callable, argc: int) -> String:
	if not _valid_name(fn_name):
		return "bad function name '%s' (use lowercase letters, digits, underscore)" % fn_name
	if not graph.has_method("register_function"):
		return "target has no register_function"
	return str(graph.call("register_function", fn_name, callable, argc))


static func _valid_name(s: String) -> bool:
	if s.is_empty():
		return false
	for i in s.length():
		var c: String = s[i]
		var ok: bool = (c >= "a" and c <= "z") or c == "_" or (i > 0 and c >= "0" and c <= "9")
		if not ok:
			return false
	return true


func random_range(lo: Variant, hi: Variant) -> float:
	if not _num(lo) or not _num(hi):
		errors.append("random_range: numbers required")
		return 0.0
	return rng.randf_range(minf(float(lo), float(hi)), maxf(float(lo), float(hi)))


func distance(a: Variant, b: Variant) -> float:
	if typeof(a) == TYPE_VECTOR3 and typeof(b) == TYPE_VECTOR3:
		return (a as Vector3).distance_to(b)
	if typeof(a) == TYPE_VECTOR2 and typeof(b) == TYPE_VECTOR2:
		return (a as Vector2).distance_to(b)
	if _num(a) and _num(b):
		return absf(float(a) - float(b))
	errors.append("distance: matching vectors or numbers required")
	return -1.0


## Replaces the first "{}" in the template with the value.
func format(template: Variant, value: Variant) -> String:
	if typeof(template) != TYPE_STRING:
		errors.append("format: template must be a string")
		return ""
	return (template as String).replace("{}", str(value))


func spawn_effect(effect_name: Variant, position: Variant) -> bool:
	if typeof(effect_name) != TYPE_STRING or (effect_name as String).is_empty():
		errors.append("spawn_effect: effect name required")
		return false
	effects.append({"effect": effect_name, "position": position})
	return true


func clamp01(v: Variant) -> float:
	if not _num(v):
		errors.append("clamp01: number required")
		return 0.0
	return clampf(float(v), 0.0, 1.0)


func lerp_f(a: Variant, b: Variant, t: Variant) -> float:
	if not (_num(a) and _num(b) and _num(t)):
		errors.append("lerp_f: numbers required")
		return 0.0
	return lerpf(float(a), float(b), clampf(float(t), 0.0, 1.0))


func _num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
