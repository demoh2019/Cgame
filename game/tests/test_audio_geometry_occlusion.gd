extends RefCounted
## Native per-source wall obstruction + bounded world raycast with stock fallback.
const Spatial = preload("res://scripts/client/audio_spatial.gd")
const AudioScene = preload("res://scripts/client/audio.gd")


func run(t) -> void:
	t.current = "geometry obstruction is an independently controlled sound filter"
	var original: float = 9000.0
	t.near(Spatial.obstruction_cutoff(original, 0.0), original, 0.0001,
		"unobstructed high frequencies are unchanged")
	t.near(Spatial.obstruction_cutoff(original, 1.0), 1400.0, 0.01,
		"a solid wall filters direct high frequencies")
	var medium: float = Spatial.obstruction_cutoff(original, 0.5)
	t.check(medium > 1400.0 and medium < original,
		"moving behind a doorway produces an intermediate low-pass")
	t.near(Spatial.obstruction_cutoff(900.0, 1.0), 900.0, 0.01,
		"the occlusion filter never brightens already muffled terrain audio")
	t.near(Spatial.obstruction_db(0.0), 0.0, 0.0001,
		"clear path does not alter the base voice volume")
	t.near(Spatial.obstruction_db(1.0), -8.0, 0.0001,
		"solid wall attenuates the sound source by a bounded 8 dB")
	t.near(Spatial.obstruction_db(0.5), -4.0, 0.0001,
		"partial obstruction blends the same 8 dB effect")
	for bad in [NAN, INF, -INF]:
		t.eq(Spatial.obstruction_cutoff(5000.0, bad), 5000.0,
			"invalid geometry samples cannot corrupt the filter")
		t.eq(Spatial.obstruction_db(bad), 0.0,
			"invalid obstruction amounts cannot change volume")

	t.current = "native AudioStreamPlayer3D uses source-local obstruction"
	var player := AudioStreamPlayer3D.new()
	t.check(player != null, "a 3D sound player can be created")
	if player.has_method("set_obstruction_amount"):
		t.near(float(player.call("get_obstruction_amount")), 0.0, 0.0001,
			"new native player starts with fully open audio")
		player.call("set_obstruction_amount", 0.6)
		t.near(float(player.call("get_obstruction_amount")), 0.6, 0.0001,
			"native mixer receives source obstruction independently")
		player.call("set_obstruction_amount", 2.0)
		t.near(float(player.call("get_obstruction_amount")), 1.0, 0.0001,
			"obstruction is clamped before reaching the audio mixer")
		player.call("set_obstruction_amount", -1.0)
		t.near(float(player.call("get_obstruction_amount")), 0.0, 0.0001,
			"the live voice can recover when a door opens")
	else:
		t.check(Spatial.obstruction_cutoff(5000.0, 0.8) < 5000.0,
			"stock Godot fallback performs geometric filtering")
	player.free()

	t.current = "live soundscape uses actual world collision with bounded queries"
	var source: String = (AudioScene as Script).source_code
	t.check(source.contains("func _physics_process(delta: float)"),
		"physics queries never run in the render or audio mixer thread")
	t.check(source.contains("OBSTRUCTION_RAYS_PER_TICK := 3"),
		"no more than three new wall checks occur per physics frame")
	t.check(source.contains("OBSTRUCTION_RECHECK_SECONDS := 0.25"),
		"long sounds refresh their geometry only on a coarse interval")
	t.check(source.contains("state.intersect_ray(ray)"),
		"physical barricades and walls block the direct sound path")
	t.check(source.contains('record["terrain_blocked"]'),
		"existing heightfield terrain obstruction remains active")
	t.check(source.contains('player.call("set_obstruction_amount", amount)'),
		"native path modifies individual 3D audio voices")
	t.check(source.contains('AudioSpatial.obstruction_cutoff(base_cutoff, amount)'),
		"stock Godot keeps per-source filtering when running without the fork")
	t.check(source.contains('AudioSpatial.obstruction_db(amount)'),
		"stock Godot keeps per-source amplitude attenuation")
	t.check(source.contains("move_toward(old_amount, target, delta * 6.0)"),
		"crossing a doorway changes occlusion smoothly without audio clicks")
	t.check(not source.contains("AudioServer.set_bus_volume_db(_sfx_bus,"),
		"world obstruction never mutes the entire SFX bus")
	t.current = "stable first buffer, fresh terrain LOS and voice priority"
	t.check(source.contains("AudioSpatial.source_cutoff(distance, false, _humidity)"),
		"initial air absorption is unblocked so occlusion is applied exactly once")
	t.check(source.contains('"original_cutoff": player.attenuation_filter_cutoff_hz'),
		"stock fallback stores the same unblocked source cutoff")
	t.check(source.contains("record[\"terrain_blocked\"] = terrain_blocked"),
		"moving listener terrain occlusion recomputes within ray budget")
	t.check(source.contains("listener_eye, source_eye, _ground"),
		"wall and terrain obstruction share the same listener/source line")
	t.check(source.contains("OBSTRUCTION_RAYS_PER_TICK := 3") and
		source.contains("rays += 1"),
		"terrain rechecks reuse existing capped physics ray budget")
	t.check(source.contains('"base_audibility": loudness') and
		source.contains('record["audibility"] = float(record.get("base_audibility"'),
		"blocked sounds lose voice priority instead of taking clear combat voices")
	t.near(Spatial.obstruction_db(1.0), Spatial.OCCLUDED_GAIN_DB, 0.0001,
		"native and stock fallback share one gain constant")
	t.near(Spatial.obstruction_db(0.5), Spatial.OCCLUDED_GAIN_DB * 0.5, 0.0001,
		"partial obstruction adjusts priority and volume consistently")
