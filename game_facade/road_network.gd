extends RefCounted
## Facade for CgameRoadNetwork (native) with GDScript fallback.
## Same API as res://scripts/shared/road_network.gd.

const Native = preload("res://game_facade/cgame_native.gd")
const Fallback = preload("res://scripts/shared/road_network.gd")
const NATIVE_CLASS := &"CgameRoadNetwork"


static func connect_sites(sites: PackedVector2Array, extra_edge_ratio: float = 0.15, seed: int = 0) -> Array:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return Array(n.call("connect_sites", sites, extra_edge_ratio, seed))
	return Fallback.connect_sites(sites, extra_edge_ratio, seed)


static func route_cost(a: Vector2, b: Vector2, height_at: Callable, slope_penalty: float) -> float:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("route_cost", a, b, height_at, slope_penalty)
	return Fallback.route_cost(a, b, height_at, slope_penalty)
