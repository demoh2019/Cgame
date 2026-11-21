extends RefCounted
## Factory and runtime helpers for the eye shader (assets/shaders/eye.gdshader).
## Original code for this project; shading concepts after Jimenez et al. 2013.

const SHADER_PATH := "res://assets/shaders/eye.gdshader"
const PUPIL_MIN := 0.12 ## constricted in bright light
const PUPIL_MAX := 0.9 ## dilated in darkness

static var _shader: Shader


static func shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	return _shader


## Deterministic per-seed variation: same (iris_color, seed) always gives identical parameters.
static func make(iris_color: Color, seed: int) -> ShaderMaterial:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed) ^ 0x5eed
	var mat := ShaderMaterial.new()
	mat.shader = shader()
	var tint := Color.from_hsv(
		iris_color.h + rng.randf_range(-0.015, 0.015),
		clampf(iris_color.s + rng.randf_range(-0.08, 0.08), 0.0, 1.0),
		clampf(iris_color.v + rng.randf_range(-0.08, 0.08), 0.0, 1.0))
	mat.set_shader_parameter("iris_color", tint)
	mat.set_shader_parameter("fibre_seed", rng.randf() * 10.0)
	mat.set_shader_parameter("fibre_density", rng.randf_range(32.0, 56.0))
	mat.set_shader_parameter("iris_radius", rng.randf_range(0.28, 0.33))
	mat.set_shader_parameter("limbus_width", rng.randf_range(0.09, 0.16))
	mat.set_shader_parameter("iris_depth", rng.randf_range(0.06, 0.1))
	mat.set_shader_parameter("sclera_color", Color(0.92, 0.89, 0.85).darkened(rng.randf_range(0.0, 0.06)))
	mat.set_shader_parameter("wetness", rng.randf_range(0.7, 0.9))
	mat.set_shader_parameter("pupil_size", 0.4)
	return mat


## Maps ambient light (0 dark .. 1 bright) to the shader's pupil_size (0..1). Returns the value set.
static func set_dilation(mat: ShaderMaterial, light_level: float) -> float:
	var size := pupil_for_light(light_level)
	mat.set_shader_parameter("pupil_size", size)
	return size


static func pupil_for_light(light_level: float) -> float:
	var l := clampf(light_level, 0.0, 1.0)
	# Pupillary light reflex is roughly logarithmic: most constriction happens at low-mid light.
	var k := sqrt(l)
	return lerpf(PUPIL_MAX, PUPIL_MIN, k)


## Eyelid coverage 0 (open) .. 1 (closed) for a blink starting at `t` seconds into `period`.
## Fast close (35 %), slower open (65 %), smooth in and out.
static func blink_occlusion(t: float, period: float = 4.0, duration: float = 0.18) -> float:
	if period <= 0.0 or duration <= 0.0:
		return 0.0
	var phase := fposmod(t, period)
	if phase >= duration:
		return 0.0
	var u := phase / duration
	var v := u / 0.35 if u < 0.35 else (1.0 - u) / 0.65
	return smoothstep(0.0, 1.0, clampf(v, 0.0, 1.0))


static func apply_blink(mat: ShaderMaterial, t: float, period: float = 4.0, duration: float = 0.18) -> float:
	var occ := blink_occlusion(t, period, duration)
	mat.set_shader_parameter("blink_occlusion", occ)
	return occ
