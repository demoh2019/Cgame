extends RefCounted
## Timed Unreal Control Bus Mix-style activity: native and portable parity,
## automatic expiry and the actual combat sound-node integration.
const Snapshots = preload("res://scripts/client/audio_mix_snapshots.gd")
const AudioScene = preload("res://scripts/client/audio.gd")


func run(t) -> void:
	t.current = "timed audio snapshot exact attack/hold/release boundary"
	var state: Dictionary = {}
	var focus := {"Ambience": -3.0, "Music": -1.0}
	t.check(Snapshots.activate_timed_mix(state, "Combat.Focus", focus, 1.0, 2.0, 1.0),
		"bounded timed profile can be activated")
	t.near(Snapshots.mix_remaining_seconds(state, "Combat.Focus"), 2.0, 0.00001,
		"new profile starts its hold counter")
	t.near(Snapshots.bus_offset_db(state, "Ambience"), 0.0, 0.00001,
		"attack begins at neutral level")
	Snapshots.tick(state, 0.5)
	t.near(Snapshots.mix_weight(state, "Combat.Focus"), 0.5, 0.00001,
		"attack advances at half weight")
	t.near(Snapshots.mix_remaining_seconds(state, "Combat.Focus"), 1.5, 0.00001,
		"hold counter decreases independently of fade")
	Snapshots.tick(state, 1.0)
	t.near(Snapshots.mix_weight(state, "Combat.Focus"), 1.0, 0.00001,
		"attack reaches authored attenuation")
	Snapshots.tick(state, 1.0)
	t.near(Snapshots.mix_weight(state, "Combat.Focus"), 0.5, 0.00001,
		"expiry within a large frame uses only its post-hold release time")
	t.near(Snapshots.mix_remaining_seconds(state, "Combat.Focus"), -1.0, 0.00001,
		"expired timers no longer count down")
	Snapshots.tick(state, 0.5)
	t.check(state.is_empty(), "the expired profile is removed when release reaches zero")

	t.current = "retrigger, layering and atomic input validation"
	var weather := {"Ambience": -1.0}
	t.check(Snapshots.activate_mix(state, "Weather.Storm", weather, 0.0),
		"independent storm mix remains manually controlled")
	t.check(Snapshots.activate_timed_mix(state, "Combat.Focus", focus, 0.25, 1.0, 2.0),
		"temporary battle stage joins independent storm stage")
	Snapshots.tick(state, 1.5)
	t.near(Snapshots.mix_weight(state, "Combat.Focus"), 0.75, 0.00001,
		"combat mix fades automatically after its hold")
	t.check(Snapshots.activate_timed_mix(state, "Combat.Focus", focus, 0.25, 1.0, 2.0),
		"new hit renews timer without re-creating source")
	t.eq(state.size(), 2, "retrigger adds no duplicate mix")
	t.near(Snapshots.mix_weight(state, "Combat.Focus"), 0.75, 0.00001,
		"retrigger preserves current mix strength")
	for bad_hold in [-1.0, 121.0, NAN, INF]:
		t.check(not Snapshots.activate_timed_mix(state, "Combat.Focus", focus,
			0.2, bad_hold, 1.0), "invalid hold leaves the live timed mix alone")
	for bad_release in [-1.0, 16.0, NAN, INF]:
		t.check(not Snapshots.activate_timed_mix(state, "Combat.Focus", focus,
			0.2, 9.0, bad_release), "invalid release leaves active state unchanged")
	t.near(Snapshots.mix_remaining_seconds(state, "Combat.Focus"), 1.0, 0.00001,
		"bad updates cannot rearm or change the active timer")
	t.check(Snapshots.deactivate_mix(state, "Combat.Focus", 0.0),
		"manual release cancels timer and removes combat only")
	t.near(Snapshots.bus_offset_db(state, "Ambience"), -1.0, 0.00001,
		"storm environment attenuation remains independent")
	t.check(Snapshots.activate_timed_mix(state, "Combat.Focus", focus, 0.0, 0.0, 0.0),
		"zero hold and release are valid for an immediate one-shot")
	Snapshots.tick(state, 0.016)
	t.check(not state.has("Combat.Focus"),
		"zero-duration one-shot cannot leave a stuck audio mix")

	t.current = "actual Albion combat events control a temporary sound focus stage"
	var scene = AudioScene.new()
	scene.mark_combat()
	t.near(scene._combat_left, AudioScene.COMBAT_SECONDS, 0.00001,
		"real server-driven combat cue refreshes combat music lifetime")
	t.check(scene._script_mix_snapshots.has("Combat.Focus"),
		"the actual game sound node activates the combat bus profile")
	scene._update_environment_mix_snapshots(false, "plains", 0.0, 0.15)
	t.near(scene._snapshot_bus_db("Ambience"), -3.0, 0.00001,
		"combat briefly reduces backdrop noise to reveal attack effects")
	t.near(scene._snapshot_bus_db("Music"), -1.0, 0.00001,
		"battle foreground mix is independent of the user's music slider")
	scene.mark_combat()
	t.eq(scene._script_mix_snapshots.size(), 1,
		"additional combat events only refresh the existing profile")
	scene._update_environment_mix_snapshots(false, "plains", 0.0, 9.0)
	t.near(scene._snapshot_bus_db("Ambience"), -3.0, 0.00001,
		"the combat focus lasts exactly the configured combat hold")
	scene._update_environment_mix_snapshots(false, "plains", 0.0, 1.5)
	t.near(scene._snapshot_bus_db("Ambience"), 0.0, 0.00001,
		"timed combat mix automatically releases without extra events")
	scene.free()

	t.current = "native timed Control Bus Mix and stock Godot fallback parity"
	if ClassDB.class_exists("AudioMixSnapshotController"):
		var native: Object = ClassDB.instantiate("AudioMixSnapshotController")
		if native != null and native.has_method("activate_timed_mix"):
			# Exercise the actual game's C++ path, not only the C++ API in isolation.
			var native_scene = AudioScene.new()
			native_scene._native_mix_snapshots = native
			native_scene.mark_combat()
			native_scene._update_environment_mix_snapshots(false, "plains", 0.0, 0.15)
			t.near(native_scene._snapshot_bus_db("Ambience"), -3.0, 0.00001,
				"real Albion sound node consumes native timed combat snapshots")
			t.eq(int(native.call("get_mix_count")), 1,
				"the actual combat event registers just one native mix")
			native.call("clear")
			native_scene.free()
			var portable: Dictionary = {}
			t.check(Snapshots.activate_timed_mix(portable, "Combat.Focus", focus,
				0.25, 1.0, 2.0), "portable profile is accepted")
			t.check(bool(native.call("activate_timed_mix", &"Combat.Focus", focus,
				0.25, 1.0, 2.0)), "native timed stage is accepted")
			for delta in [0.10, 0.35, 0.70]:
				Snapshots.tick(portable, delta)
				native.call("tick", delta)
				t.near(float(native.call("get_bus_offset_db", &"Ambience")),
					Snapshots.bus_offset_db(portable, "Ambience"), 0.00001,
					"both engines agree across the timed expiration boundary")
				t.near(float(native.call("get_mix_remaining_seconds", &"Combat.Focus")),
					Snapshots.mix_remaining_seconds(portable, "Combat.Focus"),
					0.00001, "native timer matches the portable timer")
			t.check(bool(native.call("activate_timed_mix", &"Combat.Focus", focus,
				0.25, 1.0, 2.0)), "native retrigger refreshes hold")
			t.check(Snapshots.activate_timed_mix(portable, "Combat.Focus", focus,
				0.25, 1.0, 2.0), "portable retrigger refreshes hold")
			for delta in [0.125, 0.875, 0.25, 1.8, 2.0]:
				Snapshots.tick(portable, delta)
				native.call("tick", delta)
				for bus in ["Ambience", "Music"]:
					t.near(float(native.call("get_bus_offset_db", StringName(bus))),
						Snapshots.bus_offset_db(portable, bus), 0.00001,
						"native/portable mix offsets remain identical after retrigger")
				t.eq(int(native.call("get_mix_count")), portable.size(),
					"native and script expire exactly the same temporary stages")
		else:
			t.check(true, "old Cgame keeps the scripted timed mix path")
	else:
		t.check(true, "stock Godot keeps all timed audio mixes in script")
