extends RefCounted
## Workbench-paid shelter reinforcement with owner/range and shared storm tests.

const Defs = preload("res://scripts/shared/defs.gd")
const Anchors = preload("res://scripts/shared/storm_tarp_anchors.gd")
const Shelters = preload("res://scripts/shared/portable_shelter.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const BarricadeTest = preload("res://tests/test_barricades.gd")
const Weather = preload("res://scripts/shared/weather.gd")


func _ground(world, pos: Vector2) -> Vector3:
	return Vector3(pos.x, world.height_at(pos.x, pos.y), pos.y)


func run(t) -> void:
	t.current = "workbench kit has a real nonfree recipe"
	t.eq(str(Defs.item(Anchors.ITEM_ID).get("kind")), "tarp_anchor",
		"valid item registered")
	t.eq(Defs.recipes()[Anchors.ITEM_ID]["station"], "workbench",
		"anchors cannot be crafted at a campfire")
	var crafting_bag := Inventory.new()
	crafting_bag.add("bar_2", 1)
	crafting_bag.add("fiber_2", 2)
	crafting_bag.add("cloth_2", 2)
	t.eq(Crafting.craft(crafting_bag, Anchors.ITEM_ID, false),
		Crafting.Result.NO_STATION, "requires workbench")
	t.eq(Crafting.craft(crafting_bag, Anchors.ITEM_ID, true),
		Crafting.Result.OK, "actual ingredients become one kit")
	t.eq(crafting_bag.count(Anchors.ITEM_ID), 1, "single craft output")
	var world := WorldGen.new(214)
	var sim := GameServer.new(world, 22)
	var spot: Vector2 = BarricadeTest.new()._find_place(world)
	t.check(spot != Vector2.ZERO, "real legal tarp placement exists")
	if spot == Vector2.ZERO:
		return
	var owner = sim.add_player(93, "Storm Camper")
	owner.position = _ground(world, spot + Vector2(-2.8, 0.0))
	owner.inventory.add(Anchors.ITEM_ID, 2)
	t.eq(sim.cmd_use(93, Anchors.ITEM_ID).get("reason"), "no_shelter",
		"cannot anchor imaginary structures")
	t.eq(owner.inventory.count(Anchors.ITEM_ID), 2,
		"no-shelter rejection costs nothing")
	owner.inventory.add("cloth_1", 2)
	owner.inventory.add("fiber_1", 2)
	owner.inventory.add("plank_1", 1)
	var pitched: Dictionary = sim.cmd_pitch_shelter(93, spot.x, spot.y)
	t.check(bool(pitched.get("ok", false)), "genuine owner pitches one tarp")
	if not bool(pitched.get("ok", false)):
		return
	var tarp_id: int = int(pitched["id"])
	var old_expiry: float = float(sim.shelters[tarp_id]["expires"])
	var stranger = sim.add_player(94, "Stranger")
	stranger.position = _ground(world, spot + Vector2(1.0, 0.0))
	stranger.inventory.add(Anchors.ITEM_ID, 1)
	t.eq(sim.cmd_use(94, Anchors.ITEM_ID).get("reason"), "not_owner",
		"nearby other survivor cannot upgrade another player's tarp")
	t.eq(stranger.inventory.count(Anchors.ITEM_ID), 1,
		"failed ownership cannot consume other player's kit")
	owner.position = _ground(world, spot + Vector2(15.0, 0.0))
	t.eq(sim.cmd_use(93, Anchors.ITEM_ID).get("reason"), "no_shelter",
		"owner must be physically near the tarp")
	owner.position = _ground(world, spot + Vector2(-2.8, 0.0))
	owner.mounted = true
	t.eq(sim.cmd_use(93, Anchors.ITEM_ID).get("reason"), "mounted",
		"cannot work on a shelter while mounted")
	owner.mounted = false
	owner.attack_timer = 1.0
	t.eq(sim.cmd_use(93, Anchors.ITEM_ID).get("reason"), "in_combat",
		"cannot freely reinforce during an attack")
	owner.attack_timer = 0.0

	t.current = "real paid one-time anchored tarp"
	var result: Dictionary = sim.cmd_use(93, Anchors.ITEM_ID)
	t.check(bool(result.get("ok", false)), "authorized owner can anchor nearby tarp")
	t.eq(owner.inventory.count(Anchors.ITEM_ID), 1, "one actual kit consumed")
	t.near(float(sim.shelters[tarp_id]["expires"]), old_expiry + Anchors.BONUS_SECONDS,
		0.0001, "tarp gained exactly 180 seconds, no more")
	t.eq(result.get("remaining"), Shelters.DURATION + Anchors.BONUS_SECONDS,
		"owner receives exact server expiration")
	t.eq(sim.cmd_use(93, Anchors.ITEM_ID).get("reason"), "already_anchored",
		"replaying use cannot extend shelter twice")
	t.eq(owner.inventory.count(Anchors.ITEM_ID), 1,
		"repeated RPC never charges another kit")
	t.eq(sim.shelters.size(), 1, "upgrade never creates a second shelter")
	var near_snapshot: Array = sim.snapshot_for(stranger.id)["shelters"]
	t.eq(near_snapshot.size(), 1, "nearby player sees same upgraded shelter")
	t.check(bool(near_snapshot[0].get("anchored", false)),
		"public representation reports only anchored flag")
	t.near(float(near_snapshot[0]["remaining"]),
		Shelters.DURATION + Anchors.BONUS_SECONDS, 0.0001,
		"visible timer includes added lifespan")
	t.check(not near_snapshot[0].has("owner") and not near_snapshot[0].has("owner_account"),
		"anonymous nearby users cannot read structure ownership")
	t.check(bool(sim.snapshot_for(stranger.id)["you"]["tent_anchored"]),
		"shared protection belongs to everyone in radius")
	t.check(bool(sim.snapshot_for(owner.id)["you"]["tent_anchored"]),
		"owner also gets anchored shelter at edge of cover")
	t.near(Shelters.exposure_severity(0.8, true, true), 0.08, 0.0001,
		"anchored tarp cuts 90 percent of extreme weather exposure")
	t.near(Shelters.exposure_severity(0.8, true), 0.2, 0.0001,
		"standard tarp still reduces 75 percent")
	t.near(Shelters.exposure_severity(0.8, false, true), 0.8, 0.0001,
		"anchoring cannot grant protection outside a shelter")

	t.current = "expiry and packing remove temporary anchored weather cover"
	t.check(Anchors.anchored_covers(sim.shelters, stranger.position, sim.time),
		"genuine upgraded tarp shelters a second survivor")
	var far := _ground(world, spot + Vector2(25.0, 0.0))
	t.check(not Anchors.anchored_covers(sim.shelters, far, sim.time),
		"unrelated distant players have no coverage")
	t.check(not Anchors.anchored_covers(sim.shelters, Vector3.INF, sim.time),
		"invalid positions cannot obtain protection")
	var projected: Dictionary = sim.shelters[tarp_id]
	projected["expires"] = sim.time
	t.eq(Anchors.nearest({tarp_id: projected}, owner, sim.time).get("reason"),
		"no_shelter", "expired tarp cannot be renewed after deadline")
	t.check(not Anchors.anchored_covers({tarp_id: projected}, stranger.position, sim.time),
		"expired structure gives no cover even before cleanup")
	projected["expires"] = old_expiry + Anchors.BONUS_SECONDS
	sim.shelters[tarp_id] = projected
	t.check(bool(sim.cmd_pack_shelter(93, tarp_id).get("ok", false)),
		"owner can still pack upgraded tarp")
	t.eq(sim.shelters.size(), 0, "packing removes upgrade with tarp")
	t.eq(owner.inventory.count(Anchors.ITEM_ID), 1,
		"packing never refunds previously consumed anchors")
