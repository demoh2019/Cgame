extends VBoxContainer
## Cloth simulation editor over res://scripts/shared/xpbd_cloth.gd: build from a preset, tune
## solver parameters with sliders, paint pins (cloth_tool.gd) and step a live preview.
## Original code (UI wiring only).

const XPBDCloth = preload("res://scripts/shared/xpbd_cloth.gd")
const ClothTool = preload("res://addons/cgame_sim_authoring/cloth_tool.gd")

## name -> [min, max, step]
const PARAMS: Dictionary = {
	"drag": [0.0, 2.0, 0.01],
	"compliance_stretch": [0.0, 0.01, 0.00001],
	"compliance_shear": [0.0, 0.01, 0.00001],
	"compliance_bend": [0.0, 0.5, 0.001],
	"iterations": [1.0, 8.0, 1.0],
	"friction": [0.0, 1.0, 0.01],
	"tear_threshold": [0.0, 4.0, 0.01],
	"gravity_y": [-30.0, 0.0, 0.1],
	"wind_x": [-20.0, 20.0, 0.1],
}

var cloth: RefCounted = null
var preset_name: String = ""
var brush: ClothTool = ClothTool.new()
var sliders: Dictionary = {}

var _status: Label


func _init() -> void:
	_status = Label.new()
	add_child(_status)
	for key in PARAMS:
		var r: Array = PARAMS[key]
		var s := HSlider.new()
		s.name = str(key)
		s.min_value = float(r[0])
		s.max_value = float(r[1])
		s.step = float(r[2])
		s.custom_minimum_size = Vector2(160.0, 16.0)
		s.value_changed.connect(_on_slider.bind(str(key)))
		sliders[key] = s
		add_child(s)
	create("flag")


func create(preset: String) -> bool:
	var c: RefCounted = brush.build_from_preset(preset)
	if c == null:
		_status.text = "unknown preset"
		return false
	cloth = c
	preset_name = preset
	_sync_sliders()
	_refresh_status()
	return true


func _on_slider(value: float, param: String) -> void:
	set_param(param, value)


func get_param(param: String) -> float:
	match param:
		"gravity_y":
			return (cloth.get("gravity") as Vector3).y
		"wind_x":
			return (cloth.get("wind") as Vector3).x
	return float(cloth.get(param))


## Maps a slider name to a solver property. Values are clamped to the slider range.
func set_param(param: String, value: float) -> bool:
	if cloth == null or not PARAMS.has(param):
		return false
	var r: Array = PARAMS[param]
	var v: float = clampf(value, float(r[0]), float(r[1]))
	match param:
		"gravity_y":
			var g: Vector3 = cloth.get("gravity")
			g.y = v
			cloth.set("gravity", g)
		"wind_x":
			var w: Vector3 = cloth.get("wind")
			w.x = v
			cloth.set("wind", w)
		"iterations":
			cloth.set("iterations", roundi(v))
		_:
			cloth.set(param, v)
	if sliders.has(param):
		(sliders[param] as HSlider).set_value_no_signal(v)
	return true


func _sync_sliders() -> void:
	for key in sliders:
		var s: HSlider = sliders[key]
		s.set_value_no_signal(get_param(str(key)))


## Pins (or unpins) particles within radius of a world-space point; returns affected count.
func paint_pins(center: Vector3, radius: float, pinned: bool) -> int:
	return brush.paint_pins(cloth, center, radius, pinned).size()


func pinned_count() -> int:
	var n: int = 0
	for i in int(cloth.call("particle_count")):
		if bool(cloth.call("is_pinned", i)):
			n += 1
	return n


## Steps the simulation `n` frames of `dt` seconds and returns the stats.
func step_preview(n: int, dt: float = 1.0 / 60.0, substeps: int = 4) -> Dictionary:
	for i in maxi(n, 0):
		cloth.call("step", dt, substeps)
	_refresh_status()
	return stats()


func stats() -> Dictionary:
	return {
		"max_stretch": float(cloth.call("max_stretch_error")),
		"torn_count": int(cloth.get("torn_count")),
		"particles": int(cloth.call("particle_count")),
		"constraints": int(cloth.call("constraint_count")),
		"pinned": pinned_count(),
	}


func _refresh_status() -> void:
	var s: Dictionary = stats()
	_status.text = "%s: stretch %.4f, torn %d, pinned %d" % [preset_name, float(s["max_stretch"]), int(s["torn_count"]), int(s["pinned"])]


## Serialisable config: preset, solver params and the pinned particle indices.
func export_config() -> Dictionary:
	var params: Dictionary = {}
	for key in PARAMS:
		params[key] = get_param(str(key))
	var pins: Array = []
	for i in int(cloth.call("particle_count")):
		if bool(cloth.call("is_pinned", i)):
			pins.append(i)
	return {"preset": preset_name, "params": params, "pins": pins, "stats": stats()}
