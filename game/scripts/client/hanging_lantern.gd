extends Node3D
## A lantern on a chain that swings in the weather wind and when bumped — a verlet chain pinned at the top, the
## same idea as Unity's chain of HingeJoints or an Unreal Physics Constraint chain, but integrated analytically
## (no physics bodies, no collision) so dozens of them cost nothing. Pure cosmetics, client only.
## Also: `rope_points` / `build_rope_mesh` give a sagging cable (catenary-like parabola) between two anchors.

const LINKS := [0, 3, 5, 8] # Chain links per quality tier; Low shows none.
const LINK_LENGTH := 0.18
const GRAVITY := 9.0
const DAMPING := 0.985
const WIND_FORCE := 6.0

var _points := PackedVector3Array() # Local space, index 0 is the pinned top.
var _previous := PackedVector3Array()
var _link_meshes: Array[MeshInstance3D] = []
var _lamp: MeshInstance3D
var _phase := 0.0


static func link_count(level: int) -> int:
	return LINKS[clampi(level, 0, LINKS.size() - 1)]


## One verlet step for a pinned chain. Returns nothing; `points`/`previous` are updated in place.
static func step(points: PackedVector3Array, previous: PackedVector3Array, link_length: float,
		wind: Vector3, dt: float) -> void:
	if points.size() < 2 or dt <= 0.0 or not wind.is_finite():
		return
	dt = minf(dt, 1.0 / 20.0)
	var push := Vector3(wind.x, 0.0, wind.y) * wind.z * WIND_FORCE
	for i in range(1, points.size()):
		var velocity := (points[i] - previous[i]) * DAMPING
		previous[i] = points[i]
		points[i] += velocity + (Vector3(0, -GRAVITY, 0) + push) * dt * dt
	for _iteration in 4:
		for i in range(1, points.size()):
			var delta := points[i] - points[i - 1]
			var length := delta.length()
			if length < 0.00001:
				continue
			var correction := delta * ((length - link_length) / length)
			if i == 1:
				points[i] -= correction # The anchor does not move.
			else:
				points[i - 1] += correction * 0.5
				points[i] -= correction * 0.5


## Angle of the chain's free end from vertical, radians (for tests and lamp tilt).
static func swing_angle(points: PackedVector3Array) -> float:
	if points.size() < 2:
		return 0.0
	var chain := points[points.size() - 1] - points[0]
	return atan2(Vector2(chain.x, chain.z).length(), -chain.y)


## `count + 1` points of a cable hanging between a and b: a parabola dipping `sag` metres at the middle.
static func rope_points(a: Vector3, b: Vector3, sag: float, count: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	var n := maxi(count, 1)
	for i in n + 1:
		var t := float(i) / n
		var p := a.lerp(b, t)
		p.y -= 4.0 * sag * t * (1.0 - t)
		points.append(p)
	return points


static func rope_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


## A thin square-section tube along the points (one surface, no per-frame cost).
static func build_rope_mesh(points: PackedVector3Array, radius: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var offsets := [Vector3(radius, 0, 0), Vector3(0, radius, 0), Vector3(-radius, 0, 0), Vector3(0, -radius, 0)]
	for p in points:
		for o in offsets:
			vertices.append(p + o)
	for s in range(points.size() - 1):
		for k in 4:
			var a: int = s * 4 + k
			var b: int = s * 4 + (k + 1) % 4
			indices.append_array([a, b, a + 4, b, b + 4, a + 4])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if points.size() >= 2:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func setup(level: int, glow: Color) -> void:
	var count := link_count(level)
	if count <= 0:
		set_process(false)
		return
	_phase = randf() * TAU
	var chain_material := StandardMaterial3D.new()
	chain_material.albedo_color = Color(0.22, 0.2, 0.18)
	chain_material.metallic = 0.8
	for i in count + 1:
		_points.append(Vector3(0, -LINK_LENGTH * i, 0))
		_previous.append(_points[i])
	_previous[count] += Vector3(0.0, 0.0, 0.02) # A first nudge so it settles into a swing.
	for i in count:
		var link := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.025, LINK_LENGTH * 0.9, 0.025)
		link.mesh = box
		link.material_override = chain_material
		link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(link)
		_link_meshes.append(link)
	_lamp = MeshInstance3D.new()
	var lamp_mesh := CylinderMesh.new()
	lamp_mesh.top_radius = 0.1
	lamp_mesh.bottom_radius = 0.07
	lamp_mesh.height = 0.26
	_lamp.mesh = lamp_mesh
	var lamp_material := StandardMaterial3D.new()
	lamp_material.albedo_color = glow
	lamp_material.emission_enabled = true
	lamp_material.emission = glow
	lamp_material.emission_energy_multiplier = 1.6
	_lamp.material_override = lamp_material
	_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lamp)
	_pose()


func _process(delta: float) -> void:
	if _points.size() < 2:
		return
	var wind: Vector3 = RenderingServer.global_shader_parameter_get(&"aa_vegetation_wind")
	# World wind to local space of the lantern's parent so it swings the right way on a rotated mount.
	var local := global_transform.basis.inverse() * Vector3(wind.x, 0, wind.y)
	var gust := 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.001 * 0.8 + _phase)
	step(_points, _previous, LINK_LENGTH, Vector3(local.x, local.z, wind.z * gust), delta)
	_pose()


func _pose() -> void:
	for i in _link_meshes.size():
		var a := _points[i]
		var b := _points[i + 1]
		var mid := (a + b) * 0.5
		var axis := (b - a).normalized()
		var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		var y_axis := -axis
		var x_axis := up.cross(y_axis).normalized()
		_link_meshes[i].transform = Transform3D(Basis(x_axis, y_axis, x_axis.cross(y_axis)), mid)
	var tip := _points[_points.size() - 1]
	var hang := (tip - _points[_points.size() - 2]).normalized()
	var lamp_y := -hang
	var lamp_x := Vector3.UP.cross(lamp_y)
	if lamp_x.length() < 0.001:
		lamp_x = Vector3.RIGHT
	lamp_x = lamp_x.normalized()
	_lamp.transform = Transform3D(Basis(lamp_x, lamp_y, lamp_x.cross(lamp_y)), tip + hang * 0.13)
