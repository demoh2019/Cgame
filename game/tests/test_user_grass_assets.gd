extends RefCounted
## Optional user-licensed 3D meadow asset. Default public checkout has no
## proprietary textures, and must retain the original card-grass fallback.
const Plants = preload("res://scripts/client/ground_plants.gd")


func run(t) -> void:
	t.current = "owner supplied 3D grass overrides the active drawn meadow"
	t.eq(Plants.USER_GRASS_VARIANTS.size(), 8, "user ZIP provides eight grass variations")
	t.check(Plants.USER_GRASS_GLTF.ends_with("/standard/vlkhcbxia_tier_3_nonUE.gltf"),
		"uses the standard glTF export instead of the UE-specific source")
	t.check(Plants.USER_GRASS_DISTANCE > 10.0 and Plants.USER_GRASS_DISTANCE <= 36.0,
		"high-detail grass is restricted to near-camera distances")
	t.check(Plants.SPECIES["lush_grass"]["cards"],
		"legacy photo-card metadata remains for licensed-pack-free fallback")
	t.eq(Plants.SPECIES["lush_grass_far"]["begin"], Plants.USER_GRASS_DISTANCE,
		"far cards only begin where the true 3D meshes stop")
	var installed: bool = Plants.user_grass_available()
	if installed:
		var mesh: Mesh = Plants.mesh("#usergrassA")
		t.check(mesh != null and mesh.get_surface_count() > 0,
			"installed grass produces a real imported 3D mesh")
		if mesh != null:
			t.check(mesh.has_meta("source_grass_basis"),
				"source centimeter scale and Y-axis orientation are retained")
	else:
		t.eq(Plants.mesh("#usergrassA"), null,
			"missing licensed pack remains optional instead of breaking asset imports")
	t.check((Plants as Script).source_code.contains("species == \"lush_grass\" and use_real_grass"),
		"installed mesh replacement is wired to the active draw path")
	t.check((Plants as Script).source_code.contains("visibility_range_begin"),
		"near and far variants use complementary visibility ranges")
