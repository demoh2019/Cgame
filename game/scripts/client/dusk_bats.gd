extends Node3D
## Dusk/night bats (RDR2 / Witcher 3 ambience) on the engine's native Flock3D:
## low cohesion and high separation give the jittery, darting bat flight.
## Fades in at dusk, stays through the night, leaves in storms and dungeons.
## Needs the engine fork's Flock3D; otherwise this node stays empty.

const BAT_SHADER := preload("res://assets/shaders/bat_flap.gdshader")
const MAX_BATS := 12
const ALTITUDE := 9.0


## Bats for a quality tier and time: none in daylight, storms or on Performance.
static func bat_count(level: int, daylight: float, storm: float) -> int:
	if level < 1 or storm > 0.4 or daylight > 0.45:
		return 0
	return 6 if level == 1 else MAX_BATS


var _flock: Node3D
var _jitter := 0.0


func _ready() -> void:
	if not ClassDB.class_exists("Flock3D"):
		return
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.mesh = _bat_mesh()
	m.instance_count = MAX_BATS
	m.visible_instance_count = 0
	var mat := ShaderMaterial.new()
	mat.shader = BAT_SHADER
	_flock = ClassDB.instantiate("Flock3D") as Node3D
	_flock.set("multimesh", m)
	_flock.set("material_override", mat)
	_flock.set("cast_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_flock.set("speed", 7.5)
	_flock.set("cohesion", 0.08)
	_flock.set("alignment", 0.1)
	_flock.set("separation", 6.0)
	_flock.set("separation_radius", 2.5)
	_flock.set("neighbor_radius", 5.0)
	_flock.set("home_radius", 12.0)
	_flock.set("bank", 0.2)
	_flock.set("active", false)
	_flock.visible = false
	add_child(_flock)


static func _bat_mesh() -> ArrayMesh:
	# Tiny body with scalloped membrane wings (x = span), ~0.4 m wide.
	var v := PackedVector3Array([
		Vector3(0, 0, 0.08), Vector3(0.03, 0, -0.06), Vector3(-0.03, 0, -0.06),
		Vector3(0.02, 0, 0.04), Vector3(0.2, 0, 0.03), Vector3(0.14, 0, -0.06),
		Vector3(0.02, 0, 0.04), Vector3(0.14, 0, -0.06), Vector3(0.03, 0, -0.05),
		Vector3(-0.02, 0, 0.04), Vector3(-0.14, 0, -0.06), Vector3(-0.2, 0, 0.03),
		Vector3(-0.02, 0, 0.04), Vector3(-0.03, 0, -0.05), Vector3(-0.14, 0, -0.06),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func update_view(player: Vector3, daylight: float, storm: float, level: int, delta: float, underground: bool) -> void:
	if _flock == null:
		return
	var want: int = 0 if underground else bat_count(level, daylight, storm)
	if want == 0:
		_flock.visible = false
		_flock.set("active", false)
		return
	if int(_flock.get("agent_count")) != want:
		_flock.set("agent_count", want)
	_flock.visible = true
	_flock.set("active", true)
	_flock.global_position = player + Vector3(0, ALTITUDE, 0)
	# Bats hunt insects: the swirl direction flips now and then for erratic loops.
	_jitter += delta
	_flock.set("orbit", 2.2 * signf(sin(_jitter * 0.7)) + 0.1)
