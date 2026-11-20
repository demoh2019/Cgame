extends RefCounted
## Every kind of action trains its own skill on the real server, bonuses change what the server does, and
## nothing trains from actions that were refused.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Skills = preload("res://scripts/shared/skills.gd")
const SkillsTest = preload("res://tests/test_skills.gd")
const Gateway = preload("res://scripts/server/nakama_gateway.gd")


func _ticks(server, seconds: float) -> void:
	for i in int(seconds * Defs.TICK_RATE):
		server.tick(1.0 / Defs.TICK_RATE)


func _put(server, peer: int, x: float, z: float) -> void:
	server.players[peer].position = Vector3(x, server.world.height_at(x, z), z)


func _find_node(world, kind: String, tier: int) -> Dictionary:
	for cx in range(2, 14):
		for cz in range(2, 14):
			for node in world.chunk(Vector2i(cx, cz))["nodes"]:
				if node["kind"] == kind and node["tier"] == tier and not world.is_water(node["x"], node["z"]):
					return node
	return {}


func _xp(player, skill: String) -> int:
	return int(player.skills.xp[skill])


func run(t) -> void:
	var world := WorldGen.new(42)
	_gathering(t, world)
	_combat(t, world)
	_movement(t, world)
	_consumables(t, world)
	_crafting_and_loot(t, world)
	_damage_taken(t, world)
	_perks_and_health(t, world)
	_persistence(t, world)


func _gathering(t, world) -> void:
	t.current = "gathering trains its skill"
	var server := GameServer.new(world, 1)
	var p = server.add_player(10, "Gatherer")
	var kinds := {"tree": "woodcutting", "rock": "mining", "bush": "foraging"}
	for kind in kinds:
		var node: Dictionary = _find_node(world, kind, 1)
		t.check(not node.is_empty(), "found a tier 1 %s" % kind)
		if node.is_empty():
			continue
		_put(server, 10, node["x"] - 1.5, node["z"])
		var before := _xp(p, kinds[kind])
		var started: Dictionary = server.cmd_gather(10, node["id"])
		t.check(started["ok"], "%s can be gathered by hand: %s" % [kind, str(started)])
		_ticks(server, 12.0)
		t.check(_xp(p, kinds[kind]) > before, "%s trains %s (%d -> %d)" % [kind, kinds[kind], before, _xp(p, kinds[kind])])
		for other in kinds.values():
			if other != kinds[kind]:
				pass
	t.check(_xp(p, "melee") == 0 and _xp(p, "slayer") == 0, "gathering trains nothing in combat")

	t.current = "gathering gives nothing when refused"
	var tree: Dictionary = _find_node(world, "tree", 1)
	var q = server.add_player(11, "Refused")
	_put(server, 11, tree["x"] + 40.0, tree["z"])
	t.check(not server.cmd_gather(11, tree["id"])["ok"], "too far to gather")
	_ticks(server, 6.0)
	t.eq(_xp(q, "woodcutting"), 0, "no xp for a refused gather")
	server.depleted[tree["id"]] = server.time + 100.0
	_put(server, 11, tree["x"] - 1.5, tree["z"])
	t.eq(server.cmd_gather(11, tree["id"])["reason"], "depleted", "depleted node")
	t.eq(_xp(q, "woodcutting"), 0, "no xp for a depleted node")
	server.depleted.erase(tree["id"])

	t.current = "gathering bonuses"
	var fast = server.add_player(12, "Fast")
	var slow = server.add_player(13, "Slow")
	SkillsTest.level_to(fast.skills, "woodcutting", 30)
	var node: Dictionary = _find_node(world, "tree", 1)
	_put(server, 12, node["x"] - 1.5, node["z"])
	_put(server, 13, node["x"] - 1.5, node["z"])
	var fast_seconds: float = server.cmd_gather(12, node["id"])["seconds"]
	var slow_seconds: float = server.cmd_gather(13, node["id"])["seconds"]
	t.check(fast_seconds < slow_seconds * 0.75, "a level 30 woodcutter is faster (%.2f s vs %.2f s)" % [fast_seconds, slow_seconds])
	t.near(slow_seconds / fast_seconds, 1.0 + fast.skills.bonus("gather_speed.woodcutting"), 0.001, "exactly by the skill bonus")
	# More yield: with a guaranteed bonus the average harvest is bigger.
	var lucky := GameServer.new(world, 5)
	var lp = lucky.add_player(20, "Lucky")
	SkillsTest.level_to(lp.skills, "woodcutting", 50)
	lp.skills.ranks["timber_luck"] = 4
	var plain := GameServer.new(world, 5)
	var pp = plain.add_player(21, "Plain")
	var lucky_total := 0
	var plain_total := 0
	for i in 200:
		lucky._finish_gather(lp, {"kind": "tree", "tier": 1, "id": 7000 + i})
		plain._finish_gather(pp, {"kind": "tree", "tier": 1, "id": 7000 + i})
		lucky_total += lp.inventory.count("wood_1")
		plain_total += pp.inventory.count("wood_1")
		lp.inventory.remove("wood_1", lp.inventory.count("wood_1"))
		pp.inventory.remove("wood_1", pp.inventory.count("wood_1"))
	t.check(lucky_total > plain_total * 1.06, "a lucky lumberjack gets more wood (%d vs %d over 200 trees)" % [lucky_total, plain_total])


