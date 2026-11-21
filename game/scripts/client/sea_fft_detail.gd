extends Node
## Tessendorf FFT chop on top of the sea's Gerstner swell (Sea of Thieves /
## Atlas / UE Water style). The CPU spectrum is evaluated 10 times a second
## into two small height textures; the water shader cross-fades them every
## frame, so motion stays smooth at ~1 ms of script time per update.
## High/Ultra only; lower presets keep the pure Gerstner surface.

const FftOcean = preload("res://scripts/shared/fft_ocean.gd")
const QUALITY_SCRIPT := "res://scripts/client/graphics_quality.gd"

const GRID := 32
const PATCH := 48.0 # Metres per tile; the shader repeats it.
const STEP := 0.1
const STRENGTH := [0.0, 0.0, 0.18, 0.26]

var _ocean := FftOcean.new()
var _material: ShaderMaterial
var _tex_a: ImageTexture
var _tex_b: ImageTexture
var _t0 := 0.0
var _clock := 0.0
var _strength := 0.0
var _level_poll := 0.0


static func strength_for(level: int) -> float:
	return float(STRENGTH[clampi(level, 0, 3)])


func setup(material: ShaderMaterial, level: int, seed: int = 1337) -> void:
	_material = material
	_ocean.setup(GRID, PATCH, Vector2(0.8, 0.6) * 9.0, 1.0, seed)
	_tex_a = ImageTexture.create_from_image(_normalized(_ocean.displacement_image(0.0)))
	_tex_b = ImageTexture.create_from_image(_normalized(_ocean.displacement_image(STEP)))
	_t0 = 0.0
	_clock = 0.0
	if _material != null:
		_material.set_shader_parameter("fft_height_a", _tex_a)
		_material.set_shader_parameter("fft_height_b", _tex_b)
		_material.set_shader_parameter("fft_patch_size", PATCH)
	configure(level)


func configure(level: int) -> void:
	_strength = strength_for(level)
	if _material != null:
		_material.set_shader_parameter("fft_strength", _strength)


## Unit-range heights: the shader scales them, so spectrum amplitude is free.
func _normalized(image: Image) -> Image:
	var peak := 0.0001
	for y in image.get_height():
		for x in image.get_width():
			peak = maxf(peak, absf(image.get_pixel(x, y).r))
	for y in image.get_height():
		for x in image.get_width():
			image.set_pixel(x, y, Color(image.get_pixel(x, y).r / peak, 0.0, 0.0))
	return image


func _process(delta: float) -> void:
	if _material == null:
		return
	# Follow preset changes (Auto quality included) without extra wiring.
	_level_poll += delta
	if _level_poll >= 1.0:
		_level_poll = 0.0
		# Loaded lazily: keeps this node free of the whole client graphics stack in tests.
		var quality: Script = load(QUALITY_SCRIPT) as Script
		var level: int = int(quality.call("level")) if quality != null else 0
		if not is_equal_approx(strength_for(level), _strength):
			configure(level)
	if _strength <= 0.0:
		return
	_clock += delta
	if _clock >= _t0 + STEP:
		# Advance one step: B becomes A, the next spectrum lands in B.
		_t0 += STEP
		if _clock > _t0 + STEP: # Long frame: resynchronise instead of replaying.
			_t0 = _clock
		_tex_a.update(_tex_b.get_image())
		_tex_b.update(_normalized(_ocean.displacement_image(_t0 + STEP)))
	_material.set_shader_parameter("fft_blend", clampf((_clock - _t0) / STEP, 0.0, 1.0))
