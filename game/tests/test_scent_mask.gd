extends RefCounted
## Field-crafted disguise changes infected blood-scent acquisition only.
const Defs = preload("res://scripts/shared/defs.gd")
const BloodScent = preload("res://scripts/shared/blood_scent.gd")
const FieldScentMask = preload("res://scripts/shared/field_scent_mask.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Survival = preload("res://scripts/shared/survival.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "scent camouflage: pure rules and no immunity to normal senses"
	var independent := Survival.new()
	t.check(FieldScentMask.can_apply(independent), "unprotected survivor may apply salve")
	t.check(Defs.is_item(FieldScentMask.ITEM_ID), "salve is a real registered item")
	t.eq(Defs.item(FieldScentMask.ITEM_ID)["kind"], "scent_mask", "specific safe item kind")
	t.check(Defs.recipes().has(FieldScentMask.ITEM_ID), "recipe is craftable")
	var recipe: Dictionary = Defs.recipes()[FieldScentMask.ITEM_ID]
	t.eq(recipe["station"], "", "salve is craftable outside a workbench")
	t.eq(recipe["inputs"]["fiber_1"], 2, "crafting consumes scavenged herbs")
	t.eq(recipe["inputs"]["cloth_1"], 1, "crafting consumes one cloth")
	t.eq(recipe["inputs"]["water_bottle"], 1, "crafting consumes clean water")
	t.eq(BloodScent.detection_radius(90.0, true, false, true), 0.0,
		"masked bleeding removes only the additional scent channel")
	t.check(BloodScent.detection_radius(90.0) > 24.0,
		"unchanged unmasked bleeding still reveals distant survivors")
	t.check(not FieldScentMask.can_apply(null), "no player cannot apply disguise")
	t.check(not FieldScentMask.active(independent), "new character is not masked")
	FieldScentMask.apply(independent)
	t.eq(independent.scent_mask_seconds, FieldScentMask.DURATION_SECONDS,
		"the first dose grants exactly 120 seconds")
	t.check(FieldScentMask.active(independent), "buff is active after paid use")
	t.check(not FieldScentMask.can_apply(independent), "reapplication cannot stack")
	independent.tick(50.0)
	t.near(independent.scent_mask_seconds, 70.0, 0.0001, "duration decreases")
	independent.tick(-8.0)
	t.near(independent.scent_mask_seconds, 70.0, 0.0001,
		"negative clock steps cannot extend disguise")
	independent.tick(70.0)
	t.eq(independent.scent_mask_seconds, 0.0, "effect expires at zero")
	t.check(FieldScentMask.can_apply(independent), "new salve works after expiry")
	FieldScentMask.apply(independent)
	independent.reset()
	t.eq(independent.scent_mask_seconds, 0.0, "respawn removes camouflage")

	t.current = "real field recipe, inventory debit, and duplicate-use protection"
	var world := WorldGen.new(321)
	var server := GameServer.new(world, 321)
	var survivor = server.add_player(706, "Scout")
	survivor.position = _at(world, 300.0, 0.0)
	t.check(not world.is_safe(300.0, 0.0), "scout is in frontier away from hub")
	t.eq(server.cmd_use(survivor.id, FieldScentMask.ITEM_ID)["reason"],
		"not_carried", "cannot forge a scent salve without inventory")
	survivor.inventory.add("fiber_1", 2)
	survivor.inventory.add("cloth_1", 1)
	var crafted: Dictionary = server.cmd_craft(survivor.id, FieldScentMask.ITEM_ID)
	t.check(crafted.get("ok", false), "server crafts one salve in the field")
	t.eq(survivor.inventory.count(FieldScentMask.ITEM_ID), 1,
		"crafted item is transferred into the real inventory")
	t.eq(survivor.inventory.count("fiber_1"), 0,
		"resource components are actually consumed")
	t.eq(survivor.inventory.count("cloth_1"), 0,
		"cloth component is actually consumed")
	survivor.inventory.add(FieldScentMask.ITEM_ID, 1)
	survivor.survival.add_bleeding(90.0)
	var unmasked: Dictionary = server.snapshot_for(survivor.id)["you"]
	t.check(float(unmasked["blood_scent_radius"]) > 24.0,
		"untreated severe bleeding is detectable before salve use")
	t.eq(float(unmasked["scent_mask_seconds"]), 0.0,
		"new owner snapshot reports no camouflage")

	t.current = "live infected AI: sight, scent and previous pursuit"
	var first := Zombie.new(server.new_id(), "walker", _at(world, 324.0, 0.0))
	server.zombies[first.id] = first
	server._tick_zombies(0.1)
	t.eq(first.target_id, survivor.id, "bleeding attracts infected outside vision")
	# Keep the first zombie actively pursuing: applying salve does not erase it.
	var applied: Dictionary = server.cmd_use(survivor.id, FieldScentMask.ITEM_ID)
	t.check(applied.get("ok", false), "server accepts a paid scent-masking dose")
	t.eq(survivor.inventory.count(FieldScentMask.ITEM_ID), 1,
		"using salve consumes exactly one of two owned items")
	t.eq(survivor.survival.scent_mask_seconds, FieldScentMask.DURATION_SECONDS,
		"server applies the real effect")
	var masked: Dictionary = server.snapshot_for(survivor.id)["you"]
	t.eq(float(masked["blood_scent_radius"]), 0.0,
		"private snapshot reports no scent while effect is active")
	t.eq(float(masked["scent_mask_seconds"]), FieldScentMask.DURATION_SECONDS,
		"only the owner receives the remaining disguise duration")
	t.eq(server.cmd_use(survivor.id, FieldScentMask.ITEM_ID)["reason"],
		"already_masked", "spam requests do not stack or refresh active camouflage")
	t.eq(survivor.inventory.count(FieldScentMask.ITEM_ID), 1,
		"failed reapplication does not consume another salve")
	var fresh := Zombie.new(server.new_id(), "walker", _at(world, 324.0, 0.0))
	server.zombies.erase(first.id)
	server.zombies[fresh.id] = fresh
	server._tick_zombies(0.1)
	t.eq(fresh.target_id, -1, "new infected cannot scent a masked distant survivor")
	# Ordinary sight must still work at close range, despite scent masking.
	var nearby := Zombie.new(server.new_id(), "walker", _at(world, 312.0, 0.0))
	server.zombies[nearby.id] = nearby
	server._tick_zombies(0.1)
	t.eq(nearby.target_id, survivor.id,
		"mask does not grant invisibility against normal zombie vision")

	t.current = "saved time, offline compatibility, tick, and corrupted saves"
	survivor.dirty_character = false
	server._tick_players(1.0)
	t.near(survivor.survival.scent_mask_seconds, 119.0, 0.0001,
		"server decreases the active timer")
	t.check(survivor.dirty_character, "server queues remaining time for save")
	var save: Dictionary = server.character_data(survivor)
	t.near(float(save["scent_mask_seconds"]), 119.0, 0.0001,
		"character record stores remaining mask duration")
	survivor.survival.scent_mask_seconds = 0.0
	t.check(server.apply_character(survivor, save), "persisted mask timer restores")
	t.eq(survivor.survival.scent_mask_seconds, 119.0,
		"relogin cannot refresh or clear a running mask")
	var legacy: Dictionary = save.duplicate(true)
	legacy.erase("scent_mask_seconds")
	t.check(server.apply_character(survivor, legacy), "legacy version-one save loads")
	t.eq(survivor.survival.scent_mask_seconds, 0.0,
		"legacy characters start without an active buff")
	t.check(server.apply_character(survivor, save), "restore active camouflage again")
	for invalid in [-1.0, FieldScentMask.DURATION_SECONDS + 1.0, INF, NAN, "120", true]:
		var corrupt: Dictionary = save.duplicate(true)
		corrupt["scent_mask_seconds"] = invalid
		t.check(not server.apply_character(survivor, corrupt),
			"malformed scent-mask timer is refused before changing character")
		t.eq(survivor.survival.scent_mask_seconds, 119.0,
			"rejected save never resets a live buff")
	t.current = "expiration and respawn"
	# A survival-only tick avoids unrelated outpost/weather rules and tests
	# the exact timer that the authoritative world advances each frame.
	# Keep an injury that survives a long test tick and remains scented.
	survivor.survival.bleeding = 40.0
	survivor.position = _at(world, 300.0, 0.0)
	survivor.survival.tick(119.0)
	t.eq(survivor.survival.scent_mask_seconds, 0.0, "120s expiry is exact")
	t.check(server.snapshot_for(survivor.id)["you"]["blood_scent_radius"] > 0.0,
		"blood scent returns on expiry while the wound is still present")
	t.check(server.cmd_use(survivor.id, FieldScentMask.ITEM_ID).get("ok", false),
		"remaining salve can be used again after expiry")
	survivor.survival.hurt(1000.0)
	server._on_player_death(survivor, -1)
	server._spawn_player(survivor)
	t.eq(survivor.survival.scent_mask_seconds, 0.0,
		"death and respawn remove stealth buff")
