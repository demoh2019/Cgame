@tool
extends Control
## World Partition editor panel: grid minimap, Data Layers, HLOD clusters, cell
## load/unload preview and bake/export/diff over world_partition_bake.gd.
## Works headless (all logic is callable without the UI). Original code.

const Bake = preload("res://scripts/shared/world_partition_bake.gd")

signal collect_requested
signal cell_selected(key: String)

const TOOLBAR_H := 30.0
const SIDEBAR_W := 150.0
const MAP_MARGIN := 6.0

var cell_size: float = 64.0
var hlod_cluster_cells: int = 2
var loading_ranges: Dictionary = {}
var selected_cell: String = ""
var preview_source: Vector3 = Vector3.ZERO
var preview_velocity: Vector3 = Vector3.ZERO
var show_preview: bool = true

var _wp: Bake = Bake.new()
var _actors: Array = []
var _layer_enabled: Dictionary = {}
var _last_bake: Dictionary = {}
var _prev_bake: Dictionary = {}
var _clusters: Array = []
var _loaded_cache: Array = []
var _layer_box: VBoxContainer
var _status: Label
var _spin: SpinBox


func _init() -> void:
	custom_minimum_size = Vector2(360, 300)
	var bar := HBoxContainer.new()
	bar.name = "Toolbar"
	bar.position = Vector2.ZERO
	bar.size = Vector2(600, TOOLBAR_H)
	add_child(bar)
	_spin = SpinBox.new()
	_spin.min_value = 1.0
	_spin.max_value = 4096.0
	_spin.value = cell_size
	_spin.tooltip_text = "Runtime grid cell size"
	bar.add_child(_spin)
	var collect := Button.new()
	collect.text = "Collect + Bake"
	collect.pressed.connect(func() -> void: collect_requested.emit())
	bar.add_child(collect)
	var rebake := Button.new()
	rebake.text = "Bake"
	rebake.pressed.connect(func() -> void: bake(_spin.value))
	bar.add_child(rebake)
	_status = Label.new()
	bar.add_child(_status)
	_layer_box = VBoxContainer.new()
	_layer_box.name = "Layers"
	add_child(_layer_box)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	if _layer_box == null:
		return
	_layer_box.position = Vector2(maxf(size.x - SIDEBAR_W, 0.0), TOOLBAR_H)
	_layer_box.size = Vector2(SIDEBAR_W, maxf(size.y - TOOLBAR_H, 0.0))
	queue_redraw()


# Actors / GUIDs ---------------------------------------------------------------

## Takes actor dicts {guid, position, bounds?, layers, spatially_loaded, data}.
## Copies them and gives every actor without a GUID a deterministic one
## (position + layers + duplicate ordinal), so re-importing yields the same GUIDs.
func set_actors(actors: Array) -> void:
	_actors.clear()
	var seen: Dictionary = {}
	for item in actors:
		var a: Dictionary = (item as Dictionary).duplicate(true)
		var guid: String = a.get("guid", "")
		if guid == "":
			var layers: PackedStringArray = a.get("layers", PackedStringArray())
			var base: String = "%s|%s" % [str(a.get("position", Vector3.ZERO)), ",".join(layers)]
			var n: int = int(seen.get(base, 0))
			seen[base] = n + 1
			guid = _wp.stable_guid("%s|%d" % [base, n])
			a["guid"] = guid
		_actors.append(a)
	for a in _actors:
		for layer in (a as Dictionary).get("layers", PackedStringArray()):
			if not _layer_enabled.has(layer):
				_layer_enabled[layer] = true
	_rebuild_layer_ui()


func get_actors() -> Array:
	return _actors


func get_actor(guid: String) -> Dictionary:
	for a in _actors:
		if (a as Dictionary)["guid"] == guid:
			return a
	return {}


func move_actor(guid: String, new_position: Vector3) -> bool:
	for a in _actors:
		var d: Dictionary = a
		if d["guid"] != guid:
			continue
		var old_pos: Vector3 = d.get("position", Vector3.ZERO)
		d["position"] = new_position
		if d.has("bounds"):
			var b: AABB = d["bounds"]
			b.position += new_position - old_pos
			d["bounds"] = b
		return true
	return false


# Bake / diff / export ------------------------------------------------------------

