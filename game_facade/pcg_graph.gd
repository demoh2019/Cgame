@tool
extends RefCounted
## Facade for CgamePCGGraph (native) with GDScript fallback.
##
## `create()` returns a native CgamePCGGraph when the engine has the module, otherwise the
## GDScript res://scripts/shared/pcg_graph.gd. Both use the same method names and data
## model, so graphs are built and executed by duck typing:
##
##     var g = PCGGraph.create()
##     g.graph_seed = 42
##     g.add_graph_input("in_v", "volume", "volume")
##
## State that is a plain field in GDScript is a getter on the native class, so use the
## helpers below (`executed_nodes(g)`, `cache_hits(g)`, ...) when code must run on both.
## Custom nodes registered with `register_node()` work in both implementations.

const Native = preload("res://game_facade/cgame_native.gd")
const Fallback = preload("res://scripts/shared/pcg_graph.gd")
const Presets = preload("res://scripts/shared/pcg_presets.gd")
const NATIVE_CLASS := &"CgamePCGGraph"


static func is_native() -> bool:
	return Native.available(NATIVE_CLASS)


static func create(graph_seed: int = 0) -> RefCounted:
	var g: RefCounted = ClassDB.instantiate(NATIVE_CLASS) if Native.available(NATIVE_CLASS) else Fallback.new()
	g.set("graph_seed", graph_seed)
	return g


# ---- presets

static func forest_scatter(graph_seed: int = 1337) -> RefCounted:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("forest_scatter", graph_seed)
	return Presets.forest_scatter(graph_seed)


static func ruins_debris(graph_seed: int = 4242) -> RefCounted:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("ruins_debris", graph_seed)
	return Presets.ruins_debris(graph_seed)


static func cave_rocks(graph_seed: int = 9001) -> RefCounted:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("cave_rocks", graph_seed)
	return Presets.cave_rocks(graph_seed)


# ---- data constructors and helpers (static in both implementations)

static func make_points(positions: PackedVector3Array = PackedVector3Array()) -> Dictionary:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("make_points", positions)
	return Fallback.make_points(positions)


static func make_spline(pts: PackedVector3Array, closed: bool = false) -> Dictionary:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("make_spline", pts, closed)
	return Fallback.make_spline(pts, closed)


static func make_volume(box: AABB) -> Dictionary:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("make_volume", box)
	return Fallback.make_volume(box)


static func make_landscape(height_at: Callable, normal_at: Callable = Callable()) -> Dictionary:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("make_landscape", height_at, normal_at)
	return Fallback.make_landscape(height_at, normal_at)


static func point_count(d: Variant) -> int:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("point_count", d)
	return Fallback.point_count(d)


static func pins_compatible(from_type: String, to_type: String) -> bool:
	var n: RefCounted = Native.singleton(NATIVE_CLASS)
	if n != null:
		return n.call("pins_compatible", from_type, to_type)
	return Fallback.pins_compatible(from_type, to_type)


# ---- state accessors (field in GDScript, getter on the native class)

static func executed_nodes(g: RefCounted) -> Array:
	return g.call("get_executed_nodes") if g.has_method("get_executed_nodes") else g.get("executed_nodes")


static func cache_hits(g: RefCounted) -> int:
	return g.call("get_cache_hits") if g.has_method("get_cache_hits") else g.get("cache_hits")


static func last_errors(g: RefCounted) -> Array:
	return g.call("get_last_errors") if g.has_method("get_last_errors") else g.get("last_errors")


static func debug_records(g: RefCounted) -> Dictionary:
	return g.call("get_debug") if g.has_method("get_debug") else g.get("debug")


static func debug_steps(g: RefCounted) -> Array:
	return g.call("get_debug_steps") if g.has_method("get_debug_steps") else g.get("debug_steps")
