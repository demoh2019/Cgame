extends RefCounted
## Curvature shading is built once from shared-world height, reused by all
## LOD meshes and quality presets without another terrain texture sample.
const Curvature = preload("res://scripts/client/terrain_curvature.gd")
const Horizon = preload("res://scripts/client/terrain_horizon_ao.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func _valley(x: float, z: float) -> float:
	return 0.2 * (x * x + z * z)


func _ridge(x: float, z: float) -> float:
	return -_valley(x, z)


func _flat(_x: float, _z: float) -> float:
	return 10.0


func _grid(origin: Vector2, side: int, sampler: Callable) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	for z in side:
		for x in side:
			heights[z * side + x] = float(sampler.call(
					origin.x + float(x), origin.y + float(z)))
	return heights


func run(t) -> void:
	t.current = "convex ridges and concave valleys bake into shared vertex colors"
	var valley_sampler: Callable = Callable(self, "_valley")
	var valley_heights: PackedFloat32Array = _grid(Vector2.ZERO, 3, valley_sampler)
	var colors: PackedColorArray = Curvature.build(valley_heights, Vector2.ZERO,
			3, 1.0, valley_sampler)
	t.eq(colors.size(), 9, "3x3 heightfield receives one color per vertex")
	t.check(colors[4].r > 0.9 and colors[4].g < 0.001,
			"concave bowl bright-red channel means cavity light reduction")
	t.check(colors[4].a == 1.0, "curvature colors do not change cutout/opacity")
	var ridge_sampler: Callable = Callable(self, "_ridge")
	var ridge_heights: PackedFloat32Array = _grid(Vector2.ZERO, 3, ridge_sampler)
	var ridges: PackedColorArray = Curvature.build(ridge_heights, Vector2.ZERO,
			3, 1.0, ridge_sampler)
	t.check(ridges[4].g > 0.9 and ridges[4].r < 0.001,
			"convex hill uses green channel for subtle ridge lighting")
	var flat_sampler: Callable = Callable(self, "_flat")
	var flat: PackedColorArray = Curvature.build(
			_grid(Vector2.ZERO, 3, flat_sampler),
			Vector2.ZERO, 3, 1.0, flat_sampler)
	t.near(flat[4].r + flat[4].g, 0.0, 0.00001,
			"flat ground receives no artificial cavity shading")

	t.current = "neighboring streamed chunks keep identical border response"
	var left: PackedColorArray = Curvature.build(
			_grid(Vector2.ZERO, 3, valley_sampler),
			Vector2.ZERO, 3, 1.0, valley_sampler)
	var right: PackedColorArray = Curvature.build(
			_grid(Vector2(2.0, 0.0), 3, valley_sampler),
			Vector2(2.0, 0.0), 3, 1.0, valley_sampler)
	for z in 3:
		t.check(left[z * 3 + 2].is_equal_approx(right[z * 3]),
				"world-sampled curvature matches on adjacent chunk boundary")
	t.eq(Curvature.build(PackedFloat32Array(), Vector2.ZERO, 3,
			1.0, valley_sampler).size(), 0, "invalid geometry is rejected")
	t.eq(Curvature.build(valley_heights, Vector2.ZERO, 3, 0.0,
			valley_sampler).size(), 0, "zero spacing is rejected")

	t.current = "native Godot terrain engine exports the new vertex attribute"
	var terrain := ChunkedTerrain3D.new()
	terrain.set_height_data(valley_heights, Vector2i(3, 3))
	terrain.set_color_data(colors)
	t.eq(terrain.get_color_data().size(), 9,
			"custom engine stores authored terrain color attribute")
	t.check(terrain.get_color_data()[4].is_equal_approx(colors[4]),
			"native color upload preserves visual data")
	terrain.set_height_data(valley_heights, Vector2i(3, 3))
	t.eq(terrain.get_color_data().size(), 0,
			"new heightfield invalidates old cavity shading")
	terrain.free()

	t.current = "PBR and compatibility shaders share the visual improvement"
	var shader := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(shader != null, "textured terrain shader loads")
	if shader != null:
		var code: String = shader.code
		t.check(code.contains("global uniform float aa_terrain_curvature_strength")
				and code.contains("clamp(COLOR.r") and code.contains("clamp(COLOR.g"),
				"full PBR ground uses native vertex-color cavity and ridge values")
		t.check(code.contains("ground_contact * micro_shadow * (1.0 - cavity * 0.24)"),
				"curvature combines with existing SSAO and normal micro-occlusion")
	var fallback: String = ChunkView.GROUND_SHADER
	t.check(fallback.contains("aa_terrain_curvature_strength")
			and fallback.contains("clamp(COLOR.r") and fallback.contains("clamp(COLOR.g"),
			"painted fallback terrain uses the same cavity/ridge vertex colors")
	t.check((ChunkView as Script).source_code.contains(
			"_terrain.set_color_data(TerrainCurvature.build("),
			"streamed chunks actually upload generated curvature to native engine")
	var previous := -1.0
	for tier in 4:
		var strength: float = float(Quality.profile(tier)["curvature_strength"])
		t.check(strength >= 0.0 and strength <= 1.0 and strength > previous,
				"curvature quality increases progressively across four presets")
		previous = strength
	t.check(ProjectSettings.has_setting(
			"shader_globals/aa_terrain_curvature_strength"),
			"global uniform is registered in real project settings")

	t.current = "native terrain horizon lighting"
	var flat_sky: PackedFloat32Array = Horizon.build(
		_grid(Vector2(-8.0, -8.0), 17, flat_sampler), Vector2(-8.0, -8.0),
		17, 1.0, flat_sampler, -100.0, 100.0)
	t.eq(flat_sky.size(), 17 * 17, "native C++ AO returns one sample per terrain vertex")
	t.near(flat_sky[8 * 17 + 8], 1.0, 0.00001,
		"flat terrain receives full sky with no fake darkening")
	var west_origin := Vector2(-16.0, -8.0)
	var east_origin := Vector2(0.0, -8.0)
	var west_sky: PackedFloat32Array = Horizon.build(
		_grid(west_origin, 17, valley_sampler), west_origin, 17, 1.0,
		valley_sampler, -100.0, 100.0)
	var east_sky: PackedFloat32Array = Horizon.build(
		_grid(east_origin, 17, valley_sampler), east_origin, 17, 1.0,
		valley_sampler, -100.0, 100.0)
	t.eq(west_sky.size(), 17 * 17, "valley sky field is complete")
	t.eq(east_sky.size(), 17 * 17, "neighbour's sky field is complete")
	t.check(west_sky[8 * 17 + 16] < 0.97,
		"terrain valley sees less ambient sky than a flat plain")
	for row in 17:
		t.near(west_sky[row * 17 + 16], east_sky[row * 17],
			0.00001, "adjacent terrain chunks agree at shared horizon row %d" % row)
	t.eq(Horizon.build(PackedFloat32Array(), Vector2.ZERO, 17, 1.0,
		valley_sampler, -100.0, 100.0).size(), 0,
		"missing heightfield cannot produce misaligned vertex colors")
	t.check(colors[4].b > 0.99,
		"old curvature-only data defaults to unobstructed sky")
	var pbr := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(pbr != null and pbr.code.contains("aa_terrain_horizon_ao_strength")
		and pbr.code.contains("clamp(COLOR.b, 0.0, 1.0)"),
		"textured PBR terrain uses baked sky from the native vertex color channel")
	t.check(ChunkView.GROUND_SHADER.contains("aa_terrain_horizon_ao_strength")
		and ChunkView.GROUND_SHADER.contains("clamp(COLOR.b, 0.0, 1.0)"),
		"Compatibility fallback receives the same low-cost terrain shading")
	t.check(ProjectSettings.has_setting("shader_globals/aa_terrain_horizon_ao_strength"),
		"native sky visibility has an explicitly registered renderer global")
	t.eq(float(Quality.profile(0)["horizon_ao_strength"]), 0.0,
		"Performance disables native CPU halo sampling and pixel shading")
	t.eq(float(Quality.profile(1)["horizon_ao_strength"]), 0.0,
		"Balanced disables native CPU halo sampling and pixel shading")
	t.check(float(Quality.profile(3)["horizon_ao_strength"])
		> float(Quality.profile(2)["horizon_ao_strength"]),
		"Ultra keeps more sky-depth shading than High")
	ChunkView.configure_terrain_horizon(0)
	t.check(not ChunkView.terrain_horizon_enabled,
		"low-quality terrain skips the native sky integration")
	ChunkView.configure_terrain_horizon(3)
	t.check(ChunkView.terrain_horizon_enabled,
		"Ultra enables native horizon sky visibility on streamed chunks")
	ChunkView.configure_terrain_horizon(1)
	var quality_code := load("res://scripts/client/graphics_quality.gd") as GDScript
	t.check(quality_code != null and quality_code.source_code.contains(
		"ChunkView.apply_terrain_horizon(lod_terrain)"),
		"runtime quality changes update already loaded terrain vertex colors")
