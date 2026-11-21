extends Node3D
## Cosmetic world dressing from the engine's PCG graphs: roadside props, biome ground clutter and ruin debris. One
## PCGComponent3D per graph streams 64 m cells around the player and draws them as MultiMesh instances with a visibility
## range. Purely client-side and cosmetic: no gameplay depends on it (loot and encounters are server-side, see
## scripts/server/pcg_spawns.gd). Does nothing on engines without the PCG classes or on the Performance quality tier.

const Defs = preload("res://scripts/shared/defs.gd")
const PcgGraphs = preload("res://scripts/shared/pcg_graphs.gd")
const ModelCatalog = preload("res://scripts/client/model_catalog.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const WorldRoads = preload("res://scripts/shared/world_roads.gd")

const CELL_SIZE := 64.0
const SETTLEMENT_KINDS := ["village", "farm", "outpost", "camp", "dock", "lighthouse", "tower"]
const REGION_REACH := 13 # Regions -13..12 on both axes: the whole island (as WorldRoads).
const HUB_CLEARANCE := 25.0 # Added to the hub's safe radius: no clutter on the plaza.
## The world's terrain functions are not thread-safe (cached region state), so the component bakes height, water and
## biome into grids on the main thread (BAKE_STEP metres) and the graph then runs on the worker pool reading only the
## grids. Engines without baking (older pcg_graph) fall back to main-thread cells.
const ASYNC_CELLS := true
const BAKE_STEP := 2.0
## Finished cells are written to disk and reloaded on the next run instead of regenerating. Bump CACHE_VERSION whenever
## world generation (heights, biomes, roads) or the graphs change meaning without changing their parameters.
const CACHE_DIR := "user://pcg_cache"
const CACHE_VERSION := 1
const REPOSITION_STEP := 8.0 # The streaming anchor follows the player in steps, not every frame.
const LEVEL_POLL_SECONDS := 2.0

## Budgets per GraphicsQuality level (0 Performance ... 3 Ultra). Level 0 draws nothing.
## radius: streaming radius in 64 m cells; range: visibility_range_end; spacing: lattice spacing override per graph.
const TIERS := [
	{},
	{"radius": 1, "range": 75.0, "clutter_spacing": 8.0, "roadside_spacing": 30.0, "debris_spacing": 9.0, "debris": false},
	{"radius": 2, "range": 120.0, "clutter_spacing": 6.0, "roadside_spacing": 22.0, "debris_spacing": 7.0, "debris": true},
	{"radius": 3, "range": 170.0, "clutter_spacing": 4.5, "roadside_spacing": 16.0, "debris_spacing": 5.5, "debris": true},
]

var world
var _level := -1
var _poll := 0.0
var _anchor: Node3D
var _components: Dictionary = {} # name -> PCGComponent3D
var _user_data: Dictionary = {}
var _exclusions: Array = []
var _last_anchor := Vector3(1.0e9, 0.0, 1.0e9)
static var _fallback_cache: Dictionary = {}
## Runtime PCG debugging: crosses at every generated point, coloured by asset (toggle with set_debug_draw).
static var debug_draw := false


## The budget of a quality level ({} = off). Pure: also used by tests.
static func budget(level: int) -> Dictionary:
	if not PcgGraphs.available():
		return {}
	return TIERS[clampi(level, 0, TIERS.size() - 1)]


func setup(p_world) -> bool:
	world = p_world
	if not PcgGraphs.available() or world == null:
		return false
	_anchor = Node3D.new()
	_anchor.name = "StreamAnchor"
	add_child(_anchor)
	_user_data = build_user_data(world)
	_exclusions = build_exclusions(world)
	_apply_level(GraphicsQuality.level())
	return true


## Position of the player; call every frame (cheap): moves the streaming anchor and re-reads the quality level now and then.
func update(position: Vector3, delta: float = 0.0) -> void:
	if world == null or _anchor == null:
		return
	_poll += delta
	if _poll >= LEVEL_POLL_SECONDS:
		_poll = 0.0
		if GraphicsQuality.level() != _level:
			_apply_level(GraphicsQuality.level())
	if _components.is_empty():
		return
	if Vector2(position.x - _last_anchor.x, position.z - _last_anchor.z).length() >= REPOSITION_STEP:
		_last_anchor = position
		_anchor.global_position = position


func component_names() -> Array:
	return _components.keys()


func _apply_level(level: int) -> void:
	_level = level
	for c in _components.values():
		c.clear()
		c.queue_free()
	_components.clear()
	var tier := budget(level)
	if tier.is_empty():
		return
	_make_component("roadside", PcgGraphs.roadside_dressing(), _roadside_meshes(), tier, {"spacing": tier["roadside_spacing"]}, true)
	_make_component("clutter", PcgGraphs.biome_clutter(), _clutter_meshes(), tier, {"spacing": tier["clutter_spacing"]}, false)
	if bool(tier["debris"]) and not _user_data["ruins"].is_empty():
		_make_component("debris", PcgGraphs.ruin_debris(), _debris_meshes(), tier, {"spacing": tier["debris_spacing"]}, true)
	_last_anchor = Vector3(1.0e9, 0.0, 1.0e9)


func _make_component(key: String, graph, meshes: Array[Mesh], tier: Dictionary, overrides: Dictionary, shadows: bool) -> void:
	if graph == null:
		return
	var c = ClassDB.instantiate("PCGComponent3D")
	c.name = "Pcg_" + key
	c.set_graph(graph)
	c.set_generation_seed(world.world_seed)
	c.set_extents(Vector3(0.0, 200.0, 0.0))
	c.set_overrides(overrides)
	c.set_height_sampler(Callable(world, "height_at"))
	c.set_biome_sampler(Callable(world, "biome_at"))
	c.set_water_sampler(Callable(world, "is_water"))
	c.set_user_data(_user_data)
	c.set_exclusions(_exclusions)
	var can_bake: bool = c.has_method("set_bake_step")
	c.set_async(ASYNC_CELLS and can_bake)
	if can_bake:
		c.set_bake_step(BAKE_STEP)
		c.set_persistent_cache_dir(CACHE_DIR)
		c.set_cache_version(CACHE_VERSION)
		c.set_debug_draw(debug_draw)
	c.set_cell_size(CELL_SIZE)
	c.set_streaming_radius(int(tier["radius"]))
	c.set_max_cells_per_frame(2 if (ASYNC_CELLS and can_bake) else 1)
	c.set_asset_meshes(meshes)
	c.set_cluster_instances(true)
	c.set_visibility_range_end(float(tier["range"]))
	c.set_cast_shadows(shadows)
	c.set_align_to_normal(false)
	add_child(c)
	c.set_streaming_target(c.get_path_to(_anchor))
	c.set_streaming_enabled(true)
	_components[key] = c


# --- Data from the world ------------------------------------------------------------------------------------------

## Road polylines ("roads") and ruined-city centres ("ruins") as PCG user data.
static func build_user_data(p_world) -> Dictionary:
	var roads: Array = []
	for road in p_world.roads.all_roads():
		var line := PackedVector3Array()
		for p: Vector2 in road["points"]:
			line.append(Vector3(p.x, 0.0, p.y))
		if line.size() >= 2:
			roads.append({"points": line, "width": WorldRoads.HALF_WIDTH * 2.0})
	var ruins: Array = []
	for rx in range(-REGION_REACH, REGION_REACH):
		for rz in range(-REGION_REACH, REGION_REACH):
			for site in p_world.poi.sites_in_region(rx, rz):
				if str(site["kind"]) == "city":
					ruins.append({"position": Vector3(float(site["x"]), float(site["y"]), float(site["z"]))})
	return {"roads": roads, "ruins": ruins}


## Hub plaza and settlements as exclusion cylinders.
static func build_exclusions(p_world) -> Array:
	var list: Array = [{"center": Vector3.ZERO, "radius": Defs.HUB_SAFE_RADIUS + HUB_CLEARANCE}]
	for rx in range(-REGION_REACH, REGION_REACH):
		for rz in range(-REGION_REACH, REGION_REACH):
			for site in p_world.poi.sites_in_region(rx, rz):
				if SETTLEMENT_KINDS.has(str(site["kind"])):
					list.append({"center": Vector3(float(site["x"]), 0.0, float(site["z"])), "radius": float(site["radius"])})
	return list


# --- Asset index -> mesh ------------------------------------------------------------------------------------------
# Index tables match the asset attributes documented per graph in pcg_graphs.gd. Missing models fall back to plain shapes.

func _roadside_meshes() -> Array[Mesh]:
	var out: Array[Mesh] = []
	for i in [0, 1, 4, 2, 5]: # barrel, crate, basket, bench, stool of ModelCatalog.PROPS
		out.append(_entry(ModelCatalog.PROPS, i, "box"))
	return out


func _clutter_meshes() -> Array[Mesh]:
	var out: Array[Mesh] = []
	for i in 4:
		var rock: Mesh = ModelCatalog.scanned_rock(i) if ModelCatalog.has_scanned_rocks() else ModelCatalog.stone(i)
		out.append(rock if rock != null else _fallback("rock"))
	for i in 2:
		var stone: Mesh = ModelCatalog.stone(i)
		out.append(stone if stone != null else _fallback("rock"))
	return out


func _debris_meshes() -> Array[Mesh]:
	var out: Array[Mesh] = []
	for i in [5, 6, 7]: # rubble_large, rubble_half, column of ModelCatalog.RUINS
		out.append(_entry(ModelCatalog.RUINS, i, "rock"))
	for i in 2:
		var stone: Mesh = ModelCatalog.stone(i + 2)
		out.append(stone if stone != null else _fallback("rock"))
	return out


func _entry(list: Array, index: int, fallback: String) -> Mesh:
	var entry: Dictionary = list[index]
	if ModelCatalog.exists(String(entry["path"])) and (not entry.has("tex") or ModelCatalog.exists(String(entry["tex"]))):
		var mesh := ModelCatalog.entry_mesh(entry)
		if mesh != null:
			return mesh
	return _fallback(fallback)


static func _fallback(kind: String) -> Mesh:
	if _fallback_cache.has(kind):
		return _fallback_cache[kind]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.43, 0.4) if kind == "rock" else Color(0.5, 0.36, 0.22)
	material.roughness = 1.0
	var mesh: PrimitiveMesh
	if kind == "rock":
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 1.4
		sphere.radial_segments = 7
		sphere.rings = 4
		mesh = sphere
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.8, 0.8, 0.8)
		mesh = box
	mesh.material = material
	_fallback_cache[kind] = mesh
	return mesh


## Shows or hides the PCG debug points on every dressing component (regenerates the loaded cells).
func set_debug_draw(enabled: bool) -> void:
	debug_draw = enabled
	for key in _components:
		var c = _components[key]
		if c.has_method("set_debug_draw"):
			c.set_debug_draw(enabled)
			c.clear()
