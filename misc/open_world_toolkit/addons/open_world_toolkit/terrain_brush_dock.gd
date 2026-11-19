@tool
extends VBoxContainer
class_name OWTerrainBrushDock
## Minimal dock for sculpt, splat paint, noise generation and erosion.

signal generate_requested
signal erode_requested
signal foliage_requested

var paint_enabled: CheckButton
var mode: OptionButton
var radius: SpinBox
var strength: SpinBox
var flatten_height: SpinBox
var noise_seed: SpinBox
var noise_amplitude: SpinBox
var erosion_iterations: SpinBox
var current_terrain: OWTerrain3D


func _ready() -> void:
	name = "World Terrain"
	var heading := Label.new()
	heading.text = "Open World Toolkit"
	add_child(heading)
	var note := Label.new()
	note.text = "Select an OWTerrain3D node to edit it."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	paint_enabled = CheckButton.new()
	paint_enabled.text = "Sculpt in 3D viewport"
	add_child(paint_enabled)
	mode = OptionButton.new()
	for title in ["Raise", "Lower", "Smooth", "Flatten", "Paint layer 2", "Erase layer 2"]:
		mode.add_item(title)
	add_child(mode)
	radius = _add_numeric("Brush radius (world units)", 0.1, 256.0, 5.0, 0.1)
	strength = _add_numeric("Brush strength", 0.001, 100.0, 1.0, 0.1)
	flatten_height = _add_numeric("Flatten height", -10000.0, 10000.0, 0.0, 0.25)
	var separator := HSeparator.new()
	add_child(separator)
	noise_seed = _add_numeric("Noise seed", 0, 1000000, 123, 1)
	noise_amplitude = _add_numeric("Noise amplitude", 0.0, 1000.0, 8.0, 0.5)
	var generate_button := Button.new()
	generate_button.text = "Generate heightfield"
	generate_button.pressed.connect(func(): generate_requested.emit())
	add_child(generate_button)
	erosion_iterations = _add_numeric("Thermal erosion passes", 1, 50, 8, 1)
	var erosion_button := Button.new()
	erosion_button.text = "Apply thermal erosion"
	erosion_button.pressed.connect(func(): erode_requested.emit())
	add_child(erosion_button)
	var foliage_button := Button.new()
	foliage_button.text = "Scatter linked foliage"
	foliage_button.pressed.connect(func(): foliage_requested.emit())
	add_child(foliage_button)


func _add_numeric(label_text: String, low: float, high: float, value: float, increment: float) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = increment
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spin)
	return spin


func set_terrain(terrain: OWTerrain3D) -> void:
	current_terrain = terrain
	if paint_enabled != null and terrain == null:
		paint_enabled.button_pressed = false


func apply_brush(local_position: Vector3) -> bool:
	if current_terrain == null or current_terrain.heightmap == null:
		return false
	var data := current_terrain.heightmap
	var point := Vector2(local_position.x, local_position.z)
	match mode.selected:
		0: return data.sculpt(point.x, point.y, radius.value, strength.value * 0.1, OWHeightmap.SculptMode.RAISE)
		1: return data.sculpt(point.x, point.y, radius.value, strength.value * 0.1, OWHeightmap.SculptMode.LOWER)
		2: return data.sculpt(point.x, point.y, radius.value, strength.value * 0.1, OWHeightmap.SculptMode.SMOOTH)
		3: return data.sculpt(point.x, point.y, radius.value, strength.value * 0.1, OWHeightmap.SculptMode.FLATTEN, flatten_height.value)
		4: return data.paint(point.x, point.y, radius.value, strength.value * 0.1, 1)
		5: return data.paint(point.x, point.y, radius.value, strength.value * 0.1, 0)
	return false