extends RefCounted
## Lightweight panoramic light-cookie shared by existing shadowed dungeon torches.
## Unity HDRP's cookie and Unreal Light Functions motivate this approach, but
## Godot's native OmniLight3D projector handles the actual light evaluation.
##
## The single 2:1 lat-long image contains *angular* occlusion variation, not
## a lightmap. It does not add torches, shadow passes or screen-space passes.
## Creating the texture is deferred until a Forward+ High/Ultra torch casts.

const WIDTH := 128
const HEIGHT := 64
const HIGH_SHADOW_DISTANCE := 27.0
const ULTRA_SHADOW_DISTANCE := 38.0

static var _texture: ImageTexture


## A world-independent equirectangular light mask. All longitude frequencies
## are integers, so the 0/1 horizontal seam is perfectly periodic. At poles,
## longitude dependence vanishes to prevent pinched radial artifacts.
static func intensity_at(uv: Vector2) -> float:
	if not uv.is_finite():
		return 1.0
	var azimuth: float = TAU * uv.x
	var latitude: float = PI * (clampf(uv.y, 0.0, 1.0) - 0.5)
	var horizon: float = pow(maxf(cos(latitude), 0.0), 2.0)
	var ribs: float = pow(maxf(cos(azimuth * 4.0 + sin(latitude * 2.0) * 0.23), 0.0),
		10.0) * horizon
	var grain: float = 0.028 * sin(azimuth * 3.0 + latitude * 2.5) * \
		sin(azimuth * 7.0 - latitude * 4.0) * horizon
	# Mostly open flame: little shadow bars and irregular bounce, no black
	# bands that could hide traps, monsters or gameplay interaction.
	return clampf(0.95 - 0.18 * ribs + grain, 0.72, 1.0)


## One 128x64 RGBA8 image, allocated once across ALL streamed room lights.
## Avoid repeated texture creation when Auto changes graphics tiers.
static func texture() -> Texture2D:
	if _texture != null:
		return _texture
	var image: Image = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y in HEIGHT:
		for x in WIDTH:
			var value: float = intensity_at(Vector2((float(x) + 0.5) / WIDTH,
				(float(y) + 0.5) / HEIGHT))
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	image.generate_mipmaps()
	_texture = ImageTexture.create_from_image(image)
	return _texture


static func projector_enabled(quality: int, method: String,
		casts_shadow: bool) -> bool:
	return quality >= 2 and method == "forward_plus" and casts_shadow


static func shadow_distance(quality: int) -> float:
	if quality <= 1:
		return 0.0
	return HIGH_SHADOW_DISTANCE if quality == 2 else ULTRA_SHADOW_DISTANCE


static func shadow_mode(quality: int) -> int:
	# Godot docs: dual paraboloid is faster than cube shadows. High uses
	# the cheap option, Ultra preserves cubemap accuracy in sharp corners.
	return OmniLight3D.SHADOW_DUAL_PARABOLOID if quality <= 2 else OmniLight3D.SHADOW_CUBE


## Applied only when the existing 0.13 s torch manager updates. Every
## setter is idempotent: no repeated projector or shadow-atlas mutation.
static func apply(light: OmniLight3D, quality: int, method: String,
		casts_shadow: bool) -> void:
	if light == null:
		return
	if not projector_enabled(quality, method, casts_shadow):
		if light.light_projector != null:
			light.light_projector = null
		return
	var desired_mode: int = shadow_mode(quality)
	if light.omni_shadow_mode != desired_mode:
		light.omni_shadow_mode = desired_mode
	var reach: float = shadow_distance(quality)
	if not is_equal_approx(light.distance_fade_shadow, reach):
		light.distance_fade_shadow = reach
	var shared: Texture2D = texture()
	if light.light_projector != shared:
		light.light_projector = shared
