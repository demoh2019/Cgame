extends RefCounted
## Shared, GPU-cheap moving cloud shadows: deterministic CPU LUT and GPU hookup.

const CloudShadowLut = preload("res://scripts/client/cloud_shadow_lut.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "seamless cloud field is deterministic and reused by all surfaces"
	var image: Image = CloudShadowLut.build_image()
	t.check(image != null, "cloud shadow image is created without external art files")
	if image == null:
		return
	t.eq(image.get_width(), CloudShadowLut.SIZE, "lookup image width is bounded")
	t.eq(image.get_height(), CloudShadowLut.SIZE, "lookup image height is bounded")
	t.eq(image.get_format(), Image.FORMAT_L8, "a single luminance byte per texel is enough")
	t.check(CloudShadowLut.build_image() == image, "cloud pixels are generated once")
	var texture: ImageTexture = CloudShadowLut.texture()
	t.check(texture != null, "global GPU uniform has a usable texture")
	t.check(CloudShadowLut.texture() == texture, "GPU texture upload is cached")
	var low := 1.0
	var high := 0.0
	for y in range(0, CloudShadowLut.SIZE, 8):
		for x in range(0, CloudShadowLut.SIZE, 8):
			var value: float = image.get_pixel(x, y).r
			low = minf(low, value)
			high = maxf(high, value)
			t.check(value >= 0.0 and value <= 1.0, "shadow opacity never exceeds 0..1")
	t.check(high - low > 0.25, "cloud field contains distinct sun and shade regions")

	t.current = "toroidal procedural noise has no tile boundary seams"
	var grid := PackedFloat32Array([0.1, 0.4, 0.7, 0.9])
	for uv in [Vector2(0.13, 0.31), Vector2(0.8, 0.93)]:
		var start: float = CloudShadowLut._sample(grid, 2, uv.x, uv.y)
		t.near(CloudShadowLut._sample(grid, 2, uv.x + 1.0, uv.y),
			start, 0.00001, "cloud U wraps without a seam")
		t.near(CloudShadowLut._sample(grid, 2, uv.x, uv.y + 1.0),
			start, 0.00001, "cloud V wraps without a seam")
	var at := Vector2(62.0, -104.0)
	var initial_uv: Vector2 = CloudShadowLut.world_uv(at, 0.0)
	var adjacent_uv: Vector2 = CloudShadowLut.world_uv(at + Vector2(CloudShadowLut.TILE_METERS, 0.0), 0.0)
	t.near(adjacent_uv.x - initial_uv.x, 1.0, 0.00001,
		"world X repeats by exactly one texture tile")
	t.near(adjacent_uv.y - initial_uv.y, 0.0, 0.00001,
		"world X movement does not offset the Z axis")
	t.check(CloudShadowLut.world_uv(at, 30.0) != initial_uv,
		"cloud texture scrolls over time without CPU regeneration")

	t.current = "lighting is weather-aware and quality-gated"
	t.eq(CloudShadowLut.shadow_strength(0.0, 0.0), 0.0,
		"dark night does not pay for clouds or darken terrain")
	t.eq(CloudShadowLut.shadow_strength(1.0, 0.0, false), 0.0,
		"Performance skips the cloud lookup")
	t.near(CloudShadowLut.shadow_strength(1.0, 0.0), 1.0, 0.00001,
		"midday sun shows distinct drifting cloud shadows")
	t.near(CloudShadowLut.shadow_strength(1.0, 1.0), 0.35, 0.00001,
		"heavy storm cover softens direct sunlight and cloud contrast")
	t.check(CloudShadowLut.shadow_strength(0.2, 0.0) <
		CloudShadowLut.shadow_strength(0.8, 0.0),
		"sunrise-to-noon transition is smooth")
	t.check(not GraphicsQuality.profile(0)["cloud_shadows"],
		"lowest preset prevents any cloud shading texture fetch")
	for quality in [1, 2, 3]:
		t.check(bool(GraphicsQuality.profile(quality)["cloud_shadows"]),
			"Balanced, High and Ultra retain moving cloud shadows")

	t.current = "shared shader and project define exactly one global resource"
	t.check(ProjectSettings.has_setting("shader_globals/aa_cloud_shadow_map"),
		"engine config declares cloud texture before shader compilation")
	t.check(ProjectSettings.has_setting("shader_globals/aa_cloud_shadow_strength"),
		"engine config declares shared strength")
	var code: String = FileAccess.get_file_as_string(
		"res://assets/shaders/cloud_shadow.gdshaderinc")
	t.check(code.contains("global uniform sampler2D aa_cloud_shadow_map"),
		"ground/grass/foliage shader include shares one texture")
	t.check(code.contains("texture(aa_cloud_shadow_map, uv)"),
		"one texture lookup replaces fractal noise in pixel shader")
	t.check(not code.contains("sin(") and not code.contains("cloud_noise("),
		"hot cloud fragment path avoids expensive per-pixel hashes and sine")
	t.check(code.contains("aa_cloud_shadow_strength <= 0.001"),
		"performance mode branches before sampling the cloud texture")
