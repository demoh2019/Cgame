extends RefCounted
## Deployable PvE snares must be paid for, temporary, spatially bounded,
## private to owner limits and never root players or raid bosses.
const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const InfectedSnare = preload("res://scripts/shared/infected_snare.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _open_site(world) -> Dictionary:
	for x in range(200, 264, 4):
		for z in range(120, 184, 4):
			var origin := Vector2(float(x), float(z))
			for dir in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
				var site: Vector2 = origin + dir * 2.8
				if InfectedSnare.valid_site(world, site, origin, {}) == "":
					return {"origin": origin, "site": site}
	return {}


func _at(world, at: Vector2) -> Vector3:
	return Vector3(at.x, world.height_at(at.x, at.y), at.y)


func run(t) -> void:
	t.current = "craftable trap catalog and inventory transaction"
	t.check(Defs.is_item(InfectedSnare.ITEM_ID), "tripwire is a real item")
	t.eq(Defs.item(InfectedSnare.ITEM_ID).get("kind", ""), "deployable",
		"tripwire cannot be used as food, medicine or a weapon")
	t.check(Defs.recipes().has(InfectedSnare.ITEM_ID), "craft recipe is registered")
	var recipe: Dictionary = Defs.recipes()[InfectedSnare.ITEM_ID]
	t.eq(recipe["inputs"], {"wood_1": 2, "fiber_1": 2, "scrap": 1},
		"trap consumes wood, fiber and scavenged scrap")
	t.eq(recipe["station"], "", "field construction requires no workbench")
	var inventory := Inventory.new()
	inventory.add("wood_1", 2)
	inventory.add("fiber_1", 2)
	t.eq(Crafting.craft(inventory, InfectedSnare.ITEM_ID, false),
		Crafting.Result.MISSING_INPUTS, "missing scrap prevents crafting")
	t.eq(inventory.count("wood_1"), 2, "failed craft debits nothing")
	inventory.add("scrap", 1)
	t.eq(Crafting.craft(inventory, InfectedSnare.ITEM_ID, false),
		Crafting.Result.OK, "real materials craft one tripwire")
	t.eq(inventory.count(InfectedSnare.ITEM_ID), 1, "crafted kit enters inventory")
	t.eq(inventory.count("scrap"), 0, "crafting consumes actual scrap")

	t.current = "server-authorized wilderness placement and safe rejection"
	var world := WorldGen.new(261)
	var server := GameServer.new(world, 261)
	var scout = server.add_player(601, "Scout", "test-account")
	var pair: Dictionary = _open_site(world)
	t.check(not pair.is_empty(), "deterministic open terrain supports a trap")
	if pair.is_empty():
		return
	var origin: Vector2 = pair["origin"]
	var point: Vector2 = pair["site"]
	scout.position = _at(world, origin)
	t.eq(InfectedSnare.valid_site(world, Vector2(NAN, 0.0), origin, {}),
		"invalid_position", "nonfinite trap placement cannot be forged")
	t.eq(InfectedSnare.valid_site(world, origin, origin, {}), "out_of_range",
		"cannot place wire directly under survivor")
	t.eq(InfectedSnare.valid_site(world, origin + Vector2(60.0, 0.0), origin, {}),
		"out_of_range", "placement must be close to survivor")
	t.eq(server.cmd_place_infected_snare(912, point.x, point.y).get("reason", ""),
		"dead", "unauthenticated player cannot construct a trap")
	t.eq(server.cmd_place_infected_snare(scout.id, NAN, point.y).get("reason", ""),
		"invalid_position", "server refuses nonfinite coordinates")
	t.eq(server.cmd_place_infected_snare(scout.id, point.x, point.y).get("reason", ""),
		"not_carried", "server will not mint free trap kit")
	t.eq(server.infected_snares.size(), 0, "invalid requests change no world objects")
	scout.inventory.add(InfectedSnare.ITEM_ID, 2)
	var result: Dictionary = server.cmd_place_infected_snare(scout.id, point.x, point.y)
	t.check(result.get("ok", false), "valid paid wilderness placement succeeds")
	if not result.get("ok", false):
		return
	var id: int = int(result["id"])
	t.eq(scout.inventory.count(InfectedSnare.ITEM_ID), 1,
		"successful placement consumes exactly one carried kit")
	t.eq(server.infected_snares.size(), 1, "one physical snare is server-created")
	t.check(scout.dirty_inventory and scout.dirty_character,
		"paid deployment requests an account inventory save")
	t.eq(server.cmd_place_infected_snare(scout.id, point.x, point.y).get("reason", ""),
		"blocked", "cannot stack traps in a single spot")
	t.eq(scout.inventory.count(InfectedSnare.ITEM_ID), 1,
		"blocked placement never consumes additional kit")
	var visible: Array = server.snapshot_for(scout.id).get("infected_snares", [])
	t.eq(visible.size(), 1, "trap is replicated to nearby network players")
	t.check(not visible[0].has("owner_key") and not visible[0].has("expires"),
		"snapshot never discloses account ID or absolute expiry")
	t.near(float(visible[0]["remaining"]), InfectedSnare.DURATION, 0.0001,
		"clients see only public remaining lifetime")
	var far = server.add_player(602, "Away")
	far.position = _at(world, Vector2(-500.0, -500.0))
	t.eq(server.snapshot_for(far.id)["infected_snares"].size(), 0,
		"distant clients do not receive another region's traps")
	t.check(not server.character_data(scout).has("infected_snares"),
		"temporary traps are never included in persistent character data")

	t.current = "only the first non-boss infected triggers the snare"
	var boss := Zombie.new(server.new_id(), "walker", _at(world, point))
	boss.raid_boss = true
	server.zombies[boss.id] = boss
	server._tick_zombies(0.1)
	t.eq(server.infected_snares.size(), 1, "raid bosses cannot consume tripwires")
	t.eq(boss.snared_seconds, 0.0, "raid bosses remain mobile")
	server.zombies.erase(boss.id)
	var trapped := Zombie.new(server.new_id(), "walker", _at(world, point))
	server.zombies[trapped.id] = trapped
	server._tick_zombies(0.1)
	t.eq(server.infected_snares.size(), 0, "one infected consumes the trap exactly once")
	t.check(trapped.snared_seconds > 2.7, "ordinary infected is rooted for three seconds")
	var stuck_at: Vector3 = trapped.position
	trapped._move_toward(world, Vector2(stuck_at.x, stuck_at.z),
		Vector2(stuck_at.x + 8.0, stuck_at.z), 4.0, 1.0)
	t.eq(trapped.position, stuck_at, "root prevents AI movement")
	t.eq(trapped.stuck_time, 0.0, "a snare cannot be mistaken for a destructible wall")
	t.check(not trapped.apply_snare(INF), "infinite root duration is denied")
	t.check(not trapped.apply_snare(999.0), "malformed huge root duration is denied")
	for i in range(35):
		trapped.think(world, {}, 0.1, server.rng)
	t.eq(trapped.snared_seconds, 0.0, "root expires after normal AI ticks")
	t.eq(server.snapshot_for(scout.id)["infected_snares"].size(), 0,
		"triggered trap disappears from network snapshot")

	t.current = "elite roots are shorter, usage caps and lifetime cleanup"
	var elite := Zombie.new(server.new_id(), "walker", _at(world, point))
	elite.become_elite()
	t.eq(InfectedSnare.root_duration(elite), 1.5, "elite infected resist full root duration")
	t.check(elite.apply_snare(InfectedSnare.root_duration(elite)),
		"elite can be briefly slowed")
	t.eq(elite.snared_seconds, InfectedSnare.ELITE_ROOT_SECONDS,
		"elite gets exactly reduced duration")
	var trap: Dictionary = {"id": 777, "x": point.x, "y": world.height_at(point.x, point.y),
		"z": point.y, "owner_key": "account:test-account",
		"expires": server.time + InfectedSnare.DURATION}
	t.check(InfectedSnare.catches(trap, elite, server.time), "elite is a legal PvE trigger")
	t.check(not InfectedSnare.catches(trap, boss, server.time), "boss cannot trigger trap")
	t.check(not InfectedSnare.catches(trap, elite, trap["expires"]),
		"expired trap cannot trigger after expiry")
	for j in InfectedSnare.MAX_PER_OWNER:
		var t_id: int = 500000 + j
		var entry: Dictionary = trap.duplicate(true)
		entry["id"] = t_id
		server.infected_snares[t_id] = entry
	t.eq(server.cmd_place_infected_snare(scout.id, point.x + 1.0, point.y).get("reason", ""),
		"owner_limit", "three active account snares prevent bypassing limits")
	t.eq(scout.inventory.count(InfectedSnare.ITEM_ID), 1,
		"denied cap request preserves inventory")
	server.time += InfectedSnare.DURATION + 1.0
	server._tick_world(0.1)
	t.eq(server.infected_snares.size(), 0, "expired snares are removed by the world clock")
