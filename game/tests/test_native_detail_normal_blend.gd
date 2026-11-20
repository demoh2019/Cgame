extends RefCounted
## Regression for native detail-normal-only PBR: formerly dropped by the
## engine's generated shader when detail_albedo was null.
const Stone = preload("res://scripts/client/graphics_stone_microdetail.gd")
const MeshPBR = preload("res://scripts/client/mesh_pbr_preservation.gd")
const Catalog = preload("res://scripts/client/model_catalog.gd")


## Mirror the renderer's signed tangent-space Whiteout composition for
## numerical checks; this does not replace an actual GPU screenshot test.
static func combine_packed(base_packed: Vector3, micro_packed: Vector3) -> Vector3:
	var a: Vector3 = (base_packed * 2.0 - Vector3.ONE).normalized()
	var b: Vector3 = (micro_packed * 2.0 - Vector3.ONE).normalized()
	var combined := Vector3(a.x + b.x, a.y + b.y, a.z * b.z).normalized()
	return (combined + Vector3.ONE) * 0.5


func run(t) -> void:
	Stone.clear_cache()
	t.current = "detail-normal-only shader path preserves PBR base maps"
	Stone.configure(3, "forward_plus")
	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.62, 0.59, 0.54)
	source.normal_enabled = true
	var authored_albedo := ImageTexture.new()
	var authored_normal := ImageTexture.new()
	source.albedo_texture = authored_albedo
	source.normal_texture = authored_normal
	var baked: BaseMaterial3D = MeshPBR.material_for_bake(source, true, true, true)
	t.check(baked.detail_enabled and baked.detail_normal != null,
		"native feature and micro normal are active for Ultra stone")
	t.eq(baked.detail_albedo, null,
		"colorless detail path saves a texture fetch and preserves artist albedo")
	t.eq(baked.albedo_texture, authored_albedo,
		"original PBR color texture is never overwritten")
	t.eq(baked.normal_texture, authored_normal,
		"original tangent-space normal is retained for the native composite")
	t.check(baked.heightmap_enabled,
		"Ultra parallax and corrected micro normals use the same UV field")
	t.eq(source.detail_normal, null,
		"imported source material is untouched")

	t.current = "two tangent-space normal layers blend without losing base shape"
	var flat := Vector3(0.5, 0.5, 1.0)
	var tilt := Vector3(0.72, 0.38, 0.91)
	var detail := Vector3(0.37, 0.68, 0.95)
	var flat_result := combine_packed(flat, detail)
	t.check(flat_result.distance_to(detail) < 0.03,
		"flat authored normal reproduces the micro normal without corruption")
	var base_only := combine_packed(tilt, flat)
	var blended := combine_packed(tilt, detail)
	t.check(base_only.distance_to(tilt) < 0.03,
		"flat detail does not erase an existing authored normal")
	t.check(blended.distance_to(tilt) > 0.02 and blended.distance_to(detail) > 0.02,
		"combined result retains contributions from both normal maps")
	t.check((blended * 2.0 - Vector3.ONE).is_normalized(),
		"renderer outputs a unit normal in packed tangent space")

	t.current = "fragment variation and quality gates"
	var low := Stone.normal_at(Vector2(0.23, 0.34), Stone.HIGH_AMOUNT)
	var ultra := Stone.normal_at(Vector2(0.23, 0.34), Stone.ULTRA_AMOUNT)
	t.check(Vector2(ultra.x, ultra.y).length() >
		Vector2(low.x, low.y).length(),
		"Ultra fractures and chips deepen normals at zero runtime ALU cost")
	var first: float = Stone.height_at(Vector2(0.0, 0.24))
	var periodic: float = Stone.height_at(Vector2(1.0, 0.24))
	t.near(first, periodic, 0.00001,
		"new fracture pattern remains seamless for UV repeat")
	t.check(Stone.height_at(Vector2(0.13, 0.24)) != first,
		"cracks add visible microstructure instead of a constant normal")
	Stone.configure(1, "forward_plus")
	t.check(not baked.detail_enabled and baked.detail_normal == null,
		"Balanced removes native detail shader and normal texture")
	Stone.configure(3, "mobile")
	t.check(not baked.detail_enabled,
		"Mobile backend avoids extra normal-map blending")
	Stone.configure(2, "forward_plus")
	t.check(baked.detail_enabled and baked.detail_normal != null,
		"High restores corrected micro normals without POM")
	t.check(not baked.heightmap_enabled,
		"High keeps lightweight detail shading")
	var tangentless := MeshPBR.material_for_bake(source, false, true, true)
	t.check(not tangentless.detail_enabled,
		"missing mesh tangents cannot trigger invalid normal-space shading")

	t.current = "real imported scene wiring"
	var catalog_src: String = (Catalog as Script).source_code
	t.check(catalog_src.contains("StoneMicrodetail.is_masonry_path(path)"),
		"only authored ruined stone can use corrected normal path")
	Stone.clear_cache()
