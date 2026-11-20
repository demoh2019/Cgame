extends RefCounted
## GPU-instanced foliage fading: avoid translucent draw sorting and keep low presets cheap.
const Foliage = preload("res://scripts/client/foliage.gd")
const SceneryLod = preload("res://scripts/client/scenery_lod.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "GPU foliage fade matches actual scene distance budgets"
	t.near(SceneryLod.foliage_fade_width(0), 0.0, 0.0001, "Performance skips pixel dithering")
	t.near(SceneryLod.foliage_fade_width(1), 0.0, 0.0001, "Balanced skips pixel dithering")
	t.check(SceneryLod.foliage_fade_width(2) > 0.0, "High fades distant foliage")
	t.check(SceneryLod.foliage_fade_width(3) > SceneryLod.foliage_fade_width(2),
		"Ultra has a wider smooth transition")
	t.eq(SceneryLod.foliage_fade_width(-22), 0.0, "invalid low quality clamps")
	t.eq(SceneryLod.foliage_fade_width(99), SceneryLod.foliage_fade_width(3),
		"invalid high quality clamps")
	for quality in 4:
		t.check(SceneryLod.range_for("tree:oak", quality) >
			SceneryLod.foliage_fade_width(quality), "trees fade before culling")
		t.check(SceneryLod.range_for("bush", quality) >
			SceneryLod.foliage_fade_width(quality), "bushes fade before culling")
	t.current = "material selection never fades landmarks and foreground scatter"
	t.eq(Foliage.fade_role_for("tree:Oak"), 1, "nature tree gets distant fade")
	t.eq(Foliage.fade_role_for("painted:3"), 1, "painted fallback trees fade")
	t.eq(Foliage.fade_role_for("kenney_expanded_tree:2"), 1, "imported trees fade")
	t.eq(Foliage.fade_role_for("bush"), 2, "bushes fade using their own range")
	t.eq(Foliage.fade_role_for("berry"), 2, "berries fade using bush range")
	t.eq(Foliage.fade_role_for("monument:2"), 0, "landmark cannot vanish early")
	t.eq(Foliage.fade_role_for("decor:Grass_1"), 0,
		"decor with its own author range is not misclassified")
	var source := BoxMesh.new()
	source.material = StandardMaterial3D.new()
	var tree_mesh: ArrayMesh = Foliage.swayed(source, "tree:aa_dither_test", 0.14)
	var tree_mat := tree_mesh.surface_get_material(0) as ShaderMaterial
	t.eq(int(tree_mat.get_shader_parameter("fade_role")), 1, "GPU tree role is set on material")
	var bush_mesh: ArrayMesh = Foliage.swayed(source, "bush", 0.12)
	var bush_mat := bush_mesh.surface_get_material(0) as ShaderMaterial
	t.eq(int(bush_mat.get_shader_parameter("fade_role")), 2, "GPU bush role is set on material")
	t.current = "opaque ordered dithering"
	var shader: String = Foliage.SHADER_CODE
	t.check(shader.contains("ordered_dither_4x4(FRAGCOORD.xy)"),
		"fade uses a stable, screen-space 4 by 4 threshold")
	t.check(shader.contains("if (fade_coverage < 0.999)"),
		"most visible fragments avoid the dither calculations")
	t.check(shader.contains("discard;"), "faded pixels are clipped rather than blended")
	t.check(shader.contains("distance_to_camera = length(root - CAMERA_POSITION_WORLD.xz)"),
		"one world-space distance serves both wind and disappearance")
	t.check(shader.contains("ALPHA_SCISSOR_THRESHOLD = scissor"),
		"leaf cutouts retain their original alpha")
	var project: Dictionary = ProjectSettings.get_setting("shader_globals/aa_foliage_fade_width", {})
	t.eq(str(project.get("type", "")), "float", "fade width global exists")
	t.eq(float(project.get("value", -1.0)), 0.0, "fade disabled until quality applies")
	t.check(ProjectSettings.has_setting("shader_globals/aa_foliage_tree_cull"),
		"tree draw end is shared by all instances")
	t.check(ProjectSettings.has_setting("shader_globals/aa_foliage_bush_cull"),
		"bush draw end is shared by all instances")
	var quality_source: String = (GraphicsQuality as Script).source_code
	t.check(quality_source.contains('global_shader_parameter_set(&"aa_foliage_fade_width"'),
		"quality updates the fade width without mesh regeneration")
	t.check(quality_source.contains('global_shader_parameter_set(&"aa_foliage_tree_cull"'),
		"tree distance follows the existing scene preset")
	t.check(quality_source.contains('global_shader_parameter_set(&"aa_foliage_bush_cull"'),
		"bush distance follows the existing scene preset")
