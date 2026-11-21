extends VBoxContainer
## Vehicle physics authoring panel over res://scripts/shared/vehicle_dynamics.gd and
## vehicle_presets.gd: edit suspension / transmission / tyre fields, simulate a scripted input
## run on flat ground and read back telemetry series and the engine dyno curve.
## Original code (UI wiring only); the physics models are the project's own libraries.

const VehicleDynamics = preload("res://scripts/shared/vehicle_dynamics.gd")
const VehiclePresets = preload("res://scripts/shared/vehicle_presets.gd")

const SIM_DT: float = 1.0 / 60.0
const PRESET_NAMES: PackedStringArray = ["salvage_bike", "pickup_truck", "dune_buggy"]

var config: Dictionary = {}
var last_errors: Array[String] = []
var telemetry_series: Dictionary = {}

var _title: Label
var _status: Label
var _graphs: Array[SeriesGraph] = []


## Minimal polyline plot used for the live telemetry graphs.
class SeriesGraph extends Control:
	var values: PackedFloat32Array = PackedFloat32Array()
	var line_color: Color = Color(0.4, 0.9, 0.5)

	func _init() -> void:
		custom_minimum_size = Vector2(160.0, 60.0)

	func set_values(v: PackedFloat32Array) -> void:
		values = v
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.12))
		if values.size() < 2:
			return
		var lo: float = values[0]
		var hi: float = values[0]
		for v in values:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		var span: float = maxf(hi - lo, 0.0001)
		var pts := PackedVector2Array()
		var last: float = float(values.size() - 1)
		for i in values.size():
			pts.append(Vector2(size.x * float(i) / last, size.y * (1.0 - (values[i] - lo) / span)))
		draw_polyline(pts, line_color, 1.5)


func _init() -> void:
	_title = Label.new()
	_title.text = "Vehicle"
	add_child(_title)
	_status = Label.new()
	add_child(_status)
	for i in 4:
		var g := SeriesGraph.new()
		_graphs.append(g)
		add_child(g)
	load_preset("pickup_truck")


func load_preset(preset_name: String) -> bool:
	if not PRESET_NAMES.has(preset_name):
		_status.text = "unknown preset"
		return false
	match preset_name:
		"salvage_bike":
			config = VehiclePresets.salvage_bike()
		"pickup_truck":
			config = VehiclePresets.pickup_truck()
		_:
			config = VehiclePresets.dune_buggy()
	last_errors = VehiclePresets.validate(config)
	_title.text = "Vehicle: %s" % preset_name
	return true


## Sets a field by dotted path ("mass", "engine.idle_rpm", "wheels.0.stiffness",
## "gearbox.gear_ratios"). The edit is rejected (config untouched) when it introduces a new
## validation error; `last_errors` then holds the reasons.
func set_field(path: String, value: Variant) -> bool:
	var parts: PackedStringArray = path.split(".")
	if parts.is_empty() or path == "":
		last_errors = ["empty path"]
		return false
	var candidate: Dictionary = config.duplicate(true)
	var node: Variant = candidate
	for i in parts.size() - 1:
		node = _child(node, parts[i])
		if node == null:
			last_errors = ["unknown path: %s" % path]
			return false
	var leaf: String = parts[parts.size() - 1]
	if node is Dictionary:
		var d: Dictionary = node
		d[leaf] = value
	elif node is Array:
		var a: Array = node
		if not leaf.is_valid_int() or leaf.to_int() < 0 or leaf.to_int() >= a.size():
			last_errors = ["unknown path: %s" % path]
			return false
		a[leaf.to_int()] = value
	else:
		last_errors = ["unknown path: %s" % path]
		return false
	var before: Array[String] = VehiclePresets.validate(config)
	var after: Array[String] = VehiclePresets.validate(candidate)
	var fresh: Array[String] = []
	for e in after:
		if not before.has(e):
			fresh.append(e)
	if not fresh.is_empty():
		last_errors = fresh
		_status.text = "rejected: %s" % fresh[0]
		return false
	config = candidate
	last_errors = after
	return true


func get_field(path: String) -> Variant:
	var node: Variant = config
	for part in path.split("."):
		node = _child(node, part)
		if node == null:
			return null
	return node


static func _child(node: Variant, key: String) -> Variant:
	if node is Dictionary:
		var d: Dictionary = node
		return d.get(key, null)
	if node is Array:
		var a: Array = node
		if key.is_valid_int() and key.to_int() >= 0 and key.to_int() < a.size():
			return a[key.to_int()]
	return null


