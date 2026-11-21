extends RefCounted
## Facade for CgameProceduralBuildings (native) with GDScript fallback.
## Same API as res://scripts/shared/procedural_buildings.gd.

const Native = preload("res://scripts/native/cgame_native.gd")
const Fallback = preload("res://scripts/shared/procedural_buildings.gd")
const NATIVE_CLASS := &"CgameProceduralBuildings"


static func building(seed: int, footprint: Vector2i, floors: int) -> Dictionary:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("building", seed, footprint, floors)
	return Fallback.building(seed, footprint, floors)


static func settlement(seed: int, center: Vector2, radius: float, count: int) -> Array:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("settlement", seed, center, radius, count)
	return Fallback.settlement(seed, center, radius, count)