func bake(new_cell_size: float) -> Dictionary:
	cell_size = new_cell_size
	_prev_bake = _last_bake
	_last_bake = _wp.bake(_actors, cell_size, loading_ranges)
	_clusters = _wp.hlod_clusters(_last_bake.get("cells", {}), hlod_cluster_cells)
	if selected_cell != "" and not (_last_bake["cells"] as Dictionary).has(selected_cell):
		selected_cell = ""
	_refresh_preview()
	if _status != null:
		_status.text = "%d cells, %d HLOD, %d always" % [get_cells().size(), _clusters.size(), (_last_bake["always_loaded"] as Array).size()]
	queue_redraw()
	return _last_bake


func get_cells() -> Dictionary:
	return _last_bake.get("cells", {})


func get_clusters() -> Array:
	return _clusters


func always_loaded() -> Array:
	return _last_bake.get("always_loaded", [])


func actors_in_cell(key: String) -> Array:
	var cells: Dictionary = get_cells()
	if not cells.has(key):
		return []
	var cell: Dictionary = cells[key]
	return (cell["actors"] as Array).duplicate()


func export_ofpa(dir_path: String) -> int:
	return _wp.split_one_file_per_actor(_actors, dir_path)


## Diff of the latest bake against the one before it ({} keys empty when none).
func diff_with_previous() -> Dictionary:
	if _prev_bake.is_empty() or _last_bake.is_empty():
		return {"added": [], "removed": [], "moved": [], "changed": [], "dirty_cells": []}
	return _wp.diff_bakes(_prev_bake, _last_bake)


# Data layers ---------------------------------------------------------------------

func layer_names() -> PackedStringArray:
	var names: Array = _layer_enabled.keys()
	names.sort()
	return PackedStringArray(names)


func set_layer_enabled(layer: String, enabled: bool) -> void:
	_layer_enabled[layer] = enabled
	_refresh_preview()
	_rebuild_layer_ui()
	queue_redraw()


func is_layer_enabled(layer: String) -> bool:
	return bool(_layer_enabled.get(layer, false))


func enabled_layers() -> PackedStringArray:
	var out := PackedStringArray()
	for l in layer_names():
		if bool(_layer_enabled[l]):
			out.append(l)
	return out


## Cells a streaming source would load given the currently enabled data layers.
func loaded_preview(source_pos: Vector3, velocity: Vector3) -> Array:
	return _wp.cells_to_load(source_pos, velocity, enabled_layers())


func set_preview_source(pos: Vector3, velocity: Vector3 = Vector3.ZERO) -> void:
	preview_source = pos
	preview_velocity = velocity
	_refresh_preview()
	queue_redraw()


func _refresh_preview() -> void:
	_loaded_cache = loaded_preview(preview_source, preview_velocity) if not _last_bake.is_empty() else []


## Adds `layer` to the given actors; returns the actor dicts that changed (copies).
func assign_layer(guids: Array, layer: String) -> Array:
	var out: Array = []
	if layer == "":
		return out
	for a in _actors:
		var d: Dictionary = a
		if not (d["guid"] in guids):
			continue
		var layers: PackedStringArray = d.get("layers", PackedStringArray())
		if layer in layers:
			continue
		layers.append(layer)
		d["layers"] = layers
		out.append(d.duplicate(true))
	if not out.is_empty():
		if not _layer_enabled.has(layer):
			_layer_enabled[layer] = true
		_rebuild_layer_ui()
	return out


func remove_layer(guids: Array, layer: String) -> Array:
	var out: Array = []
	for a in _actors:
		var d: Dictionary = a
		if not (d["guid"] in guids):
			continue
		var layers: PackedStringArray = d.get("layers", PackedStringArray())
		var idx: int = layers.find(layer)
		if idx < 0:
			continue
		layers.remove_at(idx)
		d["layers"] = layers
		out.append(d.duplicate(true))
	return out


func _rebuild_layer_ui() -> void:
	if _layer_box == null:
		return
	for c in _layer_box.get_children():
		_layer_box.remove_child(c)
		c.queue_free()
	var title := Label.new()
	title.text = "Data Layers"
	_layer_box.add_child(title)
	for l in layer_names():
		var cb := CheckBox.new()
		cb.text = l
		cb.button_pressed = bool(_layer_enabled[l])
		var layer_name: String = l
		cb.toggled.connect(func(on: bool) -> void: set_layer_enabled(layer_name, on))
		_layer_box.add_child(cb)


# Minimap -----------------------------------------------------------------------------

func _map_rect() -> Rect2:
	return Rect2(MAP_MARGIN, TOOLBAR_H + MAP_MARGIN,
		maxf(size.x - SIDEBAR_W - MAP_MARGIN * 2.0, 1.0), maxf(size.y - TOOLBAR_H - MAP_MARGIN * 2.0, 1.0))


