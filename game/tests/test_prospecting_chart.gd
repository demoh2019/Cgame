extends RefCounted
## Geological prospecting: genuine terrain, resource depletion, paid scouting,
## private owner-only snapshots, safe ranges and automatic waypoint cancellation.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Rules = preload("res://scripts/shared/prospecting_chart.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Radar = preload("res://scripts/client/survival_radar.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


## Locate a real rich vein for the seeded world rather than fabricating one.
func _real_vein(world) -> Dictionary:
	for cx in range(8, 20):
		for cz in range(0, 16):
			var chunk: Dictionary = world.chunk(Vector2i(cx, cz))
			for node in chunk["nodes"]:
				if str(node["kind"]) in ["ore", "rock"] and int(node["tier"]) >= Rules.MIN_TIER:
					return node
	return {}


func run(t) -> void:
	t.current = "craftable one-use geological chart uses real materials"
	t.eq(str(Defs.item(Rules.ITEM_ID).get("kind", "")), "prospecting_chart",
		"chart is distinct from ordinary equipment and threat scanning")
	var recipe: Dictionary = Defs.recipes().get(Rules.ITEM_ID, {})
	t.eq(str(recipe.get("station", "missing")), "", "field craft needs no workbench")
	t.eq(recipe.get("inputs", {}), {"cloth_1": 1, "scrap": 2, "stone_1": 1},
		"mineral scouting costs meaningful materials")
	var craft_bag := Inventory.new()
	craft_bag.add("cloth_1", 1)
	craft_bag.add("scrap", 2)
	t.eq(Crafting.craft(craft_bag, Rules.ITEM_ID, false),
		Crafting.Result.MISSING_INPUTS, "missing stone cannot create a free chart")
	t.eq(craft_bag.count("scrap"), 2, "failed craft preserves costly scrap")
	craft_bag.add("stone_1", 1)
	t.eq(Crafting.craft(craft_bag, Rules.ITEM_ID, false),
		Crafting.Result.OK, "field craft creates a chart")
	t.eq(craft_bag.count(Rules.ITEM_ID), 1, "crafted chart is in backpack")
	t.eq(craft_bag.count("scrap"), 0, "paid craft consumes both scrap")

	t.current = "scan only living high-tier resources in real world chunks"
	var world := WorldGen.new(3141)
	var vein: Dictionary = _real_vein(world)
	t.check(not vein.is_empty(), "seeded world has a T2+ ore or rock deposit")
	if vein.is_empty():
		return
	var player_at := _at(world, float(vein["x"]) + 4.0, float(vein["z"]))
	t.check(not world.is_safe(player_at.x, player_at.z),
		"rich veins exist outside protected settlement")
	t.eq(Rules.nearest(world, Vector3.INF, {}), {},
		"non-finite origin cannot reveal world resources")
	t.eq(Rules.nearest(world, Vector3.ZERO, {}), {},
		"safe-zone player cannot explore remote deposits for free")
	var selected: Dictionary = Rules.nearest(world, player_at, {})
	t.check(not selected.is_empty(), "nearby high-tier node can be found")
	if selected.is_empty():
		return
	t.check(int(selected["tier"]) >= Rules.MIN_TIER,
		"chart never points to beginner T1 materials")
	t.check(str(selected["kind"]) in ["ore", "rock"],
		"only real geological resources are eligible")
	t.check(Vector2(player_at.x, player_at.z).distance_to(
		Vector2(float(selected["x"]), float(selected["z"]))) <= Rules.SCAN_RADIUS,
		"chart cannot scan the whole map")
	t.eq(Rules.nearest(world, player_at, {}), selected,
		"seeded searches choose a deterministic high-tier deposit")
	var excluded: Dictionary = {int(selected["id"]): 100000.0}
	var alternate: Dictionary = Rules.nearest(world, player_at, excluded)
	t.check(alternate.is_empty() or int(alternate["id"]) != int(selected["id"]),
		"depleted node can never be targeted twice")

	t.current = "server rejects free and unsafe scans"
	var server := GameServer.new(world, 3141)
	var scout = server.add_player(920, "Miner")
	var outsider = server.add_player(921, "Rival")
	scout.position = player_at
	outsider.position = player_at
	t.eq(server.cmd_use(scout.id, Rules.ITEM_ID).get("reason", ""), "not_carried",
		"server verifies physical chart in backpack")
	scout.inventory.add(Rules.ITEM_ID, 2)
	scout.position = _at(world, 5.0, 5.0)
	t.eq(server.cmd_use(scout.id, Rules.ITEM_ID).get("reason", ""), "safe_zone",
		"the hub cannot consume a wilderness map")
	scout.position = player_at
	scout.mounted = true
	t.eq(server.cmd_use(scout.id, Rules.ITEM_ID).get("reason", ""), "mounted",
		"mounted scouts must dismount")
	scout.mounted = false
	scout.combat_tag_until = server.time + 10.0
	t.eq(server.cmd_use(scout.id, Rules.ITEM_ID).get("reason", ""), "in_combat",
		"scanner cannot be spammed in combat")
	scout.combat_tag_until = 0.0
	t.eq(scout.inventory.count(Rules.ITEM_ID), 2,
		"failed command spends zero charts")

	t.current = "one chart reveals private server-owned target and exact lifetime"
	var result: Dictionary = server.cmd_use(scout.id, Rules.ITEM_ID)
	t.check(bool(result.get("ok", false)) and bool(result.get("prospecting", false)),
		"real paid scan succeeds")
	t.eq(scout.inventory.count(Rules.ITEM_ID), 1,
		"one successful scan consumes exactly one chart")
	t.eq(int(scout.prospect_mark.get("id", -1)), int(selected["id"]),
		"server chooses correct real resource ID")
	t.eq(server.cmd_use(scout.id, Rules.ITEM_ID).get("reason", ""),
		"already_marked", "repeat request cannot waste a second chart")
	t.eq(scout.inventory.count(Rules.ITEM_ID), 1,
		"replayed scan does not duplicate charges")
	var personal: Dictionary = server.snapshot_for(scout.id)["you"]["prospect_mark"]
	t.eq(personal.get("tier", -1), selected["tier"], "owner sees real resource tier")
	t.eq(personal.get("kind", ""), selected["kind"], "owner sees actual material type")
	t.check(not personal.has("id") and not personal.has("until"),
		"server-private resource ID and absolute deadline do not replicate")
	t.near(float(personal.get("remaining", 0.0)), Rules.MARK_SECONDS, 0.001,
		"waypoint has bounded lifetime")
	t.eq(server.snapshot_for(outsider.id)["you"].get("prospect_mark", {}), {},
		"rival at same location cannot inspect someone else's paid resource scan")
	for actor in server.snapshot_for(outsider.id)["players"]:
		t.check(not actor.has("prospect_mark"), "nearby actor snapshots remain private")
	t.check(not server.character_data(scout).has("prospect_mark"),
		"private chart mark is ephemeral, not a persistent account item")

	var radar := Radar.new()
	radar.sim = server
	radar.actor_id = scout.id
	t.eq(radar.current_prospect_mark(), personal, "offline radar uses same authoritative mark")
	radar.actor_id = outsider.id
	t.eq(radar.current_prospect_mark(), {}, "radar cannot read another player's map")
	radar.free()

	t.current = "depleted, expired, and death marks are suppressed"
	server.depleted[int(selected["id"])] = server.time + 120.0
	t.eq(server.snapshot_for(scout.id)["you"]["prospect_mark"], {},
		"resource exhaustion immediately hides marked vein")
	server._tick_players(0.1)
	t.eq(scout.prospect_mark, {}, "server cleans depleted mark for a new chart")
	server.depleted.clear()
	scout.prospect_mark = {"id": int(selected["id"]), "kind": str(selected["kind"]),
		"tier": int(selected["tier"]), "x": selected["x"], "z": selected["z"],
		"until": server.time + 1.0}
	server.time += 1.01
	t.eq(server.snapshot_for(scout.id)["you"]["prospect_mark"], {},
		"deadline cannot keep old deposit coordinates")
	server._tick_players(0.1)
	t.eq(scout.prospect_mark, {}, "server removes expired waypoint")
	scout.prospect_mark = {"id": int(selected["id"]), "kind": str(selected["kind"]),
		"tier": int(selected["tier"]), "x": selected["x"], "z": selected["z"],
		"until": server.time + 50.0}
	scout.survival.hurt(1000.0)
	server._on_player_death(scout, -1)
	t.eq(scout.prospect_mark, {}, "death clears private prospecting state")
