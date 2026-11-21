extends RefCounted
## Exact wrapped PCG grid sampling and cloud-octave integration.

const Grid = preload("res://scripts/client/scalar_grid_sampler.gd")
const Clouds = preload("res://scripts/client/cloud_shadow_lut.gd")


func run(t) -> void:
	t.current = "native periodic scalar grid sampling"
	var grid := PackedFloat32Array([0.0, 1.0, 2.0, 3.0])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(0.25, 0.25), Vector2(0.5, 0.5),
		Vector2(0.75, 0.75), Vector2(1.25, -0.75), Vector2(-2, 3)
	])
	var original: PackedFloat32Array = grid.duplicate()
	var wrapped: PackedFloat32Array = Grid.sample_wrapped(grid, Vector2i(2, 2), uvs)
	t.eq(wrapped.size(), uvs.size(), "one sample per UV")
	t.near(wrapped[0], 0.0, 0.00001, "first lattice vertex")
	t.near(wrapped[1], 1.5, 0.00001, "mid-cell bilinear interpolation")
	t.near(wrapped[2], 3.0, 0.00001, "last lattice vertex")
	t.near(wrapped[3], 1.5, 0.00001, "wrap around the periodic seam")
	t.near(wrapped[4], wrapped[1], 0.00001, "negative and shifted UVs repeat")
	t.eq(wrapped[5], 0.0, "integer UV periods repeat exactly")
	t.eq(grid, original, "input grid is immutable")

	for smooth in [false, true]:
		var native: PackedFloat32Array = Grid.sample_wrapped(grid, Vector2i(2, 2), uvs, smooth)
		var scalar: PackedFloat32Array = Grid.sample_wrapped(grid, Vector2i(2, 2), uvs, smooth, true)
		for i in native.size():
			t.near(native[i], scalar[i], 0.00001, "native and scalar sample parity")
	var a: PackedFloat32Array = Grid.sample_wrapped(
			grid, Vector2i(2, 2), PackedVector2Array([Vector2(0.125, 0.25)]), false)
	var b: PackedFloat32Array = Grid.sample_wrapped(
			grid, Vector2i(2, 2), PackedVector2Array([Vector2(0.125, 0.25)]), true)
	t.near(a[0], 1.25, 0.00001, "linear sampling")
	t.near(b[0], 1.15625, 0.00001, "smoothstep sampling")
	t.eq(Grid.sample_wrapped(grid, Vector2i(3, 2), uvs).size(), 0,
		"wrong source dimensions are rejected")
	t.eq(Grid.sample_wrapped(grid, Vector2i(2, 2),
			PackedVector2Array([Vector2(INF, 0)])).size(), 0,
		"nonfinite UV rejected")
	t.eq(Grid.sample_wrapped(PackedFloat32Array([NAN, 0, 1, 2]),
			Vector2i(2, 2), uvs).size(), 0, "invalid scalar grid rejected")
	t.eq(Grid.sample_wrapped(PackedFloat32Array([0.4]), Vector2i.ONE, uvs).size(),
		uvs.size(), "single-cell grid remains valid")

	t.current = "real cloud LUT uses native octave batches"
	var cloud: Image = Clouds.build_image()
	var fallback: Image = Clouds.build_image(true)
	t.check(cloud != null and fallback != null, "both cloud paths create textures")
	if cloud == null or fallback == null:
		return
	t.check(Clouds.build_image() == cloud, "production cloud image stays cached")
	var biggest: float = 0.0
	for y in range(0, Clouds.SIZE, 3):
		for x in range(0, Clouds.SIZE, 3):
			biggest = maxf(biggest, absf(cloud.get_pixel(x, y).r - fallback.get_pixel(x, y).r))
	t.check(biggest <= 2.0 / 255.0, "native and stock Godot cloud alpha are byte-close")
	var source: String = (Clouds as Script).source_code
	t.check(source.contains("ScalarGridSampler.sample_wrapped("),
		"real cloud LUT builds each octave with the native grid sampler")
