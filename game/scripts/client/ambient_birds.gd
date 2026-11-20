extends MultiMeshInstance3D
## Ambient bird flock (RDR2 / Far Cry style "life in the sky"): a small boids
## flock (cohesion, alignment, separation, home pull) circles above the player
## in daylight and scatters away when a storm comes. One MultiMesh draw call;
## wing flaps run in the vertex shader. Client-only, no gameplay effect.

const FLAP_SHADER := preload("res://assets/shaders/bird_flap.gdshader")
const MAX_BIRDS := 18
const ALTITUDE := 22.0
const SPEED := 6.5

var _pos: PackedVector3Array = []
var _vel: PackedVector3Array = []
var _active := 0
var _home := Vector3.ZERO
var _fade := 0.0
var _native: Node3D # Engine Flock3D when available: the boids run in C++.


## How many birds to show: none at night, in storms or on Performance; Balanced gets a small flock.
static func flock_size(level: int, daylight: float, storm: float) -> int:
	if level < 1 or daylight < 0.35 or storm > 0.5:
		return 0
	return 8 if level == 1 else MAX_BIRDS


## One boids steering step for bird `i` (pure; tested).
static func steer(i: int, pos: PackedVector3Array, vel: PackedVector3Array, count: int, home: Vector3) -> Vector3:
	var center := Vector3.ZERO
	var align := Vector3.ZERO
	var separate := Vector3.ZERO
	var n := 0
	for j in count:
		if j == i:
			continue
		var d: Vector3 = pos[i] - pos[j]
		var dist := d.length()
		if dist < 8.0:
			center += pos[j]
			align += vel[j]
			n += 1
			if dist < 1.6 and dist > 0.001:
				separate += d / (dist * dist)
	var force := Vector3.ZERO
	if n > 0:
		force += (center / n - pos[i]) * 0.35
		force += (align / n - vel[i]) * 0.5
	force += separate * 2.5
	# Orbit the home point: pull back plus a tangential swirl, hold altitude.
	var to_home := home - pos[i]
	to_home.y = 0.0
	force += to_home * 0.04 + Vector3(-to_home.z, 0.0, to_home.x).normalized() * 1.2
	force.y += (home.y - pos[i].y) * 0.6
	return force


func _init() -> void:
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_custom_data = true
	m.mesh = _bird_mesh()
	m.instance_count = MAX_BIRDS
	m.visible_instance_count = 0
	multimesh = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = FLAP_SHADER
	mat.set_shader_parameter("body_color", plumage(""))
	material_override = mat
	_pos.resize(MAX_BIRDS)
	_vel.resize(MAX_BIRDS)
	for i in MAX_BIRDS:
		_pos[i] = Vector3(randf_range(-6, 6), randf_range(-2, 2), randf_range(-6, 6))
		_vel[i] = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * SPEED
		m.set_instance_custom_data(i, Color(randf(), randf(), 0.0, 0.0))
	if ClassDB.class_exists("Flock3D"):
		_native = ClassDB.instantiate("Flock3D") as Node3D
		_native.set("multimesh", m)
		_native.set("material_override", mat)
		_native.set("cast_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_native.set("speed", SPEED)
		_native.set("agent_scale", 1.4)
		_native.set("active", false)
		_native.visible = false
		add_child(_native)
		multimesh = null # The native child draws it; never draw the flock twice.


static func _bird_mesh() -> ArrayMesh:
	# Low-poly gull silhouette: body diamond + two swept wings (x = span).
	var v := PackedVector3Array([
		Vector3(0, 0, 0.35), Vector3(0.06, 0, 0), Vector3(0, 0, -0.3),
		Vector3(0, 0, 0.35), Vector3(0, 0, -0.3), Vector3(-0.06, 0, 0),
		Vector3(0.05, 0, 0.1), Vector3(0.55, 0, -0.12), Vector3(0.05, 0, -0.08),
		Vector3(-0.05, 0, 0.1), Vector3(-0.05, 0, -0.08), Vector3(-0.55, 0, -0.12),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var nrm := PackedVector3Array()
	nrm.resize(v.size())
	nrm.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = nrm
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Gull-white over coasts and water, dark corvids inland.
static func plumage(biome: String) -> Color:
	return Color(0.86, 0.87, 0.88) if biome == "beach" or biome == "water" else Color(0.08, 0.08, 0.09)


func update_view(player: Vector3, daylight: float, storm: float, level: int, delta: float, underground: bool, biome: String = "") -> void:
	var mat := material_override as ShaderMaterial
	if mat != null and biome != "":
		var target: Color = plumage(biome)
		var current: Color = mat.get_shader_parameter("body_color")
		if not current.is_equal_approx(target):
			mat.set_shader_parameter("body_color", current.lerp(target, clampf(delta * 0.5, 0.0, 1.0)))
	var want: int = 0 if underground else flock_size(level, daylight, storm)
	if want > 0:
		_active = want
	_fade = move_toward(_fade, 1.0 if want > 0 else 0.0, delta * 0.3)
	if _native != null:
		_update_native(player, want)
		return
	if _active == 0 or _fade <= 0.0:
		multimesh.visible_instance_count = 0
		_active = 0 if _fade <= 0.0 else _active
		return
	_home = player + Vector3(0, ALTITUDE, 0)
	# When leaving (storm/night), fly away upwards instead of popping out.
	var leaving := want == 0
	var dt := minf(delta, 0.1)
	for i in _active:
		var f := steer(i, _pos, _vel, _active, Vector3.ZERO if not leaving else Vector3(0, 40, 0))
		if leaving:
			f += Vector3(_vel[i].x, 4.0, _vel[i].z).normalized() * 3.0
		var nv: Vector3 = (_vel[i] + f * dt).limit_length(SPEED * 1.3)
		if nv.length() < SPEED * 0.6:
			nv = nv.normalized() * SPEED * 0.6
		_vel[i] = nv
		_pos[i] += nv * dt
		var fwd := nv.normalized()
		var basis := Basis.looking_at(-fwd, Vector3.UP) if absf(fwd.y) < 0.98 else Basis()
		# Bank into turns.
		basis = basis.rotated(fwd, clampf(-f.dot(basis.x) * 0.08, -0.6, 0.6))
		multimesh.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * 1.4), _home + _pos[i]))
	multimesh.visible_instance_count = _active if _fade > 0.05 else 0


func _update_native(player: Vector3, want: int) -> void:
	if _fade <= 0.0:
		_native.visible = false
		_native.set("active", false)
		_active = 0
		return
	if want > 0 and int(_native.get("agent_count")) != want:
		_native.set("agent_count", want)
	_native.visible = true
	_native.set("active", true)
	# Leaving (night/storm): the home climbs away so the flock flies off before hiding.
	_native.set("home_offset", Vector3(0, 40, 0) if want == 0 else Vector3.ZERO)
	_native.global_position = player + Vector3(0, ALTITUDE, 0)
