@tool
extends VBoxContainer
## Terrain editing panel over TerrainEditLayers (chunked, non-destructive layers) and
## HydraulicErosion. The panel is usable headless: every UI action maps to a plain method.
##
## Credits: layer/brush model by scripts/shared/terrain_edit_layers.gd (concepts from
## Terrain3D, MIT, and Unreal Landscape edit layers); erosion by scripts/shared/hydraulic_erosion.gd
## (Hans Beyer particle model / Sebastian Lague write-up, algorithm only). Panel code is original.

const TerrainEditLayers = preload("res://scripts/shared/terrain_edit_layers.gd")
const TerrainEditBridge = preload("res://scripts/client/terrain_edit_bridge.gd")
const HydraulicErosion = preload("res://scripts/shared/hydraulic_erosion.gd")

signal changed

var edit: TerrainEditLayers = TerrainEditLayers.new()
var selected_layer: int = -1
var live_target: ChunkedTerrain3D = null # Selected editor terrain, not a separate preview.
var viewport_sculpt_enabled: bool = false # Opt-in: leave normal editor selection unchanged.
var brush_kind: int = TerrainEditLayers.Brush.RAISE
var brush_radius: float = 4.0
var brush_strength: float = 1.0
var brush_falloff: int = TerrainEditLayers.Falloff.SMOOTH
var brush_target_height: float = 0.0
var brush_seed: int = 1

## Panel-level undo: {"kind": "stroke", "n": int} | {"kind": "erosion", "layer": int, "name", "rect", "delta", "alpha"}
var _ops: Array[Dictionary] = []
var _redo_ops: Array[Dictionary] = []

var _brush_option: OptionButton = null
var _radius_spin: SpinBox = null
var _strength_spin: SpinBox = null
var _layer_list: ItemList = null
var _opacity_slider: HSlider = null
var _blend_option: OptionButton = null
var _visible_check: CheckBox = null
var _preview: TextureRect = null
var _status: Label = null


func _init() -> void:
	name = "TerrainPanel"
	_build_ui()
	changed.connect(_sync_live_target)


# ------------------------------------------------------------------ data API

func setup(width: int, height: int, chunk_size: int, base_heights: PackedFloat32Array) -> void:
	live_target = null
	edit.setup(width, height, chunk_size, base_heights)
	selected_layer = -1
	_ops.clear()
	_redo_ops.clear()
	_refresh_layers()
	_refresh_preview()


## Bind the brush/layer editor directly to a ChunkedTerrain3D node in the scene.
## Its existing heights become the immutable base of this editor session.
func attach_terrain(terrain: ChunkedTerrain3D) -> bool:
	if terrain == null or not is_instance_valid(terrain):
		live_target = null
		return false
	var dimensions: Vector2i = terrain.get_height_dimensions()
	if dimensions.x < 2 or dimensions.y < 2:
		live_target = null
		return false
	if live_target == terrain:
		return true
	setup(dimensions.x, dimensions.y, terrain.chunk_quads, terrain.get_height_data())
	# The initial base was copied from this exact terrain, so no patch is due.
	edit.take_dirty_chunks()
	live_target = terrain
	return true


func _sync_live_target() -> void:
	if live_target == null or not is_instance_valid(live_target):
		return
	var result: Dictionary = TerrainEditBridge.flush_dirty(edit, live_target)
	if not bool(result.get("ok", false)) and _status != null:
		_status.text = "Terrain update refused: " + str(result.get("reason", "unknown"))


func add_layer(layer_name: String, blend: int = TerrainEditLayers.Blend.ADD, opacity: float = 1.0) -> int:
	var id: int = edit.add_layer(layer_name, blend, opacity)
	selected_layer = id
	_refresh_layers()
	changed.emit()
	return id


func remove_layer(id: int) -> bool:
	var ok: bool = edit.remove_layer(id)
	if ok and selected_layer == id:
		var ids: PackedInt32Array = edit.layer_ids()
		selected_layer = ids[ids.size() - 1] if ids.size() > 0 else -1
	_refresh_layers()
	_refresh_preview()
	changed.emit()
	return ok


func move_layer(id: int, to_index: int) -> bool:
	var ok: bool = edit.move_layer(id, to_index)
	_refresh_layers()
	_refresh_preview()
	if ok:
		changed.emit()
	return ok


func select_layer(id: int) -> void:
	selected_layer = id
	_refresh_layers()


func set_layer_visible(id: int, vis: bool) -> void:
	edit.set_layer_visible(id, vis)
	_refresh_preview()
	changed.emit()


func set_layer_opacity(id: int, opacity: float) -> void:
	edit.set_layer_opacity(id, opacity)
	_refresh_preview()
	changed.emit()


func set_layer_blend(id: int, blend: int) -> void:
	edit.set_layer_blend(id, blend)
	_refresh_preview()
	changed.emit()


