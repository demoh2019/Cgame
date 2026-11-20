extends Node3D
## Artist-directed local froxel mist. The same shader works in offline/online;
## multiplayer state, water, collision, visibility and lighting are unchanged.
## Godot Forward+ FogVolume already uses the scene's shadowed volumetric pass.
const SOURCE := "res://assets/shaders/ground_mist.gdshader"
const MIN_VISIBLE := 0.0005
const UPDATE_INTERVAL := 0.20
const ANCHOR_GRID := 8.0

var _volume: FogVolume
var _material: ShaderMaterial
var _timer := UPDATE_INTERVAL
var _density := 0.0
var _noise_offset := Vector2.ZERO
var _last_quality := -1


static func settings(biome: String, daylight: float, sun_height: float,
		storm: float, quality: int, renderer: String, underground: bool = false) -> Dictionary:
	var tier: int = clampi(quality, 0, 3)
	var active: bool = renderer == "forward_plus" and tier >= 2 and not underground
	var extent := Vector3(64.0, 12.0, 64.0) if tier == 2 else Vector3(88.0, 14.0, 88.0)
	var safe_day: float = clampf(daylight, 0.0, 1.0) if is_finite(daylight) else 0.0
	var safe_sun: float = clampf(sun_height, -1.0, 1.0) if is_finite(sun_height) else 0.0
	var safe_storm: float = clampf(storm, 0.0, 1.0) if is_finite(storm) else 0.0
	# Early mornings produce more condensation; midday remains crisp and readable.
	var morning: float = (1.0 - smoothstep(0.10, 0.50, absf(safe_sun))) * \
		smoothstep(0.08, 0.30, safe_day)
	var base: float = 0.0
	var tint := Color(0.67, 0.77, 0.81)
	match biome:
		"swamp":
			base = 0.038
			tint = Color(0.55, 0.65, 0.59)
		"forest":
			base = 0.023
			tint = Color(0.67, 0.77, 0.71)
		"beach":
			base = 0.013
			tint = Color(0.74, 0.82, 0.88)
		"plains":
			base = 0.009
		_:
			base = 0.0 # Mountains and unknown underground-like areas stay clear.
	var amount: float = 0.0
	if active:
		amount = minf(0.072, base * (0.7 + morning * 0.72 + safe_storm * 0.62) *
			(1.16 if tier == 3 else 0.86))
	return {"enabled": active and amount > MIN_VISIBLE,
		"density": amount, "tint": tint, "extent": extent}


func setup() -> void:
	if _volume != null:
		return
	var fog_shader := load(SOURCE) as Shader
	if fog_shader == null:
		push_warning("Missing ground mist shader; world remains playable.")
		return
	_material = ShaderMaterial.new()
	_material.shader = fog_shader
	_volume = FogVolume.new()
	_volume.name = "CinematicGroundMist"
	_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	_volume.size = Vector3(64.0, 12.0, 64.0)
	_volume.material = _material
	_volume.visible = false
	add_child(_volume)


## Called with the actual rendered survivor position and cached weather/biome.
## World-cell snapping avoids moving the volume every frame, minimizing TAA ghosting.
func update_view(position: Vector3, biome: String, daylight: float,
		sun_height: float, storm: float, wind: Vector2, quality: int,
		delta: float, underground: bool = false) -> void:
	var renderer: String = str(RenderingServer.get_current_rendering_method())
	var p: Dictionary = settings(biome, daylight, sun_height, storm, quality,
		renderer, underground)
	# Creating the resource lazily avoids even compiling a fog shader on Mobile
	# and Compatibility or allocating an unused volume on low quality.
	if not bool(p["enabled"]) or not is_finite(position.x) or \
			not is_finite(position.y) or not is_finite(position.z):
		if _volume != null:
			_volume.visible = false
		_density = 0.0
		_last_quality = -1
		return
	if _volume == null:
		setup()
		if _volume == null:
			return
	if _last_quality != clampi(quality, 0, 3):
		_volume.size = p["extent"]
		_last_quality = clampi(quality, 0, 3)
	_timer += maxf(0.0, delta) if is_finite(delta) else 0.0
	var speed: float = minf(0.2, maxf(0.0, delta)) if is_finite(delta) else 0.0
	if is_finite(wind.x) and is_finite(wind.y):
		_noise_offset += wind.limit_length(30.0) * speed * 0.14
	if _timer < UPDATE_INTERVAL:
		return
	var elapsed: float = minf(_timer, 0.25)
	_timer = fmod(_timer, UPDATE_INTERVAL)
	var anchor := Vector3(roundf(position.x / ANCHOR_GRID) * ANCHOR_GRID,
		position.y + 3.2,
		roundf(position.z / ANCHOR_GRID) * ANCHOR_GRID)
	if _volume.global_position.distance_squared_to(anchor) > 0.01:
		_volume.global_position = anchor
	_density = lerpf(_density, float(p["density"]),
		1.0 - exp(-1.9 * elapsed))
	_material.set_shader_parameter("density", _density)
	_material.set_shader_parameter("ground_height", position.y)
	_material.set_shader_parameter("mist_tint", Vector3(p["tint"].r, p["tint"].g, p["tint"].b))
	_material.set_shader_parameter("noise_offset", _noise_offset)
	_volume.visible = _density > MIN_VISIBLE
