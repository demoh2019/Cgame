extends RefCounted
## Server signal → client cache → party-only world/map beacon. No live network needed.

const PartySupplyBeacon = preload("res://scripts/client/party_supply_beacon.gd")
const PartySupplyRequest = preload("res://scripts/shared/party_supply_request.gd")
const GameClient = preload("res://scripts/client/game_client.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Net = preload("res://scripts/shared/net.gd")


func run(t) -> void:
	t.current = "trusted supply event only produces a timely private marker"
	var party := {"id": 4, "members": [11, 12]}
	var event := {"type": "party_supply_request", "peer": 11, "group": 4,
		"name": "Scout", "need": "food", "level": 25, "x": 15.0, "z": 12.0,
		"expires": 45.0}
	var marker: Dictionary = PartySupplyBeacon.read(event, 12, party, 0.0)
	t.check(not marker.is_empty(), "live party member can see supply location")
	t.eq(marker.get("need", ""), "food", "marker preserves approved need")
	t.near(float(marker.get("x", 0.0)), 15.0, 0.001, "coordinate is unchanged")
	t.check(PartySupplyBeacon.read(event, 13, party, 0.0).is_empty(),
		"outsider cannot render the request")
	t.check(PartySupplyBeacon.read(event, 11, party, 0.0).is_empty(),
		"sender has no duplicate personal marker")
	t.check(PartySupplyBeacon.read(event, 12, {"id": 5, "members": [11, 12]}, 0.0).is_empty(),
		"switching groups removes private coordinates")
	t.check(PartySupplyBeacon.read(event, 12, {"id": 4, "members": [12]}, 0.0).is_empty(),
		"member leaving revokes cached location")
	t.check(PartySupplyBeacon.read(event, 12, party, 45.0).is_empty(),
		"marker expires exactly on server deadline")
	t.check(PartySupplyBeacon.read(event, 12, party, 45.1).is_empty(),
		"expired markers cannot be resurrected")
	var invalid: Dictionary = event.duplicate()
	invalid["expires"] = 5000.0
	t.check(PartySupplyBeacon.read(invalid, 12, party, 0.0).is_empty(),
		"unbounded duration is not accepted")
	invalid = event.duplicate()
	invalid["x"] = INF
	t.check(PartySupplyBeacon.read(invalid, 12, party, 0.0).is_empty(),
		"invalid world coordinates are not shown")
	invalid = event.duplicate()
	invalid["need"] = "secret"
	t.check(PartySupplyBeacon.read(invalid, 12, party, 0.0).is_empty(),
		"unknown event types cannot masquerade as aid")
	invalid = event.duplicate()
	invalid["level"] = NAN
	t.check(PartySupplyBeacon.read(invalid, 12, party, 0.0).is_empty(),
		"invalid player stats are hidden")

	t.current = "real server request reaches client and expires on next snapshot"
	var world := WorldGen.new(839)
	var sim := GameServer.new(world, 839)
	var scout = sim.add_player(11, "Scout")
	var ally = sim.add_player(12, "Cook")
	scout.position = Vector3(8, world.height_at(8, 8), 8)
	ally.position = scout.position + Vector3(1, 0, 0)
	scout.survival.hunger = 25.0
	t.check(sim.cmd_party_invite(11, 12).get("ok", false), "server invite works")
	t.check(sim.cmd_party_accept(12).get("ok", false), "server accepts teammate")
	sim.drain_events()
	t.check(sim.cmd_party_supply_request(11, "food").get("ok", false),
		"server creates a real hunger signal")
	var issued: Dictionary = sim.drain_events()[0]
	t.near(float(issued.get("expires", -1.0)), sim.time + PartySupplyRequest.ALERT_SECONDS,
		0.001, "server attaches a fixed expiration")
	var net := Net.new()
	var local := GameClient.new(net)
	local.peer_id = 12
	local.server_time = sim.time
	local.you = {"party": sim.snapshot_for(12)["you"]["party"]}
	local.on_events([issued])
	t.check(not local.active_supply_beacon().is_empty(),
		"network event appears in client-visible beacon cache")
	t.eq(str(local.active_supply_beacon().get("name", "")), "Scout",
		"beacon identifies the player requesting aid")
	local.server_time = sim.time + PartySupplyRequest.ALERT_SECONDS
	t.check(local.active_supply_beacon().is_empty(), "the client hides expired beacon")
	local.server_time = sim.time
	local.you = {"party": {"id": 0, "members": []}}
	t.check(local.active_supply_beacon().is_empty(), "leaving group hides cached alert")
	local.you = {"party": sim.snapshot_for(12)["you"]["party"]}
	local.on_events([issued])
	t.check(not local.active_supply_beacon().is_empty(), "signal is usable again on valid party view")
	local.on_welcome(839, 30)
	t.check(local.active_supply_beacon().is_empty(), "reconnect clears old survivor alerts")
	local = null
	net.free()
