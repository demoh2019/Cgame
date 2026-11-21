@tool
extends RefCounted
## Facade for CgameTerrainSplines (native) with GDScript fallback.
## Same API as res://scripts/shared/terrain_splines.gd.

const Native = preload("res://scripts/native/cgame_native.gd")
const Fallback = preload("res://scripts/shared/terrain_splines.gd")
const NATIVE_CLASS := &"CgameTerrainSplines"


static func catmull_rom(points: PackedVector3Array, samples_per_segment: int) -> PackedVector3Array:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("catmull_rom", points, samples_per_segment)
	return Fallback.catmull_rom(points, samples_per_segment)


static func distance_to_polyline(p: Vector2, polyline: PackedVector2Array) -> float:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("distance_to_polyline", p, polyline)
	return Fallback.distance_to_polyline(p, polyline)


static func deform(heights: PackedFloat32Array, width: int, height: int, cell_size: float, spline: PackedVector3Array, half_width: float, falloff: float, mode: String) -> PackedFloat32Array:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("deform", heights, width, height, cell_size, spline, half_width, falloff, mode)
	return Fallback.deform(heights, width, height, cell_size, spline, half_width, falloff, mode)


static func bridge_spans(heights: PackedFloat32Array, width: int, height: int, cell_size: float, spline: PackedVector3Array, clearance: float = 2.0) -> Array:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return Array(n.call("bridge_spans", heights, width, height, cell_size, spline, clearance))
	return Fallback.bridge_spans(heights, width, height, cell_size, spline, clearance)