func _combat(t, world) -> void:
	t.current = "combat trains melee and slayer"
	var server := GameServer.new(world, 2)
	var p = server.add_player(30, "Fighter")
	p.inventory.add("club_2", 1)
	p.inventory.equip("club_2")
	_put(server, 30, 200.0, 200.0)
	var zombie := Zombie.new(server.new_id(), "walker", Vector3(201.5, world.height_at(201.5, 200.0), 200.0))
	server.zombies[zombie.id] = zombie
	server.cmd_attack(30, -1.0, 0.0)
	t.eq(_xp(p, "melee"), 0, "swinging at nothing teaches nothing")
	_ticks(server, 1.0)
	var melee_before := _xp(p, "melee")
	var swing: Dictionary = server.cmd_attack(30, 1.0, 0.0)
	t.check(swing["hit"], "hit the zombie")
	t.check(_xp(p, "melee") > melee_before, "a hit trains melee")
	t.eq(_xp(p, "marksman"), 0, "and not marksman")
	var kills := 0
	for i in 12:
		if not zombie.is_alive():
			break
		_ticks(server, 1.0)
		zombie.position = Vector3(201.5, world.height_at(201.5, 200.0), 200.0)
		p.position = Vector3(200.0, world.height_at(200.0, 200.0), 200.0)
		p.survival.health = 100.0
		server.cmd_attack(30, 1.0, 0.0)
	t.check(not zombie.is_alive(), "the zombie died")
	t.check(_xp(p, "slayer") >= int(Defs.ZOMBIES["walker"]["xp"]) * 2, "a kill trains slayer (%d)" % _xp(p, "slayer"))

	t.current = "pistol trains marksman and ammo is saved"
	var shooter = server.add_player(31, "Shooter")
	shooter.inventory.add("pistol", 1)
	shooter.inventory.equip("pistol")
	shooter.inventory.add("ammo_9mm", 50)
	_put(server, 31, 300.0, 300.0)
	var target := Zombie.new(server.new_id(), "brute", Vector3(310.0, world.height_at(310.0, 300.0), 300.0))
	server.zombies[target.id] = target
	_ticks(server, 1.0)
	server.cmd_attack(31, 1.0, 0.0)
	t.check(_xp(shooter, "marksman") > 0 and _xp(shooter, "melee") == 0, "a bullet trains marksman only")
	# Damage bonuses are applied by the server: a master of the pistol hurts more.
	var master = server.add_player(32, "Master")
	master.inventory.add("pistol", 1)
	master.inventory.equip("pistol")
	master.inventory.add("ammo_9mm", 50)
	SkillsTest.level_to(master.skills, "marksman", 50)
	master.skills.ranks["steady_aim"] = 5
	_put(server, 32, 400.0, 400.0)
	var dummy := Zombie.new(server.new_id(), "brute", Vector3(410.0, world.height_at(410.0, 400.0), 400.0))
	server.zombies[dummy.id] = dummy
	var dummy2 := Zombie.new(server.new_id(), "brute", Vector3(310.0, world.height_at(310.0, 300.0), 301.5))
	server.zombies[dummy2.id] = dummy2
	_ticks(server, 1.0)
	var plain_before: float = target.health
	server.cmd_attack(32, 1.0, 0.0)
	var master_damage: float = float(Defs.ZOMBIES["brute"]["health"]) - dummy.health
	var plain_damage: float = float(Defs.ZOMBIES["brute"]["health"]) - plain_before + 0.0
	t.check(master_damage > Combat_damage_of_pistol() * 1.3, "a marksman master does clearly more damage (%.1f)" % master_damage)
	# Ammo saving: with a high chance the stack lasts longer.
	var save_server := GameServer.new(world, 9)
	var saver = save_server.add_player(40, "Saver")
	saver.inventory.add("pistol", 1)
	saver.inventory.equip("pistol")
	saver.inventory.add("ammo_9mm", 60)
	SkillsTest.level_to(saver.skills, "marksman", 50)
	saver.skills.ranks["thrifty_shooter"] = 5
	_put(save_server, 40, 300.0, 300.0)
	for i in 40:
		saver.attack_timer = 0.0
		save_server.cmd_attack(40, 1.0, 0.0)
	var used: int = 60 - saver.inventory.count("ammo_9mm")
	t.check(used < 40 and used > 15, "some bullets are saved (%d of 40 used, bonus %.0f%%)" % [used, saver.skills.bonus("ammo_save") * 100.0])


