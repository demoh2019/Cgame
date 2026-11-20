extends Node3D
## Pooled projected impact decals (blood / infected ichor / scorch) — the Godot
## equivalent of Unity's URP Decal Projector and Unreal's deferred decals.
## A fixed ring buffer per quality tier bounds GPU cost; oldest decals are reused.

const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const BUDGET := [0, 24, 48, 96] # Low, Medium, High, Ultra.
const LIFETIME := 40.0
const FADE := 6.0

var _pool: Array[Decal] = []
var _born: Array[float] = []
var _next := 0
var _clock := 0.0
var _textures := {}
var _level := -1


static func budget(level: int) -> int:
	return BUDGET[clampi(level, 0, BUDGET.size() - 1)]


## Opacity of a decal of the given age: full, then a linear fade over the last FADE seconds.
static func alpha_for_age(age: float) -> float:
	if age < 0.0:
		return 1.0
	return clampf((LIFETIME - age) / FADE, 0.0, 1.0)


static func splat_texture(seed: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var blobs: Array[Vector3] = [Vector3(32, 32, 14)]
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(8.0, 20.0)
		blobs.append(Vector3(32 + cos(a) * r, 32 + sin(a) * r, rng.randf_range(3.0, 7.0)))
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var v := 0.0
			for b in blobs:
				v = maxf(v, 1.0 - Vector2(x - b.x, y - b.y).length() / b.z)
			image.set_pixel(x, y, Color(1, 1, 1, smoothstep(0.0, 0.25, v)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func configure(level: int) -> void:
	var wanted := budget(level)
	while _pool.size() > wanted:
		_pool.pop_back().queue_free()
		_born.pop_back()
	while _pool.size() < wanted:
		var decal := Decal.new()
		decal.size = Vector3(1.2, 2.0, 1.2)
		decal.cull_mask = 1
		decal.visible = false
		decal.upper_fade = 0.3
		decal.lower_fade = 0.3
		add_child(decal)
		_pool.append(decal)
		_born.append(-INF)
	_next = 0 if _pool.is_empty() else _next % _pool.size()


## Projects a splat onto whatever lies below `position` (terrain, floors, props).
func splat(position: Vector3, color: Color, size: float = 1.0) -> void:
	if _pool.is_empty():
		return
	var key := randi() % 4
	if not _textures.has(key):
		_textures[key] = splat_texture(key + 1)
	var decal := _pool[_next]
	_born[_next] = _clock
	_next = (_next + 1) % _pool.size()
	decal.texture_albedo = _textures[key]
	decal.modulate = color
	decal.size = Vector3(size, 2.0, size)
	decal.position = position # The pool node sits at the world origin.
	decal.rotation.y = randf() * TAU
	decal.visible = true


func _process(delta: float) -> void:
	_clock += delta
	if GraphicsQuality.level() != _level: # Follows the quality menu and auto-quality.
		_level = GraphicsQuality.level()
		configure(_level)
	for i in _pool.size():
		var decal := _pool[i]
		if not decal.visible:
			continue
		var a := alpha_for_age(_clock - _born[i])
		if a <= 0.0:
			decal.visible = false
		else:
			decal.albedo_mix = a
