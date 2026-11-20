extends RefCounted
## Craftable crossbows and authoritative single-target PvE pinning bolts.
const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "all four crossbows have balanced tiered ranged stats"
	for tier in range(1, Defs.MAX_TIER + 1):
		var id: String = "crossbow_%d" % tier
		var item: Dictionary = Defs.item(id)
		var recipe: Dictionary = Defs.recipes().get(id, {})
		t.eq(item.get("kind", ""), "weapon", "crossbow is a real inventory weapon")
		t.eq(item.get("weapon", ""), "ranged", "crossbow uses ranged mastery")
		t.eq(Defs.tier_of(id), tier, "crossbow tier follows its materials")
		t.eq(item.get("ammo", ""), "arrow", "craftable arrows are spent")
		t.eq(recipe.get("station", ""), "workbench", "crossbow requires workbench")
		t.eq(recipe.get("inputs", {}), {"plank_%d" % tier: 2,
			"bar_%d" % tier: 2, "fiber_%d" % tier: 2,
			"scrap": 1}, "crossbow costs genuine wood, metal and scrap")
		t.near(Combat.weapon_damage(id), 18.0 + 10.0 * (tier - 1),
			0.001, "crossbow damage scales per tier")
		t.near(Combat.weapon_cooldown(id), 1.55, 0.001,
			"crossbow fires more slowly than a bow")
		t.near(Combat.ranged_range(id), 25.0, 0.001,
			"crossbow ordinary reach remains bounded")
		var ability: Dictionary = Combat.active_skill(id)
		t.eq(ability.get("id", ""), "pinning_bolt",
			"all crossbows grant an equipment skill")
		t.eq(ability.get("ammo", ""), "arrow",
			"special bolt consumes the same physical ammo")
		t.eq(ability.get("ranged", false), true,
			"bolts use ray line-of-fire and cover checks")
		t.near(float(ability.get("snare_seconds", -1.0)), 2.0, 0.001,
			"equipment fixes exactly two seconds of PvE immobilization")
		t.near(float(ability.get("range", -1.0)), 28.0, 0.001,
			"aimed bolt extends normal crossbow reach by three metres")
	t.eq(Combat.active_skill("bow_1").get("id", ""), "power_draw",
		"existing bows retain their distinct active skill")
	t.near(float(Combat.ranged_noise("crossbow_1")["radius"]), 12.0,
		0.001, "crossbow is louder than the conventional bow")
	t.near(float(Combat.ranged_noise("bow_1")["radius"]), 9.0,
		0.001, "existing bow remains a quieter option")

	t.current = "workbench recipe spends resources only after validation"
	var pack := Inventory.new()
	pack.add("plank_1", 2)
	pack.add("bar_1", 2)
	pack.add("fiber_1", 2)
	pack.add("scrap", 1)
	t.eq(Crafting.craft(pack, "crossbow_1", false),
		Crafting.Result.NO_STATION, "cannot build mechanical bow in the field")
	t.eq(pack.count("scrap"), 1, "rejected craft never consumes scrap")
	t.eq(Crafting.craft(pack, "crossbow_1", true),
		Crafting.Result.OK, "real workbench builds a crossbow")
	t.eq(pack.count("crossbow_1"), 1, "craft yields exactly one crossbow")
	t.eq(pack.count("scrap"), 0, "craft consumes mechanical scrap")
	t.eq(Crafting.craft(pack, "crossbow_1", true),
		Crafting.Result.MISSING_INPUTS, "duplicate craft cannot mint gear")

	t.current = "server-authorized crafting and ammunition"
	var world := WorldGen.new(781)
	var server := GameServer.new(world, 781)
	var hunter = server.add_player(901, "CrossbowHunter")
	hunter.inventory = Inventory.new()
	hunter.inventory.add("plank_1", 2)
	hunter.inventory.add("bar_1", 2)
	hunter.inventory.add("fiber_1", 2)
	hunter.inventory.add("scrap", 1)
	hunter.position = _at(world, 200.0, 200.0)
	t.eq(server.cmd_craft(901, "crossbow_1").get("reason", ""),
		"no_station", "remote craft cannot bypass workbench")
	t.eq(server.cmd_craft(901, "crossbow_4").get("reason", ""),
		"need_skill", "high tier requires learned crafting")
	hunter.position = _at(world, GameServer.WORKBENCH_POSITION.x,
		GameServer.WORKBENCH_POSITION.y)
	t.check(server.cmd_craft(901, "crossbow_1").get("ok", false),
		"server grants properly crafted crossbow")
	t.check(hunter.inventory.equip("crossbow_1"),
		"only carried crossbows can be equipped")
	hunter.position = _at(world, 200.0, 200.0)
	t.eq(server.cmd_skill(901, 1.0, 0.0).get("reason", ""),
		"no_ammo", "zero arrows block pinning without cost")
	t.near(hunter.combat_energy, 100.0, 0.001,
		"missing arrows spend no skill energy")
	t.near(hunter.skill_timer, 0.0, 0.001,
		"missing arrows cannot start cooldown")
	t.near(hunter.noise_timer, 0.0, 0.001,
		"missing arrows never reveal survivor position")

	t.current = "normal shot deals damage but cannot immobilize"
	hunter.inventory.add("arrow", 5)
	var brute := Zombie.new(server.new_id(), "brute",
		_at(world, 220.0, 200.0))
	server.zombies[brute.id] = brute
	var health_before: float = brute.health
	var shot: Dictionary = server.cmd_attack(901, 1.0, 0.0)
	t.check(shot.get("ok", false) and shot.get("hit", false),
		"ordinary crossbow arrow hits along server line-of-fire")
	t.near(brute.health, health_before - Combat.weapon_damage("crossbow_1"),
		0.001, "ordinary hit uses true crossbow damage")
	t.near(brute.snared_seconds, 0.0, 0.001,
		"ordinary bolts do not give free crowd control")
	t.eq(hunter.inventory.count("arrow"), 4,
		"normal crossbow shot consumes one arrow")
	t.near(hunter.attack_timer, 1.55, 0.001,
		"normal shot locks the heavy mechanical trigger")
	t.near(hunter.noise_radius, 12.0, 0.001,
		"normal bolt draws more infected than a bow")

	t.current = "special bolt pins verified living infected with a single arrow"
	hunter.attack_timer = 0.0
	health_before = brute.health
	var pin: Dictionary = server.cmd_skill(901, 1.0, 0.0)
	t.check(pin.get("ok", false) and pin.get("hit", false),
		"pinning skill resolves an authentic ranged hit")
	t.eq(pin.get("hits", 0), 1, "pinning attack affects at most one target")
	t.near(brute.health, health_before -
		Combat.weapon_damage("crossbow_1") * 1.35,
		0.001, "special bolt applies equipment-derived damage")
	t.near(brute.snared_seconds, 2.0, 0.001,
		"only a living infected hit receives server-owned root")
	t.eq(hunter.inventory.count("arrow"), 3, "special bolt spends one arrow")
	t.near(hunter.combat_energy, 68.0, 0.001,
		"special attack spends 32 combat energy")
	t.near(hunter.skill_timer, 7.5, 0.001,
		"special attack starts its own cooldown")
	t.eq(server.cmd_skill(901, 1.0, 0.0).get("reason", ""),
		"cooldown", "replays cannot repeat pinning or ammo consumption")
	var pin_visible: float = -1.0
	for entry in server.snapshot_for(901)["zombies"]:
		if int(entry["id"]) == brute.id:
			pin_visible = float(entry.get("snared_seconds", -1.0))
	t.near(pin_visible, 2.0, 0.001,
		"existing server snapshots replicate the true root timer")
	var found_event := false
	for event in server.drain_events():
		if event.get("type", "") == "pinning_bolt":
			found_event = true
			t.eq(int(event["id"]), brute.id,
				"pin effect announces the actually hit enemy")
	t.check(found_event, "pinning effect is visible to clients")

	t.current = "immobilization expires without disabling infected attacks"
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	brute.target_id = hunter.id
	brute.state = Zombie.State.CHASE
	var origin: Vector3 = brute.position
	var active: Dictionary = {hunter.id: {"position": hunter.position,
		"alive": true, "safe": false, "noise": 0.0}}
	brute.think(world, active, 0.5, rng)
	t.near(brute.position.x, origin.x, 0.001,
		"immobilized infected cannot walk towards the hunter")
	t.near(brute.snared_seconds, 1.5, 0.001,
		"server tick advances the root duration")
	brute.think(world, active, 1.5, rng)
	t.near(brute.snared_seconds, 0.0, 0.001,
		"root expires rather than permanently trapping enemy")

	t.current = "raid bosses never root, despite still receiving shot damage"
	server.zombies.erase(brute.id)
	var boss := Zombie.new(server.new_id(), "brute",
		_at(world, 220.0, 200.0))
	boss.raid_boss = true
	server.zombies[boss.id] = boss
	hunter.attack_timer = 0.0
	hunter.skill_timer = 0.0
	var boss_health: float = boss.health
	t.check(server.cmd_skill(901, 1.0, 0.0).get("hit", false),
		"raid boss can still receive projectile damage")
	t.check(boss.health < boss_health, "boss takes normal ranged damage")
	t.near(boss.snared_seconds, 0.0, 0.001,
		"boss is immune to hard movement control")
	t.eq(hunter.inventory.count("arrow"), 2,
		"boss immunity does not refund a legitimate projectile")

	t.current = "invalid skill, no ammo and safe-zone PvP remain protected"
	server.zombies.clear()
	hunter.attack_timer = 0.0
	hunter.skill_timer = 0.0
	t.eq(server.cmd_skill(901, NAN, 0.0).get("reason", ""),
		"no_direction", "bad client direction is rejected")
	hunter.combat_energy = 31.0
	t.eq(server.cmd_skill(901, 1.0, 0.0).get("reason", ""),
		"no_energy", "insufficient combat energy blocks skill")
	hunter.combat_energy = 100.0
	t.check(hunter.inventory.remove("crossbow_1", 1),
		"owned weapon can be removed")
	t.eq(server.cmd_skill(901, 1.0, 0.0).get("reason", ""),
		"no_skill", "ghost equipped crossbow cannot trigger pinning")
	t.near(hunter.combat_energy, 100.0, 0.001,
		"rejected ghost attack leaves energy unchanged")
	hunter.inventory.add("crossbow_1", 1)
	t.check(hunter.inventory.equip("crossbow_1"), "equip actual carried weapon")
	var protected = server.add_player(902, "Protected")
	hunter.position = _at(world, 8.0, 0.0)
	protected.position = _at(world, 10.0, 0.0)
	var safe_health: float = protected.survival.health
	var safe_shot: Dictionary = server.cmd_skill(901, 1.0, 0.0)
	t.check(safe_shot.get("ok", false) and not safe_shot.get("hit", true),
		"pinning cannot damage protected players in safe hub")
	t.near(protected.survival.health, safe_health, 0.001,
		"safe-zone PvP immunity is preserved")
