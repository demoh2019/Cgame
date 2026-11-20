extends RefCounted
## One small, seamless cloud-opacity lookup for terrain, grass and foliage.
## This replaces repeated multi-octave hash/sine noise at every rendered pixel.
## A deterministic CPU build runs once; the texture stays cached across chunks.
const SIZE := 128
const TILE_METERS := 1024.0
const PERIODS := [8, 18, 36]
const WEIGHTS := [0.56, 0.30, 0.14]
const SEED := 220716
static var _image: Image
static var _texture: ImageTexture


static func _sample(grid: PackedFloat32Array, cells: int, u: float, v: float) -> float:
	var px: float = u * float(cells)
	var py: float = v * float(cells)
	var ix: int = int(floorf(px))
	var iy: int = int(floorf(py))
	var fx: float = px - float(ix)
	var fy: float = py - float(iy)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var x0: int = posmod(ix, cells)
	var x1: int = posmod(ix + 1, cells)
	var y0: int = posmod(iy, cells)
	var y1: int = posmod(iy + 1, cells)
	var a: float = lerpf(grid[y0 * cells + x0], grid[y0 * cells + x1], fx)
	var b: float = lerpf(grid[y1 * cells + x0], grid[y1 * cells + x1], fx)
	return lerpf(a, b, fy)


static func build_image() -> Image:
	if _image != null:
		return _image
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var layers: Array[PackedFloat32Array] = []
	for cells in PERIODS:
		var grid := PackedFloat32Array()
		grid.resize(cells * cells)
		for index in grid.size():
			grid[index] = rng.randf()
		layers.append(grid)
	var result := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	for y in SIZE:
		for x in SIZE:
			# Pixel centres are consistent with bilinear texture sampling. Each
			# source octave wraps, so adjacent cloud tiles have no hard seams.
			var u: float = (float(x) + 0.5) / float(SIZE)
			var v: float = (float(y) + 0.5) / float(SIZE)
			var value: float = 0.0
			for layer in PERIODS.size():
				value += WEIGHTS[layer] * _sample(layers[layer], PERIODS[layer], u, v)
			var shadow: float = smoothstep(0.46, 0.70, value)
			result.set_pixel(x, y, Color(shadow, shadow, shadow))
	_image = result
	return _image


static func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(build_image())
	return _texture


## Normalized and scrolling UVs remain continuous across world/chunk borders.
static func world_uv(position: Vector2, elapsed: float) -> Vector2:
	return position / TILE_METERS + Vector2(elapsed * 0.0005, elapsed * 0.0003)


static func shadow_strength(daylight: float, storm: float, enabled: bool = true) -> float:
	if not enabled:
		return 0.0
	return smoothstep(0.08, 0.50, clampf(daylight, 0.0, 1.0)) * (
		1.0 - clampf(storm, 0.0, 1.0) * 0.65)