func layer_ids() -> PackedInt32Array:
	return edit.layer_ids()


func heights() -> PackedFloat32Array:
	return edit.composite_region(Rect2i(0, 0, edit.width, edit.height))


func brush_dict() -> Dictionary:
	return {"kind": brush_kind, "radius": brush_radius, "strength": brush_strength,
		"falloff": brush_falloff, "target_height": brush_target_height, "seed": brush_seed,
		"layer": selected_layer}


## Applies `brush` (see brush_dict) at each texel-space point. One undo step per call.
## Returns the number of points that changed the layer. A layer is created if none exists.
func stroke(points: PackedVector2Array, brush: Dictionary = {}) -> int:
	var b: Dictionary = brush_dict()
	b.merge(brush, true)
	var layer_id: int = int(b["layer"])
	if layer_id < 0 or not edit.layer_ids().has(layer_id):
		layer_id = add_layer("Layer %d" % (edit.layer_count() + 1))
	var depth_before: int = edit.undo_depth()
	var changed_points: int = 0
	var step: int = 0
	for p in points:
		var r: Rect2i = edit.apply_brush(layer_id, int(b["kind"]), p, float(b["radius"]), float(b["strength"]),
			int(b["falloff"]), float(b["target_height"]), int(b["seed"]) + step)
		if r.size.x > 0:
			changed_points += 1
		step += 1
	var added: int = edit.undo_depth() - depth_before
	if added > 0:
		_ops.append({"kind": "stroke", "n": added})
		_redo_ops.clear()
		_refresh_preview()
		changed.emit()
	return changed_points


## Erodes the composited terrain inside `rect` and stores only the difference in a NEW edit
## layer (ADD blend), so the base and other layers are untouched. Returns the new layer id
## (-1 when nothing was eroded). Undoable via undo().
func apply_erosion(rect: Rect2i, droplets: int, erosion_seed: int, params: Dictionary = {}, thermal_iterations: int = 0) -> int:
	var r: Rect2i = rect.intersection(Rect2i(0, 0, edit.width, edit.height))
	if r.size.x < 3 or r.size.y < 3:
		return -1
	var src: PackedFloat32Array = edit.composite_region(r)
	var out: PackedFloat32Array = HydraulicErosion.erode(src, r.size.x, r.size.y, droplets, erosion_seed, params)
	if thermal_iterations > 0:
		out = HydraulicErosion.thermal(out, r.size.x, r.size.y, thermal_iterations)
	var delta := PackedFloat32Array()
	var alpha := PackedFloat32Array()
	delta.resize(src.size())
	alpha.resize(src.size())
	var any: bool = false
	for i in src.size():
		var d: float = out[i] - src[i]
		delta[i] = d
		if absf(d) > 0.000001:
			alpha[i] = 1.0
			any = true
	if not any:
		return -1
	var id: int = _create_filled_layer("Erosion %d" % (edit.layer_count() + 1), r, delta, alpha)
	_ops.append({"kind": "erosion", "layer": id, "name": "Erosion", "rect": r, "delta": delta, "alpha": alpha})
	_redo_ops.clear()
	_refresh_preview()
	changed.emit()
	return id


func _create_filled_layer(layer_name: String, r: Rect2i, delta: PackedFloat32Array, alpha: PackedFloat32Array) -> int:
	var id: int = edit.add_layer(layer_name, TerrainEditLayers.Blend.ADD, 1.0)
	var l: TerrainEditLayers.EditLayer = _layer_obj(id)
	var d: PackedFloat32Array = l.delta
	var a: PackedFloat32Array = l.alpha
	var k: int = 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			d[y * edit.width + x] = delta[k]
			a[y * edit.width + x] = alpha[k]
			k += 1
	l.delta = d
	l.alpha = a
	edit._grow_bounds(l, r)
	edit._mark_rect_dirty(r)
	selected_layer = id
	_refresh_layers()
	return id


func _layer_obj(id: int) -> TerrainEditLayers.EditLayer:
	var idx: int = edit._layer_index(id)
	return edit._layers[idx]


func can_undo() -> bool:
	return not _ops.is_empty()


func can_redo() -> bool:
	return not _redo_ops.is_empty()


func undo() -> bool:
	if _ops.is_empty():
		return false
	var op: Dictionary = _ops.pop_back()
	if str(op["kind"]) == "stroke":
		for _i in int(op["n"]):
			edit.undo()
	else:
		edit.remove_layer(int(op["layer"]))
		if selected_layer == int(op["layer"]):
			selected_layer = -1
	_redo_ops.append(op)
	_refresh_layers()
	_refresh_preview()
	changed.emit()
	return true


