extends RefCounted
## Real server, RPC and membership privacy checks for food/water distress pings.

const SupplyRequest = preload("res://scripts/shared/party_supply_request.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func run(t) -> void:
	t.current = "supply alerts have bounded needs and a fixed cooldown"
	t.check(SupplyRequest.valid_need("food") and SupplyRequest.valid_need("water"),
		"only food and water alert types exist")
	t.check(not SupplyRequest.valid_need("medicine"), "clients cannot invent alert categories")
	t.check(SupplyRequest.eligible("food", 60.0, 100.0), "threshold is inclusive")
	t.check(not SupplyRequest.eligible("food", 60.1, 0.0),
		"water need cannot masquerade as hunger")
	t.check(SupplyRequest.eligible("water", 100.0, 15.0),
		"dehydration is assessed independently")
	t.check(not SupplyRequest.eligible("water", 0.0, 100.0),
		"healthy thirst cannot trigger an alert")
	t.check(not SupplyRequest.eligible("food", NAN, 100.0),
		"malformed survival data is not broadcast")
	t.check(SupplyRequest.can_send(0.0, -INF), "new session can signal immediately")
	t.check(not SupplyRequest.can_send(29.9, 0.0), "repeated requests are rate limited")
	t.check(SupplyRequest.can_send(30.0, 0.0), "cooldown boundary permits a new request")
	t.check(not SupplyRequest.can_send(INF, -INF), "invalid time does not bypass cooldown")

	t.current = "supply alert cooldown rejects invalid and future session timestamps"
	t.check(not SupplyRequest.can_send(30.0, 31.0),
		"future last-send timestamp cannot bypass the anti-spam timer")
	t.check(not SupplyRequest.can_send(30.0, -2.0),
		"negative corrupted last-send timestamp is not a first-request sentinel")
	t.check(not SupplyRequest.can_send(30.0, NAN),
		"nonfinite previous request time cannot grant another alert")
	t.check(not SupplyRequest.can_send(1.0e30, 1.0e30),
		"very large equal times still respect the cooldown")
	t.check(SupplyRequest.can_send(60.0, 30.0),
		"ordinary elapsed-time boundary still permits another request")

	t.current = "server requires a living, genuinely hungry or thirsty party member"
	var world := WorldGen.new(934)
	var sim := GameServer.new(world, 934)
	var requester = sim.add_player(11, "Scout")
	var ally = sim.add_player(12, "Cook")
	var outsider = sim.add_player(13, "Stranger")
	requester.position = Vector3(8, world.height_at(8, 8), 8)
	ally.position = requester.position + Vector3(1, 0, 0)
	outsider.position = requester.position + Vector3(2, 0, 0)
	requester.survival.hunger = 24.0
	requester.survival.thirst = 17.0
	t.eq(sim.cmd_party_supply_request(11, "food").get("reason", ""), "not_in_party",
		"solo survivors cannot broadcast private group coordinates")
	t.check(sim.cmd_party_invite(11, 12).get("ok", false), "invite valid teammate")
	t.check(sim.cmd_party_accept(12).get("ok", false), "teammate joins group")
	t.eq(sim.cmd_party_supply_request(11, "medicine").get("reason", ""), "invalid_need",
		"forged request type is denied")
	t.eq(requester.supply_request_last_at, -INF,
		"rejected type does not start cooldown")
	requester.survival.hunger = 100.0
	t.eq(sim.cmd_party_supply_request(11, "food").get("reason", ""), "no_need",
		"full hunger cannot request food")
	requester.survival.hunger = 24.0
	sim.drain_events()
	var result: Dictionary = sim.cmd_party_supply_request(11, "food")
	t.check(result.get("ok", false), "server accepts real hunger alert")
	t.eq(int(result.get("level", -1)), 24, "ack contains measured hunger")
	t.near(requester.supply_request_last_at, sim.time, 0.001,
		"successful request starts authoritative cooldown")
	var events: Array = sim.drain_events()
	t.eq(events.size(), 1, "one request creates exactly one party event")
	var ping: Dictionary = events[0]
	t.eq(ping.get("type", ""), "party_supply_request", "event is typed")
	t.eq(int(ping.get("group", -1)), sim.parties.group_of(11),
		"event binds to actual party rather than a client-selected group")
	t.near(float(ping.get("x", INF)), requester.position.x, 0.001,
		"position is the authoritative server coordinate")
	t.eq(int(ping.get("level", -1)), 24, "party sees verified low hunger")
	t.eq(sim.cmd_party_supply_request(11, "water").get("reason", ""), "cooldown",
		"food and water share anti-spam timer")
	t.eq(sim.drain_events().size(), 0, "rejected requests create no events")
	sim.time += SupplyRequest.COOLDOWN
	requester.survival.thirst = 17.0
	var new_result: Dictionary = sim.cmd_party_supply_request(11, "water")
	t.check(new_result.get("ok", false), "water alert available after cooldown")
	t.eq(int(sim.drain_events()[0].get("level", 0)), 17,
		"water alert uses actual thirst, not hunger")

	t.current = "private delivery is revoked as membership changes"
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net.has_method("c_party_supply_request"),
		"authenticated client RPC is registered")
	t.check(net._event_visible_to(ping, 12), "current teammate sees request")
	t.check(not net._event_visible_to(ping, 11),
		"caller gets one RPC confirmation, not a duplicate event")
	t.check(not net._event_visible_to(ping, 13), "stranger cannot see party position")
	t.check(sim.cmd_party_leave(12).get("ok", false), "teammate can leave")
	t.check(not net._event_visible_to(ping, 12),
		"expired membership revokes an unsent location event")
	requester.survival.hurt(1000.0)
	t.eq(sim.cmd_party_supply_request(11, "food").get("reason", ""), "dead",
		"dead members cannot submit supply requests")
	net.free()
