extends RefCounted
## End-to-end owner-only corpse waypoint, real loot competition and expiry.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const DeathRecovery = preload("res://scripts/shared/death_recovery.gd")
const Atlas = preload("res://scripts/shared/expedition_atlas.gd")
const WorldMap = preload("res://scripts/client/world_map.gd")
const Radar = preload("res://scripts/client/survival_radar.gd")


class FakeClient:
	extends RefCounted
	var you: Dictionary = {}


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "only a genuine full-loot death creates a private recovery route"
	var world := WorldGen.new(114)
	var sim := GameServer.new(world, 114)
	var survivor = sim.add_player(101, "Fallen", "account-fallen")
	var stranger = sim.add_player(102, "Raider", "account-raider")
	survivor.position = _at(world, 0.0, 0.0)
	survivor.inventory.add("silver", 10)
	t.eq(sim.snapshot_for(101)["you"].get("death_recovery", {}), {},
		"safe survivor has no ghost bag waypoint")
	sim._on_player_death(survivor, -1)
	t.eq(sim.snapshot_for(101)["you"].get("death_recovery", {}), {},
		"safe-zone death does not create a loot-recovery beacon")
	t.eq(survivor.inventory.count("silver"), 10, "protected-zone death does not drop silver")
	survivor.survival.reset()
	survivor.inventory.add("wood_1", 4)
	survivor.position = _at(world, 800.0, 0.0)
	t.check(world.zone_at(800.0, 0.0) >= 2, "selected site is a full-loot PvP zone")
	sim._on_player_death(survivor, -1)
	var lost: Dictionary = sim.snapshot_for(101)["you"]["death_recovery"]
	t.check(not lost.is_empty(), "real dangerous-zone death records public backpack")
	t.eq(lost.get("x"), 800.0, "owner receives exact server-side drop X")
	t.eq(lost.get("z"), 0.0, "owner receives exact server-side drop Z")
	t.eq(lost.get("remaining"), GameServer.BAG_LIFETIME,
		"recovery compass lasts precisely as long as the real bag")
	t.check(not lost.has("items") and not lost.has("death_recovery_owner") and
		not lost.has("id"), "private navigation discloses no items, account ID or bag ID")
	t.eq(sim.snapshot_for(102)["you"]["death_recovery"], {},
		"unrelated remote player receives no private corpse waypoint")
	t.eq(Atlas.find(Atlas.objectives(sim.snapshot_for(101)["you"]), "recovery")["label"],
		"LOST BACKPACK", "owner's map atlas exposes selectable lost-backpack goal")
	t.eq(Atlas.find(Atlas.objectives(sim.snapshot_for(102)["you"]), "recovery"), {},
		"other player's expedition atlas cannot see private recovery marker")
	var bag_id: int = -1
	for id in sim.bags:
		if sim.bags[id].has("death_recovery_owner"):
			bag_id = int(id)
	t.check(bag_id > 0, "the marker points at a real lootable world bag")
	if bag_id < 0:
		return
	t.check(sim.bags[bag_id]["items"].has("wood_1"), "bag holds actual lost inventory")
	var other_view: Dictionary = sim.bags[bag_id]
	t.check(not other_view.has("allowed_tokens"),
		"PvP corpse bags remain public with no new loot reservation")
	t.eq(DeathRecovery.public_mark(sim.bags, stranger, sim.time), {},
		"server cannot derive someone else's recovery destination")

	t.current = "private waypoint follows real bag while traversing distant world"
	survivor.survival.reset()
	survivor.position = _at(world, 0.0, 0.0)
	var fake := FakeClient.new()
	fake.you = sim.snapshot_for(101)["you"]
	var map := WorldMap.new()
	map.client = fake
	var radar := Radar.new()
	radar.client = fake
	map.personal_waypoint_changed.connect(radar.set_personal_waypoint)
	t.check(map.select_objective("recovery"), "lost backpack is clickable on the atlas")
	t.eq(map.waypoint, Vector2(800.0, 0.0), "map routes to the actual loot bag")
	t.eq(radar.personal_waypoint, map.waypoint, "atlas selection guides tactical radar")
	t.eq(radar.current_death_recovery().get("remaining"), GameServer.BAG_LIFETIME,
		"the owner's radar receives the current countdown")
	var remote: Dictionary = sim.snapshot_for(102)
	t.eq(Atlas.find(Atlas.objectives(remote["you"]), "recovery"), {},
		"stranger cannot obtain recovered coordinates by watching the map")

	t.current = "public looting clears stolen bag and navigation immediately"
	stranger.position = _at(world, 800.0, 0.0)
	var stolen: Dictionary = sim.cmd_loot(stranger.id, bag_id)
	t.check(stolen.get("ok", false), "other player can steal unreserved public corpse")
	t.check(not sim.bags.has(bag_id), "empty bag is removed after actual theft")
	t.eq(DeathRecovery.public_mark(sim.bags, survivor, sim.time), {},
		"missing bag cannot keep a ghost marker on private map")
	fake.you = sim.snapshot_for(101)["you"]
	map._process(0.1)
	t.eq(map.followed_objective, "", "theft automatically cancels stale tracked goal")
	t.check(not radar.personal_waypoint.is_finite(),
		"theft automatically removes stale private radar navigation")
	map.free()
	radar.free()

	t.current = "account reconnect finds same-server bag; guests cannot hijack"
	var second_id: int = sim._make_bag(_at(world, 830.0, 0.0), {"silver": 12})
	DeathRecovery.tag(sim.bags[second_id], survivor)
	var another_id: int = sim._make_bag(_at(world, 850.0, 0.0), {"silver": 1})
	DeathRecovery.tag(sim.bags[another_id], survivor)
	var same_account = sim.add_player(104, "Returned", "account-fallen")
	t.eq(DeathRecovery.public_mark(sim.bags, same_account, sim.time).get("x"), 850.0,
		"authenticated account reconnect recovers newest still-live bag")
	t.eq(DeathRecovery.public_mark(sim.bags, stranger, sim.time), {},
		"other accounts cannot request a victim's old bag")
	var first_guest = sim.add_player(200, "Guest")
	var guest_id: int = sim._make_bag(_at(world, 870.0, 0.0), {"wood_1": 1})
	DeathRecovery.tag(sim.bags[guest_id], first_guest)
	sim.remove_player(200)
	var reused_guest = sim.add_player(200, "Reused peer ID")
	t.eq(DeathRecovery.public_mark(sim.bags, reused_guest, sim.time), {},
		"recycled guest peer ID never gains the original session's corpse")
	t.eq(DeathRecovery.public_mark(sim.bags, survivor, sim.time).get("x"), 850.0,
		"guest traffic cannot affect tracked account bag")

	t.current = "expired or empty bags cannot reveal stale or malformed coordinates"
	sim.time = GameServer.BAG_LIFETIME
	t.eq(DeathRecovery.public_mark(sim.bags, survivor, sim.time), {},
		"expiry boundary hides corpse even before cleanup tick")
	sim._tick_world(0.0)
	t.check(not sim.bags.has(second_id) and not sim.bags.has(another_id),
		"normal world tick removes expired abandoned bags")
	var forged: Dictionary = {
		99: {"id": 99, "x": INF, "z": 5.0, "expires": 5000.0,
			"items": {"silver": 1}, "death_recovery_owner": "account:account-fallen"}}
	t.eq(DeathRecovery.public_mark(forged, survivor, 0.0), {},
		"nonfinite bag coordinates never produce a navigation target")
	forged[99]["x"] = 15.0
	forged[99]["items"] = {}
	t.eq(DeathRecovery.public_mark(forged, survivor, 0.0), {},
		"already-looted empty bag never produces a target")
	t.eq(DeathRecovery.public_mark({}, survivor, INF), {},
		"invalid server time produces no guidance")
