extends Node3D
## Dust devils on dry windy plains (RDR2 ambience): now and then a spinning
## column of dust wanders past the player with the wind for ~25 s. One CPU
## particle swirl, reused; off on Performance, in calm/wet weather and off-plains.

const LIFE := 25.0

var _swirl: CPUParticles3D
var _age := LIFE
var _wait := 20.0
var _drift := Vector3.ZERO


static func allowed(level: int, biome: String, wind: Vector2, storm: float, daylight: float) -> bool:
	return level >= 1 and biome == "plains" and wind.length() > 0.35 and storm < 0.1 and daylight > 0.45


## Fade-in/out of the column over its life (0..1).
static func strength(age: float) -> float:
	if age <= 0.0 or age >= LIFE:
		return 0.0
	return smoothstep(0.0, 3.0, age) * (1.0 - smoothstep(LIFE - 4.0, LIFE, age))


func _ready() -> void:
	_swirl = CPUParticles3D.new()
	_swirl.amount = 70
	_swirl.lifetime = 3.5
	_swirl.local_coords = false
	_swirl.emitting = false
	_swirl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_swirl.emission_sphere_radius = 0.8
	_swirl.direction = Vector3.UP
	_swirl.spread = 25.0
	_swirl.initial_velocity_min = 1.5
	_swirl.initial_velocity_max = 3.0
	_swirl.gravity = Vector3(0, 0.6, 0)
	_swirl.tangential_accel_min = 9.0 # Spin around the column's axis.
	_swirl.tangential_accel_max = 13.0
	_swirl.radial_accel_min = -1.5
	_swirl.radial_accel_max = 0.5
	_swirl.scale_amount_min = 0.6
	_swirl.scale_amount_max = 1.6
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 2.2))
	_swirl.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.68, 0.6, 0.46, 0.0))
	fade.add_point(0.2, Color(0.68, 0.6, 0.46, 0.3))
	fade.set_color(fade.get_point_count() - 1, Color(0.72, 0.66, 0.54, 0.0))
	_swirl.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	m.albedo_texture = tex
	quad.material = m
	_swirl.mesh = quad
	_swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_swirl)


func update_view(world, player: Vector3, biome: String, wind: Vector2, storm: float, daylight: float, level: int, delta: float) -> void:
	if world == null:
		return
	if _age < LIFE:
		_age += delta
		_swirl.global_position += _drift * delta
		var p := _swirl.global_position
		_swirl.global_position.y = float(world.height_at(p.x, p.z)) + 0.3
		_swirl.color = Color(1, 1, 1, strength(_age)) # CPUParticles3D has no amount_ratio: fade via alpha.
		if _age >= LIFE or not allowed(level, biome, wind, storm, daylight):
			_swirl.emitting = false
			_age = LIFE
		return
	if not allowed(level, biome, wind, storm, daylight):
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = randf_range(45.0, 110.0)
	_age = 0.0
	# Start upwind and off to the side so it crosses the player's view.
	var w := wind.normalized()
	var side := Vector2(-w.y, w.x) * randf_range(-12.0, 12.0)
	var start := Vector2(player.x, player.z) - w * 24.0 + side
	_drift = Vector3(w.x, 0.0, w.y) * randf_range(1.6, 2.6)
	_swirl.global_position = Vector3(start.x, float(world.height_at(start.x, start.y)) + 0.3, start.y)
	_swirl.emitting = true