func Combat_damage_of_pistol() -> float:
	return 22.0


func _movement(t, world) -> void:
	t.current = "running and exploring"
	var server := GameServer.new(world, 3)
	var p = server.add_player(50, "Runner")
	_put(server, 50, 20.0, 0.0)
	var seq := 0
	var athletics_before := _xp(p, "athletics")
	var explorer_before := _xp(p, "explorer")
	var start: Vector3 = p.position
	for i in 120:
		seq += 1
		server.tick(0.05)
		server.submit_input(50, seq, 1.0, 0.0, true, 0.0, 0.05)
		if p.survival.stamina < 30.0:
			p.survival.stamina = 100.0
	var distance: float = Vector2(p.position.x - start.x, p.position.z - start.z).length()
	var athletics: int = _xp(p, "athletics") - athletics_before
	t.check(distance > 20.0, "the runner covered ground (%.1f m)" % distance)
	t.check(abs(athletics - int(distance / GameServer.SKILL_METERS_PER_ATHLETICS_XP)) <= 1, "athletics is distance / %d m (%d xp for %.1f m)" % [int(GameServer.SKILL_METERS_PER_ATHLETICS_XP), athletics, distance])
	t.check(_xp(p, "explorer") - explorer_before >= int(distance / GameServer.SKILL_METERS_PER_EXPLORER_XP) - 1, "travel trains explorer")
	# Walking trains explorer but not athletics.
	var walker = server.add_player(51, "Walker")
	_put(server, 51, 20.0, 20.0)
	for i in 120:
		seq += 1
		server.tick(0.05)
		server.submit_input(51, seq, 1.0, 0.0, false, 0.0, 0.05)
	t.eq(_xp(walker, "athletics"), 0, "walking is not running")
	t.check(_xp(walker, "explorer") > 0, "but it is exploring")
	# No stamina: the sprint is refused, so no athletics.
	var tired = server.add_player(52, "Tired")
	_put(server, 52, 20.0, 40.0)
	tired.survival.stamina = 0.0
	for i in 60:
		seq += 1
		server.tick(0.05)
		tired.survival.stamina = 0.0
		server.submit_input(52, seq, 1.0, 0.0, true, 0.0, 0.05)
	t.eq(_xp(tired, "athletics"), 0, "a sprint without stamina trains nothing")
	# Standing still never trains anything.
	var idle = server.add_player(53, "Idle")
	_ticks(server, 20.0)
	t.eq(_xp(idle, "athletics") + _xp(idle, "explorer"), 0, "standing still trains nothing")
	# Speed bonus: the server moves a fast character further, by exactly the bonus.
	var fast = server.add_player(54, "Fast")
	var normal = server.add_player(55, "Normal")
	SkillsTest.level_to(fast.skills, "athletics", 50)
	fast.skills.ranks["swift_feet"] = 5
	_put(server, 54, 20.0, 60.0)
	_put(server, 55, 20.0, 80.0)
	var fast_start: Vector3 = fast.position
	var normal_start: Vector3 = normal.position
	for i in 60:
		seq += 1
		server.tick(0.05)
		server.submit_input(54, seq, 1.0, 0.0, false, 0.0, 0.05)
		server.submit_input(55, seq, 1.0, 0.0, false, 0.0, 0.05)
	var fast_distance: float = Vector2(fast.position.x - fast_start.x, fast.position.z - fast_start.z).length()
	var normal_distance: float = Vector2(normal.position.x - normal_start.x, normal.position.z - normal_start.z).length()
	t.near(fast_distance / normal_distance, 1.0 + fast.skills.bonus("move_speed"), 0.02, "the athlete moves exactly the bonus faster (%.1f vs %.1f m)" % [fast_distance, normal_distance])

	t.current = "exploring new regions"
	var explorer = server.add_player(56, "Explorer")
	_put(server, 56, 300.0, 0.0) # Yellow region.
	var before := _xp(explorer, "explorer")
	_ticks(server, 0.5)
	var first: int = _xp(explorer, "explorer") - before
	t.check(first >= 40, "entering a new region is rewarded (%d xp)" % first)
	_put(server, 56, 10.0, 0.0)
	_ticks(server, 0.5)
	var again_before := _xp(explorer, "explorer")
	_put(server, 56, 300.0, 0.0)
	_ticks(server, 0.5)
	t.eq(_xp(explorer, "explorer"), again_before, "the same region pays only once")


