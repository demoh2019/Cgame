extends RefCounted
## Party destination preview and private alarm event permissions.
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const CaravanRoutes = preload("res://scripts/shared/caravan_routes.gd")
const Net = preload("res://scripts/shared/net.gd")
const Radar = preload("res://scripts/client/survival_radar.gd")


func _source(world) -> Dictionary:
	for rx in range(-4, 5):
		for rz in range(-4, 5):
			for site in world.poi.sites_in_region(rx, rz):
				if not CaravanRoutes.offer_for(world, site).is_empty():
					return site
	return {}


func run(t) -> void:
	t.current = "caravan waypoint is visible only to authenticated party members"
	var world := WorldGen.new(205)
	var source: Dictionary = _source(world)
	t.check(not source.is_empty(), "procedural map contains two trading stations")
	if source.is_empty():
		return
	var sim := GameServer.new(world, 205)
	var courier = sim.add_player(901, "Courier")
	var escort = sim.add_player(902, "Escort")
	var outsider = sim.add_player(903, "Outsider")
	var x: float = float(source["station_x"])
	var z: float = float(source["station_z"])
	courier.position = Vector3(x, world.height_at(x, z), z)
	escort.position = courier.position + Vector3(1.0, 0.0, 0.0)
	outsider.position = courier.position + Vector3(2.0, 0.0, 0.0)
	t.check(sim.cmd_caravan(901, "accept").get("ok", false),
		"real courier route accepted at NPC bench")
	t.eq(sim.snapshot_for(902)["you"]["party"].get("escort_caravan", {}), {},
		"solo outsider cannot see route before joining")
	t.check(sim.cmd_party_invite(901, 902).get("ok", false), "proximity checked invite")
	t.check(sim.cmd_party_accept(902).get("ok", false), "valid group formed")
	var shared: Dictionary = sim.snapshot_for(902)["you"]["party"]["escort_caravan"]
	t.eq(int(shared.get("owner", 0)), 901, "actual courier ID retained")
	t.eq(shared.get("dst_x", 0.0), courier.caravan_view["dst_x"],
		"destination comes from server-selected route")
	t.check(not shared.has("user_id") and not shared.has("inventory") and
		not shared.has("silver") and not shared.has("src_rx"),
		"no private account, backpack or wallet is published")
	t.eq(sim.snapshot_for(903)["you"]["party"].get("escort_caravan", {}), {},
		"nearby stranger receives nothing")
	var radar := Radar.new()
	radar.sim = sim
	radar.actor_id = 902
	t.eq(radar.current_escort_caravan(), shared, "offline radar uses same private snapshot")
	radar.actor_id = 903
	t.eq(radar.current_escort_caravan(), {}, "outsider radar has no destination")

	t.current = "only courier and current original group receive attack notice"
	var group_id: int = sim.parties.group_of(901)
	var notice := {"type": "caravan_ambushed", "peer": 901, "group": group_id,
		"count": 3, "zone": 2}
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net._event_visible_to(notice, 901), "courier receives own alarm")
	t.check(net._event_visible_to(notice, 902), "escort receives alert")
	t.check(not net._event_visible_to(notice, 903), "stranger denied")
	var forged: Dictionary = notice.duplicate(true)
	forged["group"] = 9999
	t.check(not net._event_visible_to(forged, 902), "fake group cannot route alerts")
	t.check(sim.cmd_party_leave(902).get("ok", false), "escort leaves group")
	t.eq(sim.snapshot_for(902)["you"]["party"].get("escort_caravan", {}), {},
		"party departure revokes waypoint immediately")
	t.check(not net._event_visible_to(notice, 902),
		"queued event cannot be read by former member")
	t.check(net._event_visible_to(notice, 901), "owner retains personal alert")
	escort.position = courier.position + Vector3(1.0, 0.0, 0.0)
	t.check(sim.cmd_party_invite(901, 902).get("ok", false), "new group formed")
	t.check(sim.cmd_party_accept(902).get("ok", false), "new group joined")
	t.check(sim.cmd_caravan(901, "abandon").get("ok", false), "courier cancels job")
	t.eq(sim.snapshot_for(902)["you"]["party"]["escort_caravan"], {},
		"cancelled contract is not visible to former escorts")
	net.free()
