extends RefCounted
## Native/GDScript audio voice admission, tested without AudioServer playback.
const Voices = preload("res://scripts/client/audio_voices.gd")
const AudioScript = preload("res://scripts/client/audio.gd")


func run(t) -> void:
	t.current = "combat sound outranks quieter environmental voice"
	t.eq(Voices.priority_for("enemy_destroy"), 3, "infected kill has critical priority")
	t.eq(Voices.priority_for("blaster"), 2, "weapon fire is protected")
	t.eq(Voices.priority_for("coin"), 1, "pickup foley is lower priority")
	t.eq(Voices.priority_for("unknown"), 0, "unknown sounds are cosmetic")
	var active: Array = [
		{"name": "enemy_destroy", "audibility": -75.0, "age": 2.0, "priority": 3},
		{"name": "wind", "audibility": -10.0, "age": 6.0, "priority": 0},
		{"name": "wind", "audibility": -6.0, "age": 1.0, "priority": 0}
	]
	t.eq(Voices.prioritized_victim(active, "blaster", -60.0, 2, 3, 2),
		1, "important combat event evicts cosmetic voice, not quieter critical event")
	t.eq(Voices.prioritized_victim(active, "wind", -90.0, 0, 3, 2),
		Voices.DROP_NEW, "weak ambient sound cannot steal already full named cap")
	t.eq(Voices.prioritized_victim(active, "boss", -90.0, 0, 3, 2),
		Voices.DROP_NEW, "full voice pool protects louder sounds")
	t.eq(Voices.prioritized_victim([], "hit", -10.0, 2),
		Voices.ROOM, "empty pool does not evict")

	t.current = "legacy priority-zero policy is unchanged"
	var rng := RandomNumberGenerator.new()
	rng.seed = 332112
	for trial in 100:
		var voices: Array = []
		for j in rng.randi_range(0, 24):
			voices.append({"name": "s%d" % rng.randi_range(0, 6),
				"audibility": rng.randf_range(-80.0, 5.0),
				"age": rng.randf_range(0.0, 9.0), "priority": 0})
		var name: String = "s%d" % rng.randi_range(0, 6)
		var volume: float = rng.randf_range(-80.0, 5.0)
		t.eq(Voices.prioritized_victim(voices, name, volume, 0),
			Voices.victim(voices, name, volume),
			"all priority-zero voices preserve original behavior trial %d" % trial)

	t.current = "invalid audio records fail closed"
	t.eq(Voices.prioritized_victim(active, "x", NAN, 2),
		Voices.DROP_NEW, "NaN event loudness rejected")
	t.eq(Voices.prioritized_victim(active, "x", -10.0, 4),
		Voices.DROP_NEW, "invalid new priority rejected")
	t.eq(Voices.prioritized_victim([{"name": "x", "audibility": INF, "age": 1.0}],
		"x", -10.0, 1), Voices.DROP_NEW, "invalid existing volume rejects new")
	t.eq(Voices.prioritized_victim(active, "x", -10.0, 1, 0, 2),
		Voices.DROP_NEW, "zero max voices rejected")

	t.current = "native Cgame planner matches stock Godot fallback"
	var native: Object = null
	if ClassDB.class_exists("AudioVoiceAdmissionPlanner"):
		native = ClassDB.instantiate("AudioVoiceAdmissionPlanner")
		t.check(native != null and native.has_method("select_victim"),
			"native engine admission class is registered")
		if native != null:
			rng.seed = 78541
			for trial in 300:
				var current: Array = []
				for i in rng.randi_range(0, 24):
					current.append({"name": "fx%d" % rng.randi_range(0, 7),
						"audibility": rng.randf_range(-90.0, 5.0),
						"age": rng.randf_range(0.0, 30.0),
						"priority": rng.randi_range(0, 3)})
				var candidate: String = "fx%d" % rng.randi_range(0, 7)
				var db: float = rng.randf_range(-90.0, 5.0)
				var priority: int = rng.randi_range(0, 3)
				t.eq(int(native.call("select_victim", current, candidate, db, priority, 24, 5)),
					Voices.prioritized_victim(current, candidate, db, priority),
					"native/script parity scenario %d" % trial)

	t.current = "sound concurrency stable retrigger protects fresh equal-priority audio"
	var young: Array = [
		{"name": "blaster", "audibility": -30.0, "age": 0.02, "priority": 2}
	]
	t.eq(Voices.prioritized_victim(young, "blaster", -28.0, 2, 1, 1),
		0, "legacy policy can immediately steal a fresh gunshot")
	t.eq(Voices.prioritized_victim_stable(young, "blaster", -28.0, 2, 1, 1),
		Voices.DROP_NEW, "short-lived equal-priority attack cannot be interrupted")
	t.eq(Voices.prioritized_victim_stable(young, "blaster", -18.0, 2, 1, 1),
		0, "12 dB louder same-priority shot may still win")
	t.eq(Voices.prioritized_victim_stable(young, "enemy_destroy", -90.0, 3, 1, 1),
		0, "critical kill audio preempts less important shot despite hold")
	t.eq(Voices.prioritized_victim_stable(young, "step", -5.0, 1, 1, 1),
		Voices.DROP_NEW, "low-priority steps cannot preempt new combat")
	t.eq(Voices.prioritized_victim_stable(young, "other", -25.0, 2, 2, 1),
		Voices.ROOM, "free channels never lose admission to the guard")
	t.eq(Voices.prioritized_victim_stable(young, "blaster", -28.0, 2, 1, 1, 0.0),
		Voices.prioritized_victim(young, "blaster", -28.0, 2, 1, 1),
		"zero protection restores original admission")
	var aged: Array = [
		{"name": "blaster", "audibility": -30.0, "age": 0.12, "priority": 2}
	]
	t.eq(Voices.prioritized_victim_stable(aged, "blaster", -28.0, 2, 1, 1),
		0, "hold ends at its inclusive age boundary")
	var grouped: Array = [
		{"name": "blaster", "audibility": -30.0, "age": 0.02, "priority": 2},
		{"name": "blaster", "audibility": -27.0, "age": 0.5, "priority": 2}
	]
	t.eq(Voices.prioritized_victim_stable(grouped, "blaster", -25.0, 2, 3, 2),
		1, "same-name cap evicts eligible older shot, never protected younger shot")
	t.eq(Voices.prioritized_victim_stable(grouped, "blaster", -25.0, 2, 3, 2, -1.0),
		Voices.DROP_NEW, "negative hold rejected before touching voices")
	t.eq(Voices.prioritized_victim_stable(grouped, "blaster", -25.0, 2, 3, 2, 0.12, NAN),
		Voices.DROP_NEW, "NaN loudness override rejected atomically")
	if native != null and native.has_method("select_victim_stable"):
		var examples: Array = [young, aged, grouped, active]
		for voices in examples:
			for name in ["blaster", "enemy_destroy", "wind"]:
				for priority in 4:
					var db: float = -35.0 + float(priority) * 8.0
					t.eq(int(native.call("select_victim_stable", voices, name, db, priority, 3, 2)),
						Voices.prioritized_victim_stable(voices, name, db, priority, 3, 2),
						"native/script guard agrees for deterministic priority examples")
		rng.seed = 94132
		for trial in 120:
			var current: Array = []
			for i in rng.randi_range(0, 24):
				current.append({"name": "s%d" % rng.randi_range(0, 6),
					"audibility": rng.randf_range(-85.0, 8.0),
					"age": rng.randf_range(0.0, 0.4),
					"priority": rng.randi_range(0, 3)})
			var candidate: String = "s%d" % rng.randi_range(0, 6)
			var db: float = rng.randf_range(-85.0, 8.0)
			var priority: int = rng.randi_range(0, 3)
			t.eq(int(native.call("select_victim_stable", current, candidate,
					db, priority, 24, 5)),
				Voices.prioritized_victim_stable(current, candidate, db, priority),
				"native/script protected voice admission parity trial %d" % trial)
	rng.seed = 13456
	for trial in 40:
		var voices: Array = []
		for i in rng.randi_range(0, 10):
			voices.append({"name": "s%d" % rng.randi_range(0, 3),
				"audibility": rng.randf_range(-80.0, 0.0),
				"age": rng.randf_range(0.0, 1.0),
				"priority": rng.randi_range(0, 3)})
		t.eq(Voices.prioritized_victim_stable(voices, "s1", -20.0, 1, 24, 5, 0.0),
			Voices.prioritized_victim(voices, "s1", -20.0, 1, 24, 5),
			"disabled guard retains legacy selection trial %d" % trial)

	t.current = "actual game Audio.play_at rejects before node construction"
	var audio = AudioScript.new()
	t.eq(audio._choose_voice_victim(active, "blaster", -60.0, 2),
		Voices.ROOM, "real Audio object admits sound when the global voice pool has room")
	if native != null:
		audio._native_voice_admission = native
		t.eq(audio._choose_voice_victim(active, "blaster", -60.0, 2),
			Voices.ROOM, "native implementation keeps the same free-slot semantics")
	# The actual game method must use protected admission on both binaries.
	audio._native_voice_admission = null
	var full: Array = []
	for i in Voices.MAX_VOICES:
		full.append({"name": "blaster", "audibility": -30.0,
			"age": 0.02, "priority": 2})
	t.eq(audio._choose_voice_victim(full, "blaster", -28.0, 2),
		Voices.DROP_NEW, "script fallback protects an overloaded burst of gunshots")
	if native != null and native.has_method("select_victim_stable"):
		audio._native_voice_admission = native
		t.eq(audio._choose_voice_victim(full, "blaster", -28.0, 2),
			Voices.DROP_NEW, "native planner protects the same real game sound burst")
	var script: String = (AudioScript as Script).source_code
	var begin: int = script.find("func play_at(")
	var end: int = script.find("func _physics_process(", begin)
	var live: String = script.substr(begin, end - begin)
	t.check(live.find("_choose_voice_victim(snapshot,") < live.find("var player := AudioStreamPlayer3D.new()"),
		"rejected spatial sound never allocates an AudioStreamPlayer3D")
	t.check(live.contains('"priority": priority'),
		"voice registry retains priority for subsequent admissions")
	t.check(script.contains("select_victim_stable"),
		"real Audio class prefers protected native admission")
	var online_source: String = FileAccess.get_file_as_string("res://scripts/client/online_main.gd")
	t.check(online_source.contains("Albion/AudioVoiceHoldRejects"),
		"profiler exposes suppressed sound retriggers")
	audio.free()