func _consumables(t, world) -> void:
	t.current = "eating, drinking and healing"
	var server := GameServer.new(world, 4)
	var p = server.add_player(60, "Eater")
	p.inventory.add("canned_food", 3)
	p.inventory.add("water_bottle", 3)
	p.inventory.add("bandage", 3)
	# Full: no xp for stuffing yourself.
	p.survival.hunger = 100.0
	p.survival.thirst = 100.0
	server.cmd_use(60, "canned_food")
	server.cmd_use(60, "water_bottle")
	t.eq(_xp(p, "survivalist"), 0, "eating and drinking while full teaches nothing")
	p.survival.hunger = 40.0
	p.survival.thirst = 40.0
	server.cmd_use(60, "canned_food")
	t.check(_xp(p, "survivalist") > 0, "eating when hungry trains survivalist")
	var after_food := _xp(p, "survivalist")
	server.cmd_use(60, "water_bottle")
	t.check(_xp(p, "survivalist") > after_food, "drinking when thirsty too")
	# Bandage at full health does nothing and teaches nothing.
	p.survival.health = p.survival.max_health
	t.eq(server.cmd_use(60, "bandage")["reason"], "no_effect", "a bandage on a healthy player is refused")
	t.eq(_xp(p, "medic"), 0, "no medic xp for a refused bandage")
	p.survival.health = 40.0
	t.check(server.cmd_use(60, "bandage")["ok"], "a bandage heals")
	t.check(_xp(p, "medic") > 0, "healing trains medic")
	# Heal power and food power change the numbers.
	var medic = server.add_player(61, "Medic")
	var plain = server.add_player(62, "Plain")
	SkillsTest.level_to(medic.skills, "medic", 50)
	medic.skills.ranks["field_medic"] = 5
	SkillsTest.level_to(medic.skills, "survivalist", 50)
	medic.skills.ranks["nutrition"] = 4
	for who in [medic, plain]:
		who.inventory.add("bandage", 1)
		who.inventory.add("canned_food", 1)
		who.survival.health = 20.0
		who.survival.hunger = 10.0
	medic.dirty_skills = true
	server._apply_skill_bonuses(medic)
	server.cmd_use(61, "bandage")
	server.cmd_use(62, "bandage")
	server.cmd_use(61, "canned_food")
	server.cmd_use(62, "canned_food")
	t.check(medic.survival.health - 20.0 > (plain.survival.health - 20.0) * 1.5, "a medic heals more (%.0f vs %.0f)" % [medic.survival.health - 20.0, plain.survival.health - 20.0])
	t.check(medic.survival.hunger - 10.0 > (plain.survival.hunger - 10.0) * 1.2, "good nutrition restores more")
	# Slower hunger: the same time costs a survivalist less.
	var slow = server.add_player(63, "Slow")
	var fast = server.add_player(64, "Fast")
	SkillsTest.level_to(slow.skills, "survivalist", 50)
	slow.skills.ranks["iron_stomach"] = 5
	slow.skills.ranks["camel"] = 5
	server._apply_skill_bonuses(slow)
	for who in [slow, fast]:
		who.survival.hunger = 80.0
		who.survival.thirst = 80.0
	for i in 200:
		slow.survival.tick(1.0)
		fast.survival.tick(1.0)
	t.check(80.0 - slow.survival.hunger < (80.0 - fast.survival.hunger) * 0.6, "a survivalist gets hungry slower (%.1f vs %.1f lost)" % [80.0 - slow.survival.hunger, 80.0 - fast.survival.hunger])
	t.check(80.0 - slow.survival.thirst < (80.0 - fast.survival.thirst) * 0.6, "and thirsty slower")


