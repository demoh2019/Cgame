extends Node3D
## Fish shoals in lakes and rivers (RDR2-style living water) on the engine's
## native Flock3D boids: one shoal near the player, below the surface, only where
## the water around it is deep enough. One MultiMesh draw call, no script per fish.
## Needs the engine fork's Flock3D; otherwise this node stays empty.

const Defs = preload("res://scripts/shared/defs.gd")
const FISH_SHADER := preload("res://assets/shaders/fish_swim.gdshader")
const MIN_DEPTH := 1.3
const SHOAL_RADIUS := 5.0
const SEARCH_INTERVAL := 1.0
const MAX_FISH := 14

var _flock: Node3D
var _search_left := 0.0
var _anchor := Vector3.INF


## Fish per shoal for a quality tier (Performance: none).
static func shoal_size(level: int) -> int:
	return [0, 6, 10, MAX_FISH][clampi(level, 0, 3)]


## True when a whole shoal circle around (x, z) is deep enough water.
static func deep_enough(world, x: float, z: float) -> bool:
	for i in 9:
		var ox := 0.0
		var oz := 0.0
		if i > 0:
			var a := TAU * float(i) / 8.0
			ox = cos(a) * (SHOAL_RADIUS + 1.0)
			oz = sin(a) * (SHOAL_RADIUS + 1.0)
		if Defs.WATER_LEVEL - world.height_at(x + ox, z + oz) < MIN_DEPTH:
			return false
	return true


func _ready() -> void:
	if not ClassDB.class_exists("Flock3D"):
		return
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.mesh = _fish_mesh()
	m.instance_count = MAX_FISH
	m.visible_instance_count = 0
	var mat := ShaderMaterial.new()
	mat.shader = FISH_SHADER
	_flock = ClassDB.instantiate("Flock3D") as Node3D
	_flock.set("multimesh", m)
	_flock.set("material_override", mat)
	_flock.set("cast_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_flock.set("speed", 1.6)
	_flock.set("separation_radius", 0.45)
	_flock.set("neighbor_radius", 2.5)
	_flock.set("cohesion", 0.8)
	_flock.set("orbit", 0.5)
	_flock.set("home_radius", SHOAL_RADIUS)
	_flock.set("bank", 0.02)
	_flock.set("active", false)
	_flock.visible = false
	add_child(_flock)


static func _fish_mesh() -> ArrayMesh:
	# Small streamlined body (+Z nose) with a forked tail, ~0.35 m.
	var v := PackedVector3Array([
		Vector3(0, 0, 0.18), Vector3(0.045, 0.02, 0.0), Vector3(0, 0.05, -0.02),
		Vector3(0, 0, 0.18), Vector3(0, 0.05, -0.02), Vector3(-0.045, 0.02, 0.0),
		Vector3(0.045, 0.02, 0.0), Vector3(0, 0.0, -0.14), Vector3(0, 0.05, -0.02),
		Vector3(-0.045, 0.02, 0.0), Vector3(0, 0.05, -0.02), Vector3(0, 0.0, -0.14),
		Vector3(0, 0.01, -0.13), Vector3(0, 0.06, -0.21), Vector3(0, -0.04, -0.21),
	])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in v:
		st.add_vertex(p)
	st.generate_normals()
	return st.commit()


func update_view(world, player: Vector3, level: int, daylight: float, delta: float, underground: bool) -> void:
	if _flock == null:
		return
	var want: int = 0 if underground else shoal_size(level)
	if want == 0 or world == null:
		_flock.visible = false
		_flock.set("active", false)
		_anchor = Vector3.INF
		return
	_search_left -= delta
	if _search_left <= 0.0:
		_search_left = SEARCH_INTERVAL
		# Keep the current shoal while the player stays close; else look for new water.
		if _anchor == Vector3.INF or Vector2(_anchor.x - player.x, _anchor.z - player.z).length() > 30.0:
			_anchor = _find_water(world, player)
			if _anchor != Vector3.INF:
				_flock.global_position = _anchor
				_flock.set("agent_count", want) # Re-scatters the shoal at the new spot.
	var has_water: bool = _anchor != Vector3.INF
	_flock.visible = has_water
	_flock.set("active", has_water)
	# Fish go deeper and quieter at night.
	if has_water:
		_flock.set("speed", lerpf(0.8, 1.6, clampf(daylight, 0.0, 1.0)))


func _find_water(world, player: Vector3) -> Vector3:
	for ring in [8.0, 14.0, 20.0]:
		for i in 8:
			var a := TAU * float(i) / 8.0
			var x: float = player.x + cos(a) * ring
			var z: float = player.z + sin(a) * ring
			if deep_enough(world, x, z):
				var depth: float = Defs.WATER_LEVEL - world.height_at(x, z)
				return Vector3(x, Defs.WATER_LEVEL - minf(depth * 0.5, 1.2), z)
	return Vector3.INF
