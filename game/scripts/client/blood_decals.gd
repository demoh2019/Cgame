extends Node3D
## Ground blood splats (Diablo / Left 4 Dead): pooled native Decals project a
## procedurally generated splat onto terrain under hits, then fade out. Decals
## need Forward+/Mobile; Compatibility and Performance skip them entirely.

const POOL_SIZE := 32
const LIFETIME := 24.0
const FADE := 4.0

var _pool: Array[Decal] = []
var _age: Array[float] = []
var _next := 0
static var _splat_tex: Texture2D


## Splats per hit for a tier/renderer (0 = off).
static func enabled(level: int, rendering_method: String) -> bool:
	return level >= 1 and rendering_method != "gl_compatibility"


## Zombie ichor is darker and browner than red player blood.
static func tint(zombie: bool) -> Color:
	return Color(0.22, 0.12, 0.05) if zombie else Color(0.42, 0.02, 0.02)


static func splat_texture() -> Texture2D:
	if _splat_tex != null:
		return _splat_tex
	var noise := FastNoiseLite.new()
	noise.frequency = 0.09
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var drops: Array[Vector3] = []
	for i in 7:
		drops.append(Vector3(rng.randf_range(10, 54), rng.randf_range(10, 54), rng.randf_range(2.0, 5.0)))
	for y in 64:
		for x in 64:
			var d: float = Vector2(x - 31.5, y - 31.5).length() / 22.0
			var a: float = clampf(1.0 - d + noise.get_noise_2d(x, y) * 0.55, 0.0, 1.0)
			for drop in drops:
				if Vector2(x - drop.x, y - drop.y).length() < drop.z:
					a = maxf(a, 0.9)
			a = smoothstep(0.35, 0.55, a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_splat_tex = ImageTexture.create_from_image(img)
	return _splat_tex


func _ready() -> void:
	for i in POOL_SIZE:
		var d := Decal.new()
		d.size = Vector3(1.4, 1.2, 1.4)
		d.texture_albedo = splat_texture()
		d.visible = false
		d.cull_mask = 1
		d.distance_fade_enabled = true
		d.distance_fade_begin = 35.0
		d.distance_fade_length = 10.0
		add_child(d)
		_pool.append(d)
		_age.append(LIFETIME)


func splat(world, x: float, z: float, zombie: bool, damage: float) -> void:
	if world == null:
		return
	var d := _pool[_next]
	_age[_next] = 0.0
	_next = (_next + 1) % POOL_SIZE
	var s: float = clampf(0.6 + damage / 40.0, 0.6, 1.6)
	d.size = Vector3(1.3 * s, 1.2, 1.3 * s)
	d.modulate = tint(zombie)
	d.albedo_mix = 0.9
	d.position = Vector3(x + randf_range(-0.3, 0.3), float(world.height_at(x, z)) + 0.2, z + randf_range(-0.3, 0.3))
	d.rotation.y = randf() * TAU
	d.visible = true


func _process(delta: float) -> void:
	for i in POOL_SIZE:
		if _age[i] >= LIFETIME:
			continue
		_age[i] += delta
		var d := _pool[i]
		if _age[i] >= LIFETIME:
			d.visible = false
		elif _age[i] > LIFETIME - FADE:
			d.albedo_mix = 0.9 * (LIFETIME - _age[i]) / FADE