func _cell_world_rect(cell: Dictionary) -> Rect2:
	var cs: float = float(_last_bake.get("cell_size", cell_size))
	var ls: float = cs * pow(2.0, float(int(cell["level"])))
	return Rect2(float(int(cell["x"])) * ls, float(int(cell["z"])) * ls, ls, ls)


func _world_extent() -> Rect2:
	var ext := Rect2()
	var first := true
	for k in get_cells():
		var r: Rect2 = _cell_world_rect(get_cells()[k])
		ext = r if first else ext.merge(r)
		first = false
	return ext


## Uniform scale + offset mapping world XZ to panel-local pixels.
func _view_transform() -> Transform2D:
	var ext: Rect2 = _world_extent()
	var m: Rect2 = _map_rect()
	if ext.size.x <= 0.0 or ext.size.y <= 0.0:
		return Transform2D.IDENTITY
	var s: float = minf(m.size.x / ext.size.x, m.size.y / ext.size.y)
	var origin: Vector2 = m.position + (m.size - ext.size * s) * 0.5 - ext.position * s
	return Transform2D(Vector2(s, 0.0), Vector2(0.0, s), origin)


func world_to_local(p: Vector3) -> Vector2:
	return _view_transform() * Vector2(p.x, p.z)


func local_to_world(p: Vector2) -> Vector2:
	return _view_transform().affine_inverse() * p


## Cell under a panel-local point (finest grid level wins, ties by key). "" if none.
func select_cell_at(local_pos: Vector2) -> String:
	var w: Vector2 = local_to_world(local_pos)
	var best := ""
	var best_level := 1 << 30
	var cells: Dictionary = get_cells()
	var keys: Array = cells.keys()
	keys.sort()
	for k in keys:
		var key: String = k
		var cell: Dictionary = cells[key]
		if _cell_world_rect(cell).has_point(w) and int(cell["level"]) < best_level:
			best = key
			best_level = int(cell["level"])
	selected_cell = best
	cell_selected.emit(best)
	queue_redraw()
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			select_cell_at(mb.position)


func _draw() -> void:
	draw_rect(_map_rect(), Color(0.08, 0.09, 0.11))
	var cells: Dictionary = get_cells()
	if cells.is_empty():
		return
	var xf: Transform2D = _view_transform()
	var max_count := 1
	for k in cells:
		max_count = maxi(max_count, ((cells[k] as Dictionary)["actors"] as Array).size())
	var keys: Array = cells.keys()
	keys.sort()
	for k in keys:
		var cell: Dictionary = cells[k]
		var r: Rect2 = xf * _cell_world_rect(cell)
		var heat: float = float((cell["actors"] as Array).size()) / float(max_count)
		var hue: float = fmod(0.55 + 0.12 * float(int(cell["level"])), 1.0)
		var col: Color = Color.from_hsv(hue, 0.55, 0.25 + 0.6 * heat, 0.8)
		if not cell["layers"].is_empty() and not _any_enabled(cell["layers"]):
			col = col.darkened(0.6)
		draw_rect(r, col)
		draw_rect(r, Color(1, 1, 1, 0.15), false, 1.0)
		if show_preview and k in _loaded_cache:
			draw_rect(r.grow(-1.0), Color(0.3, 1.0, 0.4, 0.9), false, 2.0)
	for c in _clusters:
		var cb: AABB = (c as Dictionary)["bounds"]
		var cr: Rect2 = xf * Rect2(cb.position.x, cb.position.z, cb.size.x, cb.size.z)
		draw_rect(cr.grow(2.0), Color(1.0, 0.6, 0.1, 0.9), false, 1.5)
	if selected_cell != "" and cells.has(selected_cell):
		draw_rect((xf * _cell_world_rect(cells[selected_cell])).grow(1.0), Color(1.0, 0.95, 0.2), false, 3.0)
	var sp: Vector2 = world_to_local(preview_source)
	draw_circle(sp, 4.0, Color(1, 0.2, 0.2))
	if preview_velocity.length_squared() > 0.0001:
		draw_line(sp, world_to_local(preview_source + preview_velocity), Color(1, 0.2, 0.2), 2.0)


func _any_enabled(layers: PackedStringArray) -> bool:
	for l in layers:
		if bool(_layer_enabled.get(l, true)):
			return true
	return false
