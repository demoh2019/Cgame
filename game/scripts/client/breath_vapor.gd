extends Node3D
## Visible breath in cold air (Red Dead Redemption 2 signature detail): a soft
## puff leaves the mouth on each exhale, more often while running. Cold comes
## from altitude (snow line), snowfall and clear mountain/snow nights.
## CPU particles, a handful at a time; off on Performance.

const MOUTH_HEIGHT := 1.6

var model: Node3D # Character model; +Z is its facing direction.
var _puffs: CPUParticles3D
var _clock := 0.0
var _next_exhale := 0.0


## 0..1 cold from ground height (m), daylight, biome and snowfall.
static func coldness(ground_height: float, daylight: float, biome: String, snowing: float) -> float:
	var altitude: float = clampf((ground_height - 60.0) / 30.0, 0.0, 1.0)
	var night_chill: float = 0.0
	if biome == "mountain" or biome == "snow" or biome == "tundra":
		night_chill = clampf((0.35 - daylight) / 0.3, 0.0, 1.0)
	return clampf(maxf(maxf(altitude, night_chill), snowing), 0.0, 1.0)


## Seconds between exhales: ~3.5 s at rest, ~1.2 s while sprinting.
static func exhale_interval(speed: float) -> float:
	return lerpf(3.5, 1.2, clampf(speed / 6.0, 0.0, 1.0))


func _ready() -> void:
	_puffs = CPUParticles3D.new()
	_puffs.emitting = false
	_puffs.one_shot = true
	_puffs.amount = 6
	_puffs.lifetime = 1.6
	_puffs.explosiveness = 0.85
	_puffs.local_coords = false
	_puffs.direction = Vector3(0, 0.15, 1)
	_puffs.spread = 14.0
	_puffs.initial_velocity_min = 0.35
	_puffs.initial_velocity_max = 0.6
	_puffs.gravity = Vector3(0, 0.12, 0)
	_puffs.damping_min = 0.4
	_puffs.damping_max = 0.6
	_puffs.scale_amount_min = 0.6
	_puffs.scale_amount_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.8))
	_puffs.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.92, 0.94, 0.97, 0.38))
	fade.set_color(1, Color(0.92, 0.94, 0.97, 0.0))
	_puffs.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
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
	_puffs.mesh = quad
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_puffs)


func update_view(cold: float, speed: float, level: int, delta: float) -> void:
	if _puffs == null or model == null or level < 1 or cold < 0.2:
		return
	_clock += delta
	if _clock < _next_exhale:
		return
	_next_exhale = _clock + exhale_interval(speed) * randf_range(0.85, 1.15)
	var facing: Vector3 = model.global_transform.basis.z.normalized()
	_puffs.global_position = model.global_position + Vector3(0, MOUTH_HEIGHT, 0) + facing * 0.18
	_puffs.global_basis = Basis.looking_at(-facing, Vector3.UP) if absf(facing.y) < 0.98 else Basis()
	# Denser, more opaque breath the colder it is.
	_puffs.amount = 4 + int(round(cold * 4.0))
	_puffs.restart()
