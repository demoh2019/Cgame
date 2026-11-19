extends RefCounted
## Direct barter regressions. No sockets needed: these are the same authoritative
## commands and inventory transactions called by the network RPC layer.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const PlayerTrade = preload("res://scripts/shared/player_trade.gd")


func _move(world, player, x: float, z: float) -> void:
	player.position = Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "atomic trade accounting and capacity"
	var first := Inventory.new()
	var second := Inventory.new()
	first.add("wood_1", 8)
	second.add("silver", 20)
	var result := PlayerTrade.exchange(first, second, {"wood_1": 4}, {"silver": 7})
	t.check(result["ok"], "two matching offers exchange")
	t.eq(first.count("wood_1"), 4, "seller keeps unoffered wood")
	t.eq(first.count("silver"), 7, "seller receives exact silver")
	t.eq(second.count("wood_1"), 4, "buyer receives exact wood")
	t.eq(second.count("silver"), 13, "buyer pays exact silver")
	t.eq(first.count("wood_1") + second.count("wood_1"), 8, "wood conserved")
	t.eq(first.count("silver") + second.count("silver"), 20, "currency conserved")
	var before_a: Dictionary = first.to_dict()
	var before_b: Dictionary = second.to_dict()
	t.eq(PlayerTrade.exchange(first, second, {"wood_1": 999}, {})["reason"],
		"invalid_quantity", "overstacked offer rejected")
	t.eq(PlayerTrade.exchange(first, second, {"wood_1": 5}, {})["reason"],
		"missing_items", "cannot promise items no longer carried")
	t.eq(PlayerTrade.exchange(first, second, {}, {})["reason"],
		"empty_trade", "empty confirmation cannot trigger a transaction")
	t.eq(first.to_dict(), before_a, "invalid transactions never change first inventory")
	t.eq(second.to_dict(), before_b, "invalid transactions never change second inventory")
	var full_first := Inventory.new(1)
	var full_second := Inventory.new(1)
	full_first.add("silver", 100)
	full_second.add("wood_1", 10)
	before_a = full_first.to_dict()
	before_b = full_second.to_dict()
	t.eq(PlayerTrade.exchange(full_first, full_second, {"silver": 1}, {"wood_1": 1})["reason"],
		"no_space", "full backpacks reject trades without partial transfers")
	t.eq(full_first.to_dict(), before_a, "full first backpack preserved")
	t.eq(full_second.to_dict(), before_b, "full second backpack preserved")
	var armored := Inventory.new()
	var buyer := Inventory.new()
	armored.add("club_1", 1)
	armored.equip("club_1")
	t.check(PlayerTrade.exchange(armored, buyer, {"club_1": 1}, {})["ok"],
		"gift of an equipped weapon is allowed")
	t.eq(armored.weapon, "", "seller no longer equips a transferred weapon")
	t.eq(buyer.count("club_1"), 1, "recipient gains weapon once")

	t.current = "server validates proximity and participants"
	var world := WorldGen.new(42)
	var server := GameServer.new(world, 1234)
	var alice = server.add_player(101, "Alice")
	var bob = server.add_player(102, "Bob")
	_move(world, alice, 3.0, 1.0)
	_move(world, bob, 4.0, 1.0)
	alice.inventory.add("wood_1", 10)
	bob.inventory.add("silver", 20)
	t.eq(server.cmd_trade_invite(101, 101)["reason"], "invalid_target",
		"cannot invite self")
	t.eq(server.cmd_trade_invite(101, 999)["reason"], "invalid_target",
		"cannot invite unknown player")
	var charlie = server.add_player(103, "Charlie")
	_move(world, charlie, 200.0, 200.0)
	t.eq(server.cmd_trade_invite(101, 103)["reason"], "not_in_safe_range",
		"remote player cannot trade even if the client sends an RPC")
	var invite: Dictionary = server.cmd_trade_invite(101, 102)
	t.check(invite["ok"], "nearby safe-hub traders can invite")
	var id: int = int(invite["trade_id"])
	t.eq(server.cmd_trade_invite(102, 103)["reason"], "busy",
		"a participant cannot join a second trade")
	t.eq(server.cmd_trade_offer(103, id, "wood_1", 1)["reason"],
		"unknown_trade", "third party cannot change a trade")
	t.eq(server.cmd_trade_accept(103, id, 0)["reason"],
		"unknown_trade", "third party cannot confirm")

	t.current = "offers, revisions, two confirmations and replay protection"
	var offered: Dictionary = server.cmd_trade_offer(101, id, "wood_1", 4)
	t.check(offered["ok"], "offer is accepted from inventory")
	var rev: int = int(offered["revision"])
	t.eq(server.cmd_trade_accept(101, id, rev - 1)["reason"], "stale_revision",
		"outdated confirmation cannot agree to changed terms")
	t.check(server.cmd_trade_accept(101, id, rev)["ok"], "first party signs")
	t.check(not bool(server.trades[id]["accepted"][102]), "second party has not signed")
	var counter: Dictionary = server.cmd_trade_offer(102, id, "silver", 7)
	rev = int(counter["revision"])
	t.check(not bool(server.trades[id]["accepted"][101]),
		"counteroffer revokes first player's prior approval")
	t.eq(server.cmd_trade_accept(101, id, rev - 1)["reason"], "stale_revision",
		"stale approval cannot sneak through after counteroffer")
	t.check(server.cmd_trade_accept(102, id, rev)["ok"], "second party confirms terms")
	t.eq(alice.inventory.count("silver"), 0, "first confirmation moves no currency")
	var final: Dictionary = server.cmd_trade_accept(101, id, rev)
	t.check(final["ok"] and final["completed"], "second signature commits exchange")
	t.eq(alice.inventory.count("silver"), 7, "seller receives payment exactly once")
	t.eq(alice.inventory.count("wood_1"), 6, "seller loses exact wood count")
	t.eq(bob.inventory.count("wood_1"), 4, "buyer receives exact wood")
	t.eq(bob.inventory.count("silver"), 13, "buyer spends exact payment")
	t.check(alice.dirty_inventory and bob.dirty_inventory, "both snapshots marked dirty")
	t.check(alice.dirty_character and bob.dirty_character, "both character saves marked dirty")
	t.eq(server.cmd_trade_accept(101, id, rev)["reason"], "unknown_trade",
		"replayed confirmation cannot duplicate items")
	t.eq(server.cmd_trade_offer(102, id, "silver", 7)["reason"], "unknown_trade",
		"completed trade cannot be edited")
	t.check(not server.trade_by_player.has(101) and not server.trade_by_player.has(102),
		"completed trades release both slots")

	t.current = "failed confirmation and lifecycle cancellation"
	var rollback := server.cmd_trade_invite(101, 102)
	var bad_id: int = int(rollback["trade_id"])
	server.cmd_trade_offer(101, bad_id, "wood_1", 3)
	var revision: int = int(server.cmd_trade_offer(102, bad_id, "silver", 5)["revision"])
	server.cmd_trade_accept(101, bad_id, revision)
	bob.inventory.remove("silver", 13)
	var rejected: Dictionary = server.cmd_trade_accept(102, bad_id, revision)
	t.eq(rejected["reason"], "missing_items", "server rechecks inventory on final acceptance")
	t.eq(alice.inventory.count("wood_1"), 6, "failed final confirm preserves seller goods")
	t.eq(bob.inventory.count("wood_1"), 4, "failed final confirm creates no wood")
	t.check(not bool(server.trades[bad_id]["accepted"][101]), "failure revokes both signatures")
	t.check(server.cmd_trade_cancel(102, bad_id)["ok"], "either party can cancel")
	t.eq(server.cmd_trade_cancel(102, bad_id)["reason"], "unknown_trade",
		"cancel is idempotent")

	var death_invite: Dictionary = server.cmd_trade_invite(101, 102)
	var death_id: int = int(death_invite["trade_id"])
	alice.survival.hurt(10000.0)
	server._on_player_death(alice, 102)
	t.check(not server.trades.has(death_id), "death terminates trade before death loot")
	t.eq(server.cmd_trade_accept(102, death_id, 0)["reason"], "unknown_trade",
		"survivor cannot complete a deceased player's trade")
	# Restore an alive character to test timeout and disconnect without respawn delay.
	alice.survival.reset()
	_move(world, alice, 3.0, 1.0)
	var timeout_invite: Dictionary = server.cmd_trade_invite(101, 102)
	var timeout_id: int = int(timeout_invite["trade_id"])
	server.time += GameServer.TRADE_TIMEOUT + 1.0
	server._tick_trades()
	t.check(not server.trades.has(timeout_id), "abandoned trade expires")
	var disconnect_invite: Dictionary = server.cmd_trade_invite(101, 102)
	var disconnect_id: int = int(disconnect_invite["trade_id"])
	server.remove_player(102)
	t.check(not server.trades.has(disconnect_id), "disconnect cancels session immediately")
	t.check(not server.trade_by_player.has(101), "other player is released on disconnect")
