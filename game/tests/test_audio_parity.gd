extends RefCounted
## Audio parity helpers: surfaces, voice limiting, spatial filtering, ducking, mix and ambience.

const Surfaces = preload("res://scripts/client/audio_surfaces.gd")
const Voices = preload("res://scripts/client/audio_voices.gd")
const Variants = preload("res://scripts/client/audio_variants.gd")
const Spatial = preload("res://scripts/client/audio_spatial.gd")
const Ducking = preload("res://scripts/client/audio_ducking.gd")
const Mix = preload("res://scripts/client/audio_mix.gd")
const Ambient = preload("res://scripts/client/audio_ambient.gd")


func run(t) -> void:
	t.current = "surface footsteps"
	t.eq(Surfaces.surface_for(true, "forest", 5.0, 0.0), "stone", "underground is stone")
	t.eq(Surfaces.surface_for(false, "plains", -0.5, 0.0), "water", "below water level")
	t.eq(Surfaces.surface_for(false, "plains", 0.4, 0.0), "sand", "shoreline")
	t.eq(Surfaces.surface_for(false, "forest", 5.0, 0.0), "leaves", "forest")
	t.eq(Surfaces.surface_for(false, "spore_swamp", 5.0, 0.0), "mud", "swamp")
	t.eq(Surfaces.surface_for(false, "mountain", 20.0, 0.0), "stone", "mountain")
	t.eq(Surfaces.surface_for(false, "plains", 5.0, 0.0), "grass", "default grass")
	t.check(Surfaces.profile("sand")["db"] < Surfaces.profile("stone")["db"], "sand quieter than stone")
	t.eq(Surfaces.profile("nope"), Surfaces.PROFILES["grass"], "unknown falls back")
	t.check(Surfaces.speed_pitch(1.0, 8.0) > Surfaces.speed_pitch(1.0, 2.0), "faster steps pitch up")
	t.check(Surfaces.speed_pitch(1.0, 100.0) <= 1.35, "pitch clamped")

	t.current = "random variation"
	var lo := Voices.variation(0.0, 0.0)
	var hi := Voices.variation(1.0, 1.0)
	t.near(lo["pitch"], 0.92, 0.001, "min pitch")
	t.near(hi["pitch"], 1.08, 0.001, "max pitch")
	t.near(Voices.variation(0.5, 0.5)["db"], 0.0, 0.001, "centre has no change")
	t.near(hi["db"], 1.5, 0.001, "max volume jitter")

	t.current = "weighted audio variations without replacement"
	var weights := PackedFloat64Array([1.0, 2.0, 3.0])
	var variants = Variants.new(weights)
	var fallback = Variants.new(weights, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2601121
	for cycle in 12:
		var heard: Array[int] = []
		for step in 3:
			var unit: float = rng.randf()
			var picked: int = variants.choose(unit)
			t.eq(picked, fallback.choose(unit), "native/fallback weighted cycle parity")
			t.check(picked >= 0 and not heard.has(picked), "each clip plays once per cycle")
			heard.append(picked)
		t.eq(variants.get_played_count(), 3, "cycle exhausted")
	t.eq(variants.choose(-0.1), -1, "invalid roll rejected")
	t.eq(variants.get_played_count(), 3, "invalid roll preserves history")
	t.eq(variants.choose(0.0), fallback.choose(0.0), "new cycle parity")
	t.eq(variants.get_played_count(), 1, "new cycle restarts at one clip")
	variants.reset()
	t.eq(variants.choose(0.0), 0, "explicit reset starts at first clip")
	var sparse = Variants.new(PackedFloat64Array([0.0, 3.0, 0.0, 1.0]), false)
	t.eq(sparse.choose(0.0), 1, "zero weights are skipped")
	t.eq(sparse.choose(0.0), 3, "only remaining nonzero clip plays")
	t.eq(sparse.choose(0.0), 1, "exhaustion restarts the cycle")
	var malformed = Variants.new(PackedFloat64Array([1.0, -1.0]), false)
	t.eq(malformed.choose(0.5), -1, "invalid configuration rejected")

	t.current = "voice limiting"
	t.check(Voices.audibility(0.0, 50.0) < Voices.audibility(0.0, 2.0), "far voices are quieter")
	var voices: Array = []
	t.eq(Voices.victim(voices, "break", -5.0), Voices.ROOM, "empty has room")
	for i in Voices.MAX_VOICES:
		voices.append({"name": "s%d" % i, "audibility": -10.0 - i, "age": float(i)})
	t.eq(Voices.victim(voices, "new", -10.0), Voices.MAX_VOICES - 1, "full: quietest voice culled")
	t.eq(Voices.victim(voices, "new", -80.0), Voices.DROP_NEW, "full: weaker new voice dropped")
	var same: Array = []
	for i in Voices.SAME_SOUND_MAX:
		same.append({"name": "hit", "audibility": -10.0, "age": float(i)})
	t.eq(Voices.victim(same, "hit", -10.0), Voices.SAME_SOUND_MAX - 1, "same-sound cap culls the oldest of equals")
	t.eq(Voices.victim(same, "other", -10.0), Voices.ROOM, "other sound unaffected by cap")

	t.current = "occlusion and air absorption"
	var ridge := func(x: float, _z: float) -> float: return 10.0 if absf(x - 5.0) < 1.0 else 0.0
	var flat := func(_x: float, _z: float) -> float: return 0.0
	t.check(Spatial.terrain_blocked(Vector3(0, 1, 0), Vector3(10, 1, 0), ridge), "ridge blocks the line")
	t.check(not Spatial.terrain_blocked(Vector3(0, 1, 0), Vector3(10, 1, 0), flat), "flat ground is clear")
	t.check(Spatial.source_cutoff(60.0, false) < Spatial.source_cutoff(5.0, false), "distance dulls highs")
	t.check(Spatial.source_cutoff(30.0, false, 1.0) < Spatial.source_cutoff(30.0, false, 0.0), "rain absorbs more")
	t.check(Spatial.source_cutoff(5.0, true) <= Spatial.MUFFLED_CUTOFF, "occluded is muffled")
	t.check(Spatial.listener_cutoff(true, 0.0) < Spatial.listener_cutoff(false, 0.0), "underground muffles")
	t.check(Spatial.listener_cutoff(false, 1.0) < Spatial.listener_cutoff(false, 0.0), "storm dulls")
	var g := Spatial.glide(20000.0, 1000.0, 0.1)
	t.check(g < 20000.0 and g > 1000.0, "glide moves toward target")

	t.current = "ducking"
	t.eq(Ducking.depth_for("death"), -12.0, "death ducks deepest")
	t.eq(Ducking.depth_for("coin"), 0.0, "unknown does not duck")
	var d := Ducking.step(0.0, -12.0, 0.1)
	t.check(d < 0.0 and d >= -12.0, "dips toward target")
	t.near(Ducking.step(-12.0, -12.0, 1.0), -12.0, 0.001, "holds at target")
	t.check(Ducking.step(-12.0, 0.0, 0.5) > -12.0, "recovers")
	t.near(Ducking.step(-1.0, 0.0, 10.0), 0.0, 0.001, "never overshoots above zero")
	t.check(Ducking.ATTACK > Ducking.RELEASE, "fast attack, slow release")

	t.current = "bus layout and sliders"
	t.near(Mix.linear_to_db(1.0), 0.0, 0.001, "full is 0 dB")
	t.near(Mix.linear_to_db(0.5), -6.02, 0.02, "half is -6 dB")
	t.eq(Mix.linear_to_db(0.0), -80.0, "zero is silent")
	Mix.ensure_buses()
	Mix.ensure_buses()
	for bus in Mix.BUSES:
		t.check(AudioServer.get_bus_index(bus) != -1, "bus " + bus)
	var named := 0
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == "Music":
			named += 1
	t.eq(named, 1, "buses created once")
	var before: float = Mix.volumes["UI"]
	Mix.set_volume("UI", 0.5, false)
	t.near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("UI")), -6.02, 0.02, "slider sets bus")
	t.near(Mix.volumes["UI"], 0.5, 0.001, "stored")
	Mix.set_volume("UI", 9.0, false)
	t.near(Mix.volumes["UI"], 1.0, 0.001, "clamped to 1")
	Mix.set_volume("UI", before, false)
	var idx := Mix.ensure_lowpass("Music")
	t.check(idx >= 0, "low-pass added")
	t.eq(Mix.ensure_lowpass("Music"), idx, "low-pass added once")

	t.current = "ambience beds and weather loops"
	t.check(Ambient.bed("swamp", 1.0, false)["pitch"] < Ambient.bed("beach", 1.0, false)["pitch"], "beds differ per biome")
	t.check(Ambient.bed("plains", 0.0, false)["db"] < Ambient.bed("plains", 1.0, false)["db"], "night bed quieter")
	t.eq(Ambient.bed("plains", 1.0, true)["db"], -26.0, "underground bed")
	t.eq(Ambient.bed("unknown", 1.0, false), Ambient.bed("plains", 1.0, false), "unknown biome uses plains")
	t.eq(Ambient.rain_db(0.0, false), -80.0, "no rain when clear")
	t.check(Ambient.rain_db(1.0, false) > Ambient.rain_db(0.3, false), "heavier storm louder")
	t.check(Ambient.rain_db(1.0, true) < Ambient.rain_db(1.0, false), "roof muffles rain")
	t.eq(Ambient.wind_db(0.0, 0.0, false), -80.0, "no wind when calm")
	t.check(Ambient.wind_db(8.0, 0.0, false) > Ambient.wind_db(2.0, 0.0, false), "stronger wind louder")
	var noise := Ambient.noise_stream(0.1, 0.9, 3)
	t.eq(noise.data.size(), int(0.1 * Ambient.RATE) * 2, "noise length")
	t.eq(noise.loop_mode, AudioStreamWAV.LOOP_FORWARD, "noise loops")
	t.eq(Ambient.noise_stream(0.1, 0.9, 3).data, noise.data, "deterministic by seed")
