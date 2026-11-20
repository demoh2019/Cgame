extends Node3D
## Dragonflies skimming over water on warm days (Ghost of Tsushima / RDR2 nature
## ambience) on the engine's native Flock3D: fast, low-cohesion darting just
## above the surface near the player. Empty on engines without Flock3D.

const Defs = preload("res://scripts/shared/defs.gd")
const FishShoals = preload("res://scripts/client/fish_shoals.gd")
const MAX_FLIES := 8

var _flock: Node3D
var _anchor := Vector3.INF
var _search_left := 0.0


static func count(level: int, daylight: float, storm: float) -> int:
	if level < 2 or daylight < 0.5 or storm > 0.2:
		return 0
	return MAX_FLIES if level >= 3 else 4


func _ready() -> void:
	if not ClassDB.class_exists("Flock3D"):
		return
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.mesh = _fly_mesh()
	m.instance_count = MAX_FLIES
	m.visible_instance_count = 0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.45, 0.55)
	mat.metallic = 0.6
	mat.roughness = 0.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flock = ClassDB.instantiate("Flock3D") as Node3D
	_flock.set("multimesh", m)
	_flock.set("material_override", mat)
	_flock.set("speed", 3.5)
	_flock.set("cohesion", 0.05)
	_flock.set("alignment", 0.05)
	_flock.set("separation", 4.0)
	_flock.set("separation_radius", 1.5)
	_flock.set("home_radius", 6.0)
	_flock.set("orbit", 1.8)
	_flock.set("active", false)
	_flock.visible = false
	add_child(_flock)


static func _fly_mesh() -> ArrayMesh:
	# Slim body along +Z with two pairs of flat wings.
	var v := PackedVector3Array([
		Vector3(0, 0, 0.07), Vector3(0.01, 0, -0.08), Vector3(-0.01, 0, -0.08),
		Vector3(0, 0, 0.03), Vector3(0.09, 0, 0.04), Vector3(0.09, 0, 0.0),
		Vector3(0, 0, 0.03), Vector3(-0.09, 0, 0.0), Vector3(-0.09, 0, 0.04),
		Vector3(0, 0, -0.0), Vector3(0.08, 0, -0.01), Vector3(0.08, 0, -0.04),
		Vector3(0, 0, -0.0), Vector3(-0.08, 0, -0.04), Vector3(-0.08, 0, -0.01),
	])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in v:
		st.add_vertex(p)
	st.generate_normals()
	return st.commit()


func update_view(world, player: Vector3, daylight: float, storm: float, level: int, delta: float, underground: bool) -> void:
	if _flock == null:
		return
	var want: int = 0 if underground or world == null else count(level, daylight, storm)
	if want == 0:
		_flock.visible = false
		_flock.set("active", false)
		_anchor = Vector3.INF
		return
	_search_left -= delta
	if _search_left <= 0.0:
		_search_left = 1.5
		if _anchor == Vector3.INF or Vector2(_anchor.x - player.x, _anchor.z - player.z).length() > 25.0:
			_anchor = Vector3.INF
			for ring in [6.0, 12.0, 18.0]:
				for i in 8:
					var a := TAU * float(i) / 8.0
					var x: float = player.x + cos(a) * ring
					var z: float = player.z + sin(a) * ring
					if FishShoals.deep_enough(world, x, z):
						_anchor = Vector3(x, Defs.WATER_LEVEL + 0.6, z)
						break
				if _anchor != Vector3.INF:
					break
			if _anchor != Vector3.INF:
				_flock.global_position = _anchor
				_flock.set("agent_count", want)
	var on: bool = _anchor != Vector3.INF
	_flock.visible = on
	_flock.set("active", on)
