extends RefCounted

const Skills = preload("res://scripts/shared/skills.gd")


## Trains a skill until it reaches `level` (one call is capped, so a high level takes a few).
static func level_to(s, skill: String, level: int) -> void:
	while s.level(skill) < level:
		s.add_xp(skill, minf(float(Skills.xp_for_level(level) - int(s.xp[skill])), 100000.0))


func run(t) -> void:
	_curve(t)
	_adding_xp(t)
	_points_and_perks(t)
	_bonuses(t)
	_persistence(t)
	_data_consistency(t)


func _curve(t) -> void:
	t.current = "xp curve"
	t.eq(Skills.level_for_xp(0), 1, "no xp is level 1")
	t.eq(Skills.level_for_xp(-50), 1, "negative xp is level 1")
	t.eq(Skills.xp_for_level(1), 0, "level 1 needs no xp")
	var previous := -1
	for level in range(1, Skills.MAX_LEVEL + 1):
		var needed := Skills.xp_for_level(level)
		t.check(needed > previous, "level %d needs more xp than the one before" % level)
		previous = needed
		t.eq(Skills.level_for_xp(needed), level, "reaching level %d xp gives level %d" % [level, level])
		if level > 1:
			t.eq(Skills.level_for_xp(needed - 1), level - 1, "one xp short of level %d" % level)
	t.eq(Skills.level_for_xp(Skills.MAX_XP * 10), Skills.MAX_LEVEL, "the level is capped")
	t.check(Skills.xp_for_level(Skills.MAX_LEVEL) <= Skills.MAX_XP, "the stored xp cap covers max level")
	t.check(Skills.xp_to_next(10) > Skills.xp_to_next(2) * 4, "later levels take clearly longer")
	t.check(Skills.xp_for_level(5) < 1000, "early levels come quickly (%d xp to level 5)" % Skills.xp_for_level(5))
	t.check(Skills.xp_for_level(Skills.MAX_LEVEL) > 100000, "the top is a long road")


func _adding_xp(t) -> void:
	t.current = "adding xp"
	var s := Skills.new()
	t.eq(s.level("woodcutting"), 1, "everything starts at level 1")
	t.eq(s.total_level(), Skills.SKILLS.size(), "total level counts every skill")
	var result := s.add_xp("woodcutting", 10)
	t.eq(result["gained"], 10, "xp is added")
	t.eq(result["levels"], [], "no level yet")
	result = s.add_xp("woodcutting", Skills.xp_to_next(1))
	t.eq(result["levels"], [2], "crossing a threshold reports the level")
	t.eq(s.level("woodcutting"), 2, "level 2")
	# A huge gain can pass several levels at once and reports each.
	result = s.add_xp("mining", Skills.xp_for_level(5) + 3)
	t.eq(result["levels"], [2, 3, 4, 5], "several levels at once")
	t.eq(s.level("mining"), 5, "level 5")
	# Training one skill never trains another.
	t.eq(s.level("melee"), 1, "other skills are untouched")
	# Invalid input.
	for bad in [0.0, -5.0, NAN, INF]:
		t.eq(s.add_xp("melee", bad)["gained"], 0, "xp amount %s is refused" % str(bad))
	t.eq(s.add_xp("not_a_skill", 10)["gained"], 0, "unknown skills are refused")
	t.eq(s.level("melee"), 1, "refused xp changed nothing")
	# The cap holds.
	s.add_xp("melee", 100000)
	s.add_xp("melee", 100000)
	s.add_xp("melee", 100000)
	s.add_xp("melee", 100000)
	s.add_xp("melee", 100000)
	t.eq(int(s.xp["melee"]), Skills.MAX_XP, "xp stops at the cap")
	t.eq(s.level("melee"), Skills.MAX_LEVEL, "max level reached")
	t.near(s.progress("melee"), 1.0, 0.0001, "a maxed skill shows full progress")
	t.eq(s.add_xp("melee", 50)["gained"], 0, "nothing more to gain at the cap")
	# Progress.
	var fresh := Skills.new()
	fresh.add_xp("crafting", Skills.xp_to_next(1) / 2)
	t.check(fresh.progress("crafting") > 0.4 and fresh.progress("crafting") < 0.6, "half way to the next level (%f)" % fresh.progress("crafting"))
	# Every action gives at least 1 xp, so small gains never round to nothing.
	t.eq(Skills.new().add_xp("athletics", 0.2)["gained"], 1, "a tiny gain still counts as 1")
	# Where gathering skills come from.
	t.eq(Skills.skill_for_node("tree"), "woodcutting", "trees train woodcutting")
	t.eq(Skills.skill_for_node("rock"), "mining", "rocks train mining")
	t.eq(Skills.skill_for_node("ore"), "mining", "ore trains mining")
	t.eq(Skills.skill_for_node("bush"), "foraging", "bushes train foraging")
	t.eq(Skills.skill_for_node("berry"), "foraging", "berries train foraging")
	t.eq(Skills.skill_for_node("crate"), "", "crates are not gathered")


