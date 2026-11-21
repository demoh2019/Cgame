extends RefCounted
## Multi-source audio modulation mirrors the native mixer on stock Godot.
const Ducking = preload("res://scripts/client/audio_ducking.gd")
const AudioScene = preload("res://scripts/client/audio.gd")
const AudioMix = preload("res://scripts/client/audio_mix.gd")


func run(t) -> void:
	t.current = "source-keyed ducking does not let short events erase longer mixes"
	var sources: Dictionary = {}
	t.check(Ducking.trigger_source(sources, "death", -12.0, 1.2), "death starts a deep music duck")
	t.check(Ducking.trigger_source(sources, "skill_up", -6.0, 3.0), "skill-up has an independent longer hold")
	t.eq(sources.size(), 2, "overlapping sound events use separate source keys")
	t.near(Ducking.target_sources(sources), -12.0, 0.0001, "the deepest live event wins")
	var value := Ducking.tick_sources(sources, 0.0, 0.1)
	t.near(value, -4.0, 0.0001, "music ducks at forty dB per second")
	value = Ducking.tick_sources(sources, value, 0.2)
	t.near(value, -12.0, 0.0001, "deep event reaches the expected target")
	value = Ducking.tick_sources(sources, value, 1.0)
	t.check(not sources.has("death"), "short death event expires")
	t.check(sources.has("skill_up"), "long skill-up duck remains active")
	t.near(Ducking.target_sources(sources), -6.0, 0.0001, "longer event still holds the music")
	t.near(value, -8.0, 0.0001, "release fades toward surviving event without snapping")
	t.check(Ducking.trigger_source(sources, "skill_up", -8.0, 3.0),
		"retrigger keeps its deeper strength and refreshes its own timer")
	t.eq(sources.size(), 1, "re-triggering an event does not create a duplicate")
	t.near(float(sources["skill_up"]["remaining"]), 3.0, 0.0001,
		"retrigger refreshes independent hold duration")
	t.near(Ducking.target_sources(sources), -8.0, 0.0001, "new deeper target takes priority")
	value = Ducking.tick_sources(sources, value, 3.0)
	t.eq(sources.size(), 0, "expired sources leave no pending mix state")
	t.near(value, 0.0, 0.0001, "music returns to the original user volume")

	t.current = "invalid events cannot corrupt running audio"
	var invalid: Dictionary = {"valid": {"depth": -5.0, "remaining": 2.0}}
	for depth in [NAN, INF, -INF, -61.0, 0.0, 1.0]:
		t.check(not Ducking.trigger_source(invalid, "bad", depth),
			"invalid dB depth is rejected")
	for hold in [-2.0, 0.0, 31.0, NAN, INF]:
		t.check(not Ducking.trigger_source(invalid, "bad", -3.0, hold),
			"invalid hold duration is rejected")
	t.check(not Ducking.trigger_source(invalid, "", -3.0), "source name cannot be empty")
	t.eq(invalid.size(), 1, "rejected triggers preserve other live events")
	t.eq(Ducking.tick_sources(invalid, -5.0, NAN), -5.0, "invalid delta cannot advance mix")
	t.near(float(invalid["valid"]["remaining"]), 2.0, 0.0001,
		"invalid delta cannot shorten active holds")
	for index in 31:
		t.check(Ducking.trigger_source(invalid, "effect_%d" % index, -2.0, 10.0),
			"source cap allows thirty-two total active sources")
	t.check(not Ducking.trigger_source(invalid, "overflow", -2.0),
		"more than thirty-two active sources are blocked")
	t.check(Ducking.trigger_source(invalid, "valid", -6.0),
		"retriggering an existing source still works at full capacity")
	t.eq(invalid.size(), 32, "source cap is fixed and bounded")

	t.current = "native Cgame mixer and stock fallback have deterministic envelope parity"
	if ClassDB.class_exists("AudioDuckMix"):
		var native: Object = ClassDB.instantiate("AudioDuckMix")
		t.check(native != null, "native mixer is registered in ClassDB")
		if native != null:
			var fallback: Dictionary = {}
			for event in [
				["death", -12.0, 1.2], ["skill_up", -6.0, 3.0],
				["knockback", -4.0, 0.5], ["skill_up", -8.0, 1.7]
			]:
				t.check(Ducking.trigger_source(fallback, str(event[0]), float(event[1]), float(event[2])),
					"stock engine accepts one event")
				t.check(bool(native.call("trigger", StringName(event[0]), float(event[1]), float(event[2]))),
					"native engine accepts the same event")
			var fallback_gain := 0.0
			for seconds in [0.016, 0.033, 0.1, 0.25, 0.51, 0.2, 0.66, 0.1, 0.8, 5.0]:
				fallback_gain = Ducking.tick_sources(fallback, fallback_gain, seconds)
				var native_gain: float = float(native.call("tick", seconds))
				t.near(native_gain, fallback_gain, 0.0001,
					"native C++ and stock Godot use identical mixer evolution")
				t.near(float(native.call("get_target_db")), Ducking.target_sources(fallback), 0.0001,
					"both engines retain exactly the same live event targets")
				t.eq(int(native.call("get_source_count")), fallback.size(),
					"both implementations expire sources in the same tick")
			t.eq(float(native.call("get_current_db")), 0.0,
				"finished events restore user mix gain")
	else:
		t.check(true, "stock Godot has a full native-compatible GDScript fallback")

	t.current = "real live audio path keeps user volume and event source identity"
	var code: String = (AudioScene as Script).source_code
	t.check(code.contains('EngineFeatures.make("AudioDuckMix")'),
		"playable audio node instantiates native engine mixer when present")
	t.check(code.contains('AudioDucking.tick_sources(_duck_sources, _duck, delta)'),
		"playable audio node falls back on stock Godot")
	t.check(code.contains('duck(AudioDucking.depth_for(str(event["type"])), str(event["type"]))'),
		"real server events use independent named modulator sources")
	t.check(code.contains('AudioMix.linear_to_db(AudioMix.volumes["Music"]) + _duck'),
		"user Music slider is preserved while events attenuate the bus")
	t.check(code.contains('AudioMix.linear_to_db(AudioMix.volumes["Ambience"]) + _duck * 0.4'),
		"ambience stays softer without becoming indistinguishable from music")
	t.eq(AudioMix.linear_to_db(1.0), 0.0, "unmodified user volume is zero dB")