func _crafting_and_loot(t, world) -> void:
	t.current = "crafting"
	var server := GameServer.new(world, 5)
	var p = server.add_player(70, "Maker")
	p.inventory.add("wood_1", 40)
	_put(server, 70, GameServer.WORKBENCH_POSITION.x + 2.0, GameServer.WORKBENCH_POSITION.y)
	t.check(server.cmd_craft(70, "plank_1", 3)["ok"], "craft planks")
	var xp_after: int = _xp(p, "crafting")
	t.check(xp_after > 0, "crafting trains crafting (%d)" % xp_after)
	t.eq(server.cmd_craft(70, "bar_1", 1)["ok"], false, "missing materials is refused")
	t.eq(_xp(p, "crafting"), xp_after, "a failed craft teaches nothing")
	_put(server, 70, 100.0, 100.0)
	server.cmd_craft(70, "plank_1", 1)
	t.eq(_xp(p, "crafting"), xp_after, "crafting away from the bench teaches nothing")
	# Refunds.
	var thrifty := GameServer.new(world, 6)
	var tp = thrifty.add_player(71, "Thrifty")
	SkillsTest.level_to(tp.skills, "crafting", 50)
	tp.skills.ranks["thrifty_maker"] = 5
	tp.skills.ranks["master_hand"] = 1
	tp.inventory.add("wood_1", 100)
	_put(thrifty, 71, GameServer.WORKBENCH_POSITION.x + 2.0, GameServer.WORKBENCH_POSITION.y)
	var made := 0
	for i in 30:
		tp.inventory.add("wood_1", 2)
		var before: int = tp.inventory.count("wood_1")
		if thrifty.cmd_craft(71, "plank_1", 1)["ok"]:
			made += 1
			if tp.inventory.count("wood_1") > before - 2:
				pass
	var wood_spent: int = 100 + 60 - tp.inventory.count("wood_1")
	t.check(wood_spent < made * 2, "a thrifty crafter saves materials (%d wood for %d planks)" % [wood_spent, made])

	t.current = "scavenging"
	var crate := {}
	for cx in range(8, 30):
		for cz in range(8, 30):
			var data: Dictionary = world.chunk(Vector2i(cx, cz))
			if crate.is_empty() and data["crates"].size() > 0:
				crate = data["crates"][0]
	var looter = server.add_player(72, "Looter")
	_put(server, 72, crate["x"] - 1.0, crate["z"])
	t.eq(_xp(looter, "scavenging"), 0, "nothing yet")
	t.check(server.cmd_loot(72, crate["id"])["ok"], "search the crate")
	t.check(_xp(looter, "scavenging") >= 12, "searching trains scavenging (%d)" % _xp(looter, "scavenging"))
	var xp_crate := _xp(looter, "scavenging")
	t.eq(server.cmd_loot(72, crate["id"])["reason"], "empty", "an empty crate")
	t.eq(_xp(looter, "scavenging"), xp_crate, "an empty crate teaches nothing")
	# Silver bonus on the same crate and rng.
	var rich_server := GameServer.new(world, 7)
	var poor_server := GameServer.new(world, 7)
	var rich = rich_server.add_player(73, "Rich")
	var poor = poor_server.add_player(73, "Poor")
	SkillsTest.level_to(rich.skills, "scavenging", 50)
	rich.skills.ranks["keen_eye"] = 5
	_put(rich_server, 73, crate["x"] - 1.0, crate["z"])
	_put(poor_server, 73, crate["x"] - 1.0, crate["z"])
	rich_server.cmd_loot(73, crate["id"])
	poor_server.cmd_loot(73, crate["id"])
	t.check(rich.inventory.count("silver") > poor.inventory.count("silver") * 1.5, "a scavenger finds more silver (%d vs %d)" % [rich.inventory.count("silver"), poor.inventory.count("silver")])


