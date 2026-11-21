extends RefCounted
## Variable Rate Shading / foveated rendering (UE5 VRS, Unity foveation,
## Metal rasterization rate maps). The top-down camera keeps the player at
## screen center, so edges are shaded at coarser rates on low presets.
## Unsupported GPUs ignore the texture; High/Ultra always shade full rate.

# Godot VRS density colors: R = horizontal, G = vertical (0 → 1x, 85 → 2x, 170 → 4x).
const RATE_1X1 := Color8(0, 0, 0)
const RATE_2X2 := Color8(85, 85, 0)
const RATE_4X4 := Color8(170, 170, 0)
const RATE_2X1 := Color8(85, 0, 0)
const TILE := 16 # Matches the common 16px shading-rate tile; Godot rescales anyway.

static var _cached: ImageTexture = null
static var _cached_key: String = ""


static func settings(level: int, rendering_method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	if rendering_method != "forward_plus" and rendering_method != "mobile":
		return {"enabled": false}
	match tier:
		0:
			return {"enabled": true, "inner": 0.42, "outer": 0.72}
		1:
			return {"enabled": true, "inner": 0.6, "outer": 0.95}
		_:
			return {"enabled": false}


## Elliptical rate map: full rate around the player, 2x2 ring, 4x4 corners.
static func build_map(size: Vector2i, inner: float, outer: float) -> Image:
	var w: int = maxi(1, size.x)
	var h: int = maxi(1, size.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var u: float = (float(x) + 0.5) / float(w) * 2.0 - 1.0
			var v: float = (float(y) + 0.5) / float(h) * 2.0 - 1.0
			var r: float = sqrt(u * u + v * v)
			var c: Color = RATE_1X1
			if r > outer:
				c = RATE_4X4
			elif r > inner:
				# Top/bottom of a landscape screen hold less gameplay than the sides.
				c = RATE_2X2 if absf(v) > absf(u) * 0.75 else RATE_2X1
			img.set_pixel(x, y, c)
	return img


static func apply(viewport: Viewport, level: int, rendering_method: String) -> bool:
	if viewport == null or not ("vrs_mode" in viewport):
		return false
	var profile: Dictionary = settings(level, rendering_method)
	if not bool(profile["enabled"]):
		viewport.vrs_mode = Viewport.VRS_DISABLED
		viewport.vrs_texture = null
		return false
	var px: Vector2i = Vector2i(viewport.get_visible_rect().size)
	var tiles := Vector2i(maxi(1, px.x / TILE), maxi(1, px.y / TILE))
	var key := "%d:%d:%.2f:%.2f" % [tiles.x, tiles.y, float(profile["inner"]), float(profile["outer"])]
	if _cached == null or key != _cached_key:
		_cached = ImageTexture.create_from_image(build_map(tiles, float(profile["inner"]), float(profile["outer"])))
		_cached_key = key
	viewport.vrs_texture = _cached
	viewport.vrs_update_mode = Viewport.VRS_UPDATE_ONCE
	viewport.vrs_mode = Viewport.VRS_TEXTURE
	return true
