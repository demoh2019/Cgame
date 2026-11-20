extends RefCounted
## Cinematic PBR skin shading only for imported character flesh.
const SkinScattering = preload("res://scripts/client/graphics_skin_scattering.gd")
const CharacterModel = preload("res://scripts/client/character_model.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "skin SSS quality scales without a low-end fullscreen pass"
	var low: Dictionary = SkinScattering.settings(0, "forward_plus")
	var balanced: Dictionary = SkinScattering.settings(1, "forward_plus")
	var high: Dictionary = SkinScattering.settings(2, "forward_plus")
	var ultra: Dictionary = SkinScattering.settings(3, "forward_plus")
	t.check(not bool(low["enabled"]) and not bool(balanced["enabled"]),
			"Performance and Balanced cannot allocate the SSS compositing pass")
	t.check(bool(high["enabled"]) and bool(ultra["enabled"]),
			"High and Ultra enable realistic subsurface scattering on imported skin")
	t.eq(int(low["quality"]), RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_DISABLED,
			"low tier disables native screen-space skin diffusion")
	t.eq(int(high["quality"]), RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_MEDIUM,
			"High uses medium-quality diffusion kernel")
	t.eq(int(ultra["quality"]), RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_HIGH,
			"Ultra uses high-quality native skin diffusion")
	t.check(float(high["strength"]) < float(ultra["strength"])
			and float(ultra["strength"]) < 0.5,
			"diffusion is cinematic but restrained enough to preserve faces")
	t.check(float(high["scale"]) < float(ultra["scale"]),
			"Ultra allows more sub-surface blur at grazing light")
	for method in ["mobile", "gl_compatibility", ""]:
		for tier in 4:
			t.check(not bool(SkinScattering.settings(tier, method)["enabled"]),
					"unsupported backends never run the native SSS pass")
	t.eq(SkinScattering.settings(-100, "forward_plus"), low, "negative quality clamps")
	t.eq(SkinScattering.settings(100, "forward_plus"), ultra, "excess quality clamps")
	t.current = "only authored opaque skin receives scattering"
	var body := MeshInstance3D.new()
	body.name = "Elf_Male_Body"
	body.mesh = BoxMesh.new()
	t.check(SkinScattering.is_skin_mesh(body), "native imported character body is skin")
	var head := MeshInstance3D.new()
	head.name = "SuperheroMesh"
	head.mesh = SphereMesh.new()
	head.set_meta("skin", true)
	t.check(SkinScattering.is_skin_mesh(head), "explicit head/body tags are supported")
	body.name = "Outfit_Female_Peasant_Body"
	t.check(not SkinScattering.is_skin_mesh(body), "clothing Body suffix is not mistaken for flesh")
	body.name = "Gear_helmet_Body"
	t.check(not SkinScattering.is_skin_mesh(body), "worn equipment never receives skin scattering")
	body.name = "Elf_Female_Hair"
	t.check(not SkinScattering.is_skin_mesh(body), "hair remains a normal cutout PBR material")
	var base := StandardMaterial3D.new()
	base.albedo_color = Color(0.66, 0.44, 0.33, 1.0)
	base.roughness = 0.63
	base.metallic = 0.0
	t.check(SkinScattering.supports(base), "regular imported opaque PBR skin is supported")
	var metal := StandardMaterial3D.new()
	metal.metallic = 0.8
	t.check(not SkinScattering.supports(metal), "metal and leather armor cannot use skin SSS")
	var hair := StandardMaterial3D.new()
	hair.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	t.check(not SkinScattering.supports(hair), "cutout eyelashes and hair remain untouched")
	t.eq(SkinScattering.variant(base, 1, "forward_plus"), base,
			"Balanced uses the authored imported material directly")
	t.eq(SkinScattering.variant(base, 3, "gl_compatibility"), base,
			"Compatibility never duplicates shader variants")

	t.current = "high-end material duplicates preserve original textures and tint"
	var albedo_texture := ImageTexture.new()
	base.albedo_texture = albedo_texture
	var skin: StandardMaterial3D = SkinScattering.variant(base, 3, "forward_plus")
	t.check(skin != base, "SSS variant never edits the source imported material")
	t.check(skin.subsurf_scatter_enabled and skin.subsurf_scatter_skin_mode,
			"native SSS and skin shader mode are both active")
	t.near(skin.subsurf_scatter_strength, float(ultra["strength"]), 0.00001,
			"native engine receives bounded physical skin-scattering strength")
	t.check(skin.albedo_texture == albedo_texture,
			"skin scattering reuses the same imported albedo resource")
	t.near(skin.roughness, base.roughness, 0.00001,
			"SSS preserves authored roughness and reflective finish")
	t.near(skin.metallic, base.metallic, 0.00001,
			"skin shading does not invent metallic reflectivity")
	t.check(skin.albedo_color == base.albedo_color,
			"player skin tint and original alpha remain unchanged")
	t.check(SkinScattering.variant(base, 3, "forward_plus") == skin,
			"all instances with the same source reuse the same GPU material")
	t.check(not base.subsurf_scatter_enabled,
			"original glTF materials are never mutated")
	var med: StandardMaterial3D = SkinScattering.variant(base, 2, "forward_plus")
	t.check(med != skin and med.subsurf_scatter_strength < skin.subsurf_scatter_strength,
			"High uses a separate cheaper shared material tier")

	t.current = "live character model switches individual head skin only"
	var actor := CharacterModel.new()
	actor.pack_mode = true
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).material = base
	mesh.name = "Superhero_Mesh"
	mesh.set_meta("skin", true)
	actor.add_child(mesh)
	var cloth := MeshInstance3D.new()
	cloth.mesh = BoxMesh.new()
	(cloth.mesh as BoxMesh).material = base
	cloth.name = "Outfit_Female_Peasant_Body"
	actor.add_child(cloth)
	actor._capture_skin_surfaces(actor)
	actor.apply_skin_quality(3, "forward_plus")
	t.check(mesh.get_surface_override_material(0) == skin,
			"real head receives shared Ultra SSS shader variant")
	t.eq(cloth.get_surface_override_material(0), null,
			"clothes are unchanged even when using the same source material")
	actor.apply_skin_quality(1, "forward_plus")
	t.eq(mesh.get_surface_override_material(0), null,
			"Balanced restores the exact original surface override")
	actor.apply_skin_quality(2, "forward_plus")
	t.check(mesh.get_surface_override_material(0) == med,
			"switching back to High selects the cheaper cached skin")
	actor.apply_skin_quality(3, "mobile")
	t.eq(mesh.get_surface_override_material(0), null,
			"backend fallback restores original opaque imported materials")
	actor.free()
	body.free()
	head.free()

	t.current = "all active actors inherit new graphics tier without per-frame work"
	var quality_source: String = (GraphicsQuality as Script).source_code
	var actor_source: String = (CharacterModel as Script).source_code
	t.check(quality_source.contains("GraphicsSkinShading.configure(_level, str(method), viewport)"),
			"global SSS quality is driven by every existing quality toggle")
	t.check(actor_source.contains("_capture_skin_surfaces(model)")
			and actor_source.contains("apply_skin_quality(SkinSSS.current_level"),
			"newly streamed actors inherit the current SSS tier")
	t.check(actor_source.contains("func apply_skin_quality("),
			"existing actors can change their material on the next preset switch")
	t.check(actor_source.contains("SkinSSS.clear_cache()"),
			"leaving the game releases cached skin material variants")
	SkinScattering.clear_cache()