func _damage_taken(t, world) -> void:
	t.current = "damage taken"
	var server := GameServer.new(world, 8)
	var p = server.add_player(80, "Tank")
	var applied: float = server._hurt_player(p, 10.0)
	t.near(applied, 10.0, 0.0001, "no reduction at the start")
	t.check(_xp(p, "toughness") > 0, "damage trains toughness (%d)" % _xp(p, "toughness"))
	var dead = server.add_player(81, "Dead")
	dead.survival.hurt(1000.0)
	var before := _xp(dead, "toughness")
	server._hurt_player(dead, 50.0)
	t.eq(_xp(dead, "toughness"), before, "the dead learn nothing")
	var armored = server.add_player(82, "Armored")
	SkillsTest.level_to(armored.skills, "toughness", 50)
	armored.skills.ranks["thick_skin"] = 5
	armored.skills.ranks["unbreakable"] = 1
	server._apply_skill_bonuses(armored)
	var reduced: float = server._hurt_player(armored, 20.0)
	t.near(reduced, 20.0 * (1.0 - armored.skills.bonus("damage_reduction")), 0.001, "damage is reduced by the bonus (%.1f of 20)" % reduced)
	t.check(reduced < 14.0, "a toughness master takes much less damage")
	# The xp per hit is bounded, so a huge hit does not level instantly.
	var big = server.add_player(83, "Big")
	big.survival.health = 5000.0
	big.survival.max_health = 5000.0
	var before_big := _xp(big, "toughness")
	server._hurt_player(big, 4000.0)
	t.check(_xp(big, "toughness") - before_big <= 6, "xp per hit is capped (%d)" % (_xp(big, "toughness") - before_big))


func _perks_and_health(t, world) -> void:
	t.current = "perks and health"
	var server := GameServer.new(world, 10)
	var p = server.add_player(90, "Buyer")
	t.eq(server.cmd_perk(90, "vitality")["reason"], "need_level", "no perk at level 1")
	t.eq(server.cmd_perk(90, "nonsense")["reason"], "unknown_perk", "unknown perk")
	t.eq(server.cmd_perk(999, "vitality")["reason"], "no_player", "unknown player")
	t.near(p.survival.max_health, Defs.MAX_HEALTH, 0.0001, "base health")
	SkillsTest.level_to(p.skills, "toughness", 20)
	server._apply_skill_bonuses(p)
	var health_at_20: float = p.survival.max_health
	t.check(health_at_20 > Defs.MAX_HEALTH + 10.0, "toughness levels raise max health (%.1f)" % health_at_20)
	p.survival.health = 50.0
	var before_health: float = p.survival.health
	var bought: Dictionary = server.cmd_perk(90, "vitality")
	t.check(bought["ok"], "buy Vitality: %s" % str(bought))
	t.near(p.survival.max_health, health_at_20 + 6.0, 0.001, "it adds 6 max health")
	t.near(p.survival.health, before_health + 6.0, 0.001, "and the new health is there at once")
	t.eq(bought["points"], p.skills.points_available(), "the remaining points are reported")
	# Respawn keeps the bonus.
	p.survival.hurt(5000.0)
	server._on_player_death(p, -1)
	server._spawn_player(p)
	t.near(p.survival.health, p.survival.max_health, 0.001, "respawn at the raised maximum")
	t.check(p.survival.max_health > Defs.MAX_HEALTH, "the bonus survives death")
	# Events tell the player.
	var seen_perk := false
	server.events.clear()
	SkillsTest.level_to(p.skills, "melee", 5)
	server._award(p, "melee", Skills.xp_to_next(5) + 1.0)
	for event in server.events:
		if event["type"] == "skill_up" and event["skill"] == "melee":
			seen_perk = true
	t.check(seen_perk, "a level up produces a skill_up event")
	server._flush_xp(p)
	var flushed := false
	for event in server.events:
		if event["type"] == "xp" and event["peer"] == 90:
			flushed = event["gains"].has("melee")
	t.check(flushed, "xp gains are reported in one message")
	var snapshot: Dictionary = server.snapshot_for(90)
	t.check(snapshot.has("skills") and snapshot["skills"].has("points"), "the snapshot carries the skill sheet")
	t.near(float(snapshot["you"]["max_health"]), p.survival.max_health, 0.001, "and the maximum health")
	t.near(float(snapshot["you"]["speed_bonus"]), p.skills.bonus("move_speed"), 0.0001, "and the speed bonus for prediction")
	t.check(not server.snapshot_for(90).has("skills"), "the sheet is not resent every snapshot")
	server.time += 4.0
	t.check(server.snapshot_for(90).has("skills"), "but it is repeated after a few seconds in case a snapshot was lost")


