extends RefCounted
## Consumable cartography finds unopened danger-zone crates without fabricating
## loot or disclosing another survivor's personal waypoint.
const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const RuinSurvey = preload("res://scripts/shared/ruin_survey.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _danger_crate(world) -> Dictionary:
	for cx in range(8, 20):
		for cz in range(0, 16):
			var chunk: Dictionary = world.chunk(Vector2i(cx, cz))
			if int(chunk["zone"]) >= RuinSurvey.MIN_ZONE and not chunk["crates"].is_empty():
				var crate: Dictionary = chunk["crates"][0].duplicate(true)
				crate["zone"] = int(chunk["zone"])
				return crate
	return {}


func _pos(world, point: Vector2) -> Vector3:
	return Vector3(point.x, world.height_at(point.x, point.y), point.y)


func run(t) -> void:
	t.current = "survey geometry skips only provably unreachable chunks"
	var centre := Vector2(32.0, 32.0)
	t.near(RuinSurvey.cell_min_distance_squared(centre, Vector2i.ZERO),
		0.0, 0.001, "current chunk has zero distance")
	t.near(RuinSurvey.cell_min_distance_squared(centre, Vector2i(3, 0)),
		160.0 * 160.0, 0.001, "east edge computes exact lower bound")
	t.check(RuinSurvey.cell_min_distance_squared(centre, Vector2i(3, 3)) >
		RuinSurvey.SCAN_RADIUS * RuinSurvey.SCAN_RADIUS,
		"diagonal corner chunk can be skipped before world generation")
	t.check(RuinSurvey.cell_min_distance_squared(Vector2(63.9, 63.9),
		Vector2i(3, 3)) < RuinSurvey.SCAN_RADIUS * RuinSurvey.SCAN_RADIUS,
		"near a cell corner the diagonal chunk still qualifies")
	t.check(is_inf(RuinSurvey.cell_min_distance_squared(Vector2(NAN, 0), Vector2i.ZERO)),
		"invalid origin is not allowed to select world chunks")
	# For several player positions, each grid cell containing a truly
	# reachable point must survive the lower-bound cull.
	var all_kept: bool = true
	for offset in [Vector2.ZERO, Vector2(31, 9), Vector2(63, 63),
			Vector2(-9, -31), Vector2(0.5, 62.5)]:
		var location: Vector2 = Vector2(1000, 1000) + offset
		var current: Vector2i = WorldGen.cell_of(location.x, location.y)
		for dx in range(-RuinSurvey.CELL_RADIUS, RuinSurvey.CELL_RADIUS + 1):
			for dz in range(-RuinSurvey.CELL_RADIUS, RuinSurvey.CELL_RADIUS + 1):
				var checked_cell: Vector2i = current + Vector2i(dx, dz)
				var cell_origin: Vector2 = WorldGen.cell_origin(checked_cell)
				for xstep in 5:
					for zstep in 5:
						var point: Vector2 = cell_origin + Vector2(
							float(xstep) * Defs.CHUNK_SIZE / 4.0,
							float(zstep) * Defs.CHUNK_SIZE / 4.0)
						if location.distance_squared_to(point) <= RuinSurvey.SCAN_RADIUS * RuinSurvey.SCAN_RADIUS:
							if RuinSurvey.cell_min_distance_squared(location, checked_cell) >
									RuinSurvey.SCAN_RADIUS * RuinSurvey.SCAN_RADIUS:
								all_kept = false
	t.check(all_kept, "no sampled reachable crate is removed by chunk pruning")

	t.current = "real gathered-item map and bounded wilderness-only scanning"
	t.check(Defs.is_item(RuinSurvey.ITEM_ID), "craftable survey chart is a real item")
	t.eq(Defs.item(RuinSurvey.ITEM_ID)["kind"], "material",
		"chart cannot be equipped as a fake weapon")
	var recipe: Dictionary = Defs.recipes().get(RuinSurvey.ITEM_ID, {})
	t.check(not recipe.is_empty(), "cartography recipe is registered")
	t.eq(recipe["station"], "", "field chart needs no workbench")
	t.eq(recipe["inputs"], {"cloth_1": 1, "fiber_1": 2, "scrap": 1},
		"exploration costs cloth, fiber and scavenged scrap")
	var bag := Inventory.new()
	bag.add("cloth_1", 1)
	bag.add("fiber_1", 2)
	t.eq(Crafting.craft(bag, RuinSurvey.ITEM_ID, false),
		Crafting.Result.MISSING_INPUTS, "missing scrap prevents map duplication")
	t.eq(bag.count("cloth_1"), 1, "failed crafting preserves ingredients")
	bag.add("scrap", 1)
	t.eq(Crafting.craft(bag, RuinSurvey.ITEM_ID, false),
		Crafting.Result.OK, "real item is produced by field crafting")
	t.eq(bag.count(RuinSurvey.ITEM_ID), 1, "one chart crafted, not free scouting")
	t.eq(bag.count("scrap"), 0, "scavenged scrap is actually spent")

	t.current = "deterministic server search only finds live dangerous crates"
	var world := WorldGen.new(3141)
	var crate: Dictionary = _danger_crate(world)
	t.check(not crate.is_empty(), "seed generates a real dangerous ruin crate")
	if crate.is_empty():
		return
	var crate_point := Vector2(float(crate["x"]), float(crate["z"]))
	var origin: Vector3 = _pos(world, crate_point + Vector2(-18.0, 0.0))
	t.check(not world.is_safe(origin.x, origin.z), "wilderness search is outside safe town")
	t.eq(RuinSurvey.nearest(world, Vector3.INF, {}), {},
		"nonfinite spoofed player position reveals no crate")
	t.eq(RuinSurvey.nearest(world, Vector3.ZERO, {}), {},
		"protected hub cannot survey distant hostile ruins")
	var found: Dictionary = RuinSurvey.nearest(world, origin, {})
	t.check(not found.is_empty(), "hostile unopened ruin is discoverable")
	if found.is_empty():
		return
	t.check(int(found["zone"]) >= RuinSurvey.MIN_ZONE, "only red/black ruins targeted")
	t.check(origin.distance_to(_pos(world, Vector2(found["x"], found["z"]))) < 220.0,
		"survey radius prevents continent-wide scouting")
	var opened: Dictionary = {int(found["id"]): 999999.0}
	var next_found: Dictionary = RuinSurvey.nearest(world, origin, opened)
	t.check(next_found.is_empty() or int(next_found["id"]) != int(found["id"]),
		"already looted world crate cannot be targeted again")
	var mark: Dictionary = {"id": int(found["id"]), "x": found["x"],
		"z": found["z"], "zone": found["zone"], "until": 75.0}
	t.check(RuinSurvey.active(mark, 0.0, {}), "fresh marker is active")
	t.check(not RuinSurvey.active(mark, 75.0, {}), "expired waypoint is hidden")
	t.check(not RuinSurvey.active(mark, 0.0, opened), "looted waypoint is hidden")
	t.eq(RuinSurvey.public_mark(mark, 75.0, {}), {},
		"expired mark cannot leak coordinates")
	var public: Dictionary = RuinSurvey.public_mark(mark, 0.0, {})
	t.check(not public.has("id") and not public.has("until"),
		"public mark has no internal crate ID or absolute server deadline")
	t.near(float(public["remaining"]), RuinSurvey.MARK_SECONDS, 0.001,
		"only bounded remaining duration is replicated")

	t.current = "authoritative paid request, no-op checks and private owner snapshots"
	var server := GameServer.new(world, 3141)
	var scout = server.add_player(964, "Ruin Scout")
	t.eq(server.cmd_survey_ruins(999).get("reason", ""), "dead",
		"nonexistent peer cannot forge maps")
	scout.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	scout.inventory.add(RuinSurvey.ITEM_ID, 2)
	t.eq(server.cmd_survey_ruins(scout.id).get("reason", ""), "no_untouched_ruins",
		"safe-zone scanning is denied without wasting chart")
	t.eq(scout.inventory.count(RuinSurvey.ITEM_ID), 2,
		"unavailable wilderness signal never spends a map")
	scout.position = origin
	scout.inventory.remove(RuinSurvey.ITEM_ID, 2)
	t.eq(server.cmd_survey_ruins(scout.id).get("reason", ""), "not_carried",
		"no free scanned coordinates without a chart")
	t.eq(scout.ruin_survey, {}, "denied command cannot create waypoint")
	scout.inventory.add(RuinSurvey.ITEM_ID, 2)
	var result: Dictionary = server.cmd_survey_ruins(scout.id)
	t.check(result.get("ok", false), "valid wilderness chart locates a real cache")
	if not result.get("ok", false):
		return
	t.eq(scout.inventory.count(RuinSurvey.ITEM_ID), 1,
		"successful survey spends exactly one map")
	t.check(scout.dirty_inventory and scout.dirty_character,
		"item change is marked for persistent inventory save")
	t.eq(result.get("x"), scout.ruin_survey.get("x"),
		"only authoritative scanned coordinates are returned")
	t.eq(result.get("zone"), scout.ruin_survey.get("zone"),
		"tier is world-calculated, not chosen by the client")
	t.eq(server.cmd_survey_ruins(scout.id).get("reason", ""), "already_marked",
		"repeated request cannot spend second chart during an active mark")
	t.eq(scout.inventory.count(RuinSurvey.ITEM_ID), 1,
		"replay preserves remaining chart")
	var owner: Dictionary = server.snapshot_for(scout.id)["you"]["ruin_survey"]
	t.check(not owner.is_empty(), "owner sees private map destination")
	t.check(not owner.has("id") and not owner.has("until"),
		"network owner snapshot omits server-only state")
	var other = server.add_player(965, "Rival Surveyor")
	other.position = origin
	t.eq(server.snapshot_for(other.id)["you"]["ruin_survey"], {},
		"another player in the same zone cannot read this personal survey")
	t.check(not server.character_data(scout).has("ruin_survey"),
		"one-use waypoint is never serialized to account data")

	t.current = "crate use, expiration and death erase personal marker"
	var target := Vector2(float(scout.ruin_survey["x"]), float(scout.ruin_survey["z"]))
	var target_id: int = int(scout.ruin_survey["id"])
	scout.position = _pos(world, target + Vector2(-1.0, 0.0))
	var opened_result: Dictionary = server.cmd_loot(scout.id, target_id)
	t.check(opened_result.get("ok", false), "real client loot opens the surveyed crate")
	t.eq(server.snapshot_for(scout.id)["you"]["ruin_survey"], {},
		"server suppresses waypoint immediately after real crate opening")
	server._tick_players(0.1)
	t.eq(scout.ruin_survey, {}, "server drops completed navigation mark")
	scout.ruin_survey = mark.duplicate(true)
	scout.ruin_survey["id"] = 999999998
	scout.ruin_survey["until"] = server.time + 2.0
	server.time += 3.0
	server._tick_players(0.1)
	t.eq(scout.ruin_survey, {}, "time expiry cleans server-owned marker")
	scout.ruin_survey = {"id": 999999998, "x": 1.0, "z": 2.0,
		"zone": 3, "until": server.time + 60.0}
	scout.survival.hurt(1000.0)
	server._on_player_death(scout, -1)
	t.eq(scout.ruin_survey, {}, "death always cancels private survey, including full-loot")
