extends Node3D
## Reusable wet shoeprints. Forward+/Mobile decals only, no gameplay impact.
## Compatibility skips the entire effect. No imported textures are needed.

const MAX_DECALS := 48
const UPDATE_INTERVAL := 0.10
const STRIDE_METERS := 0.72
const TELEPORT_METERS := 12.0
const PRESETS := [
	{"count": 0, "fade_begin": 0.0, "fade_length": 0.0, "lifetime": 0.0},
	{"count": 12, "fade_begin": 15.0, "fade_length": 7.0, "lifetime": 10.0},
	{"count": 28, "fade_begin": 23.0, "fade_length": 9.0, "lifetime": 13.0},
	{"count": 48, "fade_begin": 30.0, "fade_length": 11.0, "lifetime": 16.0},
]
static var _texture: Texture2D
var _world
var _pool: Array[Decal] = []
var _ages: Array[float] = []
var _lifetimes: Array[float] = []
var _colors: Array[Color] = []
var _cursor := 0
var _left := false
var _last_step: Vector3 = Vector3.INF
var _elapsed := 0.0
var _enabled_last := false
var _stamps := 0


static func profile(level: int) -> Dictionary:
	return PRESETS[clampi(level, 0, 3)].duplicate(true)


static func supported(method: String, level: int) -> bool:
	return (method == "forward_plus" or method == "mobile") and level > 0


static func moisture(biome: String, storm: float) -> float:
	var base := 0.0
	match biome:
		"swamp":
			base = 0.76
		"beach":
			base = 0.48
		"forest":
			base = 0.23
		"plains":
			base = 0.12
		"mountain":
			base = 0.03
	return clampf(maxf(base, clampf(storm, 0.0, 1.0) * 0.95), 0.0, 1.0)


static func footprint_color(biome: String, wetness: float) -> Color:
	var tint := Color(0.16, 0.14, 0.105)
	if biome == "swamp":
		tint = Color(0.075, 0.093, 0.072)
	elif biome == "beach":
		tint = Color(0.23, 0.195, 0.13)
	elif biome == "forest":
		tint = Color(0.11, 0.103, 0.075)
	tint.a = clampf((wetness - 0.18) * 0.42, 0.0, 0.37)
	return tint


static func texture() -> Texture2D:
	if _texture != null:
		return _texture
	# Single cached 64x64 RGBA8 sole/toe texture, shared by every decal.
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var uv := Vector2((float(x) + 0.5) / 64.0,
				(float(y) + 0.5) / 64.0)
			var toe: float = 1.0 - smoothstep(0.78, 1.08,
				Vector2((uv.x - 0.50) / 0.33, (uv.y - 0.30) / 0.25).length())
			var heel: float = 1.0 - smoothstep(0.75, 1.05,
				Vector2((uv.x - 0.50) / 0.26, (uv.y - 0.70) / 0.24).length())
			var sole: float = maxf(toe, heel * 0.85)
			var tread: float = 1.0 - 0.17 * (0.5 + 0.5 * sin(uv.y * 95.0))
			image.set_pixel(x, y, Color(0.93, 0.92, 0.88,
				clampf(sole * tread, 0.0, 1.0)))
	_texture = ImageTexture.create_from_image(image)
	return _texture


func setup(world) -> void:
	_world = world


func _make_decal() -> void:
	var d := Decal.new()
	d.name = "PooledFootprint_%02d" % _pool.size()
	d.texture_albedo = texture()
	d.size = Vector3(0.36, 0.78, 0.62)
	d.albedo_mix = 0.88
	d.upper_fade = 0.48
	d.lower_fade = 0.48
	d.normal_fade = 0.45
	d.cull_mask = 1
	d.distance_fade_enabled = true
	d.visible = false
	add_child(d)
	_pool.append(d)
	_ages.append(-1.0)
	_lifetimes.append(1.0)
	_colors.append(Color.TRANSPARENT)


func _hide_all() -> void:
	for i in _pool.size():
		_pool[i].visible = false
		_ages[i] = -1.0
	_last_step = Vector3.INF


## Called from the client scene; transparency updates are throttled to 10 Hz.
func update_view(position: Vector3, moving: bool, can_walk: bool,
		storm: float, level: int, method: String, delta: float) -> void:
	if not supported(method, level):
		if _enabled_last:
			_hide_all()
		_enabled_last = false
		return
	_enabled_last = true
	_elapsed += clampf(delta, 0.0, 0.5)
	if _elapsed < UPDATE_INTERVAL:
		return
	var dt: float = _elapsed
	_elapsed = 0.0
	var preset: Dictionary = profile(level)
	var capacity: int = int(preset["count"])
	for i in _pool.size():
		if i >= capacity:
			_pool[i].visible = false
			_ages[i] = -1.0
			continue
		if _ages[i] < 0.0:
			continue
		_ages[i] += dt
		var remaining: float = 1.0 - _ages[i] / maxf(_lifetimes[i], 0.01)
		if remaining <= 0.0:
			_pool[i].visible = false
			_ages[i] = -1.0
			continue
		var color: Color = _colors[i]
		color.a = roundf(color.a * clampf(remaining, 0.0, 1.0) * 32.0) / 32.0
		if _pool[i].modulate != color:
			_pool[i].modulate = color

	if not moving or not can_walk or not position.is_finite():
		_last_step = Vector3.INF
		return
	var biome := "plains"
	if _world != null and _world.has_method("biome_at"):
		biome = str(_world.call("biome_at", position.x, position.z))
	var wet: float = moisture(biome, storm)
	if wet < 0.24:
		_last_step = Vector3.INF
		return
	if _last_step == Vector3.INF:
		_last_step = position
		return
	var travel := Vector2(position.x - _last_step.x, position.z - _last_step.z)
	var distance: float = travel.length()
	if distance < STRIDE_METERS:
		return
	if distance > TELEPORT_METERS:
		_last_step = position
		return
	var forward: Vector2 = travel / distance
	var side := Vector2(-forward.y, forward.x) * (-0.18 if _left else 0.18)
	_left = not _left
	var at := Vector2(position.x, position.z) + side
	var ground: float = position.y
	if _world != null and _world.has_method("height_at"):
		ground = float(_world.call("height_at", at.x, at.y))
	# Skip falling, swimming and projecting marks onto cliffs below the actor.
	if absf(position.y - ground) > 1.2:
		_last_step = position
		return
	var slot: int
	if _pool.size() < capacity:
		_make_decal()
		slot = _pool.size() - 1
	else:
		slot = _cursor % capacity
	_cursor = (slot + 1) % capacity
	var d: Decal = _pool[slot]
	d.global_position = Vector3(at.x, ground + 0.22, at.y)
	d.rotation.y = atan2(forward.x, forward.y)
	d.distance_fade_begin = float(preset["fade_begin"])
	d.distance_fade_length = float(preset["fade_length"])
	var tint: Color = footprint_color(biome, wet)
	d.modulate = tint
	d.visible = tint.a > 0.005
	_ages[slot] = 0.0
	_lifetimes[slot] = float(preset["lifetime"])
	_colors[slot] = tint
	_stamps += 1
	_last_step = position