func _persistence(t, world) -> void:
	t.current = "skills are saved with the character"
	var server := GameServer.new(world, 11)
	var p = server.add_player(100, "Saver", "uid-saver")
	SkillsTest.level_to(p.skills, "melee", 25)
	SkillsTest.level_to(p.skills, "toughness", 25)
	p.skills.ranks["heavy_hands"] = 3
	p.skills.ranks["vitality"] = 2
	server._apply_skill_bonuses(p)
	p.survival.health = p.survival.max_health
	var data: Dictionary = server.character_data(p)
	t.check(data.has("skills"), "the character holds a skill sheet")
	var through_json: Dictionary = Gateway.whole_numbers_as_ints(JSON.parse_string(JSON.stringify(data)))
	t.check(server.valid_character_data(through_json), "it survives JSON and validates")
	var restored = server.add_player(101, "Restored", "uid-restored", through_json)
	t.eq(restored.skills.xp, p.skills.xp, "xp restored")
	t.eq(restored.skills.ranks, p.skills.ranks, "perks restored")
	t.near(restored.survival.max_health, p.survival.max_health, 0.001, "max health restored")
	t.check(restored.survival.max_health > Defs.MAX_HEALTH, "the bonus is active after loading")
	t.near(restored.survival.health, p.survival.health, 0.01, "health above 100 is accepted when skills explain it")
	# Old characters.
	var legacy: Dictionary = through_json.duplicate(true)
	legacy.erase("skills")
	var old = server.add_player(102, "Old", "uid-old", legacy)
	t.eq(old.skills.total_level(), Skills.SKILLS.size(), "a character from before skills starts at level 1")
	t.near(old.survival.max_health, Defs.MAX_HEALTH, 0.001, "with the normal health")
	# Forgeries are refused as a whole.
	var forged: Dictionary = through_json.duplicate(true)
	forged["skills"]["xp"]["melee"] = -5
	t.check(not server.valid_character_data(forged), "a forged skill sheet makes the whole character invalid")
	var rich: Dictionary = through_json.duplicate(true)
	rich["skills"]["ranks"]["forest_master"] = 1
	t.check(not server.valid_character_data(rich), "perks without the level are refused")
	var tough: Dictionary = through_json.duplicate(true)
	tough["health"] = 5000.0
	t.check(not server.valid_character_data(tough), "health beyond anything skills can give is refused")
	var live = server.add_player(103, "Live", "uid-live")
	SkillsTest.level_to(live.skills, "mining", 10)
	var before: Dictionary = live.skills.to_dict()
	t.check(not server.apply_character(live, forged), "a refused load")
	t.eq(live.skills.to_dict(), before, "leaves the live skills untouched")
