extends RefCounted
## Procedural lens dirt for bloom (Unreal "Bloom Dirt Mask", Battlefield / Mirror's
## Edge look): bright light sources reveal smudges and specks on the "lens".
## Godot multiplies glow by Environment.glow_map, so the mask is an HDR texture
## around 0.7 with smudges above 1: glow is boosted where the lens is dirty.

const WIDTH := 192
const HEIGHT := 108

static var _texture: Texture2D


static func texture() -> Texture2D:
	if _texture != null:
		return _texture
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var noise := FastNoiseLite.new()
	noise.frequency = 0.035
	var smudges: Array[Vector3] = []
	for i in 14:
		smudges.append(Vector3(rng.randf() * WIDTH, rng.randf() * HEIGHT, rng.randf_range(6.0, 22.0)))
	var img := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBF)
	for y in HEIGHT:
		for x in WIDTH:
			var v: float = 0.7 + noise.get_noise_2d(x, y) * 0.12
			for s in smudges:
				var d: float = Vector2(x - s.x, y - s.y).length() / s.z
				v += maxf(0.0, 1.0 - d * d) * 0.9
			# Fine specks of dust.
			if rng.randf() < 0.004:
				v += 1.2
			img.set_pixel(x, y, Color(v, v * 0.98, v * 0.95))
	_texture = ImageTexture.create_from_image(img)
	return _texture


## glow_map_strength for a tier/renderer (0 = off).
static func strength(level: int, rendering_method: String) -> float:
	if rendering_method != "forward_plus" or level < 2:
		return 0.0
	return 0.55 if level == 2 else 0.7


static func apply(env: Environment, level: int, rendering_method: String) -> void:
	if env == null:
		return
	var s: float = strength(level, rendering_method)
	if s > 0.0:
		if env.glow_map == null:
			env.glow_map = texture()
		env.glow_map_strength = s
	elif env.glow_map_strength != 0.0:
		env.glow_map_strength = 0.0
