extends RefCounted
## Real inventory, safe throwing, PvE targets, capped AoE, anti-spam and save tests.

const Defs = preload("res://scripts/shared/defs.gd")
const FlashCharge = preload("res://scripts/shared/flash_charge.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")


func _open_location(world) -> Vector3:
	for x in range(140, 300, 16):
		for z in range(140, 300, 16):
			var p := Vector3(float(x), world.height_at(float(x), float(z)), float(z))
			if not FlashCharge.landing(world, p, Vector2.RIGHT).is_empty():
				return p
	return Vector3.INF


func run(t) -> void:
	t.current = "workbench cost and server-verified throw"
	t.check(Defs.is_item("flash_charge"), "registered as a real consumable")
	t.eq(Defs.recipes()["flash_charge"]["station"], "workbench",
		"flash item requires a workbench")
	var bag := Inventory.new()
	bag.add("scrap", 2)
	bag.add("bar_2", 1)
	bag.add("cloth_1", 1)
	bag.add("stone_1", 1)
	t.eq(Crafting.craft(bag, "flash_charge", false), Crafting.Result.NO_STATION,
		"cannot make charges in the field")
	t.eq(Crafting.craft(bag, "flash_charge", true), Crafting.Result.OK,
		"actual ingredients craft one charge")
	t.eq(bag.count("flash_charge"), 1, "one paid charge added")
	var world := WorldGen.new(721)
	var sim := GameServer.new(world, 721)
	var origin: Vector3 = _open_location(world)
	t.check(origin.is_finite(), "procedural world has a clear throwing corridor")
	if not origin.is_finite():
		return
	var player = sim.add_player(811, "Horde Scout")
	player.position = origin
	var landing: Dictionary = FlashCharge.landing(world, origin, Vector2.RIGHT)
	t.check(not landing.is_empty(), "impact comes from real terrain")
	t.eq(FlashCharge.landing(world, origin, Vector2.ZERO), {},
		"zero direction denied")
	t.eq(FlashCharge.landing(world, origin, Vector2(NAN, 0.0)), {},
		"nonfinite direction denied")
	t.eq(FlashCharge.landing(world, Vector3.ZERO, Vector2.RIGHT), {},
		"safe hub does not allow crowd control")
	t.eq(sim.cmd_throw_flash(999, 1.0, 0.0)["reason"], "dead",
		"unknown peer cannot throw")
	t.eq(sim.cmd_throw_flash(811, 1.0, 0.0)["reason"], "no_targets",
		"empty flash wastes no inventory item")

	t.current = "server picks only bounded living non-boss targets"
	var center := Vector2(float(landing["x"]), float(landing["z"]))
	for index in 6:
		var site := center + Vector2(0.0, float(index) * 0.4)
		var walker = Zombie.new(sim.new_id(), "walker",
			Vector3(site.x, world.height_at(site.x, site.y), site.y))
		sim.zombies[walker.id] = walker
	var boss = Zombie.new(sim.new_id(), "brute",
		Vector3(center.x + 0.5, world.height_at(center.x + 0.5, center.y), center.y))
	boss.raid_boss = true
	sim.zombies[boss.id] = boss
	var chosen: Array = FlashCharge.targets(world, landing, sim.zombies)
	t.check(chosen.size() > 0 and chosen.size() <= FlashCharge.MAX_TARGETS,
		"radius and target count bounded")
	t.check(not chosen.has(boss), "raid boss excluded")
	t.eq(sim.cmd_throw_flash(811, NAN, 0.0)["reason"], "invalid_landing",
		"invalid network heading cannot apply damage")
	t.eq(sim.cmd_throw_flash(811, 1.0, 0.0)["reason"], "not_carried",
		"the item cannot be spoofed")
	player.inventory.add("flash_charge", 2)
	var before: int = player.inventory.count("flash_charge")
	var result: Dictionary = sim.cmd_throw_flash(811, 1.0, 0.0)
	t.check(bool(result.get("ok", false)), "valid thrown charge resolves")
	t.eq(int(result.get("hits", 0)), chosen.size(), "server count equals actual stunned enemies")
	t.eq(player.inventory.count("flash_charge"), before - 1, "exactly one charge consumed")
	t.eq(boss.stagger_seconds, 0.0, "raid bosses immune")
	for enemy in chosen:
		t.near(enemy.stagger_seconds, FlashCharge.STAGGER_SECONDS, 0.001,
			"normal infected briefly incapacitated")
	t.near(player.noise_radius, FlashCharge.PLAYER_NOISE_RADIUS,
		0.001, "explosion alerts other infected")
	t.eq(sim.cmd_throw_flash(811, 1.0, 0.0)["reason"], "cooldown",
		"replays do not stack stuns")
	t.eq(player.inventory.count("flash_charge"), before - 1,
		"failed repeated action spends nothing")
	t.check(player.dirty_inventory and player.dirty_character,
		"consumed kit and timer marked dirty")
	t.near(float(sim.snapshot_for(811)["you"]["flash_cooldown"]),
		FlashCharge.COOLDOWN_SECONDS, 0.001,
		"owner sees remaining cooldown")
	t.current = "save migration and strict timer validation"
	var save: Dictionary = sim.character_data(player)
	t.check(sim.apply_character(player, save), "saved timer can be restored")
	t.eq(player.flash_cooldown, FlashCharge.COOLDOWN_SECONDS,
		"rejoin does not skip server timer")
	for invalid in [-1.0, NAN, INF, FlashCharge.COOLDOWN_SECONDS + 1.0, "12"]:
		var bad: Dictionary = save.duplicate(true)
		bad["flash_cooldown"] = invalid
		t.check(not sim.apply_character(player, bad), "invalid timer rejected")
		t.eq(player.flash_cooldown, FlashCharge.COOLDOWN_SECONDS,
			"failed parse does not mutate player state")
	var legacy: Dictionary = save.duplicate(true)
	legacy.erase("flash_cooldown")
	t.check(sim.apply_character(player, legacy), "old character saves still load")
	t.eq(player.flash_cooldown, 0.0, "old character starts with no cooldown")
	sim._tick_players(0.1)
	t.check(sim.snapshot_for(811)["you"].has("flash_cooldown"),
		"cooldown remains visible to character after tick")
