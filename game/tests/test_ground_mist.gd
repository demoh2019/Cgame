extends RefCounted
## Fog volumes use native Forward+ froxels and remain off for low-end/dungeons.
const GroundMist = preload("res://scripts/client/ground_mist.gd")
const Online = preload("res://scripts/client/online_main.gd")
const ShaderPath := "res://assets/shaders/ground_mist.gdshader"


func run(t) -> void:
	t.current = "renderer and quality budgets"
	for method in ["mobile", "gl_compatibility", ""]:
		for tier in range(4):
			var disabled: Dictionary = GroundMist.settings(
				"swamp", 0.45, 0.1, 1.0, tier, method)
			t.check(not bool(disabled["enabled"]), "no custom fog on unsupported backends")
			t.near(float(disabled["density"]), 0.0, 0.00001,
				"unsupported renderer never creates mist density")
	for tier in [0, 1]:
		t.check(not bool(GroundMist.settings("swamp", 0.7, 0.1, 1.0,
			tier, "forward_plus")["enabled"]), "low presets omit fog volume")
	t.check(not bool(GroundMist.settings("swamp", 0.7, 0.1, 1.0,
		3, "forward_plus", true)["enabled"]), "dungeons never spawn mist")
	var high: Dictionary = GroundMist.settings("swamp", 0.45, 0.1, 0.4, 2, "forward_plus")
	var ultra: Dictionary = GroundMist.settings("swamp", 0.45, 0.1, 0.4, 3, "forward_plus")
	t.check(bool(high["enabled"]) and bool(ultra["enabled"]), "high fidelity renders local mist")
	t.check(float(ultra["density"]) > float(high["density"]), "ultra increases local detail mood")
	t.check((ultra["extent"] as Vector3).x > (high["extent"] as Vector3).x,
		"ultra offers a larger but bounded local froxel region")

	t.current = "biome color, storm and golden-hour density"
	var morning: Dictionary = GroundMist.settings("forest", 0.45, 0.04, 0.0, 3, "forward_plus")
	var midday: Dictionary = GroundMist.settings("forest", 0.95, 0.8, 0.0, 3, "forward_plus")
	t.check(float(morning["density"]) > float(midday["density"]),
		"low-angle morning light reveals fog ribbons without obscuring midday")
	var storm: Dictionary = GroundMist.settings("forest", 0.45, 0.04, 1.0, 3, "forward_plus")
	t.check(float(storm["density"]) > float(morning["density"]), "wet weather boosts vapor")
	var swamp: Dictionary = GroundMist.settings("swamp", 0.45, 0.04, 0.0, 3, "forward_plus")
	t.check(float(swamp["density"]) > float(morning["density"]), "marsh has denser ground mist")
	t.check(swamp["tint"] != morning["tint"], "swamp has unique scattering albedo")
	var mountain: Dictionary = GroundMist.settings("mountain", 0.45, 0.04, 1.0, 3, "forward_plus")
	t.check(not bool(mountain["enabled"]), "windswept mountains stay clear")
	for biome in ["plains", "swamp", "forest", "beach", "mountain", "unknown"]:
		for tier in range(4):
			var p: Dictionary = GroundMist.settings(biome, NAN, INF, NAN, tier, "forward_plus")
			t.check(is_finite(float(p["density"])) and float(p["density"]) >= 0.0
				and float(p["density"]) <= 0.072, "all bad weather inputs remain bounded")
			t.check((p["extent"] as Vector3).x <= 88.0,
				"froxel box never fills the entire 700m world")

	t.current = "quality-gated 3D vapor layers"
	for renderer in ["mobile", "gl_compatibility", "unknown"]:
		for tier in 4:
			var p: Dictionary = GroundMist.settings("swamp", 0.5, 0.1, 1.0, tier, renderer)
			t.near(float(p["vapor_3d_detail"]), 0.0, 0.0001,
				"unsupported renderer skips all 3D fog noise")
	for tier in [0, 1, 2]:
		var p: Dictionary = GroundMist.settings("swamp", 0.5, 0.1, 1.0,
			tier, "forward_plus")
		t.near(float(p["vapor_3d_detail"]), 0.0, 0.0001,
			"only Ultra evaluates the new 3D vapor noise")
	var ultra_vapor: Dictionary = GroundMist.settings(
		"swamp", 0.5, 0.1, 1.0, 3, "forward_plus")
	t.near(float(ultra_vapor["vapor_3d_detail"]), 0.55, 0.0001,
		"Ultra adds thin layered vapor turbulence")
	var dungeon_vapor: Dictionary = GroundMist.settings(
		"swamp", 0.5, 0.1, 1.0, 3, "forward_plus", true)
	t.near(float(dungeon_vapor["vapor_3d_detail"]), 0.0, 0.0001,
		"underground avoids extra fog work")
	for biome in ["beach", "swamp", "forest", "plains", "mountain"]:
		var p: Dictionary = GroundMist.settings(
			biome, 0.5, 0.2, 0.9, 3, "forward_plus")
		t.check(float(p["vapor_3d_detail"]) >= 0.0 and
			float(p["vapor_3d_detail"]) <= 0.55,
			"vapor complexity is always bounded across biomes")
	t.check((GroundMist as Script).source_code.contains(
		'_material.set_shader_parameter("vapor_3d_detail"'),
		"quality changes update the shared fog material")
	t.check((GroundMist as Script).source_code.contains(
		'_volume.has_method("set_snapped_world_anchor")'),
		"native world-grid position snapping is used when available")
	t.check((GroundMist as Script).source_code.contains(
		"_volume.global_position = anchor"),
		"stock Godot retains the existing stable anchor fallback")

	t.current = "shader and scene wiring"
	var shader := load(ShaderPath) as Shader
	t.check(shader != null, "one real Godot fog shader exists")
	if shader != null:
		t.check(shader.code.begins_with("shader_type fog;"),
			"shader is native fog, not transparent screen-plane")
		t.check(shader.code.contains("WORLD_POSITION") and shader.code.contains("UVW"),
			"world-anchored froxel noise fades smoothly at volume bounds")
		t.check(shader.code.contains("DENSITY =") and shader.code.contains("ALBEDO ="),
			"volumetric density and physically illuminated scattering are authored")
		t.check(shader.code.contains("if (vapor_3d_detail > 0.001)"),
			"3D noise is skipped in the High and lower GPU presets")
		t.check(shader.code.contains("float mist_noise3(vec3 p)"),
			"Ultra calculates genuine 3D value noise in world coordinates")
		t.check(shader.code.contains("height * 0.24") and
			shader.code.contains("WORLD_POSITION.xz + noise_offset"),
			"air layers vary vertically but retain wind-driven world anchoring")
		t.check(shader.code.contains("outskirts = 1.0 - smoothstep("),
			"original finite-volume fade still prevents hard box edges")
		t.check(not shader.code.contains("sampler3D"),
			"3D vapor detail requires no new texture allocation")
	var mist := GroundMist.new()
	mist.setup()
	var volume: FogVolume = mist.get_node_or_null("CinematicGroundMist") as FogVolume
	t.check(volume != null, "one bounded Godot FogVolume is created")
	if volume != null:
		t.check(volume.material is ShaderMaterial, "real volume material uses fog shader")
		t.check(not volume.visible, "default state never renders before weather arrives")
		mist.setup()
		t.eq(mist.get_child_count(), 1, "setup reuses the same native fog volume")
	mist.free()
	var online: String = (Online as Script).source_code
	t.check(online.contains("GroundMist.new()") and online.contains("_ground_mist.update_view("),
		"multiplayer camera streams localized fog without server code")
