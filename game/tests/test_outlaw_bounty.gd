extends RefCounted
## Regression: bounty pay is server-owned, capped and tied to verified, fresh PvP kills.

const Bounty = preload("res://scripts/shared/outlaw_bounty.gd")
const Honor = preload("res://scripts/shared/pvp_honor.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func _place(world, player, x: float) -> void:
	player.position = Vector3(x, world.height_at(x, 0.0), 0.0)


func run(t) -> void:
	t.current = "outlaw bounty caps and risk zones"
	t.eq(Bounty.silver_for(0, 100.0), 0, "hub offers no bounty")
	t.eq(Bounty.silver_for(1, 100.0), 0, "yellow zone offers no bounty")
	t.eq(Bounty.silver_for(2, 49.9), 0, "non-outlaw has no bounty")
	t.eq(Bounty.silver_for(2, 50.0), 15, "red wanted reward at threshold")
	t.eq(Bounty.silver_for(3, 50.0), 30, "black zone doubles starting reward")
	t.eq(Bounty.silver_for(2, 74.9), 15, "first bracket is bounded")
	t.eq(Bounty.silver_for(2, 75.0), 25, "second wanted bracket")
	t.eq(Bounty.silver_for(3, 100.0), 50, "black maximum is capped at fifty silver")
	for malformed in [NAN, INF, -1.0, 101.0]:
		t.eq(Bounty.silver_for(3, malformed), 0, "corrupt infamy cannot mint currency")

	t.current = "verified identities and fresh honor are required"
	var world := WorldGen.new(817)
	var server := GameServer.new(world, 817)
	var hunter = server.add_player(21, "Bounty Hunter", "verified-hunter")
	var criminal = server.add_player(22, "Wanted Outlaw", "verified-outlaw")
	criminal.pvp_infamy = 50.0
	t.eq(Bounty.reward_for_kill(hunter, criminal, 2, {"ok": false, "awarded": 4}),
		0, "a refused honor record never pays")
	t.eq(Bounty.reward_for_kill(hunter, criminal, 2, {"ok": true, "awarded": 0}),
		0, "repeated-victim honor cooldown blocks bounty")
	t.eq(Bounty.reward_for_kill(hunter, criminal, 2, {"ok": true, "awarded": 4}),
		15, "fresh verified outlaw kill pays")
	var guest = server.add_player(23, "Guest")
	t.eq(Bounty.reward_for_kill(guest, criminal, 2, {"ok": true, "awarded": 4}),
		0, "unverified guest cannot farm silver")
	var same_account = server.add_player(24, "Alt", "verified-outlaw")
	t.eq(Bounty.reward_for_kill(same_account, criminal, 2, {"ok": true, "awarded": 4}),
		0, "two characters on same account cannot farm silver")

	t.current = "live server kill, duplicate death and private event"
	_place(world, hunter, 800.0)
	_place(world, criminal, 801.0)
	var silver_before: int = hunter.inventory.count("silver")
	server._damage_target(hunter, {"kind": "player", "id": criminal.id}, 1000.0)
	t.check(not criminal.survival.alive, "wanted criminal dies after a confirmed hit")
	t.eq(hunter.inventory.count("silver") - silver_before, 15,
		"server transfers one red-zone reward into hunter inventory")
	t.eq(hunter.pvp_infamy, 0.0, "lawful bounty kill adds no criminal infamy")
	t.eq(hunter.pvp_honor, Honor.RED_REWARD, "normal honor remains independent")
	var received := 0
	for event in server.events:
		if str(event.get("type", "")) == "outlaw_bounty":
			received += 1
			t.eq(int(event.get("peer", -1)), hunter.id, "award targets actual hunter")
			t.eq(int(event.get("silver", 0)), 15, "award event uses server amount")
	t.eq(received, 1, "one bounty notification is emitted per legitimate kill")
	var net := Net.new()
	net.role = "server"
	net.sim = server
	t.check(net._event_visible_to({"type": "outlaw_bounty", "peer": hunter.id}, hunter.id),
		"owner receives the payout notice")
	t.check(not net._event_visible_to({"type": "outlaw_bounty", "peer": hunter.id}, criminal.id),
		"other players cannot inspect private payout")
	net.free()
	criminal.survival.reset()
	_place(world, criminal, 801.0)
	server.time += 1.0
	server._damage_target(hunter, {"kind": "player", "id": criminal.id}, 1000.0)
	t.eq(hunter.inventory.count("silver") - silver_before, 15,
		"killing the same account again inside the honor cooldown pays nothing")

	t.current = "guests and alts still earn no currency in live combat"
	var visitor = server.add_player(30, "Unverified")
	var outlaw_guest_target = server.add_player(31, "Account Wanted", "wanted-31")
	outlaw_guest_target.pvp_infamy = 75.0
	_place(world, visitor, 800.0)
	_place(world, outlaw_guest_target, 801.0)
	server._damage_target(visitor, {"kind": "player", "id": outlaw_guest_target.id}, 1000.0)
	t.eq(visitor.inventory.count("silver"), 0, "guest PvP can never mint bounty")
	var alt_attacker = server.add_player(32, "Fake Hunter", "same-wallet")
	var alt_victim = server.add_player(33, "Fake Criminal", "same-wallet")
	alt_victim.pvp_infamy = 100.0
	_place(world, alt_attacker, 800.0)
	_place(world, alt_victim, 801.0)
	server._damage_target(alt_attacker, {"kind": "player", "id": alt_victim.id}, 1000.0)
	t.eq(alt_attacker.inventory.count("silver"), 0, "same verified account cannot transfer bounty")

	t.current = "full backpack preserves bounty as reserved overflow"
	var full_hunter = server.add_player(40, "Full Backpack", "full-hunter")
	var full_outlaw = server.add_player(41, "Full Outlaw", "full-outlaw")
	full_outlaw.pvp_infamy = 100.0
	for index in full_hunter.inventory.slots.size():
		full_hunter.inventory.slots[index] = {"id": "wood_1", "count": 100}
	_place(world, full_hunter, 800.0)
	_place(world, full_outlaw, 801.0)
	server._damage_target(full_hunter, {"kind": "player", "id": full_outlaw.id}, 1000.0)
	t.eq(full_hunter.inventory.count("silver"), 0, "a full inventory cannot bypass slot limits")
	var found_overflow := false
	for bag in server.bags.values():
		if int(bag["items"].get("silver", 0)) == 35:
			found_overflow = true
			break
	t.check(found_overflow, "overflowed silver remains in the world for authorized pickup")