func _flat(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	if dir.y >= -0.0001:
		return {"hit": false}
	var d: float = origin.y / -dir.y
	if d < 0.0 or d > max_dist:
		return {"hit": false}
	return {"hit": true, "distance": d, "normal": Vector3.UP, "friction": 1.0}


## Runs the vehicle on flat ground. `inputs_script` is an Array of segments
## {"duration": s, "throttle": 0..1, "brake": 0..1, "steer": -1..1, ...}; an empty script holds
## full throttle for the whole run. Returns (and stores) the telemetry series:
## {"time","speed","rpm","gear": PackedFloat32Array, "compression": Array[PackedFloat32Array]}.
func simulate(seconds: float, inputs_script: Array = []) -> Dictionary:
	var car := VehicleDynamics.new()
	car.setup(config)
	car.reset(Vector3(0.0, car.static_ride_height() + 0.1, 0.0))
	var steps: int = maxi(1, roundi(seconds / SIM_DT))
	var time_s := PackedFloat32Array()
	var speed := PackedFloat32Array()
	var rpm := PackedFloat32Array()
	var gear := PackedFloat32Array()
	var comp: Array = []
	for w in car.wheel_count():
		comp.append(PackedFloat32Array())
	var ground := Callable(self, "_flat")
	for i in steps:
		var t_now: float = float(i) * SIM_DT
		car.step(SIM_DT, _inputs_at(t_now, inputs_script), ground)
		var tel: Dictionary = car.telemetry()
		time_s.append(t_now + SIM_DT)
		speed.append(float(tel["speed"]))
		rpm.append(float(tel["rpm"]))
		gear.append(float(int(tel["gear"])))
		var wheels: Array = tel["wheels"]
		for w in wheels.size():
			var wd: Dictionary = wheels[w]
			var series: PackedFloat32Array = comp[w]
			series.append(float(wd["compression"]))
			comp[w] = series
	telemetry_series = {"time": time_s, "speed": speed, "rpm": rpm, "gear": gear, "compression": comp}
	_graphs[0].set_values(speed)
	_graphs[1].set_values(rpm)
	_graphs[2].set_values(gear)
	if not comp.is_empty():
		_graphs[3].set_values(comp[0] as PackedFloat32Array)
	_status.text = "simulated %.1f s, %d samples" % [seconds, steps]
	return telemetry_series


static func _inputs_at(t_now: float, inputs_script: Array) -> Dictionary:
	if inputs_script.is_empty():
		return {"throttle": 1.0}
	var acc: float = 0.0
	for seg in inputs_script:
		var d: Dictionary = seg
		acc += float(d.get("duration", 1.0))
		if t_now < acc:
			return d
	return inputs_script[inputs_script.size() - 1] as Dictionary


## Engine dyno: [{"rpm","torque" (N m),"power_kw"}] sampled evenly from idle to redline.
func torque_curve_samples(count: int = 32) -> Array[Dictionary]:
	var car := VehicleDynamics.new()
	car.setup(config)
	var engine: Dictionary = config.get("engine", {})
	var lo: float = float(engine.get("idle_rpm", 900.0))
	var hi: float = float(engine.get("redline_rpm", 6500.0))
	var n: int = maxi(count, 2)
	var out: Array[Dictionary] = []
	for i in n:
		var r: float = lerpf(lo, hi, float(i) / float(n - 1))
		var tq: float = car.torque_at(r)
		out.append({"rpm": r, "torque": tq, "power_kw": tq * r * TAU / 60.0 / 1000.0})
	return out


# ---- JSON persistence ----------------------------------------------------

static func _encode(v: Variant) -> Variant:
	if v is Vector3:
		var v3: Vector3 = v
		return {"_v3": [v3.x, v3.y, v3.z]}
	if v is Vector2:
		var v2: Vector2 = v
		return {"_v2": [v2.x, v2.y]}
	if v is Dictionary:
		var src: Dictionary = v
		var out: Dictionary = {}
		for k in src:
			out[k] = _encode(src[k])
		return out
	if v is Array:
		var arr: Array = v
		var outa: Array = []
		for e in arr:
			outa.append(_encode(e))
		return outa
	return v


static func _decode(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = v
		if d.size() == 1 and d.has("_v3"):
			var a3: Array = d["_v3"]
			return Vector3(float(a3[0]), float(a3[1]), float(a3[2]))
		if d.size() == 1 and d.has("_v2"):
			var a2: Array = d["_v2"]
			return Vector2(float(a2[0]), float(a2[1]))
		var out: Dictionary = {}
		for k in d:
			out[k] = _decode(d[k])
		return out
	if v is Array:
		var arr: Array = v
		var outa: Array = []
		for e in arr:
			outa.append(_decode(e))
		return outa
	return v


func save_config(path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(_encode(config), "\t"))
	f.close()
	return true


func load_config(path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return false
	var cfg: Dictionary = _decode(parsed) as Dictionary
	last_errors = VehiclePresets.validate(cfg)
	if not last_errors.is_empty():
		return false
	config = cfg
	return true
