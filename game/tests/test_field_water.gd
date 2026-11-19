extends RefCounted
## Lake-water risk, inventory-paid filtration, rate limiting and safe save migration.

const Defs = preload("res://scripts/shared/defs.gd")
const FieldWater = preload("res://scripts/shared/field_water.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _shore(world) -> Vector3:
	for x in range(-260, 261, 4):
		for z in range(-260, 261, 4):
			var position := Vector3(float(x), world.height_at(float(x), float(z)), float(z))
			if FieldWater.can_access_lake(world, position):
				return position
	return Vector3.INF


func run(t) -> void:
	t.current = "water is only reachable on a valid shore"
	var world := WorldGen.new(42)
	var server := GameServer.new(world, 42)
	var person = server.add_player(240, "River Scout")
	t.check(not FieldWater.can_access_lake(world, Vector3.INF), "nonfinite coordinates cannot drink")
	t.eq(server.cmd_drink_water(999)["reason"], "dead", "unknown peer cannot drink")
	person.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	person.survival.thirst = 30.0
	t.eq(server.cmd_drink_water(240)["reason"], "no_water", "hub is not a valid shoreline")
	var shore: Vector3 = _shore(world)
	t.check(shore.is_finite(), "deterministic world includes accessible water")
	if not shore.is_finite():
		return
	person.position = shore
	person.survival.thirst = 98.0
	t.eq(server.cmd_drink_water(240)["reason"], "not_thirsty", "full hydration cannot waste filters")
	person.survival.thirst = 25.0

	t.current = "unfiltered lake water carries an explicit, bounded risk"
	var first: Dictionary = server.cmd_drink_water(240)
	t.check(first["ok"] and not first["filtered"], "untreated lake drink succeeds but is risky")
	t.near(person.survival.thirst, 60.0, 0.0001, "water restores exactly 35 thirst")
	t.near(person.survival.infection, FieldWater.UNTREATED_INFECTION, 0.0001, "direct drinking adds server-owned infection")
	t.eq(server.cmd_drink_water(240)["reason"], "cooldown", "replay cannot instantly refill hydration")
	person.inventory.add("charcoal_filter", 1)
	t.eq(server.cmd_drink_water(240)["reason"], "cooldown", "cooldown prevents spending filter early")
	t.eq(person.inventory.count("charcoal_filter"), 1, "denied request does not waste filter")
	server._tick_players(FieldWater.COOLDOWN_SECONDS)
	t.near(person.lake_drink_cooldown, 0.0, 0.0001, "authoritative clock releases cooldown")

	t.current = "one filter makes one lake drink safe"
	var prior_infection: float = person.survival.infection
	var treated: Dictionary = server.cmd_drink_water(240)
	t.check(treated["ok"] and treated["filtered"], "server consumes inventory-owned filter")
	t.eq(person.inventory.count("charcoal_filter"), 0, "one filter debited")
	t.near(person.survival.infection, prior_infection, 0.0001, "filtered drink adds no infection")
	t.check(person.lake_drink_cooldown > 0.0, "filtered water also has cooldown")
	t.check(person.dirty_character, "survival changes marked for persistence")
	var snapshot: Dictionary = server.snapshot_for(240)
	t.eq(snapshot["you"]["lake_drink_cooldown"], FieldWater.COOLDOWN_SECONDS, "owner sees authoritative remaining cooldown")
	t.check(Defs.is_item("charcoal_filter"), "filter is part of authoritative item catalog")
	t.check(Defs.recipes().has("charcoal_filter"), "filter is craftable")

	t.current = "craft filter using materials, not a free command"
	var crafter = server.add_player(241, "Crafter")
	crafter.inventory.add("cloth_1", 1)
	crafter.inventory.add("wood_1", 1)
	t.eq(server.cmd_craft(241, "charcoal_filter")["reason"], "missing_inputs", "cannot craft without stone")
	t.eq(crafter.inventory.count("wood_1"), 1, "failed recipe is atomic")
	crafter.inventory.add("stone_1", 1)
	t.check(server.cmd_craft(241, "charcoal_filter")["ok"], "valid T1 filter crafting succeeds")
	t.eq(crafter.inventory.count("charcoal_filter"), 1, "filter enters carried inventory")

	t.current = "save fields are bounded and legacy characters load"
	var saved: Dictionary = server.character_data(person)
	t.check(saved.has("lake_drink_cooldown"), "character persists lake cooldown")
	person.lake_drink_cooldown = 0.0
	t.check(server.apply_character(person, saved), "saved lake cooldown restores")
	t.near(person.lake_drink_cooldown, FieldWater.COOLDOWN_SECONDS, 0.0001, "relogin cannot skip drinking timer")
	for value in [-1.0, NAN, INF, FieldWater.COOLDOWN_SECONDS + 1.0, "12"]:
		var bad: Dictionary = saved.duplicate(true)
		bad["lake_drink_cooldown"] = value
		t.check(not server.apply_character(person, bad), "invalid cooldown rejected before mutations")
		t.near(person.lake_drink_cooldown, FieldWater.COOLDOWN_SECONDS, 0.0001, "rejected save left timer unchanged")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("lake_drink_cooldown")
	t.check(server.apply_character(person, legacy), "older version-1 save remains loadable")
	t.eq(person.lake_drink_cooldown, 0.0, "legacy player starts with no cooldown")
