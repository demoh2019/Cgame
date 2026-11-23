extends RefCounted
## Real paid rest produces bounded, saved bonus skill training, without free XP.
const Training = preload("res://scripts/shared/rested_training.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const CampRest = preload("res://scripts/shared/camp_rest.gd")
const Skills = preload("res://scripts/shared/skills.gd")


func run(t) -> void:
	t.current = "pure rested credit: upper bounds and finite inputs"
	t.eq(Training.refill(0, false), 60, "hub rest produces sixty points of future bonus")
	t.eq(Training.refill(0, true), 30, "field fire offers a smaller reward")
	t.eq(Training.refill(235, false), Training.MAX_CREDIT, "credit capped at 240")
	t.eq(Training.bonus_for(20.0, 30), 10, "at least 50 percent extra XP for completed work")
	t.eq(Training.bonus_for(20.0, 30, 1), 15, "novice skill earns 75 percent bonus")
	t.eq(Training.bonus_for(20.0, 30, 9), 15, "novice threshold is inclusive")
	t.eq(Training.bonus_for(20.0, 30, 10), 12, "developing skill earns 60 percent")
	t.eq(Training.bonus_for(20.0, 30, 24), 12, "developing threshold is inclusive")
	t.eq(Training.bonus_for(20.0, 30, 25), 10, "advanced skill gets 50 percent")
	t.eq(Training.bonus_for(20.0, 30, 0), 0, "invalid skill level cannot mint XP")
	t.eq(Training.bonus_for(40.0, 3), 3, "cannot overspend scarce credit")
	t.eq(Training.bonus_for(0.0, 30), 0, "no bonus on zero XP")
	t.eq(Training.bonus_for(NAN, 30), 0, "NaN work ignored")
	t.eq(Training.bonus_for(INF, 30), 0, "infinite work ignored")
	for invalid in [-1, 241, NAN, INF, 0.5, "15", true]:
		t.check(not Training.valid_credit(invalid), "invalid saved credit rejected")
	t.check(Training.valid_credit(0) and Training.valid_credit(240.0),
		"valid integer credit survives JSON's numeric roundtrip")

	t.current = "server-owned rest, failed payments and cooldown do not grant XP"
	var world := WorldGen.new(801)
	var server := GameServer.new(world, 801)
	var player = server.add_player(801, "Rested")
	var hub := GameServer.WORKBENCH_POSITION
	player.position = Vector3(hub.x, world.height_at(hub.x, hub.y), hub.y)
	t.eq(player.rested_xp_credit, 0, "new account has no reserved bonus")
	t.eq(server.cmd_rest(801).get("reason"), "fully_rested", "no free credit while healthy")
	t.eq(player.rested_xp_credit, 0, "failed rest gives no credit")
	player.survival.health = 50.0
	t.eq(server.cmd_rest(801).get("reason"), "missing_items", "missing wood stops rest")
	t.eq(player.rested_xp_credit, 0, "unpaid rest cannot mint XP")
	player.inventory.add("wood_1", 2)
	t.check(bool(server.cmd_rest(801).get("ok", false)), "paid hub rest succeeds")
	t.eq(player.rested_xp_credit, Training.HUB_GRANT, "rested reserve increases once")
	t.eq(server.snapshot_for(801)["you"]["rested_xp_credit"], Training.HUB_GRANT,
		"private snapshot shows only own bonus")
	t.eq(server.cmd_rest(801).get("reason"), "cooldown", "spam rest blocked")
	t.eq(player.rested_xp_credit, Training.HUB_GRANT, "blocked repeat does not refill")

	t.current = "only actual skill XP spends the bonus reserve"
	var baseline: int = int(player.skills.xp["medic"])
	server._award(player, "medic", 20.0)
	t.eq(int(player.skills.xp["medic"]) - baseline, 35, "novice skill receives 75 percent extra XP")
	t.eq(player.rested_xp_credit, 45, "exactly fifteen extra credits consumed")
	server._award(player, "does_not_exist", 20.0)
	t.eq(player.rested_xp_credit, 45, "unknown skill cannot drain bonus")
	server._award(player, "medic", 0.0)
	t.eq(player.rested_xp_credit, 45, "zero experience cannot drain bonus")

	t.current = "reconnect preserves spent balance; corrupt saves fail atomically"
	var saved: Dictionary = server.character_data(player)
	t.eq(saved["rested_xp_credit"], 45, "credit recorded with the character")
	t.check(server.valid_character_data(saved), "rested save is validated")
	var restored = server.add_player(802, "Rested", "same-account", saved)
	t.eq(restored.rested_xp_credit, 45, "reconnect does not refill credit")
	t.eq(restored.rest_cooldown, CampRest.COOLDOWN, "cooldown survives reconnect")
	for invalid in [-1, 241, NAN, INF, 25.5, "25", true]:
		var bad: Dictionary = saved.duplicate(true)
		bad["rested_xp_credit"] = invalid
		t.check(not server.apply_character(restored, bad), "forged/rested save refused")
		t.eq(restored.rested_xp_credit, 45, "invalid load does not modify current credit")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("rested_xp_credit")
	t.check(server.apply_character(restored, legacy), "older version-one save still loads")
	t.eq(restored.rested_xp_credit, 0, "old character has no unearned training")

	t.current = "server training adapts to expertise and never spends credit at XP cap"
	var advanced = server.add_player(803, "Advanced")
	advanced.rested_xp_credit = 80
	advanced.skills.xp["medic"] = Skills.xp_for_level(10)
	var intermediate_before: int = int(advanced.skills.xp["medic"])
	server._award(advanced, "medic", 20.0)
	t.eq(int(advanced.skills.xp["medic"]) - intermediate_before, 32,
		"level 10 skill gets 60 percent extra XP")
	t.eq(advanced.rested_xp_credit, 68, "intermediate spends twelve bonus credit")
	advanced.skills.xp["medic"] = Skills.xp_for_level(25)
	var expert_before: int = int(advanced.skills.xp["medic"])
	server._award(advanced, "medic", 20.0)
	t.eq(int(advanced.skills.xp["medic"]) - expert_before, 30,
		"level 25 skill gets 50 percent extra XP")
	t.eq(advanced.rested_xp_credit, 58, "expert spends ten bonus credit")
	advanced.skills.xp["medic"] = Skills.MAX_XP
	server._award(advanced, "medic", 20.0)
	t.eq(advanced.rested_xp_credit, 58, "XP capped skill cannot consume bonus reserve")
