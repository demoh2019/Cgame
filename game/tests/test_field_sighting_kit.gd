extends RefCounted
## Paid ranged preparation: only server-confirmed infected hits spend charges.
const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const FieldSightingKit = preload("res://scripts/shared/field_sighting_kit.gd")
const RangedCover = preload("res://scripts/shared/ranged_cover.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _open_lane(world) -> Vector2:
	# Terrain cover is real; don't assume arbitrary coordinates are fire lanes.
	for offset in 45:
		var origin := Vector2(800.0, float(offset - 22) * 19.0)
		if world.zone_at(origin.x, origin.y) != 2 or world.is_water(origin.x, origin.y):
			continue
		if world.is_water(origin.x + 15.0, origin.y):
			continue
		if RangedCover.first_blocker_distance(world, origin, Vector2.RIGHT, 27.0) == INF:
			return origin
	return Vector2.INF


func _at(world, at: Vector2) -> Vector3:
	return Vector3(at.x, world.height_at(at.x, at.y), at.y)


func run(t) -> void:
	t.current = "sighting: crafting catalog and owned ranged equipment"
	var kit: Dictionary = Defs.item(FieldSightingKit.ITEM_ID)
	t.eq(kit.get("kind"), "sighting_kit", "consumable is registered")
	t.eq(Defs.recipes()[FieldSightingKit.ITEM_ID]["inputs"],
		{"bar_1": 1, "fiber_1": 2, "scrap": 2}, "requires real metal, fiber and salvage")
	t.eq(Defs.recipes()[FieldSightingKit.ITEM_ID]["station"], "workbench",
		"precision preparation requires workbench")
	var world := WorldGen.new(713)
	var lane: Vector2 = _open_lane(world)
	t.check(lane.is_finite(), "open authoritative firing lane exists")
	if not lane.is_finite():
		return
	var server := GameServer.new(world, 713)
	var hunter = server.add_player(130, "Scout")
	t.eq(server.cmd_use(130, FieldSightingKit.ITEM_ID).get("reason"), "not_carried",
		"no item cannot prepare a ranged weapon")
	hunter.inventory.add(FieldSightingKit.ITEM_ID, 2)
	t.eq(server.cmd_use(130, FieldSightingKit.ITEM_ID).get("reason"), "need_ranged",
		"cannot use the kit unarmed")
	hunter.inventory.add("club_1", 1)
	t.check(hunter.inventory.equip("club_1"), "real melee weapon equipped")
	t.eq(server.cmd_use(130, FieldSightingKit.ITEM_ID).get("reason"), "need_ranged",
		"melee cannot obtain ranged buff")
	hunter.inventory.add("bow_1", 1)
	t.check(hunter.inventory.equip("bow_1"), "crafted-style bow equipped")
	hunter.attack_timer = 1.0
	t.eq(server.cmd_use(130, FieldSightingKit.ITEM_ID).get("reason"), "in_combat",
		"active weapon cooldown prevents preparation")
	t.eq(hunter.inventory.count(FieldSightingKit.ITEM_ID), 2, "failed use is free")
	hunter.attack_timer = 0.0
	t.check(bool(server.cmd_use(130, FieldSightingKit.ITEM_ID).get("ok", false)),
		"server consumes one physical sighting kit")
	t.eq(hunter.inventory.count(FieldSightingKit.ITEM_ID), 1, "single kit spent")
	t.eq(hunter.sighted_hits, FieldSightingKit.HITS, "exactly four charges issued")
	t.eq(server.cmd_use(130, FieldSightingKit.ITEM_ID).get("reason"), "already_sighted",
		"replay cannot refresh partially unused charge stack")

	t.current = "sighting: ammo, misses, real infected and skill exclusions"
	hunter.position = _at(world, lane)
	t.eq(server.cmd_attack(130, 1.0, 0.0).get("reason"), "no_ammo",
		"unloaded ranged weapon cannot spend calibration")
	t.eq(hunter.sighted_hits, FieldSightingKit.HITS, "missing ammo preserves charges")
	hunter.attack_timer = 0.0
	hunter.inventory.add("arrow", 16)
	var brute := Zombie.new(server.new_id(), "brute", _at(world, lane + Vector2(9.0, 0.0)))
	server.zombies[brute.id] = brute
	var miss: Dictionary = server.cmd_attack(130, -1.0, 0.0)
	t.check(bool(miss.get("ok", false)) and not bool(miss.get("hit", true)),
		"real fired miss is still a legal attack")
	t.eq(hunter.sighted_hits, FieldSightingKit.HITS, "miss does not spend bonus")
	hunter.attack_timer = 0.0
	var before_health: float = brute.health
	var first: Dictionary = server.cmd_attack(130, 1.0, 0.0)
	t.eq(first.get("target", ""), "zombie", "server ray selects living infected")
	t.near(before_health - brute.health,
		Combat.weapon_damage("bow_1") * FieldSightingKit.DAMAGE_FACTOR,
		0.001, "calibrated bow deals 12 percent extra infected damage")
	t.eq(hunter.sighted_hits, 3, "confirmed hit spends precisely one charge")
	hunter.attack_timer = 0.0
	hunter.skill_timer = 0.0
	server.cmd_skill(130, 1.0, 0.0)
	t.eq(hunter.sighted_hits, 3, "active weapon skills cannot spend ordinary-sight charges")

	t.current = "sighting: strict version-one save and owner-only state"
	var saved: Dictionary = server.character_data(hunter)
	t.check(server.valid_character_data(saved), "legitimate save validates")
	t.eq(saved["sighted_hits"], 3, "remaining count saved without refresh")
	hunter.sighted_weapon = ""
	hunter.sighted_hits = 0
	t.check(server.apply_character(hunter, saved), "owned ranged preparation can reload")
	t.eq(hunter.sighted_hits, 3, "reload restores exact charge remainder")
	t.eq(int(server.snapshot_for(130)["you"]["sighted_hits"]), 3,
		"owner privately sees remaining bonuses")
	var forged: Dictionary = saved.duplicate(true)
	forged["sighted_hits"] = 5
	t.check(not server.apply_character(hunter, forged), "extra charges are rejected")
	t.eq(hunter.sighted_hits, 3, "invalid save is atomic")
	forged = saved.duplicate(true)
	forged["sighted_hits"] = 1.5
	t.check(not server.apply_character(hunter, forged), "fractional charges rejected")
	forged = saved.duplicate(true)
	forged["sighted_weapon"] = "pistol"
	t.check(not server.apply_character(hunter, forged), "unowned ghost firearm rejected")

	t.current = "sighting: PvP, three remaining hits and equipment swap"
	server.zombies.clear()
	var rival = server.add_player(131, "Rival")
	rival.position = _at(world, lane + Vector2(9.0, 0.0))
	hunter.attack_timer = 0.0
	var player_shot: Dictionary = server.cmd_attack(130, 1.0, 0.0)
	t.eq(player_shot.get("target", ""), "player", "PvP is server-verified in red zone")
	t.eq(hunter.sighted_hits, 3, "PvP receives and spends no PvE bonus")
	hunter.combat_tag_until = 0.0
	rival.position = _at(world, lane + Vector2(-30.0, 0.0))
	var second := Zombie.new(server.new_id(), "brute", _at(world, lane + Vector2(9.0, 0.0)))
	server.zombies[second.id] = second
	for remaining in [2, 1, 0]:
		hunter.attack_timer = 0.0
		var strike: Dictionary = server.cmd_attack(130, 1.0, 0.0)
		t.eq(strike.get("target", ""), "zombie", "verified repeat ranged hit")
		t.eq(hunter.sighted_hits, remaining, "charge decrements once per hit")
	t.eq(hunter.sighted_weapon, "", "exhaustion clears prepared weapon")
	hunter.attack_timer = 0.0
	before_health = second.health
	server.cmd_attack(130, 1.0, 0.0)
	t.near(before_health - second.health, Combat.weapon_damage("bow_1"),
		0.001, "unprepared ranged hit reverts to standard damage")
	hunter.attack_timer = 0.0
	hunter.combat_tag_until = 0.0 # Fights now set a short combat tag; preparing waits for it.
	hunter.skill_timer = 0.0
	t.check(bool(server.cmd_use(130, FieldSightingKit.ITEM_ID).get("ok", false)),
		"remaining kit can prepare after charges are spent")
	hunter.inventory.add("crossbow_1", 1)
	t.check(bool(server.cmd_use(130, "crossbow_1").get("ok", false)),
		"server swaps to physically carried crossbow")
	t.eq(hunter.sighted_hits, 0, "swapping weapon clears calibration")
	t.eq(hunter.sighted_weapon, "", "no stale prepared weapon")
	var old: Dictionary = server.character_data(hunter)
	old.erase("sighted_weapon")
	old.erase("sighted_hits")
	t.check(server.apply_character(hunter, old), "old version-one characters still load")
	t.eq(hunter.sighted_hits, 0, "legacy saves grant no free ranged bonus")
