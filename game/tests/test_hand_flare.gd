extends RefCounted
## Paid visual lighting, secure server timing, AI reaction and save validation.
const HandFlare = preload("res://scripts/shared/hand_flare.gd")
const HandFlareVisual = preload("res://scripts/client/hand_flare_visual.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	var night: float = WorldCycle.DAY_LENGTH * 0.75
	var day: float = WorldCycle.DAY_LENGTH * 0.25
	t.current = "craftable 3D light and night-only validation"
	t.eq(Defs.item(HandFlare.ITEM_ID).get("kind"), "hand_flare", "registered consumable")
	t.eq(Defs.recipes()[HandFlare.ITEM_ID]["output"], HandFlare.ITEM_ID, "craftable")
	t.eq(HandFlare.ignite_reason(0.0, night, Vector3(210, 0, 145), false), "", "night allowed")
	t.eq(HandFlare.ignite_reason(0.0, day, Vector3(210, 0, 145), false), "daylight", "day refused")
	t.eq(HandFlare.ignite_reason(0.0, night, Vector3.ZERO, true), "safe_zone", "hub refused")
	t.eq(HandFlare.ignite_reason(1.0, night, Vector3(210, 0, 145), false), "already_burning", "no stacking")
	t.eq(HandFlare.ignite_reason(NAN, night, Vector3(210, 0, 145), false), "invalid_state", "invalid fuel denied")
	t.eq(HandFlare.infected_radius(120.0, true, true, false), 28.0, "night visual cue")
	t.eq(HandFlare.infected_radius(120.0, true, false, false), 0.0, "day has no extra cue")
	t.eq(HandFlare.infected_radius(120.0, false, true, false), 0.0, "dead has no cue")
	t.eq(HandFlare.infected_radius(120.0, true, true, true), 0.0, "hub is safe")
	t.eq(HandFlare.remaining(3.0, 10.0), 0.0, "expiry clamps to zero")
	t.eq(HandFlare.remaining(3.0, -100.0), 3.0, "negative delta cannot refill")
	var visual := HandFlareVisual.new()
	t.check(visual is Node3D and visual.has_method("set_burning"), "real 3D visual")
	visual.set_burning(true)
	t.check(visual.visible, "active light visible")
	visual.set_burning(false)
	t.check(not visual.visible, "inactive light hidden")
	visual.free()

	t.current = "live authoritative item and nearby player state"
	var world := WorldGen.new(845)
	var server := GameServer.new(world, 845)
	var survivor = server.add_player(99, "Scout")
	var witness = server.add_player(100, "Witness")
	survivor.position = Vector3(210, world.height_at(210, 145), 145)
	witness.position = survivor.position + Vector3(3, 0, 0)
	survivor.inventory.add(HandFlare.ITEM_ID, 2)
	server.time = day
	t.eq(server.cmd_use(99, HandFlare.ITEM_ID).get("reason"), "daylight", "no daytime consumption")
	t.eq(survivor.inventory.count(HandFlare.ITEM_ID), 2, "failed use leaves fuel")
	server.time = night
	t.check(bool(server.cmd_use(99, HandFlare.ITEM_ID).get("ok", false)), "night ignition succeeds")
	t.eq(survivor.inventory.count(HandFlare.ITEM_ID), 1, "exact one item debited")
	t.eq(server.cmd_use(99, HandFlare.ITEM_ID).get("reason"), "already_burning", "no free refuel")
	t.eq(server.snapshot_for(99)["you"]["flare_seconds"], HandFlare.BURN_SECONDS, "own timer replicated")
	var seen: bool = false
	for peer in server.snapshot_for(100)["players"]:
		if int(peer["id"]) == 99:
			seen = bool(peer.get("flare_lit", false))
	t.check(seen, "rival sees real burning flare")
	server._tick_players(3.0)
	t.eq(survivor.flare_seconds, 117.0, "fuel decreases on server")
	var saved: Dictionary = server.character_data(survivor)
	t.eq(saved["flare_seconds"], 117.0, "fuel saved for reconnect")
	var reconnect := GameServer.new(WorldGen.new(845), 845)
	var returned = reconnect.add_player(999, "Scout", "same-account", saved)
	t.eq(returned.flare_seconds, 117.0, "relogin cannot refill light")
	var invalid: Dictionary = saved.duplicate(true)
	invalid["flare_seconds"] = INF
	t.check(not reconnect.apply_character(returned, invalid), "infinite burn rejected")
	invalid = saved.duplicate(true)
	invalid["flare_seconds"] = 121.0
	t.check(not reconnect.apply_character(returned, invalid), "over-cap burn rejected")
	t.eq(returned.flare_seconds, 117.0, "invalid save does not mutate player")

	t.current = "real infected AI respects mobile flare detection"
	var zombie := Zombie.new(server.new_id(), "walker",
		survivor.position + Vector3(25, 0, 0))
	server.zombies[zombie.id] = zombie
	server.tick_count = 2
	server._tick_zombies(0.05)
	t.eq(zombie.target_id, 99, "flare visible outside ordinary walker night sight")
	survivor.flare_seconds = 0.0
	zombie.state = Zombie.State.IDLE
	zombie.target_id = -1
	zombie.think_timer = 0.0
	server._tick_zombies(0.05)
	t.check(zombie.target_id != 99, "extinguished flare does not reveal idle survivor")