func redo() -> bool:
	if _redo_ops.is_empty():
		return false
	var op: Dictionary = _redo_ops.pop_back()
	if str(op["kind"]) == "stroke":
		for _i in int(op["n"]):
			edit.redo()
	else:
		var r: Rect2i = op["rect"]
		var delta: PackedFloat32Array = op["delta"]
		var alpha: PackedFloat32Array = op["alpha"]
		op["layer"] = _create_filled_layer("Erosion %d" % (edit.layer_count() + 1), r, delta, alpha)
	_ops.append(op)
	_refresh_layers()
	_refresh_preview()
	changed.emit()
	return true


## Grayscale height preview (RGB8), normalised to the composite min/max.
func preview_image() -> Image:
	var w: int = edit.width
	var h: int = edit.height
	var hs: PackedFloat32Array = heights()
	var img: Image = Image.create(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGB8)
	if hs.is_empty():
		return img
	var lo: float = hs[0]
	var hi: float = hs[0]
	for v in hs:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var span: float = maxf(hi - lo, 0.0001)
	for y in h:
		for x in w:
			var t: float = (hs[y * w + x] - lo) / span
			img.set_pixel(x, y, Color(t, t, t))
	return img


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var viewport_sculpt := CheckBox.new()
	viewport_sculpt.text = "Sculpt selected terrain (3D viewport)"
	viewport_sculpt.tooltip_text = "When enabled, left-click the selected ChunkedTerrain3D in the 3D view to sculpt. Disable to select or move objects normally."
	viewport_sculpt.toggled.connect(func(enabled: bool) -> void: viewport_sculpt_enabled = enabled)
	add_child(viewport_sculpt)
	_brush_option = OptionButton.new()
	for n in ["Raise", "Lower", "Smooth", "Flatten", "Noise", "Erode"]:
		_brush_option.add_item(n)
	_brush_option.item_selected.connect(func(i: int) -> void: brush_kind = i)
	add_child(_brush_option)
	_radius_spin = _spin("Radius", 1.0, 64.0, brush_radius, func(v: float) -> void: brush_radius = v)
	_strength_spin = _spin("Strength", 0.01, 10.0, brush_strength, func(v: float) -> void: brush_strength = v)
	_layer_list = ItemList.new()
	_layer_list.custom_minimum_size = Vector2(0, 80)
	_layer_list.item_selected.connect(_on_layer_selected)
	add_child(_layer_list)
	var row := HBoxContainer.new()
	add_child(row)
	row.add_child(_button("Add", func() -> void: add_layer("Layer %d" % (edit.layer_count() + 1))))
	row.add_child(_button("Remove", func() -> void: remove_layer(selected_layer)))
	row.add_child(_button("Undo", func() -> void: undo()))
	row.add_child(_button("Redo", func() -> void: redo()))
	_visible_check = CheckBox.new()
	_visible_check.text = "Visible"
	_visible_check.button_pressed = true
	_visible_check.toggled.connect(func(on: bool) -> void: set_layer_visible(selected_layer, on))
	add_child(_visible_check)
	_opacity_slider = HSlider.new()
	_opacity_slider.min_value = 0.0
	_opacity_slider.max_value = 1.0
	_opacity_slider.step = 0.01
	_opacity_slider.value = 1.0
	_opacity_slider.value_changed.connect(func(v: float) -> void: set_layer_opacity(selected_layer, v))
	add_child(_opacity_slider)
	_blend_option = OptionButton.new()
	for n in ["Add", "Max", "Replace"]:
		_blend_option.add_item(n)
	_blend_option.item_selected.connect(func(i: int) -> void: set_layer_blend(selected_layer, i))
	add_child(_blend_option)
	add_child(_button("Erode whole map into new layer", func() -> void:
		apply_erosion(Rect2i(0, 0, edit.width, edit.height), 2000, brush_seed)))
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(128, 128)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_preview)
	_status = Label.new()
	add_child(_status)


func _spin(label: String, lo: float, hi: float, value: float, cb: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label
	row.add_child(lab)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = value
	s.value_changed.connect(cb)
	row.add_child(s)
	add_child(row)
	return s


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _on_layer_selected(index: int) -> void:
	var ids: PackedInt32Array = edit.layer_ids()
	if index >= 0 and index < ids.size():
		# The list shows the top layer first.
		selected_layer = ids[ids.size() - 1 - index]


func _refresh_layers() -> void:
	if _layer_list == null:
		return
	_layer_list.clear()
	var ids: PackedInt32Array = edit.layer_ids()
	for i in range(ids.size() - 1, -1, -1):
		var l: TerrainEditLayers.EditLayer = _layer_obj(ids[i])
		_layer_list.add_item("%s%s" % [l.name, "" if l.visible else " (hidden)"])


func _refresh_preview() -> void:
	if _preview == null or edit.width < 2:
		return
	_preview.texture = ImageTexture.create_from_image(preview_image())
	if _status != null:
		_status.text = "%dx%d, %d layers" % [edit.width, edit.height, edit.layer_count()]
