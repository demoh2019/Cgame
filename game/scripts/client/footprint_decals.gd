extends Node3D
## Bounded, pooled native Forward+ Decals for rain-soaked mud and high snow.
## One small shared image per surface; no server simulation or terrain edits.

const MAX_MARKS := 32
const STEP_DISTANCE := 0.83
const TELEPORT_DISTANCE := 5.0
const DURATION := 12.0
const FADE_INTERVAL := 0.25
const TEX_SIZE := 64

var _decals: Array[Decal] = []
var _births: Array[float] = []
var _reuse := 0
var _previous := Vector3.INF
var _stride := 0.0
var _left := false
var _seconds := 0.0
var _fade_elapsed := 0.0
var _enabled := false
var _mud: Texture2D
var _snow: Texture2D
var _normal: Texture2D


static func surface_kind(level: int, renderer: String, storm: float,
		biome: String, elevation: float, underground: bool, flooded: bool) -> String:
	if level < 2 or renderer != "forward_plus" or underground or flooded:
		return ""
	if not is_finite(storm) or not is_finite(elevation):
		return ""
	if biome == "mountain" and elevation >= 88.0:
		return "snow"
	if storm >= 0.32 and biome in ["forest", "swamp", "plains", "beach"]:
		return "mud"
	return ""


static func mask_at(uv: Vector2) -> float:
	var p: Vector2 = (uv - Vector2(0.5, 0.5)) * 2.0
	var toe: float = 1.0 - smoothstep(0.76, 1.04,
		Vector2(p.x / 0.69, (p.y + 0.33) / 0.59).length())
	var heel: float = 1.0 - smoothstep(0.73, 1.02,
		Vector2(p.x / 0.60, (p.y - 0.4) / 0.5).length())
	return clampf(maxf(toe, heel) *
		(0.9 + 0.1 * sin((p.y + p.x * 0.25) * 28.0)), 0.0, 1.0)


static func valid_stride(before: Vector3, after: Vector3, walking: bool) -> bool:
	if not walking or not before.is_finite() or not after.is_finite():
		return false
	var length: float = Vector2(after.x - before.x, after.z - before.z).length()
	return length > 0.001 and length <= TELEPORT_DISTANCE and \
		absf(after.y - before.y) < 1.2


func _make_texture(tint: Color, is_normal: bool = false) -> Texture2D:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var uv := Vector2((float(x) + 0.5) / TEX_SIZE,
				(float(y) + 0.5) / TEX_SIZE)
			var coverage: float = mask_at(uv)
			if is_normal:
				var delta := 1.0 / float(TEX_SIZE)
				var dx: float = mask_at(uv + Vector2(delta, 0.0)) - \
					mask_at(uv - Vector2(delta, 0.0))
				var dy: float = mask_at(uv + Vector2(0.0, delta)) - \
					mask_at(uv - Vector2(0.0, delta))
				var normal: Vector3 = Vector3(-dx * 1.2, -dy * 1.2, 1.0).normalized()
				img.set_pixel(x, y, Color(normal.x * 0.5 + 0.5,
					normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, coverage))
			else:
				img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, tint.a * coverage))
	return ImageTexture.create_from_image(img)


func _get_decal() -> int:
	if _decals.size() < MAX_MARKS:
		var mark := Decal.new()
		mark.name = "GroundFootprint%02d" % _decals.size()
		mark.size = Vector3(0.48, 0.26, 0.82)
		mark.normal_fade = 0.85
		mark.distance_fade_enabled = true
		mark.distance_fade_begin = 27.0
		mark.distance_fade_length = 13.0
		mark.visible = false
		add_child(mark)
		_decals.append(mark)
		_births.append(-DURATION)
		_reuse = _decals.size() % MAX_MARKS
		return _decals.size() - 1
	var result := _reuse
	_reuse = (_reuse + 1) % MAX_MARKS
	return result


func _stamp(at: Vector3, heading: Vector2, kind: String, level: int) -> void:
	if _mud == null:
		_mud = _make_texture(Color(0.18, 0.13, 0.10, 0.67))
		_snow = _make_texture(Color(0.36, 0.44, 0.52, 0.53))
	var i: int = _get_decal()
	var mark: Decal = _decals[i]
	_left = not _left
	var lateral: Vector2 = Vector2(-heading.y, heading.x)
	var side: float = -0.14 if _left else 0.14
	mark.global_position = at + Vector3(lateral.x * side, 0.1, lateral.y * side)
	mark.rotation.y = atan2(heading.x, heading.y)
	mark.texture_albedo = _snow if kind == "snow" else _mud
	if level >= 3:
		if _normal == null:
			_normal = _make_texture(Color.WHITE, true)
		mark.texture_normal = _normal
	else:
		mark.texture_normal = null
	mark.albedo_mix = 0.72 if kind == "snow" else 0.55
	mark.modulate = Color.WHITE
	mark.visible = true
	_births[i] = _seconds


func _fade() -> void:
	for i in _decals.size():
		var mark: Decal = _decals[i]
		if not mark.visible:
			continue
		var time_left: float = DURATION - (_seconds - _births[i])
		if time_left <= 0.0:
			mark.visible = false
		else:
			mark.modulate = Color(1.0, 1.0, 1.0,
				clampf(time_left / 3.0, 0.0, 1.0))


func clear_marks() -> void:
	for mark in _decals:
		mark.visible = false
	_previous = Vector3.INF
	_stride = 0.0


## The caller owns terrain, weather and movement state. Only this local
## presentation node changes, never the authoritative terrain or save game.
func update_track(at: Vector3, walking: bool, delta: float, storm: float,
		biome: String, level: int, renderer: String, underground: bool = false,
		flooded: bool = false) -> void:
	if not is_finite(delta) or delta <= 0.0 or delta > 0.25:
		return
	_seconds += delta
	_fade_elapsed += delta
	var kind: String = surface_kind(level, renderer, storm, biome,
		at.y, underground, flooded)
	if kind == "":
		if _enabled:
			clear_marks()
		_enabled = false
		_previous = at
		return
	_enabled = true
	if _fade_elapsed >= FADE_INTERVAL:
		_fade_elapsed = fmod(_fade_elapsed, FADE_INTERVAL)
		_fade()
	if not valid_stride(_previous, at, walking):
		_previous = at
		_stride = 0.0
		return
	var move: Vector2 = Vector2(at.x - _previous.x, at.z - _previous.z)
	_previous = at
	var distance: float = move.length()
	_stride += distance
	if _stride >= STEP_DISTANCE:
		_stride = fmod(_stride, STEP_DISTANCE)
		_stamp(at, move / distance, kind, level)