func _points_and_perks(t) -> void:
	t.current = "points and perks"
	var s := Skills.new()
	t.eq(s.points_earned(), 0, "no points at the start")
	t.eq(s.buy_perk("sharp_axe"), Skills.Buy.LEVEL, "level 1 is too low for any perk")
	t.eq(s.buy_perk("not_a_perk"), Skills.Buy.UNKNOWN, "unknown perk")
	s.add_xp("woodcutting", Skills.xp_for_level(5))
	t.eq(s.points_earned(), 4, "each level gives a point")
	t.eq(s.buy_perk("sharp_axe"), Skills.Buy.OK, "level 5 and a point buys Sharp Axe")
	t.eq(s.rank("sharp_axe"), 1, "rank 1")
	t.eq(s.points_available(), 3, "one point spent")
	t.eq(s.buy_perk("sharp_axe"), Skills.Buy.LEVEL, "rank 2 needs level 10")
	t.eq(s.rank("sharp_axe"), 1, "a refused purchase changes nothing")
	t.eq(s.buy_perk("timber_luck"), Skills.Buy.LEVEL, "Timber Luck needs level 10")
	# Points from other skills pay for perks in this one.
	level_to(s, "mining", 20)
	t.eq(s.buy_perk("sharp_axe"), Skills.Buy.LEVEL, "points do not replace skill level")
	level_to(s, "woodcutting", 30)
	for i in 4:
		t.eq(s.buy_perk("sharp_axe"), Skills.Buy.OK, "rank %d of Sharp Axe" % (i + 2))
	t.eq(s.rank("sharp_axe"), 5, "max rank reached")
	t.eq(s.buy_perk("sharp_axe"), Skills.Buy.MAX_RANK, "no more ranks than the maximum")
	t.eq(s.next_rank_requirement("sharp_axe"), {}, "a maxed perk has no next rank")
	# Prerequisites.
	var p := Skills.new()
	level_to(p, "woodcutting", 50)
	t.eq(p.buy_perk("forest_master"), Skills.Buy.REQUIRES, "the capstone needs Sharp Axe rank 3 first")
	for i in 3:
		p.buy_perk("sharp_axe")
	t.eq(p.rank("sharp_axe"), 3, "rank 3 bought")
	t.eq(p.buy_perk("forest_master"), Skills.Buy.OK, "now the capstone is available (cost 5)")
	t.eq(p.points_spent(), 3 + 5, "cost is per rank: 3 x 1 + 5")
	# Costs: Timber Luck costs 2 per rank.
	var q := Skills.new()
	q.add_xp("woodcutting", Skills.xp_for_level(11))
	var before := q.points_available()
	t.eq(q.buy_perk("timber_luck"), Skills.Buy.OK, "Timber Luck")
	t.eq(before - q.points_available(), 2, "it costs two points")
	# The tree is fully defined.
	for perk_id in Skills.PERKS:
		var perk: Dictionary = Skills.PERKS[perk_id]
		t.check(Skills.SKILLS.has(perk["skill"]), "%s belongs to a real skill" % perk_id)
		t.check(Skills.BONUS_CAPS.has(perk["bonus"]), "%s gives a capped bonus" % perk_id)
		t.check(int(perk["max_rank"]) >= 1 and int(perk["cost"]) >= 1 and int(perk["level"]) >= 2 and int(perk["level"]) <= Skills.MAX_LEVEL, "%s has sane numbers" % perk_id)
		t.check(int(perk["level"]) + int(perk["level_step"]) * (int(perk["max_rank"]) - 1) <= Skills.MAX_LEVEL, "%s top rank is reachable" % perk_id)
		if perk.has("requires"):
			t.check(Skills.PERKS.has(perk["requires"]) and Skills.PERKS[perk["requires"]]["skill"] == perk["skill"], "%s requires a perk of its own skill" % perk_id)
	for skill in Skills.SKILLS:
		var branch: String = Skills.SKILLS[skill]["branch"]
		t.check(Skills.BRANCHES.has(branch) and Skills.BRANCHES[branch]["skills"].has(skill), "%s is listed in its branch" % skill)
		var perk_count := 0
		for perk_id in Skills.PERKS:
			if Skills.PERKS[perk_id]["skill"] == skill:
				perk_count += 1
		t.check(perk_count >= 2, "%s has perks to spend points on (%d)" % [skill, perk_count])
		for bonus_name in Skills.SKILLS[skill]["passive"]:
			t.check(Skills.BONUS_CAPS.has(bonus_name), "%s passive %s has a cap" % [skill, bonus_name])
	# Everything can be afforded by maxing every skill.
	var all_cost := 0
	for perk_id in Skills.PERKS:
		all_cost += int(Skills.PERKS[perk_id]["cost"]) * int(Skills.PERKS[perk_id]["max_rank"])
	var maxed := Skills.new()
	for skill in Skills.SKILLS:
		level_to(maxed, skill, 50)
	t.check(maxed.points_earned() > all_cost, "a fully levelled character can buy every perk (%d points, %d needed)" % [maxed.points_earned(), all_cost])
	t.check(all_cost > 100, "but it is a real choice early on (%d points for everything)" % all_cost)


