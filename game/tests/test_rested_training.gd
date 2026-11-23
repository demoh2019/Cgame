extends RefCounted
## Real paid rest produces bounded, saved bonus skill training, without free XP.
const Training = preload("res://scripts/shared/rested_training.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const CampRest = preload("res://scripts/shared/camp_rest.gd")
const Skills = preload("res://scripts/shared/skills.gd")
const CrossTraining = preload("res://scripts/shared/cross_training.gd")
const DeepPractice = preload("res://scripts/shared/deep_practice.gd")


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

	t.current = "cross-training: distinct skill branches, not repeat farming"
	t.eq(CrossTraining.branches_count({}, 10.0), 0, "new survivor starts without practice")
	var practice: Dictionary = {}
	practice = CrossTraining.record(practice, "woodcutting", 10.0, 10.0)
	practice = CrossTraining.record(practice, "mining", 10.0, 11.0)
	t.eq(CrossTraining.branches_count(practice, 11.0), 1, "two gathering skills count as one branch")
	practice = CrossTraining.record(practice, "medic", 3.0, 12.0)
	t.eq(CrossTraining.branches_count(practice, 12.0), 1, "tiny XP is ineligible")
	practice = CrossTraining.record(practice, "medic", 6.0, 12.0)
	practice = CrossTraining.record(practice, "crafting", 6.0, 13.0)
	t.eq(CrossTraining.branches_count(practice, 13.0), 3, "three branches unlock diverse practice")
	t.check(CrossTraining.active_for(practice, "mining", 20.0, 13.0),
		"fourth substantial action receives cross-training boost")
	t.check(not CrossTraining.active_for(practice, "mining", 1.0, 13.0),
		"tick-based or trivial XP does not get extra rate")
	t.eq(Training.bonus_for(20.0, 100, 1, true), 19, "novice practice raises rate to 95 percent")
	t.eq(Training.bonus_for(20.0, 100, 10, true), 16, "intermediate practice adds 20 percent")
	t.eq(Training.bonus_for(20.0, 100, 25, true), 14, "expert practice adds 20 percent")
	t.eq(Training.bonus_for(20.0, 3, 1, true), 3, "cross-training cannot overspend reserve")
	var refreshed: Dictionary = CrossTraining.record(practice, "woodcutting", 10.0, 14.0)
	t.eq(refreshed["gathering"], 10.0, "repeated branch cannot refresh before cooldown")
	refreshed = CrossTraining.record(refreshed, "woodcutting", 10.0, 25.0)
	t.eq(refreshed["gathering"], 25.0, "eligible practice can refresh after cooldown")
	t.eq(CrossTraining.branches_count(refreshed, 205.1), 0, "practice ages out after 180 seconds")
	t.eq(CrossTraining.branches_count({"unknown": 20.0, "craft": NAN, "combat": INF}, 30.0),
		0, "forged or malformed practice entries are ignored")
	t.eq(CrossTraining.branches_count({"combat": 31.0}, 30.0), 0,
		"future timestamps cannot keep training active")
	t.eq(CrossTraining.branches_count(practice, NAN), 0, "invalid clock never activates practice")

	t.current = "confirmed server XP activates cross-training, private and reconnect-safe"
	var varied = server.add_player(804, "Varied")
	varied.rested_xp_credit = 120
	server.time = 10.0
	server._award(varied, "woodcutting", 10.0)
	server._award(varied, "medic", 10.0)
	server._award(varied, "crafting", 10.0)
	t.eq(int(server.snapshot_for(varied.id)["you"]["practice_branches"]), 3,
		"server confirms three independent skill branches")
	t.check(bool(server.snapshot_for(varied.id)["you"]["cross_training_active"]),
		"training status is visible to the owner")
	var xp_before: int = int(varied.skills.xp["mining"])
	server._award(varied, "mining", 20.0)
	t.eq(int(varied.skills.xp["mining"]) - xp_before, 39,
		"verified cross-trained action gets 95 percent extra XP")
	t.eq(varied.rested_xp_credit, 77, "reserve pays for each real bonus")
	var varied_saved: Dictionary = server.character_data(varied)
	t.check(not varied_saved.has("practice_state"), "session practice never enters persistent saves")
	var new_session = server.add_player(806, "Varied again", "varied-account", varied_saved)
	t.eq(int(server.snapshot_for(new_session.id)["you"]["practice_branches"]), 0,
		"reconnect starts without unearned practice")
	server.time = 191.0
	t.eq(int(server.snapshot_for(varied.id)["you"]["practice_branches"]), 0,
		"expired practice disappears from client snapshot")

	t.current = "XP credit is spent only on bonus XP that actually fits below the cap"
	var capped = server.add_player(805, "Capped")
	capped.rested_xp_credit = 60
	capped.skills.xp["medic"] = Skills.MAX_XP - 23
	server._award(capped, "medic", 20.0)
	t.eq(int(capped.skills.xp["medic"]), Skills.MAX_XP, "training reaches XP cap exactly")
	t.eq(capped.rested_xp_credit, 57, "only three credited bonus XP are charged")
	server._award(capped, "medic", 20.0)
	t.eq(capped.rested_xp_credit, 57, "no charge on capped skill")
	capped.skills.xp["medic"] = Skills.MAX_XP - 5
	server._award(capped, "medic", 20.0)
	t.eq(capped.rested_xp_credit, 57, "base action XP alone reaches the cap")

	t.current = "deep practice: two distinct skills in one branch"
	var deep: Dictionary = {}
	t.eq(DeepPractice.trained_branches(deep, 20.0), 0, "new training has no discipline depth")
	deep = DeepPractice.record(deep, "woodcutting", 10.0, 20.0)
	deep = DeepPractice.record(deep, "woodcutting", 10.0, 21.0)
	t.eq(DeepPractice.skills_in_branch(deep, "gathering", 21.0), 1,
		"repeating a skill does not simulate a new technique")
	t.eq(deep["woodcutting"], 20.0, "same-skill refresh is rate limited")
	deep = DeepPractice.record(deep, "mining", 4.0, 21.0)
	t.eq(DeepPractice.skills_in_branch(deep, "gathering", 21.0), 1,
		"tiny progress cannot count as a different technique")
	deep = DeepPractice.record(deep, "mining", 10.0, 22.0)
	t.eq(DeepPractice.skills_in_branch(deep, "gathering", 22.0), 2,
		"two meaningful skills build one discipline")
	t.eq(DeepPractice.trained_branches(deep, 22.0), 1,
		"deep training counts practiced disciplines, not actions")
	t.check(DeepPractice.active_for(deep, "foraging", 20.0, 22.0),
		"third skill in mastered discipline receives a training bonus")
	t.check(not DeepPractice.active_for(deep, "medic", 20.0, 22.0),
		"unrelated discipline cannot borrow training depth")
	t.check(not DeepPractice.active_for(deep, "foraging", 1.0, 22.0),
		"trivial tick awards cannot use training depth")
	t.check(not DeepPractice.active_for(deep, "unrecognized", 20.0, 22.0),
		"unknown skills cannot activate the reward")
	t.eq(DeepPractice.skills_in_branch(deep, "gathering", 203.0), 0,
		"depth expires after three minutes")
	t.eq(DeepPractice.skills_in_branch(
		{"woodcutting": NAN, "mining": INF, "foraging": 99.0}, "gathering", 22.0),
		0, "invalid or future timestamps never earn depth")
	t.eq(DeepPractice.skills_in_branch(deep, "gathering", NAN), 0,
		"invalid server clock never enables depth")
	t.eq(Training.bonus_for(20.0, 100, 1, false, true), 17,
		"novice deep-practice bonus alone adds 10 percentage points")
	t.eq(Training.bonus_for(20.0, 100, 10, true, true), 18,
		"developing player can combine both training bonuses")
	t.eq(Training.bonus_for(20.0, 100, 25, true, true), 16,
		"expert combines disciplined and varied practice")
	t.eq(Training.bonus_for(20.0, 100, 1, true, true), 20,
		"novice combined training is capped at +100 percent")
	t.eq(Training.bonus_for(20.0, 3, 1, true, true), 3,
		"deep practice cannot overspend the paid reserve")

	t.current = "deep practice is live, server-owned, and reconnect-safe"
	var focused = server.add_player(807, "Focused")
	focused.rested_xp_credit = 220
	server.time = 20.0
	server._award(focused, "woodcutting", 10.0)
	server._award(focused, "mining", 10.0)
	t.eq(int(server.snapshot_for(focused.id)["you"]["deep_practice_branches"]), 1,
		"the owner can see the newly trained gathering discipline")
	var before_foraging: int = int(focused.skills.xp["foraging"])
	server._award(focused, "foraging", 20.0)
	t.eq(int(focused.skills.xp["foraging"]) - before_foraging, 37,
		"real gathering work receives the +85 percent novice bonus")
	t.eq(focused.rested_xp_credit, 187,
		"deep practice consumes only confirmed bonus XP from paid rest")
	server._award(focused, "medic", 10.0)
	server._award(focused, "crafting", 10.0)
	server._award(focused, "melee", 10.0)
	server._award(focused, "marksman", 10.0)
	t.eq(int(server.snapshot_for(focused.id)["you"]["deep_practice_branches"]), 2,
		"gathering and combat both become deeply trained disciplines")
	var before_slayer: int = int(focused.skills.xp["slayer"])
	server._award(focused, "slayer", 20.0)
	t.eq(int(focused.skills.xp["slayer"]) - before_slayer, 40,
		"real combat mastery combines both bonuses but caps at twice base XP")
	var focused_saved: Dictionary = server.character_data(focused)
	t.check(not focused_saved.has("deep_practice_state"),
		"discipline state cannot be forged through saved character data")
	var relogged = server.add_player(808, "Focused again", "focused-account", focused_saved)
	t.eq(int(server.snapshot_for(relogged.id)["you"]["deep_practice_branches"]), 0,
		"reconnecting clears temporary training depth")
	server.time = 201.0
	t.eq(int(server.snapshot_for(focused.id)["you"]["deep_practice_branches"]), 0,
		"old discipline exercises expire without extra permanent bonuses")
