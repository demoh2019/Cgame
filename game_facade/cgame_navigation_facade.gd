extends RefCounted
## Single entry point for the navigation helpers. Uses the native C++ classes of the
## `cgame_navigation` engine module (CgameNavmeshBaker, CgameOffMeshLinkGenerator,
## CgameHierarchicalPathfinder, CgameDynamicCarver) when the running engine has them, and falls
## back to the GDScript implementations under res://scripts/shared/ otherwise. Both back ends
## expose the same method names, so callers only differ in how the objects are created, which
## this class hides. Pass `force_gdscript = true` to compare back ends or to debug.
##
## Differences callers must respect (the helpers below paper over them):
##  - The native baker bakes through NavigationServer3D (Recast). With a dummy server (headless
##    without a navigation backend) it returns tiles with "baked" == false and no polygons;
##    use `baker_can_bake()` to check. The GDScript baker always bakes.
##  - `tile_to_navigation_mesh()` hides the different method names for tile -> NavigationMesh.
##  - Native-only extras (plan_on_map, set_server_map, export_obstructions, create_links_on_map)
##    are exposed through `is_native()` guarded helpers and are no-ops on the fallback.

const _HPA_SCRIPT = preload("res://scripts/shared/hierarchical_pathfinder.gd")
const _OFF_MESH_SCRIPT = preload("res://scripts/shared/off_mesh_links.gd")
const _BAKER_SCRIPT = preload("res://scripts/shared/navmesh_baker.gd")
const _CARVING_SCRIPT = preload("res://scripts/shared/navmesh_carving.gd")


## True when the engine was built with the cgame_navigation module.
static func is_native() -> bool:
	return ClassDB.class_exists("CgameHierarchicalPathfinder")


static func _use_native(force_gdscript: bool, native_class: String) -> bool:
	return not force_gdscript and ClassDB.class_exists(native_class)


## HPA* pathfinder over a walkability grid. `walkable` is `func(x: int, y: int) -> bool`.
static func make_hpa(width: int, height: int, cluster_size: int, walkable: Callable, force_gdscript: bool = false) -> Object:
	var pf: Object
	if _use_native(force_gdscript, "CgameHierarchicalPathfinder"):
		pf = ClassDB.instantiate("CgameHierarchicalPathfinder")
	else:
		pf = _HPA_SCRIPT.new()
	pf.build(width, height, cluster_size, walkable)
	return pf


## Navmesh baker. `config` uses the keys of the GDScript baker (cell_size, agent_radius, ...).
static func make_baker(config: Dictionary = {}, force_gdscript: bool = false) -> Object:
	var baker: Object
	if _use_native(force_gdscript, "CgameNavmeshBaker"):
		baker = ClassDB.instantiate("CgameNavmeshBaker")
	else:
		baker = _BAKER_SCRIPT.new()
	baker.configure(config)
	return baker


## True when `baker` can produce tiles (GDScript baker always; native needs a real NavigationServer3D).
static func baker_can_bake(baker: Object) -> bool:
	if baker.get_class() != "CgameNavmeshBaker":
		return true
	return bool(baker.can_bake())


## NavigationMesh for a baked tile, regardless of back end.
static func tile_to_navigation_mesh(baker: Object, tile: Dictionary) -> NavigationMesh:
	if baker.has_method("tile_to_navigation_mesh"):
		return baker.tile_to_navigation_mesh(tile)
	return baker.to_navigation_mesh(tile)


## Dynamic obstacle carver with a tile rebake budget.
static func make_carver(bounds: Rect2, tile_size: float, agent_radius: float, force_gdscript: bool = false) -> Object:
	var carver: Object
	if _use_native(force_gdscript, "CgameDynamicCarver"):
		carver = ClassDB.instantiate("CgameDynamicCarver")
	else:
		carver = _CARVING_SCRIPT.new()
	carver.setup(bounds, tile_size, agent_radius)
	return carver


## Off-mesh links (drop / jump / gap) from a heightfield. Returns Array of
## {from: Vector2i, to: Vector2i, kind: String, bidirectional: bool}.
static func generate_off_mesh_links(width: int, height: int, height_at: Callable, walkable: Callable,
		max_drop: float = 3.0, max_jump_up: float = 1.2, max_gap: int = 2, walk_step: float = 0.5,
		force_gdscript: bool = false) -> Array:
	if _use_native(force_gdscript, "CgameOffMeshLinkGenerator"):
		var gen: Object = ClassDB.instantiate("CgameOffMeshLinkGenerator")
		return gen.generate(width, height, height_at, walkable, max_drop, max_jump_up, max_gap, walk_step)
	return _OFF_MESH_SCRIPT.generate(width, height, height_at, walkable, max_drop, max_jump_up, max_gap, walk_step)


## Chains NavigationServer3D paths across region corridors (native only). Empty on the fallback.
static func plan_on_map(pf: Object, map_rid: RID, from: Vector3, to: Vector3, region_size: float) -> PackedVector3Array:
	if pf.has_method("plan_on_map"):
		return pf.plan_on_map(map_rid, from, to, region_size)
	return PackedVector3Array()


## Mirrors the carver's obstacles on a NavigationServer3D map (native only, no-op otherwise).
static func carver_set_server_map(carver: Object, map_rid: RID, y: float = 0.0, height: float = 2.0) -> void:
	if carver.has_method("set_server_map"):
		carver.set_server_map(map_rid, y, height)