func _bonuses(t) -> void:
	t.current = "bonuses"
	var s := Skills.new()
	t.near(s.bonus("melee_damage"), 0.0, 0.00001, "no bonus at level 1")
	t.near(s.bonus("not_a_bonus"), 0.0, 0.00001, "unknown bonus is zero")
	s.add_xp("melee", Skills.xp_for_level(11))
	t.near(s.bonus("melee_damage"), 0.008 * 10.0, 0.0001, "10 levels of melee: +8% damage")
	t.near(s.bonus("crit_chance"), 0.02, 0.0001, "and 2% crit chance")
	# A perk adds on top.
	level_to(s, "melee", 30)
	s.buy_perk("heavy_hands")
	s.buy_perk("heavy_hands")
	t.near(s.bonus("melee_damage"), 0.008 * (s.level("melee") - 1) + 0.10, 0.0001, "passive and two ranks of Heavy Hands")
	# Several skills can feed the same bonus.
	var m := Skills.new()
	m.add_xp("explorer", Skills.xp_for_level(11))
	t.near(m.bonus("xp_gain"), 0.02, 0.0001, "explorer levels speed up all training")
	t.near(m.bonus("carry_capacity"), 0.08, 0.0001, "and add carrying capacity")
	# XP gain applies to later gains.
	var gain: int = m.add_xp("mining", 100.0)["gained"]
	t.eq(gain, 102, "2%% more xp for a 100 xp action (got %d)" % gain)
	# Caps hold even with everything maxed.
	var maxed := Skills.new()
	for skill in Skills.SKILLS:
		level_to(maxed, skill, 50)
	for perk_id in Skills.PERKS:
		maxed.ranks[perk_id] = int(Skills.PERKS[perk_id]["max_rank"])
	for name in Skills.BONUS_CAPS:
		t.check(maxed.bonus(name) <= float(Skills.BONUS_CAPS[name]) + 0.000001, "%s stays under its cap" % name)
	# A maxed character lands below the hard caps, which only guard against future rebalancing mistakes.
	t.near(maxed.bonus("move_speed"), 0.003 * 49.0 + 0.02 * 5.0, 0.0001, "maxed athletics: +24.7% movement speed")
	t.near(maxed.bonus("damage_reduction"), 0.004 * 49.0 + 0.1 + 0.06, 0.0001, "maxed toughness: 35.6% damage reduction")
	t.check(maxed.bonus("max_health") <= Skills.MAX_HEALTH_BONUS, "health bonus is capped")
	t.check(not maxed.all_bonuses().is_empty(), "a maxed character lists its bonuses")
	t.check(Skills.new().all_bonuses().is_empty(), "a new character has none")
	t.check(Skills.describe_bonus("move_speed", 0.15).begins_with("+15%"), "bonuses read as percentages")
	t.eq(Skills.describe_bonus("max_health", 12.0), "+12 max health", "health reads as points")


