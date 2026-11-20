extends RefCounted
## Craft, placement, world-owned fuse and nonduplicating barricade damage.
## Run through the real GameServer inventory and multiplayer event gates.

const Defs = preload("res://scripts/shared/defs.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const SiegeCharge = preload("res://scripts/shared/siege_charge.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, site: Vector2) -> Vector3:
	return Vector3(site.x, world.height_at(site.x, site.y), site.y)


func _build_site(world) -> Vector2:
	# Search for a truly clear, level red-zone wall site, not a hardcoded
	# coordinate that can overlap new generated rocks/roads/ruins.
	for x in range(660, 1050, 16):
		for z in range(-200, 201, 16):
			var site := Vector2(float(x), float(z))
			if world.zone_at(site.x, site.y) != 2:
				continue
			if world.is_water(site.x, site.y) or world.normal_at(
					site.x, site.y).y < Structures.MIN_SLOPE_NORMAL_Y:
				continue
			var left: Vector2 = site + Vector2(-2.8, 0.0)
			var right: Vector2 = site + Vector2(2.8, 0.0)
			if world.is_water(left.x, left.y) or world.is_water(right.x, right.y):
				continue
			var clear: bool = true
			for obstacle in world.blockers_near(site.x, site.y, 5.0):
				if site.distance_to(Vector2(float(obstacle["x"]),
						float(obstacle["z"]))) < float(obstacle["radius"]) + 3.6:
					clear = false
					break
			if clear:
				return site
	return Vector2.INF


func run(t) -> void:
	t.current = "a tier-three siege charge consumes advanced crafting materials"
	t.eq(Defs.item(SiegeCharge.ITEM_ID).get("kind", ""), "siege_charge",
		"dedicated item type routes via normal inventory use")
	t.eq(int(Defs.item(SiegeCharge.ITEM_ID).get("tier", 0)), 3,
		"high-tier attack equipment requires advanced mastery")
	var recipe: Dictionary = Defs.recipes().get(SiegeCharge.ITEM_ID, {})
	t.eq(str(recipe.get("station", "")), "workbench",
		"charge is fabricated at a workbench")
	t.eq(recipe.get("inputs", {}), {"bar_3": 2, "scrap": 8,
		"cloth_2": 2, "stone_2": 2}, "explicit finite advanced-material bill")
	var bag := Inventory.new()
	for item in recipe["inputs"]:
		bag.add(str(item), int(recipe["inputs"][item]))
	t.eq(Crafting.craft(bag, SiegeCharge.ITEM_ID, false),
		Crafting.Result.NO_STATION, "cannot construct siege gear in wilderness")
	t.eq(Crafting.craft(bag, SiegeCharge.ITEM_ID, true),
		Crafting.Result.OK, "bench crafts one physical siege charge")
	t.eq(bag.count(SiegeCharge.ITEM_ID), 1, "one paid charge exists")
	t.eq(bag.count("bar_3"), 0, "refined metal is consumed")
	t.eq(Crafting.craft(bag, SiegeCharge.ITEM_ID, true),
		Crafting.Result.MISSING_INPUTS, "craft replay cannot mint extra explosives")

	t.current = "real server selects nearby hostile barricade, no client target ids"
	var world := WorldGen.new(319)
	var server := GameServer.new(world, 319)
	var site: Vector2 = _build_site(world)
	t.check(site.is_finite(), "a safe clear red-zone construction site was found")
	if not site.is_finite():
		return
	var builder = server.add_player(401, "Defender", "wall-owner")
	var raider = server.add_player(402, "Besieger", "raider-account")
	var ally = server.add_player(403, "Defender Ally", "ally-account")
	var spectator = server.add_player(404, "Spectator")
	builder.guild_id = "castle-guild"
	ally.guild_id = "castle-guild"
	raider.guild_id = "enemy-guild"
	builder.position = _at(world, site + Vector2(-2.8, 0.0))
	raider.position = _at(world, site + Vector2(2.8, 0.0))
	ally.position = _at(world, site + Vector2(-16.0, 0.0))
	spectator.position = _at(world, site + Vector2(300.0, 0.0))
	builder.inventory.add("wood_1", 12)
	builder.inventory.add("stone_1", 6)
	var built: Dictionary = server.cmd_build(builder.id, site.x, site.y)
	t.check(bool(built.get("ok", false)), "real T1 barricade built and paid for")
	if not bool(built.get("ok", false)):
		return
	var wall_id: int = int(built["id"])
	t.eq(str(server.barricades[wall_id].get("owner_guild", "")),
		"castle-guild", "real wall tracks trusted build-time guild")
	t.eq(server.cmd_use(raider.id, SiegeCharge.ITEM_ID).get("reason", ""),
		"not_carried", "no remote spoofing consumables")

	raider.inventory.add(SiegeCharge.ITEM_ID, 4)
	builder.inventory.add(SiegeCharge.ITEM_ID, 1)
	t.eq(server.cmd_use(builder.id, SiegeCharge.ITEM_ID).get("reason", ""),
		"protected_wall", "owner cannot waste a charge against own structure")
	t.eq(builder.inventory.count(SiegeCharge.ITEM_ID), 1,
		"owner denial does not consume their charge")
	ally.position = _at(world, site + Vector2(-2.8, 0.0))
	ally.inventory.add(SiegeCharge.ITEM_ID, 1)
	t.eq(server.cmd_use(ally.id, SiegeCharge.ITEM_ID).get("reason", ""),
		"protected_wall", "verified guildmate cannot plant against ally")
	t.eq(ally.inventory.count(SiegeCharge.ITEM_ID), 1,
		"guild protection does not burn explosives")
	ally.position = _at(world, site + Vector2(-16.0, 0.0))
	raider.position = _at(world, site + Vector2(40.0, 0.0))
	t.eq(server.cmd_use(raider.id, SiegeCharge.ITEM_ID).get("reason", ""),
		"no_wall_nearby", "remote use cannot plant charges")
	raider.position = _at(world, site + Vector2(2.8, 0.0))
	var stone_id: int = 94440
	world.add_dynamic_blocker(stone_id, site.x + 1.5, site.y, 0.35)
	t.eq(server.cmd_use(raider.id, SiegeCharge.ITEM_ID).get("reason", ""),
		"blocked", "other physical cover prevents planting through a solid")
	t.eq(raider.inventory.count(SiegeCharge.ITEM_ID), 4,
		"blocked placement is fully atomic")
	world.remove_dynamic_blocker(stone_id)

	t.current = "charge arming is paid, bounded, local and server-owned"
	var health_before: float = float(server.barricades[wall_id]["hp"])
	var placed: Dictionary = server.cmd_use(raider.id, SiegeCharge.ITEM_ID)
	t.check(bool(placed.get("ok", false)), "legal enemy siege charge can be planted")
	if not bool(placed.get("ok", false)):
		return
	var charge_id: int = int(placed["id"])
	t.eq(server.siege_charges.size(), 1, "one transient charge exists")
	t.eq(int(server.siege_charges[charge_id]["wall"]), wall_id,
		"server freezes authentic target id")
	t.eq(raider.inventory.count(SiegeCharge.ITEM_ID), 3,
		"planting consumes one purchased charge exactly once")
	t.near(float(server.siege_charges[charge_id]["until"]) - server.time,
		SiegeCharge.FUSE_SECONDS, 0.001, "fuse is a server clock deadline")
	t.eq(server.cmd_use(raider.id, SiegeCharge.ITEM_ID).get("reason", ""),
		"owner_limit", "replayed or stacked charge from same user denied")
	t.eq(raider.inventory.count(SiegeCharge.ITEM_ID), 3,
		"denied placement has no inventory cost")
	var other = server.add_player(405, "Second Raider", "other-account")
	other.position = _at(world, site + Vector2(2.8, 0.0))
	other.inventory.add(SiegeCharge.ITEM_ID, 1)
	t.eq(server.cmd_use(other.id, SiegeCharge.ITEM_ID).get("reason", ""),
		"wall_armed", "a second raider cannot stack charges on same wall")
	var armed: Array = server.events.filter(func(event):
		return str(event.get("type", "")) == "siege_charge_armed")
	t.eq(armed.size(), 1, "one warning is broadcast for the paid charge")
	if not armed.is_empty():
		var net := Net.new()
		net.role = "server"
		net.sim = server
		t.check(net._event_visible_to(armed[0], raider.id),
			"local attacker sees the fuse warning")
		t.check(net._event_visible_to(armed[0], builder.id),
			"local defender receives reaction time")
		t.check(not net._event_visible_to(armed[0], spectator.id),
			"distant spectator cannot track hidden base locations")
		net.free()

	t.current = "server tick explodes once, respects HP and releases blocking"
	server.time = SiegeCharge.FUSE_SECONDS - 0.1
	server._tick_siege_charges()
	t.near(float(server.barricades[wall_id]["hp"]), health_before,
		0.001, "early processing cannot blow up a wall")
	server.tick(0.15)
	t.eq(server.siege_charges.size(), 0, "armed charge removed before detonation")
	t.check(not server.barricades.has(wall_id), "160 raw damage destroys a T1 barricade")
	t.check(not world.dynamic_blockers.has(wall_id),
		"destroyed wall immediately frees world movement and firing lanes")
	var blast: Array = server.events.filter(func(event):
		return str(event.get("type", "")) == "siege_charge_detonated")
	t.eq(blast.size(), 1, "exactly one detonation event is emitted")
	if not blast.is_empty():
		t.check(bool(blast[0].get("broken", false)),
			"detonation acknowledges actual wall destruction")
	t.eq(server.decoys.size(), 1, "detonation creates one positional sound lure")
	for sound in server.decoys.values():
		t.near(float(sound["x"]), site.x, 0.001,
			"infected hear the actual wall, never a nearby fake player")
		t.near(float(sound["z"]), site.y, 0.001, "detonation sound has exact wall location")
		t.near(float(sound["expires"]) - server.time, SiegeCharge.NOISE_SECONDS,
			0.001, "detonation sound is short and server-timed")
	t.near(raider.noise_timer, 0.0, 0.001,
		"explosion does not falsely mark adjacent survivors noisy")
	var blast_count: int = blast.size()
	server._tick_siege_charges()
	t.eq(server.events.filter(func(event):
		return str(event.get("type", "")) == "siege_charge_detonated").size(),
		blast_count, "reprocessing the fuse cannot double-damage or re-award")

	t.current = "reinforced T4 wall survives blast, no position spoofing"
	var another: Dictionary = server.cmd_build(builder.id, site.x, site.y)
	t.check(bool(another.get("ok", false)), "owner can rebuild after first wall is destroyed")
	if not bool(another.get("ok", false)):
		return
	var second_wall_id: int = int(another["id"])
	server.barricades[second_wall_id]["tier"] = 4
	server.barricades[second_wall_id]["hp"] = 600.0
	var next: Dictionary = server.cmd_use(raider.id, SiegeCharge.ITEM_ID)
	t.check(bool(next.get("ok", false)), "attacker can rearm after earlier fuse resolved")
	if not bool(next.get("ok", false)):
		return
	server.time += SiegeCharge.FUSE_SECONDS
	server._tick_siege_charges()
	t.near(float(server.barricades[second_wall_id]["hp"]), 520.0, 0.001,
		"existing tier-four mitigation halves a 160 raw damage charge")
	t.eq(raider.inventory.count(SiegeCharge.ITEM_ID), 2,
		"two real detonations cost exactly two charges")

	t.current = "removed wall fizzles pending blast, no zombie/player kill credit"
	var final: Dictionary = server.cmd_use(raider.id, SiegeCharge.ITEM_ID)
	t.check(bool(final.get("ok", false)), "one more real charge is planted")
	if not bool(final.get("ok", false)):
		return
	var kill_before: int = raider.kills
	t.check(server.damage_barricade(second_wall_id, 5000.0),
		"defender's wall can be destroyed before the fuse expires")
	server.time += SiegeCharge.FUSE_SECONDS
	server._tick_siege_charges()
	t.eq(server.siege_charges.size(), 0, "orphaned explosive is cleaned up")
	t.check(not server.barricades.has(second_wall_id),
		"old wall is never recreated or awarded by a stale charge")
	t.eq(raider.kills, kill_before, "siege blast cannot mint PvE kill rewards")
	var fizzles: Array = server.events.filter(func(event):
		return str(event.get("type", "")) == "siege_charge_fizzled")
	t.eq(fizzles.size(), 1, "an expired target produces one harmless fizzle")
