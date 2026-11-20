extends RefCounted
## Paid mining specialisation: real T2+ harvests, higher infected noise,
## no free refresh, bounded persistent charges and capacity-safe payouts.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Rules = preload("res://scripts/shared/mining_wedges.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Progression = preload("res://scripts/shared/progression.gd")
const GatheringNoise = preload("res://scripts/shared/gathering_noise.gd")


func _veins(world) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for cx in range(8, 17):
		for cz in range(0, 13):
			var chunk: Dictionary = world.chunk(Vector2i(cx, cz))
			for node in chunk["nodes"]:
				if str(node["kind"]) in ["ore", "rock"] and (
						int(node["tier"]) >= Rules.MIN_TIER):
					found.append(node)
					if found.size() >= 6:
						return found
	return found


func _place(player, world, node: Dictionary) -> void:
	var x: float = float(node["x"])
	var z: float = float(node["z"])
	player.position = Vector3(x, world.height_at(x, z), z)


func _finished_event(server, node_id: int) -> Dictionary:
	for event in server.events:
		if str(event.get("type", "")) == "gathered" and (
				int(event.get("node", -1)) == node_id):
			return event
	return {}


func run(t) -> void:
	t.current = "industrial craft uses genuine T2 metal and salvage"
	t.eq(Defs.item(Rules.ITEM_ID).get("kind", ""), "mining_wedges",
		"new expedition item is a usable mining preparation")
	var recipe: Dictionary = Defs.recipes().get(Rules.ITEM_ID, {})
	t.eq(recipe.get("station", ""), "workbench", "upgrades are made at a real workshop")
	t.eq(recipe.get("inputs", {}), {"bar_2": 1, "scrap": 3, "stone_1": 2},
		"expensive metal and scavenged materials are required")
	var materials := Inventory.new()
	materials.add("bar_2", 1)
	materials.add("scrap", 3)
	materials.add("stone_1", 2)
	t.eq(Crafting.craft(materials, Rules.ITEM_ID, false),
		Crafting.Result.NO_STATION, "missing workbench prevents free equipment")
	t.eq(materials.count("bar_2"), 1, "failed craft spends no T2 metal")
	t.eq(Crafting.craft(materials, Rules.ITEM_ID, true),
		Crafting.Result.OK, "workshop can craft one physical wedge kit")
	t.eq(materials.count(Rules.ITEM_ID), 1, "one kit appears in inventory")
	t.eq(materials.count("scrap"), 0, "three scrap were consumed")

	t.current = "bounded rules deny low tier, unrelated and inventory-starved yields"
	t.check(Rules.valid_state(0) and Rules.valid_state(Rules.CHARGES),
		"zero and full legitimate saved charges are permitted")
	for forged in [-1, Rules.CHARGES + 1, 2.0, "2", INF]:
		t.check(not Rules.valid_state(forged),
			"malformed or replay-inflated mining charges are refused")
	t.eq(Rules.bonus("tree", 4, 2, 100, 4, true), 0,
		"logging is not mining and gets no wedge reward")
	t.eq(Rules.bonus("ore", 1, 2, 100, 3, true), 0,
		"beginner ore never spends industrial preparation")
	t.eq(Rules.bonus("rock", 2, 2, 100, 4, false), 0,
		"unverified / forged harvesting cannot mint bonus yield")
	t.eq(Rules.bonus("ore", 2, 0, 100, 3, true), 0,
		"no prepared charges means no extra resources")
	t.eq(Rules.bonus("ore", 2, 2, 4, 3, true), 0,
		"missing inventory capacity preserves paid mining charges")
	t.eq(Rules.bonus("ore", 2, 2, 5, 3, true), Rules.EXTRA_YIELD,
		"exactly enough backpack room permits a paid high-tier bonus")
	t.near(Rules.harvest_noise(GatheringNoise.ORE_RADIUS, Rules.EXTRA_YIELD),
		Rules.NOISE_RADIUS, 0.001, "paid high-tier mining is substantially louder")
	t.near(Rules.harvest_noise(GatheringNoise.ORE_RADIUS, 0),
		GatheringNoise.ORE_RADIUS, 0.001, "ordinary mining sound is unchanged")

	t.current = "server activation requires real pickaxe, kit and no active fight"
	var world := WorldGen.new(3141)
	var deposits: Array[Dictionary] = _veins(world)
	t.check(deposits.size() >= 5, "seeded island has several genuine T2+ veins")
	if deposits.size() < 5:
		return
	var server := GameServer.new(world, 3141)
	var miner = server.add_player(772, "Industrial Miner")
	_place(miner, world, deposits[0])
	t.eq(server.cmd_use(miner.id, Rules.ITEM_ID).get("reason", ""), "not_carried",
		"forged item use never creates a wedge buff")
	miner.inventory.add(Rules.ITEM_ID, 2)
	t.eq(server.cmd_use(miner.id, Rules.ITEM_ID).get("reason", ""), "need_pickaxe",
		"wedge kit cannot be fitted without carried mining tools")
	t.eq(miner.inventory.count(Rules.ITEM_ID), 2,
		"rejected activation preserves both actual kits")
	miner.inventory.add("pickaxe_4", 1)
	miner.attack_timer = 1.0
	t.eq(server.cmd_use(miner.id, Rules.ITEM_ID).get("reason", ""), "in_combat",
		"active combat prevents installing specialist preparation")
	miner.attack_timer = 0.0
	var activation: Dictionary = server.cmd_use(miner.id, Rules.ITEM_ID)
	t.check(bool(activation.get("ok", false)) and bool(activation.get("mining_wedges", false)),
		"prepared wedges are activated by existing item-use command")
	t.eq(int(activation.get("charges", 0)), Rules.CHARGES,
		"no arbitrary charge count can be submitted by a client")
	t.eq(miner.wedge_charges, Rules.CHARGES, "server owns prepared charge counter")
	t.eq(miner.inventory.count(Rules.ITEM_ID), 1, "exactly one kit spent")
	t.eq(server.cmd_use(miner.id, Rules.ITEM_ID).get("reason", ""),
		"already_prepared", "active preparation cannot be topped up or stacked")
	t.eq(miner.inventory.count(Rules.ITEM_ID), 1, "repeated command cannot waste kit")
	t.check(miner.dirty_inventory and miner.dirty_character,
		"real item consumption is scheduled for account persistence")
	t.eq(server.snapshot_for(miner.id)["you"].get("mining_wedge_charges", -1),
		Rules.CHARGES, "owner's status shows the server counter")
	var rival = server.add_player(773, "Rival")
	rival.position = miner.position
	t.check(not server.snapshot_for(rival.id)["players"][0].has("mining_wedge_charges"),
		"non-owner player snapshots never leak preparation state")

	t.current = "account saves survive relog without refreshing charges"
	var save: Dictionary = server.character_data(miner)
	t.eq(save.get("wedge_charges", -1), Rules.CHARGES,
		"only actual paid remaining charges are stored")
	t.check(server.valid_character_data(save), "valid saved account passes schema")
	var tampered: Dictionary = save.duplicate(true)
	tampered["wedge_charges"] = Rules.CHARGES + 1
	t.check(not server.apply_character(miner, tampered),
		"persistent state cannot grant forged additional charges")
	t.eq(miner.wedge_charges, Rules.CHARGES,
		"failed account load changes nothing")
	tampered = save.duplicate(true)
	tampered["wedge_charges"] = "3"
	t.check(not server.apply_character(miner, tampered),
		"textual and fractional save fields are not silently converted")
	miner.wedge_charges = 0
	t.check(server.apply_character(miner, save),
		"valid account reload restores still-unused paid preparation")
	t.eq(miner.wedge_charges, Rules.CHARGES,
		"relogin cannot generate more than the previously held three charges")
	var legacy: Dictionary = save.duplicate(true)
	legacy.erase("wedge_charges")
	t.check(server.apply_character(miner, legacy),
		"older account versions without wedge field remain valid")
	t.eq(miner.wedge_charges, 0, "legacy accounts do not receive free charges")
	t.check(server.apply_character(miner, save),
		"restoring original paid account state remains supported")

	t.current = "only completed real high-tier harvests receive extra resources and louder noise"
	miner.progression.gathering_xp["ore"] = Progression.XP_PER_LEVEL * 4
	miner.progression.gathering_xp["stone"] = Progression.XP_PER_LEVEL * 4
	for i in range(3):
		var node: Dictionary = deposits[i]
		_place(miner, world, node)
		t.check(miner.progression.can_gather(str(node["kind"]), int(node["tier"])),
			"real tier-gated mining profession allows work")
		var id: int = int(node["id"])
		var gather: Dictionary = server.cmd_gather(miner.id, id)
		t.check(bool(gather.get("ok", false)), "server starts valid T2+ gathering action")
		if not bool(gather.get("ok", false)):
			return
		var item: String = "%s_%d" % ["ore" if node["kind"] == "ore" else "stone",
			int(node["tier"])]
		var before: int = miner.inventory.count(item)
		var charges_before: int = miner.wedge_charges
		server._finish_gather(miner, node)
		var event: Dictionary = _finished_event(server, id)
		t.eq(int(event.get("wedge_bonus", 0)), Rules.EXTRA_YIELD,
			"confirmed gather receives precisely two additional resources")
		t.eq(miner.inventory.count(item) - before, int(event.get("amount", -1)),
			"server event reports exactly what entered backpack")
		t.eq(miner.wedge_charges, charges_before - 1,
			"one and only one charge is spent per completed high-tier node")
		t.eq(miner.noise_radius, Rules.NOISE_RADIUS,
			"loud extraction is audible to nearby infected")
		t.eq(float(event.get("harvest_noise", 0)), Rules.NOISE_RADIUS,
			"server event advertises real high-risk noise")
		t.check(server.depleted.has(id), "harvest marks real world node depleted")
		t.eq(server.cmd_gather(miner.id, id).get("reason", ""), "depleted",
			"repeat network request never reuses one exhausted deposit")
		if i == 0:
			var progress_save: Dictionary = server.character_data(miner)
			t.eq(progress_save.get("wedge_charges", -1), 2,
				"save after first real vein preserves two charges, not three")
	t.eq(miner.wedge_charges, 0, "three completed deposits exhaust the kit")
	t.eq(server.snapshot_for(miner.id)["you"].get("mining_wedge_charges", -1), 0,
		"exhaustion appears in private owner HUD")

	t.current = "full backpack or lost tools cannot consume remaining charges"
	miner.wedge_charges = 1
	var full_node: Dictionary = deposits[3]
	_place(miner, world, full_node)
	miner.inventory = Inventory.new(1)
	miner.inventory.add("pickaxe_4", 1)
	t.eq(miner.inventory.free_space_for("ore_2"), 0,
		"single-slot test bag has no capacity for resource stacks")
	t.check(bool(server.cmd_gather(miner.id, int(full_node["id"])).get("ok", false)),
		"gathering is possible even with no free item slot")
	server._finish_gather(miner, full_node)
	t.eq(miner.wedge_charges, 1,
		"no bonus stored means no paid wedge charge consumed")
	t.eq(_finished_event(server, int(full_node["id"])).get("wedge_bonus", -1), 0,
		"full inventory cannot produce fake bonus rewards")
	var lost_tool: Dictionary = deposits[4]
	_place(miner, world, lost_tool)
	miner.inventory = Inventory.new()
	miner.inventory.add("pickaxe_4", 1)
	t.check(bool(server.cmd_gather(miner.id, int(lost_tool["id"])).get("ok", false)),
		"mining action starts while the pickaxe exists")
	miner.inventory.remove("pickaxe_4", 1)
	server._finish_gather(miner, lost_tool)
	t.eq(miner.wedge_charges, 1,
		"disposing of the required tool cancels premium bonus at completion")
	t.eq(_finished_event(server, int(lost_tool["id"])).get("wedge_bonus", -1), 0,
		"gearless mining cannot gain wedge bonus")
	miner.survival.hurt(1000.0)
	server._on_player_death(miner, -1)
	t.eq(miner.wedge_charges, 0, "death cancels remaining mining preparation")