func _persistence(t) -> void:
	t.current = "persistence"
	var s := Skills.new()
	s.add_xp("woodcutting", Skills.xp_for_level(12))
	s.add_xp("slayer", 777)
	s.buy_perk("sharp_axe")
	s.zones_seen = 6
	var copy := Skills.new()
	t.check(copy.load_dict(s.to_dict()), "a saved skill sheet loads")
	t.eq(copy.xp, s.xp, "xp round trips")
	t.eq(copy.ranks, s.ranks, "perks round trip")
	t.eq(copy.zones_seen, 6, "explored regions round trip")
	t.eq(copy.points_available(), s.points_available(), "points follow")
	# Through JSON (floats instead of ints), as Nakama stores it.
	var through_json: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var from_json := Skills.new()
	t.check(from_json.load_dict(through_json), "a JSON round trip loads")
	t.eq(int(from_json.xp["woodcutting"]), int(s.xp["woodcutting"]), "xp survives JSON")
	t.eq(from_json.rank("sharp_axe"), 1, "perks survive JSON")
	# Old characters without a skill sheet are handled by the server; an empty sheet is the start.
	var fresh := Skills.new()
	t.check(fresh.load_dict({"v": 1, "xp": {}}), "an empty sheet is a new character")
	t.eq(fresh.total_level(), Skills.SKILLS.size(), "all level 1")


func _data_consistency(t) -> void:
	t.current = "forged data"
	var good := Skills.new()
	good.add_xp("melee", Skills.xp_for_level(8))
	good.buy_perk("heavy_hands")
	var base: Dictionary = good.to_dict()
	var target := Skills.new()
	target.add_xp("mining", 500)
	var snapshot: Dictionary = target.to_dict()

	var cases := {
		"wrong version": func(d: Dictionary) -> void: d["v"] = 2,
		"missing xp": func(d: Dictionary) -> void: d.erase("xp"),
		"xp not a dictionary": func(d: Dictionary) -> void: d["xp"] = [1, 2],
		"unknown skill": func(d: Dictionary) -> void: d["xp"]["hacking"] = 10,
		"negative xp": func(d: Dictionary) -> void: d["xp"]["melee"] = -1,
		"fractional xp": func(d: Dictionary) -> void: d["xp"]["melee"] = 10.5,
		"xp over the cap": func(d: Dictionary) -> void: d["xp"]["melee"] = Skills.MAX_XP + 1,
		"infinite xp": func(d: Dictionary) -> void: d["xp"]["melee"] = INF,
		"text xp": func(d: Dictionary) -> void: d["xp"]["melee"] = "99999",
		"unknown perk": func(d: Dictionary) -> void: d["ranks"]["god_mode"] = 1,
		"rank above the maximum": func(d: Dictionary) -> void: d["ranks"]["heavy_hands"] = 6,
		"negative rank": func(d: Dictionary) -> void: d["ranks"]["heavy_hands"] = -1,
		"perk below its level": func(d: Dictionary) -> void: d["ranks"]["executioner"] = 1,
		"perk without its prerequisite": func(d: Dictionary) -> void:
			d["xp"]["woodcutting"] = Skills.MAX_XP
			d["ranks"]["forest_master"] = 1,
		"more perks than points": func(d: Dictionary) -> void:
			d["xp"]["melee"] = Skills.xp_for_level(25)
			d["ranks"]["heavy_hands"] = 5
			d["ranks"]["precision"] = 5
			d["ranks"]["executioner"] = 1,
		"zones out of range": func(d: Dictionary) -> void: d["zones"] = 9999,
		"ranks not a dictionary": func(d: Dictionary) -> void: d["ranks"] = "all",
	}
	for case_name in cases:
		var data: Dictionary = base.duplicate(true)
		cases[case_name].call(data)
		var victim := Skills.new()
		victim.add_xp("mining", 500)
		t.check(not victim.load_dict(data), "rejected: %s" % case_name)
		t.eq(victim.to_dict(), snapshot, "unchanged after rejecting: %s" % case_name)
	t.check(not Skills.new().load_dict("not a dictionary"), "text is not a skill sheet")
	t.check(not Skills.new().load_dict(null), "null is not a skill sheet")
