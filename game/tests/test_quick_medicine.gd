extends RefCounted
## The smart treatment hotkey must use real server-owned medicine only.
const QuickMedicine = preload("res://scripts/shared/quick_medicine.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func run(t) -> void:
	var server := GameServer.new(WorldGen.new(4567), 4567)
	var player = server.add_player(81, "Medic")
	player.inventory.remove("bandage", player.inventory.count("bandage"))
	t.current = "smart medicine: ownership, no-effect and single-use"
	t.eq(server.cmd_quick_medicine(999).get("reason", ""), "dead",
		"unknown peer cannot use another player's inventory")
	t.eq(server.cmd_quick_medicine(81).get("reason", ""), "no_treatment",
		"healthy player spends nothing")
	player.survival.health = 40.0
	t.eq(server.cmd_quick_medicine(81).get("reason", ""), "no_treatment",
		"injured player gets no free supplies")
	player.inventory.add("bandage", 1)
	var result: Dictionary = server.cmd_quick_medicine(81)
	t.check(bool(result.get("ok", false)), "real bandage heals")
	t.eq(str(result.get("item", "")), "bandage", "server picked owned medicine")
	t.near(player.survival.health, 68.0, 0.001, "normal item heal applies once")
	t.eq(player.inventory.count("bandage"), 0, "exactly one bandage spent")
	t.eq(QuickMedicine.pick(player.inventory, player.survival), "",
		"selection refuses ghost medical items")

	t.current = "smart medicine: fracture priority and blood scent reduction"
	player.survival.fracture = 45.0
	player.survival.bleeding = 14.0
	player.inventory.add("field_splint", 1)
	player.inventory.add("bandage", 1)
	result = server.cmd_quick_medicine(81)
	t.eq(str(result.get("item", "")), "field_splint",
		"fracture care wins over simultaneous bleeding")
	t.near(player.survival.fracture, 0.0, 0.001, "fracture corrected by splint")
	t.near(player.survival.bleeding, 14.0, 0.001, "splint cannot stop bleeding")
	t.eq(player.inventory.count("bandage"), 1, "other medicine untouched")
	result = server.cmd_quick_medicine(81)
	t.eq(str(result.get("item", "")), "bandage", "bleeding prioritized over health")
	t.near(player.survival.bleeding, 0.0, 0.001, "bandage stops blood loss")

	t.current = "smart medicine: infection severity and finite resource spending"
	player.survival.health = player.survival.max_health
	player.survival.infection = 85.0
	player.inventory.add("antibiotics", 1)
	player.inventory.add("field_antiseptic", 1)
	result = server.cmd_quick_medicine(81)
	t.eq(str(result.get("item", "")), "antibiotics", "high infection uses strong cure")
	t.near(player.survival.infection, 0.0, 0.001, "severe infection cured")
	t.eq(player.inventory.count("antibiotics"), 0, "antibiotics spent once")
	t.eq(player.inventory.count("field_antiseptic"), 1, "weaker backup untouched")
	player.survival.infection = 22.0
	result = server.cmd_quick_medicine(81)
	t.eq(str(result.get("item", "")), "field_antiseptic",
		"moderate infection uses moderate cure")
	t.near(player.survival.infection, 0.0, 0.001, "antiseptic treats infection")

	t.current = "smart medicine: small scratches, mounts, recall and death"
	player.survival.health = player.survival.max_health - 5.0
	player.inventory.add("bandage", 1)
	t.eq(server.cmd_quick_medicine(81).get("reason", ""), "no_treatment",
		"five-point scratch does not auto-waste bandages")
	player.survival.health = 30.0
	player.mounted = true
	t.eq(server.cmd_quick_medicine(81).get("reason", ""), "mounted",
		"riding cannot bypass normal item restrictions")
	t.eq(player.inventory.count("bandage"), 1, "failed mount use is free")
	player.mounted = false
	player.recall = {"active": true}
	t.eq(server.cmd_quick_medicine(81).get("reason", ""), "recall_channeling",
		"cannot treat while channeling")
	t.eq(player.inventory.count("bandage"), 1, "cancelled treatment spends nothing")
	player.recall.clear()
	result = server.cmd_quick_medicine(81)
	t.eq(str(result.get("item", "")), "bandage", "normal healing resumes")
	t.eq(player.inventory.count("bandage"), 0, "successful heal spends supply")
	player.survival.hurt(1000.0)
	t.eq(server.cmd_quick_medicine(81).get("reason", ""), "dead",
		"dead characters cannot use field medicine")
	var net := Net.new()
	t.check(net.has_method("c_quick_medicine"),
		"server-authenticated quick-treatment RPC registered")
	net.free()
