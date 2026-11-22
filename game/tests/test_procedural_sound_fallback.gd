extends RefCounted
## Assets.sound() falls back to procedurally synthesized streams for missing sound assets.

const Assets = preload("res://scripts/client/assets.gd")
const ProceduralSounds = preload("res://scripts/client/procedural_sounds.gd")


func run(t) -> void:
	t.current = "name mapping"
	t.eq(str(ProceduralSounds.preset_for_sound_name("footstep_grass").get("preset", "")), "footstep", "footstep_grass -> footstep")
	t.eq(str((ProceduralSounds.preset_for_sound_name("footstep_grass")["args"] as Array)[0]), "grass", "surface suffix picks the variant")
	t.eq(str(ProceduralSounds.preset_for_sound_name("zombie_groan").get("preset", "")), "zombie_groan", "zombie groan")
	t.eq(str(ProceduralSounds.preset_for_sound_name("gunfire_shotgun").get("preset", "")), "gunshot", "gunfire is a gunshot, not fire")
	t.eq(str((ProceduralSounds.preset_for_sound_name("gunfire_shotgun")["args"] as Array)[0]), "shotgun", "caliber suffix")
	t.eq(str(ProceduralSounds.preset_for_sound_name("campfire").get("preset", "")), "fire_crackle", "fire")
	t.eq(str(ProceduralSounds.preset_for_sound_name("wind_strong").get("preset", "")), "wind", "wind")
	t.eq(str(ProceduralSounds.preset_for_sound_name("ui_click").get("preset", "")), "ui_click", "ui click")
	t.check(ProceduralSounds.preset_for_sound_name("coin").is_empty(), "unrelated names are not synthesized")

	t.current = "fallback stream"
	ProceduralSounds.clear_fallback_cache()
	var groan: AudioStream = ProceduralSounds.fallback_stream("zombie_groan_missing_asset")
	t.check(groan != null, "a missing zombie groan gets a procedural stream")
	if groan != null:
		t.near(groan.get_length(), 1.6, 0.05, "finite length equal to the preset duration")
	t.check(ProceduralSounds.fallback_stream("zombie_groan_missing_asset") == groan, "cached per name")
	t.eq(ProceduralSounds.fallback_cache_size(), 1, "one cache entry")
	t.check(ProceduralSounds.fallback_stream("coin_missing") == null, "unmapped name stays null")

	t.current = "Assets.sound"
	var real: AudioStream = Assets.sound("walking")
	t.check(real != null and not (real.resource_path.is_empty()), "imported assets still win over synthesis")
	var synth: AudioStream = Assets.sound("footstep_wood_test")
	t.check(synth != null, "missing footstep asset plays a synthesized stream instead of silence")
	t.check(Assets.sound("footstep_wood_test") == synth, "Assets caches the synthesized stream")
	t.check(Assets.sound("definitely_not_a_sound_xyz") == null, "unknown names without assets stay null")
