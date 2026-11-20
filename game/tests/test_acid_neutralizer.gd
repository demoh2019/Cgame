extends RefCounted
## Field chemistry does not undo direct spitter damage. It removes only
## live, server-owned lingering puddles after paying for a real item.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Acid = preload("res://scripts/shared/acid_spitter.gd")
const Neutralizer = preload("res://scripts/shared/acid_neutralizer.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _red_dry(world) -> Vector2:
	for x in range(730, 990, 12):
		for z in range(-95, 96, 12):
			if world.zone_at(float(x), float(z)) >= Acid.MIN_ZONE \
					and not world.is_water(float(x), float(z)) \
					and not world.is_safe(float(x), float(z)):
				return Vector2(x, z)
	return Vector2.INF


func _pool(id: int, center: Vector2, world, now: float) -> Dictionary:
	return Acid.make_pool(id, center, world.height_at(center.x, center.y), now, 888)


func _at(world, center: Vector2) -> Vector3:
	return Vector3(center.x, world.height_at(center.x, center.y), center.y)


func run(t) -> void:
	t.current = "craftable field chemical, no free charges"
	t.check(Defs.is_item(Neutralizer.ITEM_ID), "alkali kit exists as an inventory item")
	t.eq(Defs.item(Neutralizer.ITEM_ID)["kind"], "acid_neutralizer",
		"only this specialized consumable can neutralize acid")
	var recipe: Dictionary = Defs.recipes().get(Neutralizer.ITEM_ID, {})
	t.check(not recipe.is_empty(), "field anti-acid kit has a registered recipe")
	t.eq(recipe["station"], "", "an expedition survivor crafts the kit without a bench")
	t.eq(recipe["inputs"], {"stone_1": 2, "water_bottle": 1, "cloth_1": 1},
		"kit consumes stone, clean water and cloth")
	var bag := Inventory.new()
	bag.add("stone_1", 2)
	bag.add("cloth_1", 1)
	t.eq(Crafting.craft(bag, Neutralizer.ITEM_ID, false), Crafting.Result.MISSING_INPUTS,
		"missing water cannot produce a free chemical")
	t.eq(bag.count("stone_1"), 2, "failed crafting leaves all stones")
	bag.add("water_bottle", 1)
	t.eq(Crafting.craft(bag, Neutralizer.ITEM_ID, false), Crafting.Result.OK,
		"crafting actually exchanges materials for one kit")
	t.eq(bag.count(Neutralizer.ITEM_ID), 1, "exactly one anti-acid kit crafted")
	t.eq(bag.count("stone_1"), 0, "stone paid at craft time")
	t.eq(bag.count("water_bottle"), 0, "clean water paid at craft time")

	t.current = "pure hazard selection: nearest three active only"
	var world := WorldGen.new(44)
	var spot: Vector2 = _red_dry(world)
	t.check(spot.is_finite(), "found a deterministic dry red-zone test site")
	if not spot.is_finite():
		return
	var pools: Dictionary = {}
	pools[10] = _pool(10, spot + Vector2(2.0, 0.0), world, 0.0)
	pools[11] = _pool(11, spot + Vector2(1.0, 0.0), world, 0.0)
	pools[12] = _pool(12, spot, world, 0.0)
	pools[13] = _pool(13, spot + Vector2(5.0, 0.0), world, 0.0)
	pools[14] = _pool(14, spot + Vector2(8.0, 0.0), world, 0.0)
	pools[15] = _pool(15, spot, world, -10.0)
	t.eq(Neutralizer.targets(pools, _at(world, spot), 0.0), [12, 11, 10],
		"only closest three live pools are selected in deterministic order")
	t.eq(Neutralizer.targets(pools, _at(world, spot), 10.0), [],
		"expired pools cannot be selected or waste an item")
	t.eq(Neutralizer.targets(pools, Vector3.INF, 0.0), [],
		"nonfinite player position gives no valid neutralization")
	t.eq(Neutralizer.targets(pools, _at(world, spot), NAN), [],
		"nonfinite server clock gives no valid neutralization")
	var corrupt: Dictionary = {99: {"x": NAN, "z": 0.0, "expires": 5.0}}
	t.eq(Neutralizer.targets(corrupt, _at(world, spot), 0.0), [],
		"nonfinite puddle coordinates cannot be targeted")
	var farther: Vector3 = _at(world, spot + Vector2(20.0, 0.0))
	t.eq(Neutralizer.targets(pools, farther, 0.0), [],
		"neutralizer cannot reach distant acid")
	var twin: Dictionary = {
		2: _pool(2, spot + Vector2(1.0, 0.0), world, 0.0),
		1: _pool(1, spot + Vector2(-1.0, 0.0), world, 0.0)
	}
	t.eq(Neutralizer.targets(twin, _at(world, spot), 0.0), [1, 2],
		"equal-distance pools are ordered by stable server ID")

	t.current = "authoritative inventory and no-op refusal"
	var sim := GameServer.new(world, 44)
	var actor = sim.add_player(981, "Hazard Cleaner")
	actor.position = _at(world, spot)
	t.eq(sim.cmd_use(actor.id, Neutralizer.ITEM_ID).get("reason", ""),
		"not_carried", "missing chemical cannot clear an acid puddle")
	actor.inventory.add("stone_1", 2)
	actor.inventory.add("water_bottle", 1)
	actor.inventory.add("cloth_1", 1)
	t.check(sim.cmd_craft(actor.id, Neutralizer.ITEM_ID).get("ok", false),
		"server can craft the kit outdoors using actual materials")
	t.eq(actor.inventory.count(Neutralizer.ITEM_ID), 1, "crafted kit is carried")
	t.eq(sim.cmd_use(actor.id, Neutralizer.ITEM_ID).get("reason", ""),
		"no_acid_nearby", "server refuses wasteful use when no acid exists")
	t.eq(actor.inventory.count(Neutralizer.ITEM_ID), 1,
		"refused use cannot debit a kit")
	actor.inventory.add(Neutralizer.ITEM_ID, 2)
	for pool_id in pools:
		sim.acid_pools[pool_id] = pools[pool_id].duplicate(true)
	var first: Dictionary = sim.cmd_use(actor.id, Neutralizer.ITEM_ID)
	t.check(first.get("ok", false), "carried kit clears nearby hazards")
	t.eq(first.get("neutralized", -1), Neutralizer.MAX_CLEARED,
		"one kit clears at most three active pools")
	t.eq(actor.inventory.count(Neutralizer.ITEM_ID), 2,
		"one real kit is removed once for three cleared pools")
	t.check(actor.dirty_inventory and actor.dirty_character,
		"server flags inventory and character as dirty")
	for pool_id in [10, 11, 12]:
		t.check(not sim.acid_pools.has(pool_id),
			"nearest active pool is genuinely erased from world simulation")
	t.check(sim.acid_pools.has(13), "fourth pool is not cleared for free")
	t.check(sim.acid_pools.has(14), "distant pool is left alone")
	t.check(sim.acid_pools.has(15), "already expired pool is ignored")
	t.eq(sim.snapshot_for(actor.id)["acid_pools"].size(), 2,
		"connected client sees remaining non-expired pools, including those outside cleaning range")

	t.current = "no stale-damage tick, repeat and safe-zone checks"
	var second: Dictionary = sim.cmd_use(actor.id, Neutralizer.ITEM_ID)
	t.check(second.get("ok", false), "second paid dose can remove fourth pool")
	t.eq(second.get("neutralized", -1), 1, "only actual remaining live pool is cleared")
	t.eq(actor.inventory.count(Neutralizer.ITEM_ID), 1,
		"second successful action consumes exactly one additional kit")
	var before_health: float = actor.survival.health
	sim.time = Acid.POOL_TICK_SECONDS
	sim._tick_acid_pools()
	t.near(actor.survival.health, before_health, 0.0001,
		"already-neutralized acid cannot damage survivor on next tick")
	t.eq(sim.cmd_use(actor.id, Neutralizer.ITEM_ID).get("reason", ""),
		"no_acid_nearby", "repeated network use cannot double-charge or over-clear")
	t.eq(actor.inventory.count(Neutralizer.ITEM_ID), 1,
		"replayed/no-op request keeps the kit")
	actor.position = _at(world, Vector2(4.0, 0.0))
	t.eq(sim.cmd_use(actor.id, Neutralizer.ITEM_ID).get("reason", ""),
		"safe_zone", "cannot use cleaning chemical to target protected hub")
	t.eq(actor.inventory.count(Neutralizer.ITEM_ID), 1,
		"safe-zone denial preserves inventory")
	actor.survival.hurt(1000.0)
	t.eq(sim.cmd_use(actor.id, Neutralizer.ITEM_ID).get("reason", ""),
		"dead", "dead survivors cannot spend field kits")
	t.eq(actor.inventory.count(Neutralizer.ITEM_ID), 1,
		"dead client command changes no inventory")
	t.check(not sim.character_data(actor).has("acid_pools"),
		"temporary hazard pools do not pollute persistent character data")
