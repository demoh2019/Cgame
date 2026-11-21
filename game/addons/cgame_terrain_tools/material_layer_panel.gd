@tool
extends VBoxContainer
## Material layer stack editor over scripts/client/material_layers.gd.
## Add/remove/reorder layers, change blend mode and parameters, build a preview
## ShaderMaterial and export/import the stack as JSON (Colors stored as HTML strings).
##
## Credits: shader generation and its sources (Dave Hoskins hash MIT, Barre-Brisebois/Hill RNM,
## Golus triplanar, Opsenica height blend) are documented in material_layers.gd. Panel code is original.

const MaterialLayers = preload("res://scripts/client/material_layers.gd")

signal changed

var stack: Dictionary = {"normal_blend": "rnm", "layers": []}

var _list: ItemList = null
var _mode_option: OptionButton = null
var _status: Label = null


func _init() -> void:
	name = "MaterialLayerPanel"
	_build_ui()


func layer_count() -> int:
	var layers: Array = stack["layers"]
	return layers.size()


func layer_names() -> PackedStringArray:
	var out := PackedStringArray()
	var layers: Array = stack["layers"]
	for l in layers:
		var d: Dictionary = l
		out.append(str(d["name"]))
	return out


## Adds a layer on top; returns its index. Layer 0 is the base (its blend is ignored).
func add_layer(layer_name: String, albedo: Color = Color(0.5, 0.5, 0.5), mode: String = MaterialLayers.MODE_HEIGHT) -> int:
	var layers: Array = stack["layers"]
	var layer: Dictionary = {"name": layer_name, "albedo": albedo, "roughness": 0.8, "metallic": 0.0,
		"uv_scale": 1.0, "blend": {"mode": mode}}
	layers.append(layer)
	_refresh()
	changed.emit()
	return layers.size() - 1


func remove_layer(index: int) -> bool:
	var layers: Array = stack["layers"]
	if index < 0 or index >= layers.size():
		return false
	layers.remove_at(index)
	_refresh()
	changed.emit()
	return true


func move_layer(index: int, to_index: int) -> bool:
	var layers: Array = stack["layers"]
	if index < 0 or index >= layers.size():
		return false
	var l: Variant = layers[index]
	layers.remove_at(index)
	layers.insert(clampi(to_index, 0, layers.size()), l)
	_refresh()
	changed.emit()
	return true


func set_blend_mode(index: int, mode: String) -> bool:
	var layers: Array = stack["layers"]
	if index < 0 or index >= layers.size() or not mode in [MaterialLayers.MODE_HEIGHT, MaterialLayers.MODE_SLOPE,
			MaterialLayers.MODE_NOISE, MaterialLayers.MODE_MASK, MaterialLayers.MODE_VERTEX_COLOR]:
		return false
	var layer: Dictionary = layers[index]
	var blend: Dictionary = layer.get("blend", {})
	blend["mode"] = mode
	layer["blend"] = blend
	changed.emit()
	return true


func set_param(index: int, key: String, value: Variant) -> bool:
	var layers: Array = stack["layers"]
	if index < 0 or index >= layers.size():
		return false
	var layer: Dictionary = layers[index]
	layer[key] = value
	changed.emit()
	return true


func set_blend_param(index: int, key: String, value: Variant) -> bool:
	var layers: Array = stack["layers"]
	if index < 0 or index >= layers.size():
		return false
	var layer: Dictionary = layers[index]
	var blend: Dictionary = layer.get("blend", {})
	blend[key] = value
	layer["blend"] = blend
	changed.emit()
	return true


func shader_code() -> String:
	return MaterialLayers.generate_shader_code(stack)


## ShaderMaterial for previewing the stack (shares the cached Shader for equal structures).
func preview_material() -> ShaderMaterial:
	return MaterialLayers.build_material(stack)


func export_json() -> String:
	return JSON.stringify(_to_json_value(stack), "\t")


## Replaces the stack from JSON produced by export_json(). Returns false on bad input.
func import_json(text: String) -> bool:
	var json := JSON.new()
	if json.parse(text) != OK:
		return false
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return false
	var d: Dictionary = parsed
	if not d.get("layers") is Array:
		return false
	var restored: Variant = _from_json_value(d)
	stack = restored
	_refresh()
	changed.emit()
	return true


func _to_json_value(v: Variant) -> Variant:
	if v is Color:
		var c: Color = v
		return "#" + c.to_html(true)
	if v is Dictionary:
		var src: Dictionary = v
		var out: Dictionary = {}
		for k in src.keys():
			out[k] = _to_json_value(src[k])
		return out
	if v is Array:
		var arr: Array = v
		var res: Array = []
		for e in arr:
			res.append(_to_json_value(e))
		return res
	return v


func _from_json_value(v: Variant) -> Variant:
	if v is String:
		var s: String = v
		if s.length() in [7, 9] and s.begins_with("#") and s.substr(1).is_valid_html_color():
			return Color.html(s)
		return s
	if v is Dictionary:
		var src: Dictionary = v
		var out: Dictionary = {}
		for k in src.keys():
			out[k] = _from_json_value(src[k])
		return out
	if v is Array:
		var arr: Array = v
		var res: Array = []
		for e in arr:
			res.append(_from_json_value(e))
		return res
	return v


func _build_ui() -> void:
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 100)
	add_child(_list)
	var row := HBoxContainer.new()
	add_child(row)
	row.add_child(_button("Add", func() -> void: add_layer("layer%d" % layer_count())))
	row.add_child(_button("Remove", func() -> void: _for_selected(func(i: int) -> void: remove_layer(i))))
	row.add_child(_button("Up", func() -> void: _for_selected(func(i: int) -> void: move_layer(i, i + 1))))
	row.add_child(_button("Down", func() -> void: _for_selected(func(i: int) -> void: move_layer(i, i - 1))))
	_mode_option = OptionButton.new()
	for m in [MaterialLayers.MODE_HEIGHT, MaterialLayers.MODE_SLOPE, MaterialLayers.MODE_NOISE,
			MaterialLayers.MODE_MASK, MaterialLayers.MODE_VERTEX_COLOR]:
		_mode_option.add_item(m)
	_mode_option.item_selected.connect(func(i: int) -> void:
		_for_selected(func(li: int) -> void: set_blend_mode(li, _mode_option.get_item_text(i))))
	add_child(_mode_option)
	_status = Label.new()
	add_child(_status)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _for_selected(cb: Callable) -> void:
	var sel: PackedInt32Array = _list.get_selected_items()
	if sel.size() > 0:
		cb.call(sel[0])


func _refresh() -> void:
	if _list == null:
		return
	_list.clear()
	for n in layer_names():
		_list.add_item(n)
	_status.text = "%d layers" % layer_count()
