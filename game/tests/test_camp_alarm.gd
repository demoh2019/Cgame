extends RefCounted
## Camp alarms: real fuel, paid recipe, server-owned threat scans and private
## notifications. Neither attackers nor clients can forge enemy sightings.
const CampAlarm = preload("res://scripts/shared/camp_alarm.gd")
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")
const Persist = preload("res://scripts/server/world_persistence.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const BarricadeTest = preload("res://tests/test_barricades.gd")


func _at(world, point: Vector2) -> Vector3:
	return Vector3(point.x, world.height_at(point.x, point.y), point.y)


## The actual _tick_world() alarm pathway must produce identical private
## notifications with native batched counts and the old exhaustive scan.
static func _dense_camp_alarm_server(force_fallback: bool) -> Dictionary:
	var sim := GameServer.new(WorldGen.new(932), 932)
	sim.time = 2.1
	if force_fallback:
		sim._pack_spatial_grid = RefCounted.new()
	var owner = sim.add_player(341, "Alarm owner")
	owner.position = Vector3(200.0, WorldGen.HUB_HEIGHT, 200.0)
	for i in range(4):
		var id: int = 88000 + i
		sim.campfires[id] = {
			"id": id, "x": 200.0 + float(i) * 200.0,
			"y": WorldGen.HUB_HEIGHT, "z": 200.0,
			"expires": 100.0, "alarm_owner": owner.id,
			"alarm_group": 0, "alarm_until": 90.0,
			"alarm_next_scan": 2.0, "alarm_next_alert": 0.0,
		}
	for i in range(32):
		var position := Vector3(1400.0 + float(i) * 30.0, WorldGen.HUB_HEIGHT, 1400.0)
		if i == 0 or i == 4 or i == 5 or i == 6:
			position = Vector3(200.0, WorldGen.HUB_HEIGHT, 200.0)
		elif i == 1:
			position = Vector3(220.0, WorldGen.HUB_HEIGHT, 200.0)
		elif i == 2:
			position = Vector3(200.0, WorldGen.HUB_HEIGHT + 8.0, 200.0)
		elif i == 3:
			position = Vector3(200.0, WorldGen.HUB_HEIGHT + 9.0, 200.0)
		elif i == 7:
			position = Vector3(400.0, WorldGen.HUB_HEIGHT, 200.0)
		elif i == 8:
			position = Vector3(600.0, WorldGen.HUB_HEIGHT, 200.0)
		var infected := Zombie.new(95000 + i, "walker", position)
		if i == 4:
			infected.raid_boss = true # Existing alarm counts all actual living infected.
		sim.zombies[infected.id] = infected
	sim._tick_world(0.1)
	var alarms: Array = []
	for event in sim.events:
		if event.get("type", "") == "camp_alarm":
			alarms.append({"peer": int(event["peer"]),
				"count": int(event["count"]), "x": float(event["x"])})
	var schedules: Array = []
	for id in sim.campfires:
		var fire: Dictionary = sim.campfires[id]
		schedules.append({"id": id,
			"next_scan": float(fire.get("alarm_next_scan", 0.0)),
			"next_alert": float(fire.get("alarm_next_alert", 0.0))})
	var stats: Dictionary = sim.get_camp_alarm_query_stats()
	return {"alarms": alarms, "schedules": schedules, "stats": stats}


func run(t) -> void:
	t.current = "Native Mass-style camp cylinder counts preserve real server events"
	var old_server: Dictionary = _dense_camp_alarm_server(true)
	var fast_server: Dictionary = _dense_camp_alarm_server(false)
	var native_available: bool = ClassDB.class_exists("AIProximityGrid2D") \
		and ClassDB.class_has_method("AIProximityGrid2D", "query_cylinder_counts_batch")
	t.eq(fast_server["alarms"], old_server["alarms"],
		"native cylinders emit the same private bounded alarm events as full scanning")
	t.eq(fast_server["schedules"], old_server["schedules"],
		"native prefilter cannot change scan interval or alert cooldown")
	t.eq(fast_server["alarms"], [
		{"peer": 341, "count": 5, "x": 200.0},
		{"peer": 341, "count": 1, "x": 400.0},
		{"peer": 341, "count": 1, "x": 600.0},
	], "same live infected, bosses, vertical gates and five-enemy cap")
	t.eq(bool(fast_server["stats"].get("native", false)), native_available,
		"actual server tick uses native cylinder batch only where available")
	t.check(not bool(old_server["stats"].get("native", false)),
		"forced legacy server uses original GDScript scans")
	if native_available:
		t.eq(int(fast_server["stats"]["centers"]), 4,
			"native batch processes all due camp alarms together")
		t.eq(int(fast_server["stats"]["targets"]), 32,
			"native query considers the real living infected cohort")


	t.current = "paid camp sentry recipe and strict fire geometry"
	t.check(Defs.is_item(CampAlarm.ITEM_ID), "alarm kit is a real craftable item")
	t.eq(Defs.recipes()[CampAlarm.ITEM_ID]["inputs"],
		{"wood_1": 1, "fiber_1": 2, "scrap": 2}, "field craft has real costs")
	var fire := {"id": 11, "x": 10.0, "y": 5.0, "z": 10.0, "expires": 120.0}
	var here := Vector3(10, 5, 10)
	t.eq(CampAlarm.arm_reason({}, here, 0.0), "no_fire", "cannot arm without fire")
	t.eq(CampAlarm.arm_reason(fire, Vector3.INF, 0.0),
		"invalid_position", "nonfinite positions rejected")
	t.eq(CampAlarm.arm_reason(fire, Vector3(20, 5, 10), 0.0),
		"too_far", "remote arm attempts rejected")
	t.eq(CampAlarm.arm_reason(fire, Vector3(10, 10, 10), 0.0),
		"too_far", "other floor cannot reach fire")
	t.eq(CampAlarm.arm_reason(fire, here, 80.0), "low_fuel",
		"alarm refuses a nearly extinguished fire without charging a kit")
	t.eq(CampAlarm.arm_reason(fire, here, 0.0), "", "adequate fire can be armed")
	CampAlarm.install(fire, 11, 22, 0.0)
	t.eq(CampAlarm.arm_reason(fire, here, 2.0), "already_armed",
		"cannot waste another kit on same active alarm")
	t.near(CampAlarm.seconds_left(fire, 0.0), 120.0, 0.001,
		"alarm cannot outlast physical fire")
	t.eq(CampAlarm.seconds_left(fire, 120.0), 0.0,
		"fuse expires when fire does")

	t.current = "malformed alarm clocks cannot produce false infected warnings"
	var bad_scan: Dictionary = fire.duplicate(true)
	bad_scan["alarm_next_scan"] = NAN
	var test_enemy := Zombie.new(955, "walker", Vector3(19, 5, 10))
	t.eq(CampAlarm.scan(bad_scan, {955: test_enemy}, 2.0), 0,
		"invalid scan deadline cannot cause an alarm notification")
	bad_scan["alarm_next_scan"] = 2.0
	bad_scan["alarm_next_alert"] = NAN
	t.eq(CampAlarm.scan(bad_scan, {955: test_enemy}, 2.0), 0,
		"invalid alert cooldown cannot bypass notification rate limits")
	bad_scan["alarm_next_alert"] = INF
	t.eq(CampAlarm.scan(bad_scan, {955: test_enemy}, 2.0), 0,
		"infinite alert deadline cannot be converted into a warning")
	bad_scan["alarm_next_alert"] = 0.0
	t.eq(CampAlarm.scan(bad_scan, {955: test_enemy}, NAN), 0,
		"invalid simulation timestamp cannot leak an alarm")
	t.eq(CampAlarm.scan(bad_scan, {955: test_enemy}, 2.0), 1,
		"normal finite clock values continue to allow real detections")

	t.current = "bounded two-second scans and 24-second repeated warning cap"
	var enemies: Dictionary = {}
	var walker := Zombie.new(401, "walker", Vector3(19, 5, 10))
	enemies[401] = walker
	t.eq(CampAlarm.scan(fire, enemies, 1.9), 0,
		"no scan before minimum sampling interval")
	t.eq(CampAlarm.scan(fire, enemies, 2.0), 1,
		"one close real infected triggers a warning")
	t.eq(CampAlarm.scan(fire, enemies, 2.1), 0,
		"no per-frame warning spam")
	t.eq(CampAlarm.scan(fire, enemies, 4.0), 0,
		"warning cannot bypass cooldown after next scan")
	t.eq(CampAlarm.scan(fire, enemies, 26.0), 1,
		"another warning available after fixed cooldown")
	walker.position = Vector3(100, 5, 10)
	t.eq(CampAlarm.scan(fire, enemies, 28.0), 0,
		"distant infected are not detected")
	t.eq(CampAlarm.scan(fire, enemies, 50.0), 0,
		"no fabricated detections when camp is clear")
	t.eq(CampAlarm.scan(fire, enemies, 120.0), 0,
		"alarm never fires after expiry")
	var visible := FieldCampfire.visible({11: fire}, here, 2.0, 50.0)
	t.eq(visible.size(), 1, "nearby campfire remains visible")
	t.check(float(visible[0].get("alarm_seconds", 0.0)) > 0.0,
		"public campfire snapshot includes only alarm duration")
	t.check(not visible[0].has("alarm_owner") and not visible[0].has("alarm_group"),
		"snapshot never exposes owner/group identifiers")

	t.current = "real game server authorizes paid camp alarm and hides broadcasts"
	var world := WorldGen.new(214)
	var sim := GameServer.new(world, 214)
	var site: Vector2 = BarricadeTest.new()._find_place(world)
	t.check(site != Vector2.ZERO, "valid dry site exists")
	if site == Vector2.ZERO:
		return
	var survivor = sim.add_player(101, "Sentry")
	var ally = sim.add_player(102, "Scout")
	var outsider = sim.add_player(103, "Unknown")
	var origin := site + Vector2(-2.8, 0)
	survivor.position = _at(world, origin)
	ally.position = _at(world, site + Vector2(-9, 0))
	outsider.position = _at(world, site + Vector2(-12, 0))
	survivor.inventory.add("wood_1", 3)
	survivor.inventory.add("stone_1", 1)
	t.eq(sim.cmd_arm_camp_alarm(999, 1).get("reason", ""), "dead",
		"unregistered peer cannot arm an alarm")
	var lit: Dictionary = sim.cmd_light_campfire(101, site.x, site.y)
	t.check(lit.get("ok", false), "real material-paid fire is lit")
	if not bool(lit.get("ok", false)):
		return
	var fire_id: int = int(lit["id"])
	t.eq(sim.cmd_arm_camp_alarm(101, fire_id).get("reason", ""),
		"missing_kit", "server denies free alarm arming")
	t.check(sim.cmd_party_invite(101, 102).get("ok", false), "invite teammate")
	t.check(sim.cmd_party_accept(102).get("ok", false), "teammate consents")
	ally.position = _at(world, origin + Vector2(0, 1.0))
	outsider.position = _at(world, origin + Vector2(0, 2.0))
	survivor.inventory.add(CampAlarm.ITEM_ID, 2)
	var ready: Dictionary = sim.cmd_arm_camp_alarm(101, fire_id)
	t.check(ready.get("ok", false), "server arms kit on an active campfire")
	t.eq(survivor.inventory.count(CampAlarm.ITEM_ID), 1,
		"server spends exactly one item")
	t.eq(sim.cmd_arm_camp_alarm(101, fire_id).get("reason", ""),
		"already_armed", "cannot double-pay for a live sentry")
	t.eq(survivor.inventory.count(CampAlarm.ITEM_ID), 1,
		"failed second attempt cannot waste another kit")
	t.check(survivor.dirty_inventory and survivor.dirty_character,
		"persistent inventory and character marked dirty")
	t.check(not Persist.capture(sim).has("campfires"),
		"alarm and campfire are temporary, never persisted")
	sim.zombies.clear()
	var danger := Zombie.new(sim.new_id(), "walker",
		_at(world, site + Vector2(8, 0)))
	sim.zombies[danger.id] = danger
	sim.time = 2.1
	sim._tick_world(0.1)
	var alert: Dictionary = {}
	for event in sim.drain_events():
		if event.get("type", "") == "camp_alarm":
			alert = event
	t.check(not alert.is_empty(), "real infected near armed fire creates a warning")
	if alert.is_empty():
		return
	t.check(int(alert.get("count", 0)) > 0, "bounded nonzero threat count")
	t.check(not alert.has("enemy_id") and not alert.has("enemy_position"),
		"warnings never expose exact target locations")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net.has_method("c_arm_camp_alarm"),
		"authenticated multiplayer arming RPC is wired")
	t.check(net._event_visible_to(alert, 101), "owner sees nearby warning")
	t.check(net._event_visible_to(alert, 102), "current nearby teammate sees warning")
	t.check(not net._event_visible_to(alert, 103), "outsider cannot spy on camp")
	ally.position = _at(world, site + Vector2(200, 0))
	t.check(not net._event_visible_to(alert, 102),
		"remote teammate cannot remotely track camp enemy counts")
	ally.position = _at(world, origin + Vector2(0, 1.0))
	t.check(sim.cmd_party_leave(102).get("ok", false), "ally leaves party")
	t.check(not net._event_visible_to(alert, 102),
		"party leave revokes queued alarm visibility")
	sim.time = 2.2
	sim._tick_world(0.1)
	for event in sim.drain_events():
		t.check(event.get("type", "") != "camp_alarm",
			"no duplicate alert on the following tick")
	sim.remove_player(101)
	t.eq(CampAlarm.seconds_left(sim.campfires[fire_id], sim.time), 0.0,
		"owner disconnect immediately disables session-only sentry")
	t.check(not net._event_visible_to(alert, 101),
		"disconnected owner cannot receive historic warnings")
	net.free()
