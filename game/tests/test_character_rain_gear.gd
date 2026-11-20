extends RefCounted
## Weathered PBR clothes and gear: no broken imported art or per-frame churn.
const RainGear = preload("res://scripts/client/character_rain_gear.gd")
const CharacterModel = preload("res://scripts/client/character_model.gd")
const EntityView = preload("res://scripts/client/entity_view.gd")
const OnlineGame = preload("res://scripts/client/online_main.gd")


func run(t) -> void:
	t.current = "weather and quality budget"
	t.eq(RainGear.step_for(1.0, 0, "forward_plus"), 0,
		"Performance has zero wardrobe shader variants")
	t.eq(RainGear.step_for(1.0, 1, "forward_plus"), 1,
		"Balanced uses a low-cost rain sheen")
	t.eq(RainGear.step_for(1.0, 2, "forward_plus"), 3,
		"High adds physically layered rain highlights")
	t.eq(RainGear.step_for(1.0, 3, "forward_plus"), 4,
		"Ultra can use the full glossy rain response")
	t.eq(RainGear.step_for(1.0, 3, "gl_compatibility"), 1,
		"Compatibility never enables clear-coat lighting")
	t.eq(RainGear.step_for(1.0, 3, "mobile"), 1,
		"mobile render path stays in the cheap material tier")
	for invalid in [NAN, INF, -1.0, 0.0]:
		t.eq(RainGear.step_for(invalid, 3, "forward_plus"), 0,
			"invalid/no storm cannot create bogus rain variants")
	t.check(RainGear.step_for(0.45, 3, "forward_plus") <
		RainGear.step_for(0.9, 3, "forward_plus"),
		"material wetness rises with server-driven weather")

	t.current = "imported PBR resources survive wet clear coat"
	var base := StandardMaterial3D.new()
	base.albedo_color = Color(0.52, 0.36, 0.24, 0.8)
	base.roughness = 0.88
	base.metallic = 0.16
	base.metallic_specular = 0.48
	t.check(RainGear.supports(base), "regular opaque PBR clothing is eligible")
	var wet := RainGear.variant(base, 4)
	t.check(wet != base and wet is StandardMaterial3D,
		"wet appearance uses a separate material, never mutates imported art")
	t.check(wet.clearcoat_enabled and wet.clearcoat > 0.0,
		"Ultra creates a real native clearcoat lobe")
	t.check(wet.roughness < base.roughness and wet.roughness >= 0.28,
		"wet cloth has physically smoother microfacets with a bounded floor")
	t.near(wet.metallic, base.metallic, 0.000001,
		"wetness does not invent metallic content")
	t.near(wet.metallic_specular, base.metallic_specular, 0.000001,
		"source specularity is maintained")
	t.near(wet.albedo_color.a, base.albedo_color.a, 0.000001,
		"alpha stays authored")
	t.check(wet.albedo_color.r < base.albedo_color.r,
		"damp cloth darkens subtly instead of bleaching")
	t.check(not base.clearcoat_enabled and base.roughness == 0.88,
		"original imported dry material remains untouched")
	t.check(RainGear.variant(base, 4) == wet,
		"every player shares the same cached material variant")
	t.check(RainGear.variant(base, 0) == base,
		"dry mode restores actual original material without copying")
	var low := RainGear.variant(base, 1)
	t.check(not low.clearcoat_enabled and low.roughness < base.roughness,
		"Balanced darkens and smooths fabric without paying clearcoat cost")
	var cutout := StandardMaterial3D.new()
	cutout.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	t.check(not RainGear.supports(cutout), "hair and other cutouts are not coated")
	t.check(RainGear.variant(cutout, 4) == cutout,
		"masked surfaces remain untouched and correctly alpha-tested")

	t.current = "actual character outfits and dynamically attached gear"
	var actor := CharacterModel.new()
	var cloth := MeshInstance3D.new()
	cloth.name = "Outfit_Torso"
	var shape := BoxMesh.new()
	shape.material = base
	cloth.mesh = shape
	actor.add_child(cloth)
	actor._capture_wet_surfaces(actor)
	actor.set_wetness_step(4)
	t.check(cloth.get_surface_override_material(0) == wet,
		"real mesh surface override selects shared Ultra material")
	actor.set_wetness_step(4)
	t.check(cloth.get_surface_override_material(0) == wet,
		"unchanged weather avoids per-frame material churn")
	actor.set_wetness_step(0)
	t.eq(cloth.get_surface_override_material(0), null,
		"dry weather restores authored mesh material override exactly")
	var hood := MeshInstance3D.new()
	hood.name = "Gear_head_hood"
	var hood_shape := BoxMesh.new()
	hood_shape.material = base
	hood.mesh = hood_shape
	actor.add_child(hood)
	actor.set_wetness_step(3)
	actor._capture_wet_surfaces(actor)
	t.check((hood.get_surface_override_material(0) as StandardMaterial3D).clearcoat_enabled,
		"newly equipped headgear inherits the current rain sheen")
	var skin := MeshInstance3D.new()
	skin.name = "Superhero_Skin"
	var skin_shape := BoxMesh.new()
	skin_shape.material = base
	skin.mesh = skin_shape
	actor.add_child(skin)
	actor._capture_wet_surfaces(actor)
	t.eq(skin.get_surface_override_material(0), null,
		"skin never receives a fabric-water clearcoat")
	actor.free()

	t.current = "multiplayer scene plumbing"
	var character_source: String = (CharacterModel as Script).source_code
	t.check(character_source.contains("_capture_wet_surfaces(model)") and
		character_source.contains("if gear_changed:"),
		"base outfit and live gear additions both register for weather")
	var entity_source: String = (EntityView as Script).source_code
	t.check(entity_source.contains("model.set_wetness_step(_wetness_step)"),
		"new streamed party members and infected inherit current rain")
	var game_source: String = (OnlineGame as Script).source_code
	t.check(game_source.contains("RainGear.step_for(atmosphere.storm") and
		game_source.contains("entities.set_wetness_step(gear_step)"),
		"existing day-night weather applies rain to all nearby actors")
	RainGear.clear_cache()
