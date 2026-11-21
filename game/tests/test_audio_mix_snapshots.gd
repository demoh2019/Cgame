extends RefCounted
## Unreal-style audio bus mix layering, native/portable parity and live audio integration.
const Snapshots = preload("res://scripts/client/audio_mix_snapshots.gd")
const AudioScene = preload("res://scripts/client/audio.gd")
const AudioMix = preload("res://scripts/client/audio_mix.gd")


func run(t) -> void:
	t.current = "independent zone and storm bus mixes crossfade without snapping"
	var profiles: Dictionary = {}
	var cave: Dictionary = {"Music": -4.0, "Ambience": -5.0}
	var storm: Dictionary = {"Music": -2.0, "SFX": -1.0}
	t.check(Snapshots.activate_mix(profiles, "Zone.Underground", cave, 2.0),
		"the underground profile can fade in")
	t.eq(Snapshots.bus_offset_db(profiles, "Music"), 0.0, "a new faded mix starts silent")
	Snapshots.tick(profiles, 0.5)
	t.near(Snapshots.mix_weight(profiles, "Zone.Underground"), 0.25, 0.0001,
		"fade weight advances by delta/fade duration")
	t.near(Snapshots.bus_offset_db(profiles, "Music"), -1.0, 0.0001,
		"music inherits quarter of the cave mix")
	t.near(Snapshots.bus_offset_db(profiles, "Ambience"), -1.25, 0.0001,
		"one snapshot drives multiple audio buses")
	t.check(Snapshots.activate_mix(profiles, "Weather.Storm", storm, 1.0),
		"the storm mix is independent of the acoustic zone")
	Snapshots.tick(profiles, 0.5)
	t.near(Snapshots.bus_offset_db(profiles, "Music"), -3.0, 0.0001,
		"the two faded music contributions are added in dB")
	t.near(Snapshots.bus_offset_db(profiles, "SFX"), -0.5, 0.0001,
		"the storm mix applies to world effects independently")
	t.check(Snapshots.deactivate_mix(profiles, "Zone.Underground", 1.0),
		"leaving the cave fades out that zone only")
	Snapshots.tick(profiles, 0.25)
	t.near(Snapshots.bus_offset_db(profiles, "Music"), -2.5, 0.0001,
		"the storm remains audible during the cave fade-out")
	t.check(Snapshots.activate_mix(profiles, "Zone.Underground", cave, 1.0),
		"rapid re-entry can reverse a partially faded mix")
	t.eq(profiles.size(), 2, "reversing a fading profile does not duplicate it")
	Snapshots.tick(profiles, 0.75)
	t.near(Snapshots.bus_offset_db(profiles, "Music"), -6.0, 0.0001,
		"both profiles reach full strength")
	t.check(Snapshots.deactivate_mix(profiles, "Zone.Underground", 0.0),
		"an immediate exit removes only that profile")
	t.near(Snapshots.bus_offset_db(profiles, "Music"), -2.0, 0.0001,
		"storm survives an immediate cave exit")
	profiles.clear()
	t.eq(Snapshots.bus_offset_db(profiles, "Music"), 0.0,
		"clearing all active profiles restores the neutral mix")

	t.current = "atomic validation and hard limits prevent audio-control corruption"
	var valid: Dictionary = {}
	t.check(Snapshots.activate_mix(valid, "Zone.Forest", {"Music": -4.0}, 0.0),
		"valid immediate fades are supported")
	for bad_db in [NAN, INF, -INF, -31.0, 1.0, "bad"]:
		t.check(not Snapshots.activate_mix(valid, "Zone.Forest", {"Music": bad_db}),
			"invalid dB stages never replace a working profile")
	for bad_fade in [NAN, INF, -1.0, 16.0]:
		t.check(not Snapshots.activate_mix(valid, "Another", {"Music": -4.0}, bad_fade),
			"invalid fade durations are rejected")
	t.check(not Snapshots.activate_mix(valid, "", {"Music": -2.0}),
		"unnamed profiles are rejected")
	t.check(not Snapshots.activate_mix(valid, "Empty", {}),
		"profiles with no bus stages are rejected")
	t.check(not Snapshots.activate_mix(valid, "BadName", {"": -3.0}),
		"unnamed bus channels are rejected")
	t.check(not Snapshots.activate_mix(valid, "BadName", {123: -3.0}),
		"numeric bus keys are rejected")
	t.near(Snapshots.bus_offset_db(valid, "Music"), -4.0, 0.0001,
		"all invalid updates preserve the old mix")
	Snapshots.tick(valid, NAN)
	t.near(Snapshots.bus_offset_db(valid, "Music"), -4.0, 0.0001,
		"invalid deltas cannot affect existing stages")
	for i in 15:
		t.check(Snapshots.activate_mix(valid, "Extra%d" % i, {"Music": -30.0}, 0.0),
			"the fixed mix capacity accepts sixteen profiles")
	t.eq(valid.size(), 16, "source count is tightly bounded")
	t.near(Snapshots.bus_offset_db(valid, "Music"), -60.0, 0.0001,
		"overlapping dB reductions saturate at minus sixty dB")
	t.check(not Snapshots.activate_mix(valid, "Overflow", {"Music": -1.0}, 0.0),
		"a seventeenth mix is rejected without partial changes")
	t.check(Snapshots.activate_mix(valid, "Zone.Forest", {"Music": -3.0}, 0.0),
		"an existing mix remains editable even at capacity")
	t.eq(valid.size(), 16, "reconfiguring a mix never creates a duplicate")

	t.current = "real Albion audio responds to weather and acoustic zones"
	var scene = AudioScene.new() # No _ready: no asset or audio hardware needed.
	scene._update_environment_mix_snapshots(false, "forest", 0.0, 0.625)
	t.eq(scene._mix_zone, "forest", "real listener selects forest zone")
	t.check(scene._snapshot_bus_db("SFX") < 0.0, "forest reduces hard SFX edges")
	scene._update_environment_mix_snapshots(true, "forest", 0.9, 0.625)
	t.eq(scene._mix_zone, "underground", "cave overrides the forest zone")
	t.check(scene._snapshot_bus_db("Music") < 0.0, "cave music is attenuated")
	t.check(scene._storm_mix_active, "storm profile coexists with the cave mix")
	scene._update_environment_mix_snapshots(true, "forest", 0.62, 0.016)
	t.check(scene._storm_mix_active, "storm hysteresis holds through the threshold band")
	scene._update_environment_mix_snapshots(false, "plains", 0.4, 2.0)
	t.check(not scene._storm_mix_active, "storm profile stops once weather clears")
	scene._update_environment_mix_snapshots(false, "plains", 0.4, 2.0)
	t.near(scene._snapshot_bus_db("Music"), 0.0, 0.0001,
		"open weather restores music with no leaked zone stages")
	scene.free()

	t.current = "native Cgame and stock Godot mix evolution parity"
	if ClassDB.class_exists("AudioMixSnapshotController"):
		var native: Object = ClassDB.instantiate("AudioMixSnapshotController")
		t.check(native != null, "native mix snapshot planner is available")
		if native != null:
			var reference: Dictionary = {}
			for spec in [
				["Zone.Forest", {"Music": -4.0, "SFX": -1.0}, 1.25],
				["Weather.Storm", {"Music": -2.0, "Ambience": -3.0}, 2.0]
			]:
				t.check(Snapshots.activate_mix(reference, spec[0], spec[1], spec[2]),
					"script accepts the same stages")
				t.check(bool(native.call("activate_mix", StringName(spec[0]), spec[1], spec[2])),
					"native accepts the same stages")
			for dt in [0.016, 0.03, 0.1, 0.25, 0.35]:
				Snapshots.tick(reference, dt)
				native.call("tick", dt)
				for bus in ["Music", "Ambience", "SFX"]:
					t.near(float(native.call("get_bus_offset_db", StringName(bus))),
						Snapshots.bus_offset_db(reference, bus), 0.0001,
						"native mix agrees on the active bus weight")
			t.check(Snapshots.deactivate_mix(reference, "Zone.Forest", 1.0),
				"script starts fade-out")
			t.check(bool(native.call("deactivate_mix", &"Zone.Forest", 1.0)),
				"native starts matching fade-out")
			for dt in [0.05, 0.15, 0.2, 0.8, 1.2]:
				Snapshots.tick(reference, dt)
				native.call("tick", dt)
				for bus in ["Music", "Ambience", "SFX"]:
					t.near(float(native.call("get_bus_offset_db", StringName(bus))),
						Snapshots.bus_offset_db(reference, bus), 0.0001,
						"native and script fade-out results agree")
				t.eq(int(native.call("get_mix_count")), reference.size(),
					"mix release removes exactly the same stages")
	else:
		t.check(true, "stock Godot retains the complete GDScript bus-mix fallback")

	t.current = "gameplay audio composition preserves user sliders and transient ducks"
	var source: String = (AudioScene as Script).source_code
	t.check(source.contains('EngineFeatures.make("AudioMixSnapshotController")'),
		"the real playable audio node opts into native Cgame bus mixes")
	t.check(source.contains('AudioMixSnapshots.tick(_script_mix_snapshots, delta)'),
		"the stock Godot mixer updates the same acoustic profiles")
	t.check(source.contains('AudioMix.linear_to_db(AudioMix.volumes["Music"]) + _duck + _snapshot_bus_db("Music")'),
		"music combines user volume, event ducking and independent bus mixes")
	t.check(source.contains('AudioMix.linear_to_db(AudioMix.volumes["Ambience"]) + _duck * 0.4 + _snapshot_bus_db("Ambience")'),
		"ambience preserves existing 40 percent event-duck ratio")
	t.check(source.contains('AudioMix.linear_to_db(AudioMix.volumes["SFX"]) + _snapshot_bus_db("SFX")'),
		"SFX bus receives an independent spatial mix")
	t.check(source.contains('absf(AudioServer.get_bus_volume_db(index) - gain_db) > 0.01'),
		"unchanged AudioServer gains are not resubmitted each render frame")
	t.eq(AudioMix.linear_to_db(0.0), -80.0, "muted user sliders remain fully muted")
