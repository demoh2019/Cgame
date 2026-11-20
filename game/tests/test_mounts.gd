extends RefCounted
## Travel gear, server authority, safe movement and persistence.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const Mounts = preload("res://scripts/shared/mounts.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "craftable travel equipment"
	t.eq(Defs.item(Mounts.ITEM_ID).get("kind"), "mount", "bike is a real inventory item")
	t.eq(Defs.recipes()[Mounts.ITEM_ID]["station"], "workbench", "bike needs a station")
	var world := WorldGen.new(42)
	var base := Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	var walking := Movement.step(world, base, {"x": 1.0}, 0.05)
	var riding := Movement.step(world, base, {"x": 1.0, "mounted": true}, 0.05)
	t.check(riding.x > walking.x, "bike moves faster than walking")
	var overweight := Movement.step(world, base, {"x": 1.0, "mounted": true,
		"cargo_factor": 0.5}, 0.05)
	t.check(overweight.x <= walking.x + 0.001, "overload prevents mounted speed")
	var injured := Movement.step(world, base, {"x": 1.0, "mounted": true,
		"injury_factor": Defs.FRACTURE_SPEED_FACTOR}, 0.05)
	t.check(injured.x <= walking.x + 0.001, "fractures prevent mounted speed")

	var sim := GameServer.new(world, 42)
	var player = sim.add_player(2, "Cyclist")
	t.current = "server-authoritative mounting"
	t.eq(sim.cmd_toggle_mount(2).get("reason"), "missing_bike", "cannot conjure a bike")
	t.eq(player.inventory.add(Mounts.ITEM_ID, 1), 0, "bike fits into backpack")
	t.eq(sim.cmd_toggle_mount(2).get("mounted"), true, "owned bike can be mounted")
	t.eq(sim.cmd_attack(2, 1.0, 0.0).get("reason"), "mounted", "no mounted combat")
	t.eq(sim.cmd_dodge(2, 1.0, 0.0).get("reason"), "mounted", "no mounted dodge")
	t.eq(sim.cmd_craft(2, "bandage").get("reason"), "mounted", "no mounted crafting")
	t.eq(sim.snapshot_for(2)["you"]["mounted"], true, "replicate riding state")
	var before_stamina: float = player.survival.stamina
	sim.tick(0.05)
	sim.submit_input(2, 1, 1.0, 0.0, true, 0.0, 0.05)
	t.near(player.survival.stamina, before_stamina, 0.01,
		"riding never consumes sprint stamina")

	t.current = "damage and cooldown"
	t.check(sim._hurt_player(player, 4.0) > 0.0, "actual damage applies")
	t.eq(player.mounted, false, "damage dismounts rider")
	t.check(player.mount_cooldown >= Mounts.HIT_COOLDOWN - 0.01,
		"damage starts remount lock")
	t.eq(sim.cmd_toggle_mount(2).get("reason"), "cooldown", "no instant remount")
	player.mount_cooldown = 0.0
	player.survival.fracture = 15.0
	t.eq(sim.cmd_toggle_mount(2).get("reason"), "fracture", "fracture prevents riding")
	player.survival.fracture = 0.0
	player.combat_tag_until = sim.time + 10.0
	t.eq(sim.cmd_toggle_mount(2).get("reason"), "in_combat", "combat tag prevents riding")
	player.combat_tag_until = 0.0
	t.eq(sim.cmd_toggle_mount(2).get("mounted"), true, "mount after locks")
	t.eq(sim.cmd_toggle_mount(2).get("mounted"), false, "manual dismount")
	t.check(player.mount_cooldown >= Mounts.MANUAL_COOLDOWN, "manual remount delay")

	t.current = "item loss and save"
	player.mount_cooldown = 0.0
	t.eq(sim.cmd_toggle_mount(2).get("mounted"), true, "mount after lock clears")
	t.check(player.inventory.remove(Mounts.ITEM_ID, 1), "bike can be lost or traded")
	sim.tick(0.05)
	t.eq(player.mounted, false, "loss of item dismounts rider")
	var save: Dictionary = sim.character_data(player)
	t.check(not save.has("mounted"), "transient riding cannot be saved")
	var restored = sim.add_player(3, "Rejoined", "", save)
	t.eq(restored.mounted, false, "relogin does not grant a bike")
	t.eq(restored.inventory.count(Mounts.ITEM_ID), 0, "item loss persists")
