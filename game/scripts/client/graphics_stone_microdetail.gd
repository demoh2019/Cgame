extends RefCounted
## Cached native PBR detail normals for masonry walls/ruins.
## Unreal DetailTexturing + Unity HDRP Detail Map idea, but using Godot's
## existing Standard/ORM Material3D detail_normal stage, without mesh rebuilds.
##
## Dynamic Auto quality only toggles existing material shader variants; the
## two 128x128 textures are created lazily and shared by all eligible walls.

const IMAGE_SIZE := 128
const HIGH_AMOUNT := 0.22
const ULTRA_AMOUNT := 0.40
const MASONRY_PARTS := ["wall", "pillar", "column", "rubble", "stairs", "stone"]

static var _quality := 1
static var _method := "gl_compatibility"
static var _tracked: Array[WeakRef] = []
static var _high_texture: ImageTexture
static var _ultra_texture: ImageTexture


## Exclude beds, torches, barrels, wood, leather and other imported art.
## ModelCatalog uses this only on authored dungeon meshes, never on actors.
static func is_masonry_path(path: String) -> bool:
	var lower: String = path.to_lower()
	if not lower.begins_with("dungeon/"):
		return false
	var filename: String = lower.get_file().get_basename()
	for fragment in MASONRY_PARTS:
		if filename.contains(fragment):
			return true
	return false


static func supported(material: BaseMaterial3D, has_tangents: bool) -> bool:
	return material != null and has_tangents and not material.detail_enabled and \
		material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and \
		material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL


static func tier_for(quality: int, method: String) -> int:
	if method != "forward_plus":
		return 0
	return clampi(quality, 0, 3) if quality >= 2 else 0


## Tileable, zero-memory-height signal: integer spatial frequencies make
## both wrap boundaries continuous. Derivatives become small bump normals.
## No noise octaves or image work occur in the runtime shader.
static func height_at(uv: Vector2) -> float:
	var x: float = TAU * uv.x
	var y: float = TAU * uv.y
	var chip: float = sin(x * 9.0 + sin(y * 5.0) * 0.38) * \
		sin(y * 11.0 + cos(x * 4.0) * 0.42)
	var grain: float = sin(x * 19.0 + y * 13.0) * 0.30
	return chip * 0.70 + grain


static func normal_at(uv: Vector2, amount: float) -> Vector3:
	var step: float = 1.0 / float(IMAGE_SIZE)
	var dx: float = height_at(uv + Vector2(step, 0.0)) - \
		height_at(uv - Vector2(step, 0.0))
	var dy: float = height_at(uv + Vector2(0.0, step)) - \
		height_at(uv - Vector2(0.0, step))
	return Vector3(-dx * amount, -dy * amount, 1.0).normalized()


static func _generate(amount: float) -> ImageTexture:
	var image := Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBA8)
	for y in IMAGE_SIZE:
		for x in IMAGE_SIZE:
			var uv := Vector2((float(x) + 0.5) / IMAGE_SIZE,
				(float(y) + 0.5) / IMAGE_SIZE)
			var normal: Vector3 = normal_at(uv, amount)
			image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5,
				normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, 1.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func texture_for(tier: int) -> Texture2D:
	if tier < 2:
		return null
	if tier == 2:
		if _high_texture == null:
			_high_texture = _generate(HIGH_AMOUNT)
		return _high_texture
	if _ultra_texture == null:
		_ultra_texture = _generate(ULTRA_AMOUNT)
	return _ultra_texture


static func _set_detail(material: BaseMaterial3D, tier: int) -> void:
	var enabled: bool = tier >= 2
	if not enabled:
		if material.detail_enabled:
			material.detail_enabled = false
		# Drop this reference from each material during downgrade; two
		# shared CPU textures stay cached for the next Auto upscale.
		if material.detail_normal != null:
			material.detail_normal = null
		return
	var new_normal: Texture2D = texture_for(tier)
	if material.detail_normal != new_normal:
		material.detail_normal = new_normal
	if material.detail_uv_layer != BaseMaterial3D.DETAIL_UV_1:
		material.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
	if not material.detail_enabled:
		material.detail_enabled = true


## Called once for each *baked* copied masonry surface with valid UV tangents.
## Uses WeakRef so the graphics manager never owns an unloaded world mesh.
static func register(material: BaseMaterial3D, valid_tangents: bool) -> bool:
	if not supported(material, valid_tangents):
		return false
	_tracked.append(weakref(material))
	_set_detail(material, tier_for(_quality, _method))
	return true


## Profile changes are rare. The no-change branch does not iterate objects,
## and streamed in masonry inherits the latest profile upon registration.
static func configure(quality: int, method: String) -> void:
	var level: int = clampi(quality, 0, 3)
	if level == _quality and method == _method:
		return
	_quality = level
	_method = method
	var tier: int = tier_for(level, method)
	for i in range(_tracked.size() - 1, -1, -1):
		var value: Variant = _tracked[i].get_ref()
		if not (value is BaseMaterial3D):
			_tracked.remove_at(i)
		else:
			_set_detail(value as BaseMaterial3D, tier)


## Called on game shutdown/test teardown; never deletes source glTF assets.
static func clear_cache() -> void:
	_tracked.clear()
	_high_texture = null
	_ultra_texture = null
	_quality = 1
	_method = "gl_compatibility"
