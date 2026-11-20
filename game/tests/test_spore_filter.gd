extends RefCounted
## Field respirator regression: material cost, atomic use, finite save migration,
## authoritative spore protection and exact expiry when a server tick overruns.

const Defs = preload("res://scripts/shared/defs.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const SporeHazard = preload("res://scripts/shared/spore_hazard.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


class TestBiome:
	func is_safe(_x: float, _z: float) -> bool:
		return false

	func zone_at(_x: float, _z: float) -> int:
		return 2

	func biome_at(_x: float, _z: float) -> String:
		return "swamp"


func run(t) -> void:
	t.current = "field spore filter catalog and crafting economy"
	t.check(Defs.is_item(SporeHazard.FILTER_ITEM_ID), "craftable mask exists in item catalog")
	t.eq(Defs.item(SporeHazard.FILTER_ITEM_ID)["kind"], "spore_filter", "mask is independently usable")
	var recipe: Dictionary = Defs.recipes()[SporeHazard.FILTER_ITEM_ID]
	t.eq(recipe["station"], "", "filter can be crafted during a field expedition")
	t.eq(recipe["inputs"]["charcoal_filter"], 1, "spore protection consumes a real water filter")
	t.eq(recipe["inputs"]["field_antiseptic"], 1, "recipe also spends medical supplies")
	var bag := Inventory.new()
	t.eq(Crafting.craft(bag, SporeHazard.FILTER_ITEM_ID, false),
		Crafting.Result.MISSING_INPUTS, "empty inventory cannot mint a filter")
	bag.add("charcoal_filter", 1)
	bag.add("cloth_1", 2)
	bag.add("field_antiseptic", 1)
	t.eq(Crafting.craft(bag, SporeHazard.FILTER_ITEM_ID, false),
		Crafting.Result.OK, "legal field recipe succeeds with inventory-paid inputs")
	t.eq(bag.count(SporeHazard.FILTER_ITEM_ID), 1, "one respirator is produced")
	t.eq(bag.count("field_antiseptic"), 0, "antiseptic is consumed once")

	t.current = "pure bounded ambient-only protection"
	var fake := TestBiome.new()
	var pos := Vector3(450.0, 0.0, 450.0)
	var ordinary: Dictionary = SporeHazard.status(fake, pos, 100.0)
	var filtered: Dictionary = SporeHazard.status(fake, pos, 100.0, "",
		SporeHazard.FILTER_DURATION_SECONDS)
	t.near(float(filtered["protection"]), SporeHazard.FILTER_REDUCTION, 0.00001,
		"field mask lowers ambient exposure but not to zero")
	t.near(float(filtered["rate"]), float(ordinary["rate"]) * 0.25, 0.00001,
		"standalone filter prevents exactly 75 percent of airborne infection")
	t.near(float(SporeHazard.status(fake, pos, 100.0, "sealed_suit_2",
		SporeHazard.FILTER_DURATION_SECONDS)["protection"]), 0.9125, 0.00001,
		"sealed armor and respirator combine multiplicatively")
	t.near(float(SporeHazard.status(fake, pos, 100.0, "sealed_suit_4",
		SporeHazard.FILTER_DURATION_SECONDS)["protection"]), SporeHazard.MAX_PROTECTION,
		0.00001, "stacked protection never grants absolute immunity")
	for invalid in [-1.0, NAN, INF, SporeHazard.FILTER_DURATION_SECONDS + 1.0]:
		t.near(float(SporeHazard.status(fake, pos, 100.0, "", invalid)["protection"]),
			0.0, 0.00001, "invalid timers cannot create a free protective buff")

	t.current = "authoritative use, duplicate calls, split-tick exposure and snapshot"
	var world := WorldGen.new(311)
	var swamp := Vector2.ZERO
	for gx in range(-15, 16):
		for gz in range(-15, 16):
			var at := Vector2(float(gx) * 80.0, float(gz) * 80.0)
			if at.length() >= 270.0 and world.biome_at(at.x, at.y) == "swamp":
				swamp = at
				break
		if swamp != Vector2.ZERO:
			break
	t.check(swamp != Vector2.ZERO, "generated world has a reachable hostile swamp")
	if swamp == Vector2.ZERO:
		return
	var server := GameServer.new(world, 311)
	var player = server.add_player(901, "Field Medic")
	player.position = Vector3(swamp.x, world.height_at(swamp.x, swamp.y), swamp.y)
	server.time = 100.0
	t.eq(server.cmd_use(player.id, SporeHazard.FILTER_ITEM_ID)["reason"],
		"not_carried", "server does not create free masks")
	player.inventory.add(SporeHazard.FILTER_ITEM_ID, 2)
	t.check(server.cmd_use(player.id, SporeHazard.FILTER_ITEM_ID)["ok"],
		"owned filter activates server-side")
	t.eq(player.inventory.count(SporeHazard.FILTER_ITEM_ID), 1,
		"one charge paid for exactly once")
	t.eq(server.cmd_use(player.id, SporeHazard.FILTER_ITEM_ID)["reason"],
		"already_filtered", "replayed use cannot stack or refresh the timer")
	t.eq(player.inventory.count(SporeHazard.FILTER_ITEM_ID), 1,
		"rejected replay does not consume a second item")
	t.near(float(server.snapshot_for(player.id)["you"]["spore"]["protection"]),
		SporeHazard.FILTER_REDUCTION, 0.00001,
		"owner snapshot reports real protected exposure")
	player.survival.infection = 0.0
	server._tick_players(1.0)
	t.near(player.survival.infection, SporeHazard.DAY_INFECTION_PER_SECOND * 0.25,
		0.0001, "respirator reduces server-injected infection")
	t.near(player.spore_filter_seconds, SporeHazard.FILTER_DURATION_SECONDS - 1.0,
		0.0001, "only server tick reduces the duration")
	player.spore_filter_seconds = 0.25
	player.survival.infection = 0.0
	server._tick_players(1.0)
	var expected_dose: float = SporeHazard.DAY_INFECTION_PER_SECOND * (0.25 * 0.25 + 0.75)
	t.near(player.survival.infection, expected_dose, 0.0001,
		"expiring mid-tick protects only the first quarter-second")
	t.eq(player.spore_filter_seconds, 0.0, "remaining duration clamps at zero")
	t.near(float(server.snapshot_for(player.id)["you"]["spore"]["protection"]),
		0.0, 0.0001, "snapshot drops spent protection immediately")
	t.check(server.cmd_use(player.id, SporeHazard.FILTER_ITEM_ID)["ok"],
		"fresh consumable can be used after real expiry")
	t.eq(player.inventory.count(SporeHazard.FILTER_ITEM_ID), 0,
		"refresh consumes a fresh, owned item")

	t.current = "relogin migration, strict save validation and death"
	var stored: float = player.spore_filter_seconds
	var saved: Dictionary = server.character_data(player)
	t.check(saved.has("spore_filter_seconds"), "remaining filter time is persisted")
	player.spore_filter_seconds = 0.0
	t.check(server.apply_character(player, saved), "valid account reload restores filter")
	t.near(player.spore_filter_seconds, stored, 0.0001,
		"relogin cannot restart or erase the consumable timer")
	for invalid in [-1.0, NAN, INF, SporeHazard.FILTER_DURATION_SECONDS + 1.0, "10", true]:
		var corrupted: Dictionary = saved.duplicate(true)
		corrupted["spore_filter_seconds"] = invalid
		t.check(not server.apply_character(player, corrupted),
			"corrupt persisted filter cannot bypass save validation")
		t.near(player.spore_filter_seconds, stored, 0.0001,
			"rejected save has no partial effects")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("spore_filter_seconds")
	t.check(server.apply_character(player, legacy), "older v1 characters remain compatible")
	t.eq(player.spore_filter_seconds, 0.0, "legacy accounts start with no filter")
	t.check(server.apply_character(player, saved), "modern account reload succeeds")
	player.survival.hurt(1000.0)
	server._on_player_death(player, -1)
	t.eq(player.spore_filter_seconds, 0.0, "death removes temporary field filtration")
