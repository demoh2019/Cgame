extends VBoxContainer
## VFX debugger over res://scripts/client/vfx_graph.gd: load an asset, step the system frame by
## frame, inspect per-particle attributes, read the per-module timing table and break on
## particle-count thresholds. Original code (UI wiring only).

const VfxGraph = preload("res://scripts/client/vfx_graph.gd")

var system: Dictionary = {}
var asset: Dictionary = {}
var frame: int = 0
## emitter name -> particle count threshold; stepping stops being "clear" once one is reached.
var breakpoints: Dictionary = {}
var hit_breakpoints: Array[String] = []

var _status: Label


func _init() -> void:
	_status = Label.new()
	add_child(_status)


func load_asset(asset_def: Dictionary, seed_value: int = 1) -> bool:
	var defs: Dictionary = asset_def.get("emitters", {})
	if defs.is_empty():
		_status.text = "asset has no emitters"
		return false
	asset = asset_def
	system = VfxGraph.create_system(asset_def, seed_value)
	frame = 0
	hit_breakpoints.clear()
	_status.text = "loaded %d emitters" % defs.size()
	return true


func emitter_names() -> Array:
	return (system.get("order", []) as Array).duplicate()


## Advances one frame of `dt` seconds. Returns true when no breakpoint was hit.
func step(dt: float = 1.0 / 60.0) -> bool:
	if system.is_empty():
		return false
	VfxGraph.tick(system, dt)
	frame += 1
	hit_breakpoints.clear()
	for name_v in breakpoints:
		var name_s: String = str(name_v)
		var threshold: int = int(breakpoints[name_v])
		var count: int = total() if name_s == "*" else VfxGraph.particle_count(system, name_s)
		if count >= threshold:
			hit_breakpoints.append(name_s)
	_status.text = "frame %d, %d particles" % [frame, total()]
	return hit_breakpoints.is_empty()


## Steps up to `max_frames` frames, stopping at the first breakpoint. Returns frames stepped.
func run_until_breakpoint(max_frames: int, dt: float = 1.0 / 60.0) -> int:
	var n: int = 0
	while n < max_frames:
		n += 1
		if not step(dt):
			break
	return n


func total() -> int:
	return VfxGraph.total_particles(system)


func set_breakpoint(emitter: String, threshold: int) -> void:
	breakpoints[emitter] = threshold


func clear_breakpoints() -> void:
	breakpoints.clear()
	hit_breakpoints.clear()


## All attributes of one live particle, or {} when emitter/index is out of range.
func inspect(emitter: String, index: int) -> Dictionary:
	var em: VfxGraph.Emitter = VfxGraph.get_emitter(system, emitter)
	if em == null or index < 0 or index >= em.count:
		return {}
	var out: Dictionary = {
		"position": em.pos[index], "velocity": em.vel[index], "color": em.col[index],
		"size": em.size[index], "age": em.age[index], "lifetime": em.life[index],
	}
	for key in em.custom:
		var a: VfxGraph.Attr = em.custom[key]
		out[str(key)] = a.data[index]
	return out


## Per-module timing rows sorted by cost: [{module, usec}] from the system profile.
func timing_table() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var prof: Dictionary = system.get("profile", {})
	for key in prof:
		rows.append({"module": str(key), "usec": int(prof[key])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["usec"]) > int(b["usec"]))
	return rows
