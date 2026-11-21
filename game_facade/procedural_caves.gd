extends RefCounted
## Facade for CgameProceduralCaves (native) with GDScript fallback.
## Same API as res://scripts/shared/procedural_caves.gd.

const Native = preload("res://game_facade/cgame_native.gd")
const Fallback = preload("res://scripts/shared/procedural_caves.gd")
const NATIVE_CLASS := &"CgameProceduralCaves"


static func generate(width: int, height: int, seed: int, fill: float = 0.47, steps: int = 5) -> PackedByteArray:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("generate", width, height, seed, fill, steps)
	return Fallback.generate(width, height, seed, fill, steps)


static func regions(grid: PackedByteArray, w: int, h: int) -> Array:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("regions", grid, w, h)
	return Fallback.regions(grid, w, h)


static func chambers(grid: PackedByteArray, w: int, h: int, min_size: int) -> Array:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("chambers", grid, w, h, min_size)
	return Fallback.chambers(grid, w, h, min_size)
