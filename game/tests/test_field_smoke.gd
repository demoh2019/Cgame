extends RefCounted
## Paid smoke clouds; sight-only; no permanent state, client coordinates or free items.
const Smoke = preload("res://scripts/shared/field_smoke.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const EvasionTest = preload("res://tests/test_evasion.gd")
const Persist = preload("res://scripts/server/world_persistence.gd")


func run(t) -> void:
	var world := WorldGen.new(2090)
	var site: Vector2 = EvasionTest.new()._clear_red_zone_spot(world)
	t.current = "server-authoritative smoke charges consume items exactly once"
	t.check(site.is_finite(), "real dry dangerous-zone field site")
	if not site.is_finite():
		return
	var sim := GameServer.new(world, 2090)
	var scout = sim.add_player(89, "Smoker")
	scout.position = Vector3(site.x, world.height_at(site.x, site.y), site.y)
	t.eq(str(Defs.item(Smoke.ITEM_ID).get("kind", "")), "smoke_charge",
		"craftable tactical item exists")
	t.eq(sim.cmd_use(89, Smoke.ITEM_ID).get("reason", ""), "not_carried",
		"absent charge cannot be deployed")
	scout.inventory.add(Smoke.ITEM_ID, 2)
	var first: Dictionary = sim.cmd_use(89, Smoke.ITEM_ID)
	t.check(first.get("ok", false), "real charge deploys a cloud")
	t.eq(scout.inventory.count(Smoke.ITEM_ID), 1, "one charge consumed")
	t.eq(sim.smoke_clouds.size(), 1, "one cloud created")
	t.near(scout.smoke_cooldown, Smoke.COOLDOWN, 0.001,
		"recharge server-owned")
	t.eq(sim.cmd_use(89, Smoke.ITEM_ID).get("reason", ""), "cooldown",
		"repeat use cannot stack clouds")
	t.eq(scout.inventory.count(Smoke.ITEM_ID), 1,
		"rejected use never eats a charge")
	t.eq(sim.cmd_use(999, Smoke.ITEM_ID).get("reason", ""), "dead",
		"unknown peer cannot deploy charges")
	t.current = "smoke is a visual-only first-acquisition defense"
	t.check(Smoke.inside(sim.smoke_clouds, scout.position, sim.time),
		"living player inside cloud radius")
	t.near(Smoke.signature(1.0, sim.smoke_clouds, scout.position, sim.time, 0.0, true),
		Smoke.MULTIPLIER, 0.001, "quiet visual signature reduced")
	t.eq(Smoke.signature(1.0, sim.smoke_clouds, scout.position, sim.time, 1.0, true),
		1.0, "noise instantly defeats smoke vision bonus")
	t.eq(Smoke.signature(1.0, sim.smoke_clouds, scout.position, sim.time, 0.0, false),
		1.0, "dead players get no smoke bonus")
	t.near(Smoke.signature(0.4, sim.smoke_clouds, scout.position, sim.time, 0.0, true),
		Smoke.MIN_VISUAL, 0.001, "smoke stacks but respects minimum visibility")
	var outside := Vector3(site.x + Smoke.RADIUS + 1.0, scout.position.y, site.y)
	t.eq(Smoke.signature(1.0, sim.smoke_clouds, outside, sim.time, 0.0, true),
		1.0, "outside radius has no bonus")
	scout.noise_timer = 0.0
	t.near(sim._visual_signature_for(scout), Smoke.MULTIPLIER, 0.001,
		"server infected vision uses same smoke factor as own HUD")
	var infected := Zombie.new(sim.new_id(), "walker",
		Vector3(site.x + 11.0, world.height_at(site.x + 11.0, site.y), site.y))
	var info: Dictionary = {89: {"position": scout.position, "alive": true,
		"safe": false, "noise": 0.0, "scent": 0.0,
		"visual_signature": sim._visual_signature_for(scout)}}
	infected._select_target(info, Vector2(infected.position.x, infected.position.z))
	t.eq(infected.target_id, -1, "smoke conceals from distant passive infected")
	info[89]["visual_signature"] = 1.0
	infected._select_target(info, Vector2(infected.position.x, infected.position.z))
	t.eq(infected.target_id, 89, "unconcealed player is spotted from same distance")
	scout.noise_timer = 1.0
	t.eq(sim._visual_signature_for(scout), 1.0,
		"server cannot treat gunfire or sprint as silent")
	t.current = "smoke cover respects floors and malformed world state"
	var cloud_data: Dictionary = sim.smoke_clouds.values()[0]
	var upstairs: Vector3 = scout.position + Vector3(0.0, Smoke.HEIGHT_LIMIT + 1.0, 0.0)
	t.check(not Smoke.inside(sim.smoke_clouds, upstairs, sim.time),
		"ground-floor smoke cannot cloak players on another floor")
	t.eq(Smoke.signature(1.0, sim.smoke_clouds, upstairs, sim.time, 0.0, true),
		1.0, "infected still see an upstairs player through ground-level smoke")
	t.eq(Smoke.visible(sim.smoke_clouds, upstairs, sim.time, 50.0), [],
		"far-above observer does not receive ground-level cosmetic smoke")
	t.check(Smoke.inside(sim.smoke_clouds, scout.position, sim.time),
		"the actual throwing survivor retains the normal cover bonus")
	var dirty: Dictionary = {
		1: {"x": site.x, "z": site.y, "y": scout.position.y,
			"expires": INF, "id": 1},
		2: {"x": NAN, "z": site.y, "y": scout.position.y,
			"expires": sim.time + 10.0, "id": 2},
		3: {"x": site.x, "z": site.y, "y": NAN,
			"expires": sim.time + 10.0, "id": 3},
		4: {"x": site.x, "z": site.y, "y": scout.position.y,
			"expires": NAN, "id": 4},
		5: {"x": site.x, "z": site.y, "y": scout.position.y,
			"expires": sim.time, "id": 5},
		6: "corrupt-cloud"
	}
	t.check(not Smoke.inside(dirty, scout.position, sim.time),
		"invalid or expired smoke never grants free concealment")
	t.eq(Smoke.visible(dirty, scout.position, sim.time, 50.0), [],
		"invalid cloud data is never serialized into the visible world")
	t.eq(Smoke.signature(1.0, sim.smoke_clouds, scout.position, sim.time, -0.1, true),
		1.0, "invalid negative noise time cannot mint stealth")
	t.eq(Smoke.visible({7: cloud_data}, scout.position, sim.time, 50.0).size(), 1,
		"live smoke remains visible at ordinary height")

	t.current = "replication, expiry and storage safety"
	var snap: Dictionary = sim.snapshot_for(89)
	t.eq(snap["smoke_clouds"].size(), 1, "owner sees the deployed cloud")
	t.check(not snap["smoke_clouds"][0].has("owner"),
		"public state has no private owner peer")
	t.check(not snap["smoke_clouds"][0].has("owner_account"),
		"public state has no account IDs")
	var far_player = sim.add_player(90, "Remote")
	far_player.position = Vector3(site.x + 250.0,
		world.height_at(site.x + 250.0, site.y), site.y)
	t.eq(sim.snapshot_for(90)["smoke_clouds"].size(), 0,
		"interest radius hides remote cloud positions")
	t.check(not Persist.capture(sim).has("smoke_clouds"),
		"smoke never persisted as permanent world data")
	sim.time += Smoke.DURATION + 0.1
	t.check(not Smoke.inside(sim.smoke_clouds, scout.position, sim.time),
		"expired cloud does not grant a stale bonus")
	sim._tick_world(0.05)
	t.eq(sim.smoke_clouds.size(), 0, "server cleans expired cloud")
	scout.smoke_cooldown = 0.0
	t.check(sim.cmd_use(89, Smoke.ITEM_ID).get("ok", false),
		"second real charge still usable after expiry")
	t.eq(scout.inventory.count(Smoke.ITEM_ID), 0,
		"second cast cannot mint additional smoke charges")
