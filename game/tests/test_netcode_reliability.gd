extends RefCounted
## Crash-safe deal journal, PvP lag compensation and frame hitch attribution.

const TradeJournal = preload("res://scripts/server/trade_journal.gd")
const LagCompensation = preload("res://scripts/server/lag_compensation.gd")
const FrameHitchAnalyzer = preload("res://scripts/client/frame_hitch_analyzer.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")


func run(t) -> void:
	t.current = "trade journal"
	var path := "user://test_trade_journal.json"
	DirAccess.remove_absolute(path)
	var journal := TradeJournal.new()
	t.check(journal.open_file(path), "fresh journal opens")
	t.check(journal.record("tx1", "alice", {"silver": 5}, "bob", {"silver": 95}), "deal is journaled")
	t.check(journal.record("tx2", "alice", {"silver": 1}, "carol", {"silver": 9}), "second deal is journaled")
	var reopened := TradeJournal.new()
	t.check(reopened.open_file(path), "journal survives a restart")
	t.eq(reopened.entries.size(), 2, "both unsettled deals are recovered")
	t.eq(TradeJournal.replay_kind(reopened.entries["tx1"]), "pair", "untouched deal replays as a pair")
	t.eq(int(reopened.entries["tx1"]["b"]["data"]["silver"]), 95, "after-image is preserved")
	reopened.supersede("alice")
	t.eq(TradeJournal.replay_kind(reopened.entries["tx1"]), "single", "newer save of one side leaves one live side")
	reopened.supersede("bob")
	t.check(not reopened.entries.has("tx1"), "deal with both sides newer is dropped")
	reopened.settle("tx2")
	t.eq(reopened.entries.size(), 0, "settled deals leave the journal")
	var after := TradeJournal.new()
	after.open_file(path)
	t.eq(after.entries.size(), 0, "settlement is durable")
	var bad := FileAccess.open(path, FileAccess.WRITE)
	bad.store_string("{not json")
	bad.close()
	t.check(not TradeJournal.new().open_file(path), "corrupt money journal is refused, not guessed")
	DirAccess.remove_absolute(path)

	t.current = "lag compensation"
	t.eq(LagCompensation.rewind_for(0.0), 0.0, "no measured ping, no rewind")
	t.near(LagCompensation.rewind_for(0.1), 0.17, 0.0001, "half RTT plus interpolation")
	t.eq(LagCompensation.rewind_for(2.0), LagCompensation.MAX_REWIND, "rewind is capped")
	var history := LagCompensation.new()
	history.record(7, 1.0, Vector3(0, 0, 0))
	history.record(7, 1.1, Vector3(1, 0, 0))
	t.near(history.position_at(7, 1.05, Vector3(9, 0, 0)).x, 0.5, 0.0001, "interpolates between ticks")
	t.eq(history.position_at(7, 1.2, Vector3(9, 0, 0)), Vector3(9, 0, 0), "present uses the live position")
	t.eq(history.position_at(8, 1.0, Vector3(3, 0, 3)), Vector3(3, 0, 3), "unknown target uses the live position")

	var world = WorldGen.new(4321)
	var server := GameServer.new(world, 77)
	var hunter = server.add_player(901, "Hunter")
	var prey = server.add_player(902, "Prey")
	var spot := Vector2(400.0, 400.0)
	for r in range(400, 4000, 100):
		if ZoneRisk.allows_pvp(world.zone_at(float(r), float(r))) and ZoneRisk.allows_pvp(world.zone_at(float(r) + 3.0, float(r) + 1.2)):
			spot = Vector2(r, r)
			break
	var base := Vector3(spot.x, world.height_at(spot.x, spot.y), spot.y)
	hunter.position = base
	prey.position = base + Vector3(0, 0, 1.2)
	server.lag_history.record(prey.id, server.time, prey.position)
	server.time += 0.1
	prey.position = base + Vector3(3.0, 0, 1.2) # Sidestepped after the hunter saw it.
	server.lag_history.record(prey.id, server.time, prey.position)
	var zone_ok: bool = ZoneRisk.allows_pvp(world.zone_at(base.x, base.z))
	t.check(zone_ok, "found a PvP zone for the duel")
	var no_lag: Dictionary = server._find_hit(hunter, Vector2(base.x, base.z), Vector2(0, 1), 1.0, false)
	t.check(no_lag.is_empty(), "without ping the sidestep escapes the swing")
	server.peer_round_trip[hunter.id] = 0.06 # 30 ms one way + interpolation ~ 0.15 s back.
	var with_lag: Dictionary = server._find_hit(hunter, Vector2(base.x, base.z), Vector2(0, 1), 1.0, false)
	t.check(zone_ok and str(with_lag.get("kind", "")) == "player", "rewound target is hit where the attacker saw it")

	t.current = "hitch analyzer"
	var analyzer := FrameHitchAnalyzer.new()
	for i in 40:
		analyzer.sample(1.0 / 60.0, {"compiles": 10, "cells": 4, "vram": 1.0e9})
	var compile_hitch: Dictionary = analyzer.sample(0.09, {"compiles": 12, "cells": 4, "vram": 1.0e9})
	t.eq(compile_hitch.get("cause"), "shader_compile", "pipeline compiles explain the hitch")
	var stream_hitch: Dictionary = analyzer.sample(0.08, {"compiles": 12, "cells": 6, "vram": 1.0e9})
	t.eq(stream_hitch.get("cause"), "streaming", "cell loads explain the hitch")
	t.check(analyzer.sample(1.0 / 60.0, {"compiles": 12, "cells": 6, "vram": 1.0e9}).is_empty(), "normal frame is no hitch")
	t.near(analyzer.median(), 1.0 / 60.0, 0.0001, "hitches never pollute the baseline")
	t.check(analyzer.describe().contains("shaders 1"), "summary counts causes")
