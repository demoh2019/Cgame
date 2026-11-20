extends Node3D
## Atmospheric detail without a particle simulator or per-mote draw calls.
## One 3x3 camera-local grid, one persistent GPU MultiMesh, and one shader.
## Stable per-world-tile positions avoid popping while crossing chunk borders.

const TILE_SIZE := 42.0
const GRID_SIDE := 3
const CELL_COUNT := GRID_SIDE * GRID_SIDE
const MAX_PER_TILE := 28
const MAX_INSTANCES := CELL_COUNT * MAX_PER_TILE
const UPDATE_INTERVAL := 0.25
const PRESETS := [
	{"per_tile": 0, "radius": 0.0},
	{"per_tile": 8, "radius": 36.0},
	{"per_tile": 16, "radius": 48.0},
	{"per_tile": 28, "radius": 64.0},
]

var _world
var _batch: MultiMesh
var _renderer: MultiMeshInstance3D
var _material: ShaderMaterial
var _center_cell := Vector2i(1000000, 1000000)
var _elapsed := UPDATE_INTERVAL
var _generated_tiles := 0


static func profile(level: int) -> Dictionary:
	return PRESETS[clampi(level, 0, PRESETS.size() - 1)].duplicate(true)


static func tile_seed(cell: Vector2i) -> int:
	# Deterministic integer hashing, independent of frame count and CPU/GPU.
	return (cell.x * 73856093) ^ (cell.y * 19349663) ^ 9023141


static func grid_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(floori(world_position.x / TILE_SIZE),
		floori(world_position.z / TILE_SIZE))


## Pure cinematic rules. Night forest/swamp fireflies; in warm, dry weather
## sunlight catches pollen near the camera. Rain suppresses both effects.
static func visibility(biome: String, daylight: float, storm: float, level: int) -> Dictionary:
	var p: Dictionary = profile(level)
	if int(p["per_tile"]) == 0:
		return {"fireflies": 0.0, "pollen": 0.0, "count": 0,
			"radius": 0.0}
	var sun: float = clampf(daylight, 0.0, 1.0)
	var rain: float = clampf(storm, 0.0, 1.0)
	var day_factor: float = smoothstep(0.20, 0.70, sun)
	var night_factor: float = 1.0 - smoothstep(0.07, 0.35, sun)
	var firefly_biome := 1.0 if biome == "swamp" else (
		0.65 if biome == "forest" else 0.0)
	var pollen_biome := 0.0
	match biome:
		"forest":
			pollen_biome = 0.45
		"plains":
			pollen_biome = 0.60
		"beach":
			pollen_biome = 0.30
		"mountain":
			pollen_biome = 0.23
		"swamp":
			pollen_biome = 0.12
	var fireflies: float = night_factor * firefly_biome * (1.0 - rain * 0.92)
	var pollen: float = day_factor * pollen_biome * (1.0 - rain * 0.96)
	return {
		"fireflies": clampf(fireflies, 0.0, 1.0),
		"pollen": clampf(pollen, 0.0, 1.0),
		"count": CELL_COUNT * int(p["per_tile"]),
		"radius": float(p["radius"]),
	}


func setup(world) -> void:
	_world = world


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_material = ShaderMaterial.new()
	_material.shader = load("res://assets/shaders/ambient_motes.gdshader")
	quad.material = _material
	_batch = MultiMesh.new()
	_batch.transform_format = MultiMesh.TRANSFORM_3D
	_batch.use_custom_data = true
	_batch.mesh = quad
	_batch.instance_count = MAX_INSTANCES
	_batch.visible_instance_count = 0
	_renderer = MultiMeshInstance3D.new()
	_renderer.name = "AtmosphericPollenAndFireflies"
	_renderer.multimesh = _batch
	_renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The stable 3x3 grid spans [-42,84] from its anchor, with bounded
	# vertex drift; cliffs/mountains still fit into the culling volume.
	_renderer.custom_aabb = AABB(Vector3(-44.0, -180.0, -44.0),
		Vector3(TILE_SIZE * 3.0 + 4.0, 500.0, TILE_SIZE * 3.0 + 4.0))
	_renderer.visible = false
	add_child(_renderer)


## One update per quarter-second; no per-mote CPU work while standing still.
## The world input is the same height-map model the chunk streamer uses.
func update_view(center: Vector3, biome: String, daylight: float,
		storm: float, wind: Vector2, level: int, delta: float) -> void:
	if _batch == null or _renderer == null:
		return
	_elapsed += clampf(delta, 0.0, UPDATE_INTERVAL)
	if _elapsed < UPDATE_INTERVAL:
		return
	_elapsed = 0.0
	var state: Dictionary = visibility(biome, daylight, storm, level)
	var should_show: bool = int(state["count"]) > 0 and (
		float(state["fireflies"]) > 0.005 or float(state["pollen"]) > 0.005)
	_renderer.visible = should_show
	if not should_show:
		_batch.visible_instance_count = 0
		return
	var cell: Vector2i = grid_cell(center)
	if cell != _center_cell:
		_regenerate(cell)
		_center_cell = cell
	# Interleaved instance order keeps every grid tile represented even
	# when a lower quality preset reduces the visible instance count.
	_batch.visible_instance_count = int(state["count"])
	_material.set_shader_parameter("firefly_strength", float(state["fireflies"]))
	_material.set_shader_parameter("pollen_strength", float(state["pollen"]))
	_material.set_shader_parameter("fade_distance", float(state["radius"]))
	_material.set_shader_parameter("ambient_wind", wind.limit_length(10.0))


func _regenerate(cell: Vector2i) -> void:
	position = Vector3(float(cell.x) * TILE_SIZE, 0.0, float(cell.y) * TILE_SIZE)
	for tile_index in CELL_COUNT:
		var tile: Vector2i = cell + Vector2i(
			tile_index % GRID_SIDE - 1, int(tile_index / GRID_SIDE) - 1)
		var rng := RandomNumberGenerator.new()
		rng.seed = tile_seed(tile)
		for j in MAX_PER_TILE:
			var x: float = (float(tile.x) + rng.randf()) * TILE_SIZE
			var z: float = (float(tile.y) + rng.randf()) * TILE_SIZE
			var ground: float = 0.0
			if _world != null and _world.has_method("height_at"):
				ground = float(_world.call("height_at", x, z))
			# Emphasize low-level mist/light, never cloud-height particles.
			var y: float = ground + rng.randf_range(0.8, 3.8)
			var is_firefly: bool = j % 3 == 0
			var phase: float = rng.randf()
			var pulse: float = rng.randf()
			var brightness: float = rng.randf_range(0.52, 1.0)
			var slot: int = j * CELL_COUNT + tile_index
			_batch.set_instance_transform(slot, Transform3D(Basis(),
				Vector3(x - position.x, y, z - position.z)))
			_batch.set_instance_custom_data(slot, Color(
				1.0 if is_firefly else 0.0, phase, pulse, brightness))
	_generated_tiles += CELL_COUNT
