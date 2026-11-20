extends RefCounted
## Native temperature-sensitive sound flight time and a real bounded thunder
## queue shared by both offline and online storm VFX.
const Thunder = preload("res://scripts/client/storm_thunder.gd")
const Online = preload("res://scripts/client/online_main.gd")
const Solo = preload("res://scripts/client/client_main.gd")


func _height(_x: float, _z: float) -> float:
	return 0.0


func _bad_height(_x: float, _z: float) -> float:
	return NAN


func run(t) -> void:
	t.current = "speed of sound matches native and fallback engines"
	t.near(Thunder.propagation_delay(343.42, 20.0), 1.0, 0.0005,
		"343.42m lightning is heard about one second after the flash")
	t.near(Thunder.propagation_delay(0.0), 0.0, 0.00001,
		"lightning at listener needs no artificial delay")
	t.check(Thunder.propagation_delay(1000.0, -20.0) >
			Thunder.propagation_delay(1000.0, 35.0),
		"cold air conducts the audible thunder later than warm air")
	t.check(Thunder.propagation_delay(2400.0) > 6.9 and
			Thunder.propagation_delay(2400.0) < 7.1,
		"outer hearing limit gives a bounded seven-second delay")
	for invalid in [NAN, INF, -INF, -1.0, 2400.1]:
		t.eq(Thunder.propagation_delay(invalid), -1.0,
			"corrupt or out-of-range distances never create thunder")
	for temperature in [NAN, INF, -41.0, 61.0]:
		t.eq(Thunder.propagation_delay(100.0, temperature), -1.0,
			"corrupt temperature cannot create infinite delay")
	if ClassDB.class_exists("SoundPropagation"):
		var native: Object = ClassDB.instantiate("SoundPropagation")
		if native != null and native.has_method("travel_delay_seconds"):
			for temp in [-30.0, 0.0, 20.0, 50.0]:
				for meters in [0.0, 50.0, 343.42, 1000.0, 2400.0]:
					t.near(float(native.call("travel_delay_seconds", meters, temp)),
						meters / (331.3 + 0.606 * temp), 0.0005,
						"native engine time-of-flight agrees with the stock-Godot model")

	t.current = "one cached procedural non-looping 3D thunder waveform"
	var waveform: AudioStreamWAV = Thunder.thunder_wave()
	t.check(waveform != null and waveform.data.size() > 0,
		"a real thunder waveform is available without downloadable assets")
	t.eq(waveform.mix_rate, Thunder.SAMPLE_RATE,
		"sample rate is fixed and predictable")
	t.eq(waveform.data.size(),
		int(Thunder.SAMPLE_RATE * Thunder.SAMPLE_SECONDS) * 2,
		"only one bounded mono 16-bit PCM allocation")
	t.eq(waveform.loop_mode, AudioStreamWAV.LOOP_DISABLED,
		"lightning does not create a looping rumble")
	t.eq(Thunder.thunder_wave(), waveform,
		"consecutive strikes reuse exactly the same waveform allocation")
	t.eq(waveform.data.decode_s16(0), 0,
		"attack envelope starts at silence rather than an audio click")

	t.current = "only real server impact queues sound; storms are bounded"
	var sound := Thunder.new()
	var listener := Vector3(0.0, 1.5, 0.0)
	var real_event := {"type": "lightning_struck", "x": 343.42, "z": 0.0}
	t.check(not sound.on_strike({"type": "lightning_warning", "x": 0.0, "z": 0.0},
		listener, _height, false), "a lightning warning cannot generate thunder")
	t.check(not sound.on_strike(real_event, listener, _height, true),
		"an underground listener stays insulated from outdoor thunder")
	t.eq(sound.queued_count(), 0, "invalid events cannot accumulate")
	t.check(sound.on_strike(real_event, listener, _height, false),
		"real impact creates a delayed event in world space")
	t.eq(sound.queued_count(), 1, "exactly one audible event is scheduled")
	t.near(float(sound._pending[0]["remaining"]), 1.0, 0.0005,
		"listener distance fixes arrival time at impact")
	t.check(not sound.on_strike({"type": "lightning_struck", "x": NAN, "z": 0.0},
		listener, _height, false), "nonfinite server coordinates are rejected")
	t.check(not sound.on_strike(real_event, Vector3.INF, _height, false),
		"invalid listener cannot create sound")
	t.check(not sound.on_strike(real_event, listener, _bad_height, false),
		"invalid terrain altitude cannot create sound")
	t.check(not sound.on_strike({"type": "lightning_struck", "x": 3000.0, "z": 0.0},
		listener, _height, false), "unrelated distant storms do not fill queues")
	sound._process(0.2)
	t.eq(sound.queued_count(), 1, "first 0.2 seconds remain silent at 343m")
	t.check(float(sound._pending[0]["remaining"]) > 0.79,
		"pending thunder counts down without creating an audio player")

	# Four nearest-to-arrive strikes win, not an unbounded allocation.
	for i in 6:
		sound.on_strike({"type": "lightning_struck", "x": 500.0 + float(i) * 120.0,
			"z": 0.0}, listener, _height, false)
	t.check(sound.queued_count() <= Thunder.MAX_PENDING,
		"thunder queue cannot grow beyond four concurrent strikes")
	var soon := {"type": "lightning_struck", "x": 60.0, "z": 0.0}
	t.check(sound.on_strike(soon, listener, _height, false),
		"nearby thunder takes precedence over a distant queued strike")
	t.eq(sound.queued_count(), Thunder.MAX_PENDING,
		"nearest sound replaces an existing queued entry")
	sound.free()

	t.current = "both client modes consume the actual server strike event"
	var online_source: String = (Online as Script).source_code
	var solo_source: String = (Solo as Script).source_code
	t.check(online_source.contains("_storm_thunder.on_strike(event, here,"),
		"network events schedule real sound without a second gameplay event")
	t.check(solo_source.contains("_storm_thunder.on_strike(game_event, survivor.position,"),
		"local authoritative simulation uses the same delayed thunder")
	t.check(online_source.contains('str(event.get("type", "")) == "lightning_struck"'),
		"network client never turns a warning into thunder")
	t.check(solo_source.contains('str(game_event.get("type", "")) == "lightning_struck"'),
		"solo client never turns a warning into thunder")
	t.check(online_source.contains("UiSettings.flash_scale() > 0.0"),
		"flash accessibility stays independent of thunder sound")
