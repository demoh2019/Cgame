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

	t.current = "actual game Audio.play_at rejects before node construction"
	var audio = AudioScript.new()
	t.eq(audio._choose_voice_victim(active, "blaster", -60.0, 2),
		1, "real Audio object uses portable admission policy")
	if native != null:
		audio._native_voice_admission = native
		t.eq(audio._choose_voice_victim(active, "blaster", -60.0, 2),
			1, "real Audio object delegates to the Cgame native planner")
	var script: String = (AudioScript as Script).source_code
	var begin: int = script.find("func play_at(")
	var end: int = script.find("func _physics_process(", begin)
	var live: String = script.substr(begin, end - begin)
	t.check(live.find("_choose_voice_victim(snapshot,") < live.find("var player := AudioStreamPlayer3D.new()"),
		"rejected spatial sound never allocates an AudioStreamPlayer3D")
	t.check(live.contains('"priority": priority'),
		"voice registry retains priority for subsequent admissions")
	audio.free()
