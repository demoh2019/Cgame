extends RefCounted
## Real server-owned night lantern, infected visibility and a lightweight bike light.

const BikeLantern = preload("res://scripts/shared/bike_lantern.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Mounts = preload("res://scripts/shared/mounts.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const TrailBikeVisual = preload("res://scripts/client/trail_bike_visual.gd")


func run(t) -> void:
	t.current = "craftable night bicycle lamp"
	t.eq(Defs.item(BikeLantern.ITEM_ID).get("kind"), "bike_light",
		"dynamo lamp is a real economic item")
	t.eq(Defs.recipes()[BikeLantern.ITEM_ID]["station"], "workbench",
		"lamp needs workbench craft")
	var inventory := Inventory.new()
	t.eq(BikeLantern.lit(inventory, true, true, true), false,
		"no free lantern for owners without the item")
	inventory.add(BikeLantern.ITEM_ID, 1)
	t.eq(BikeLantern.lit(inventory, true, true, true), false,
		"lamp alone never creates a bicycle")
	inventory.add(Mounts.ITEM_ID, 1)
	t.eq(BikeLantern.lit(inventory, true, true, true), true,
		"owned lamp shines during night cycling")
	for blocked in [
		{"riding": false, "alive": true, "night": true},
		{"riding": true, "alive": false, "night": true},
		{"riding": true, "alive": true, "night": false}
	]:
		t.eq(BikeLantern.lit(inventory, bool(blocked["riding"]),
			bool(blocked["alive"]), bool(blocked["night"])), false,
			"dismounted, dead and daylight states cannot shine")
	t.eq(BikeLantern.reveal_radius(inventory, true, true, true),
		BikeLantern.REVEAL_RADIUS, "light has a bounded infected reveal radius")
	t.eq(BikeLantern.reveal_radius(inventory, false, true, true), 0.0,
		"on-foot walking remains stealth-neutral")

	t.current = "server-owned lantern state and sight danger"
	var world = preload("res://scripts/shared/world_gen.gd").new(42)
	var server := GameServer.new(world, 42)
	var rider = server.add_player(717, "NightCourier")
	rider.inventory.add(Mounts.ITEM_ID, 1)
	rider.inventory.add(BikeLantern.ITEM_ID, 1)
	server.time = WorldCycle.DAY_LENGTH * 0.75
	t.check(WorldCycle.is_night(server.time), "test night is an actual shared clock night")
	t.eq(server.cmd_toggle_mount(717).get("mounted"), true, "authentic rider mounts")
	t.eq(server.snapshot_for(717)["you"]["bike_lamp_lit"], true,
		"server reports lamp activation at night")
	var z := Zombie.new(300, "walker",
		rider.position + Vector3(19.0, 0, 0))
	var night_player := {
		"position": rider.position, "alive": true, "safe": false,
		"visual_signature": 0.35, "notice_multiplier": 1.0,
		"weather_sight": 0.5, "noise": 0.0, "firelight": BikeLantern.REVEAL_RADIUS
	}
	z._select_target({717: night_player}, Vector2(z.position.x, z.position.z))
	t.eq(z.target_id, 717, "idle infected detects illuminated rider past stealth sight")
	z.target_id = -1
	z.state = Zombie.State.IDLE
	night_player["firelight"] = 0.0
	z._select_target({717: night_player}, Vector2(z.position.x, z.position.z))
	t.eq(z.target_id, -1, "stealthed unlit rider stays undetected at same distance")
	server.time = 0.0
	t.eq(server.snapshot_for(717)["you"]["bike_lamp_lit"], false,
		"daylight does not waste dynamic lights or expose the rider")
	server.time = WorldCycle.DAY_LENGTH * 0.75
	server.cmd_toggle_mount(717)
	t.eq(server.snapshot_for(717)["you"]["bike_lamp_lit"], false,
		"dismount switches lamp off with no extra network action")
	rider.inventory.remove(BikeLantern.ITEM_ID, 1)
	t.eq(server.snapshot_for(717)["you"]["bike_lamp_lit"], false,
		"selling a lantern cannot leave a phantom light")

	t.current = "client-only 3D lamp geometry"
	var visual := TrailBikeVisual.new()
	visual.build()
	t.check(visual.get_node_or_null("DynamoBeam") != null,
		"procedural bike has a headlight")
	visual.set_lamp(true)
	t.eq(visual.get_node("DynamoBeam").visible, true,
		"night light is visible during mounted travel")
	visual.set_lamp(false)
	t.eq(visual.get_node("DynamoBeam").visible, false,
		"turning lamp off removes point light rendering")
	visual.free()
