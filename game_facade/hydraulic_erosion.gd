extends RefCounted
## Facade for CgameHydraulicErosion (native) with GDScript fallback.
## Same API as res://scripts/shared/hydraulic_erosion.gd.

const Native = preload("res://game_facade/cgame_native.gd")
const Fallback = preload("res://scripts/shared/hydraulic_erosion.gd")
const NATIVE_CLASS := &"CgameHydraulicErosion"


static func erode(heights: PackedFloat32Array, width: int, height: int, droplets: int, seed: int, params: Dictionary = {}) -> PackedFloat32Array:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("erode", heights, width, height, droplets, seed, params)
	return Fallback.erode(heights, width, height, droplets, seed, params)


static func thermal(heights: PackedFloat32Array, width: int, height: int, iterations: int, talus: float = 0.6) -> PackedFloat32Array:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("thermal", heights, width, height, iterations, talus)
	return Fallback.thermal(heights, width, height, iterations, talus)


static func max_slope(heights: PackedFloat32Array, width: int, height: int) -> float:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("max_slope", heights, width, height)
	return Fallback.max_slope(heights, width, height)
