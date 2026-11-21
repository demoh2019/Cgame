extends RefCounted
## Deterministic replay recorder and versioned save migrations.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const ReplayRecorder = preload("res://scripts/server/replay_recorder.gd")
const SaveMigrations = preload("res://scripts/server/save_migrations.gd")

const SEED := 4242
const TICKS := 40 # 2 simulated seconds at 0.05 s


static func _make_server(p_seed: int, p_world_seed: int) -> Object:
	var server := GameServer.new(WorldGen.new(p_world_seed), p_seed)
	server.craft_quality_enabled = false
	server.zombies.clear()
	return server


static func _record() -> ReplayRecorder:
	var rec := ReplayRecorder.new(SEED, SEED)
	rec.add_initial_player(1, "Alpha")
	rec.add_initial_player(2, "Beta")
	var seq := 0
	for i in range(TICKS):
		seq += 1
		rec.record_command(1, "submit_input", [seq, 1.0, 0.0, false, 0.0, 0.05])
		rec.record_command(2, "submit_input", [seq, 0.0, -1.0, i % 2 == 0, 1.5, 0.05])
		if i % 10 == 5:
			rec.record_command(1, "cmd_attack", [1.0, 0.0, 0.0])
			rec.record_command(2, "cmd_attack", [0.0, 1.0, 0.0])
		rec.end_tick(0.05)
	return rec


static func _migration_validate(d: Dictionary) -> Array:
	var problems: Array = []
	if d.has("money"):
		problems.append("legacy money key survived")
	if not d.has("silver"):
		problems.append("silver missing")
	return problems


func run(t) -> void:
	t.current = "replay determinism"
	var rec := _record()
	t.eq(rec.frames.size(), TICKS, "one frame per tick")
	var replay: Dictionary = rec.to_dict()
	var first: Dictionary = ReplayRecorder.play(replay, Callable(self, "_wrap_make"))
	var second: Dictionary = ReplayRecorder.play(replay, Callable(self, "_wrap_make"))
	t.check(bool(first["ok"]), "replay runs without rejected commands")
	t.eq(first["hashes"].size(), TICKS, "a hash per tick")
	t.eq(ReplayRecorder.compare(first["hashes"], second["hashes"]), -1, "two fresh servers replay identically")
	t.check(int(first["hashes"][0]) != int(first["hashes"][TICKS - 1]), "state actually changes over the session")

	t.current = "replay tamper detection"
	var tampered: Dictionary = rec.to_dict()
	var frame: Dictionary = tampered["frames"][12]
	for c in frame["commands"]:
		var cmd: Dictionary = c
		if cmd["method"] == "submit_input" and int(cmd["peer"]) == 1:
			cmd["args"][1] = -1.0 # walk the other way
	var bad: Dictionary = ReplayRecorder.play(tampered, Callable(self, "_wrap_make"))
	t.eq(ReplayRecorder.compare(first["hashes"], bad["hashes"]), 12, "divergence appears at the tampered tick")
	t.eq(ReplayRecorder.compare([1, 2, 3], [1, 2]), 2, "length mismatch diverges at the shorter end")

	t.current = "replay method whitelist"
	var evil := ReplayRecorder.new(SEED, SEED)
	evil.add_initial_player(1, "Alpha")
	t.check(not evil.record_command(1, "tick", [1.0]), "recorder refuses tick")
	t.check(not evil.record_command(1, "add_player", [9, "x"]), "recorder refuses add_player")
	t.check(evil.record_command(1, "cmd_attack", [1.0, 0.0]), "recorder accepts cmd_*")
	evil.end_tick(0.05)
	var forged: Dictionary = evil.to_dict()
	forged["frames"][0]["commands"].append({"peer": 1, "method": "restore", "args": []})
	var refused: Dictionary = ReplayRecorder.play(forged, Callable(self, "_wrap_make"))
	t.check(not bool(refused["ok"]), "play flags a forged non-cmd method")
	t.eq(refused["rejected"].size(), 1, "exactly one command rejected")

	t.current = "replay save/load"
	var path := "user://test_replay_roundtrip.replay"
	t.check(rec.save(path), "replay saves")
	var loaded: Dictionary = ReplayRecorder.load(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	t.check(not loaded.is_empty(), "replay loads")
	var third: Dictionary = ReplayRecorder.play(loaded, Callable(self, "_wrap_make"))
	t.eq(ReplayRecorder.compare(first["hashes"], third["hashes"]), -1, "loaded replay reproduces the hashes")
	t.check(ReplayRecorder.load("user://does_not_exist.replay").is_empty(), "missing file loads empty")

	t.current = "save migrations"
	var reg = SaveMigrations.character_registry()
	var v1 := {"version": 1, "health": 80.0, "money": 250}
	var snapshot: Dictionary = v1.duplicate(true)
	var v3: Dictionary = reg.migrate(v1, 3)
	t.eq(v3.get("version"), 3, "chain reaches v3")
	t.eq(v3.get("silver"), 250, "money renamed to silver")
	t.check(not v3.has("money"), "legacy key removed")
	t.near(float(v3.get("focus", 0.0)), 100.0, 0.0001, "focus default added")
	t.check(v1 == snapshot, "input dictionary untouched")
	t.eq(int(reg.migrate({"version": 2, "silver": 5}, 3).get("focus", -1)), 100, "starting mid-chain works")
	t.eq(reg.migrate({"version": 3, "silver": 1, "focus": 7.0}, 3).get("focus"), 7.0, "current save passes through")

	var gap = SaveMigrations.new()
	gap.register(1, 2, Callable(SaveMigrations, "example_v1_to_v2"))
	t.check(gap.migrate(v1, 3).is_empty(), "gap in chain refused")
	t.check(gap.last_error.contains("gap"), "gap reports an error")
	t.check(reg.migrate({"version": 4}, 3).is_empty(), "downgrade refused")
	t.check(reg.last_error.contains("downgrade"), "downgrade reports an error")
	t.check(reg.migrate({"health": 1}, 3).is_empty(), "missing version refused")
	t.check(not gap.register(1, 3, Callable(SaveMigrations, "example_v1_to_v2")), "multi-version step refused")

	t.current = "migration roundtrip verification"
	var ok_problems: Array[String] = reg.verify_roundtrip(v1, 3, Callable(self, "_migration_validate_cb"))
	t.eq(ok_problems.size(), 0, "good migration verifies clean")
	var broken = SaveMigrations.new()
	broken.register(1, 2, func(d: Dictionary) -> Dictionary:
		d["money"] = d.get("money", 0) # forgets the rename
		return d)
	var bad_problems: Array[String] = broken.verify_roundtrip(v1, 2, Callable(self, "_migration_validate_cb"))
	t.check(bad_problems.size() >= 2, "broken migration reports problems")
	var mutator = SaveMigrations.new()
	var shared := {"inner": [1]}
	mutator.register(1, 2, func(d: Dictionary) -> Dictionary:
		return d)
	t.eq(mutator.verify_roundtrip({"version": 1, "silver": 1, "inner": shared["inner"]}, 5, Callable()).size(), 1,
		"missing step to target is reported")


func _wrap_make(p_seed: int, p_world_seed: int) -> Object:
	return _make_server(p_seed, p_world_seed)


func _migration_validate_cb(d: Dictionary) -> Array:
	return _migration_validate(d)
