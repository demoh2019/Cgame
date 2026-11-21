@tool
extends RefCounted
## Facade for CgameTerrainEditLayers (native) with GDScript fallback.
##
## Use `create()` instead of `TerrainEditLayers.new()`. Both implementations expose the
## same method names, so the returned object is used by duck typing. The enums below
## have the same values as the native ones.
##
## The helpers at the bottom replace the editor panel's direct access to private
## fields (`_layers`, `_layer_index`, `_grow_bounds`, `_mark_rect_dirty`): they call the
## public native per-texel API and only fall back to the private fields for the
## GDScript implementation.

const Native = preload("res://scripts/native/cgame_native.gd")
const Fallback = preload("res://scripts/shared/terrain_edit_layers.gd")
const NATIVE_CLASS := &"CgameTerrainEditLayers"

enum Blend { ADD, MAX, REPLACE }
enum Brush { RAISE, LOWER, SMOOTH, FLATTEN, NOISE, ERODE }
enum Falloff { LINEAR, SMOOTH, SPHERE, CONSTANT }


static func is_native() -> bool:
	return Native.available(NATIVE_CLASS)


## Returns a new native CgameTerrainEditLayers, or the GDScript implementation.
static func create() -> RefCounted:
	if Native.available(NATIVE_CLASS):
		return ClassDB.instantiate(NATIVE_CLASS)
	return Fallback.new()


## Adds a layer pre-filled with `delta`/`alpha` for `rect` (row-major) and returns its id.
static func add_layer_from_region(edit: RefCounted, layer_name: String, rect: Rect2i, delta: PackedFloat32Array, alpha: PackedFloat32Array, blend: int = Blend.ADD, opacity: float = 1.0) -> int:
	if edit.has_method("add_layer_from_region"):
		return edit.call("add_layer_from_region", layer_name, rect, delta, alpha, blend, opacity)
	var id: int = edit.add_layer(layer_name, blend, opacity)
	write_layer_region(edit, id, rect, delta, alpha)
	return id


## Writes delta/alpha for a rect without going through the undo stack.
static func write_layer_region(edit: RefCounted, id: int, rect: Rect2i, delta: PackedFloat32Array, alpha: PackedFloat32Array) -> bool:
	if edit.has_method("write_layer_region"):
		return edit.call("write_layer_region", id, rect, delta, alpha)
	# GDScript fallback: same effect through the private fields.
	var idx: int = edit._layer_index(id)
	if idx < 0:
		return false
	var l = edit._layers[idx]
	var d: PackedFloat32Array = l.delta
	var a: PackedFloat32Array = l.alpha
	var k: int = 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			d[y * edit.width + x] = delta[k]
			a[y * edit.width + x] = alpha[k]
			k += 1
	l.delta = d
	l.alpha = a
	edit._grow_bounds(l, rect)
	edit._mark_rect_dirty(rect)
	return true


## Writes a single texel without going through the undo stack.
static func set_layer_texel(edit: RefCounted, id: int, x: int, y: int, delta: float, alpha: float = 1.0) -> bool:
	if edit.has_method("set_layer_texel"):
		return edit.call("set_layer_texel", id, x, y, delta, alpha)
	return write_layer_region(edit, id, Rect2i(x, y, 1, 1), PackedFloat32Array([delta]), PackedFloat32Array([alpha]))
