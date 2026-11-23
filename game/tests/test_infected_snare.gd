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


## Exercises the real server tick, preserving exactly the same trap
## placement/expiry/one-shot state between accelerated and scalar execution.
static func _run_dense_snare_tick(force_fallback: bool) -> Dictionary:
	var sim := GameServer.new(WorldGen.new(778), 778)
	sim.tick_count = 2 # No population or steering rebuild this tick.
	if force_fallback:
		# A valid old-engine substitute has no new cross-set query method.
		sim._pack_spatial_grid = RefCounted.new()
	for i in range(32):
		var x: float = 350.0 if i <= 2 else (390.0 if i == 3 else (
			470.0 if i == 5 else 1000.0 + float(i) * 20.0))
		var z: float = 350.0 if i <= 3 or i == 5 else 1000.0
		var infected := Zombie.new(60000 + i, "walker",
			Vector3(x, WorldGen.HUB_HEIGHT, z))
		infected.think_timer = 100.0
		infected._ai_has_selected_once = true
		infected.raid_boss = i == 0
		sim.zombies[infected.id] = infected
	for j in range(8):
		var point := Vector2(350.0, 350.0) if j == 0 else (
			Vector2(390.0, 350.0) if j == 1 else (
			Vector2(470.0, 350.0) if j == 2 else
			Vector2(5000.0 + float(j) * 10.0, 6000.0)))
		sim.infected_snares[70000 + j] = {
			"id": 70000 + j, "x": point.x, "z": point.y,
			"expires": 0.0 if j == 2 else 100.0,
		}
	sim._tick_zombies(0.05)
	var fired: Array = []
	for event in sim.events:
		if event.get("type", "") == "snare_triggered":
			fired.append({"id": int(event["id"]), "zombie": int(event["zombie"])})
	return {
		"fired": fired, "remaining": sim.infected_snares.keys(),
		"stats": sim.get_snare_query_stats(),
		"first_root": sim.zombies[60001].snared_seconds,
		"duplicate_root": sim.zombies[60002].snared_seconds,
		"second_root": sim.zombies[60003].snared_seconds,
		"boss_root": sim.zombies[60000].snared_seconds,
		"expired_root": sim.zombies[60005].snared_seconds,
	}


func run(t) -> void:
	t.current = "Native cross-set snare broadphase keeps scalar authoritative results"
	var scalar: Dictionary = _run_dense_snare_tick(true)
	var accelerated: Dictionary = _run_dense_snare_tick(false)
	var cross_available: bool = ClassDB.class_exists("AIProximityGrid2D") \
		and ClassDB.instantiate("AIProximityGrid2D").has_method("query_cross_radius_batch")
	t.eq(bool(scalar["stats"]["native"]), false,
		"old-engine control always uses the exhaustive trap loop")
	t.eq(bool(accelerated["stats"]["native"]), cross_available,
		"real dense encounter automatically selects native cross-set broadphase")
	t.eq(accelerated["fired"], scalar["fired"],
		"spatial optimization preserves actual one-shot trap event order")
	t.eq(accelerated["remaining"], scalar["remaining"],
		"native candidates cannot consume additional or expired traps")
	t.eq(accelerated["fired"], [
		{"id": 70000, "zombie": 60001}, {"id": 70001, "zombie": 60003}
	], "bosses cannot trip snares and first eligible infected owns each hit")
	t.check(float(accelerated["first_root"]) > 0.0 \
		and float(accelerated["second_root"]) > 0.0,
		"both real infected are rooted only after authoritative catches")
	t.eq(accelerated["duplicate_root"], 0.0,
		"later infected never consume an already removed trap")
	t.eq(accelerated["boss_root"], 0.0,
		"raid boss is not rooted even when the native grid returns its position")
	t.eq(accelerated["expired_root"], 0.0,
		"expired spatial candidates fail final authoritative trigger rules")
	if cross_available:
		t.eq(int(accelerated["stats"]["population"]), 32,
			"native batch includes the actual simulation cohort")
		t.eq(int(accelerated["stats"]["traps"]), 8,
			"native batch includes every server-owned trap")
		t.check(int(accelerated["stats"]["candidates"]) < 32 * 8,
			"native broadphase prunes distant checks before exact trigger evaluation")
	else:
		t.eq(int(accelerated["stats"]["candidates"]), 0,
			"older engine binaries expose no fabricated native statistics")

	t.current = "Original placement, ownership and lifetime regressions"

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
	t.current = "corrupt snare state cannot trigger roots or leak bogus markers"
	var clean_visible: Array = InfectedSnare.visible({777: trap}, elite.position,
		server.time, 4.0)
	t.eq(clean_visible.size(), 1, "valid trap remains visible to nearby survivors")
	t.check(not clean_visible[0].has("expires") and not clean_visible[0].has("owner_key"),
		"ordinary trap markers still redact private owner and expiry data")
	for impossible_expiry in [NAN, INF, "never"]:
		var bad_expiry: Dictionary = trap.duplicate(true)
		bad_expiry["expires"] = impossible_expiry
		t.check(not InfectedSnare.catches(bad_expiry, elite, server.time),
			"corrupt expiry never authorizes a snare root")
		t.eq(InfectedSnare.visible({777: bad_expiry}, elite.position,
			server.time, 4.0), [],
			"corrupt expiry never reaches player snapshots")
	var bad_location: Dictionary = trap.duplicate(true)
	bad_location["x"] = NAN
	t.check(not InfectedSnare.catches(bad_location, elite, server.time),
		"non-finite trap coordinates never trigger PvE control")
	t.eq(InfectedSnare.visible({777: bad_location}, elite.position,
		server.time, 4.0), [], "non-finite markers are suppressed")
	bad_location = trap.duplicate(true)
	bad_location["y"] = INF
	t.eq(InfectedSnare.visible({777: bad_location}, elite.position,
		server.time, 4.0), [], "bad marker altitude is not sent to clients")
	for bad_radius in [NAN, INF, -1.0, 0.0]:
		t.eq(InfectedSnare.visible({777: trap}, elite.position,
			server.time, bad_radius), [],
			"invalid/negative observer radius cannot reveal field traps")
	t.eq(InfectedSnare.visible({777: trap}, elite.position, INF, 4.0), [],
		"invalid simulation timestamp cannot reveal a trap")
	t.check(not InfectedSnare.catches(trap, elite, NAN),
		"invalid world time cannot trigger a trap")

	t.current = "elite roots are shorter, usage caps and lifetime cleanup"
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
