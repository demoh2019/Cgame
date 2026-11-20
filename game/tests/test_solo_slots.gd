extends RefCounted
## Different offline survivors cannot share a save, signal or ENet port.
const SoloSlots = preload("res://scripts/client/solo_slots.gd")
const LocalServer = preload("res://scripts/client/local_server.gd")


func _argument_after(args: PackedStringArray, flag: String) -> String:
	var index: int = args.find(flag)
	return str(args[index + 1]) if index >= 0 and index + 1 < args.size() else ""


func run(t) -> void:
	t.current = "three separate solo survivors preserve old first-slot files"
	t.eq(SoloSlots.SLOT_COUNT, 3, "three selectable local characters")
	t.eq(SoloSlots.character_path(1), "user://albion_after_solo_character.json",
		"first survivor keeps old inventory and progression save")
	t.eq(SoloSlots.world_path(1), "user://solo_world.json",
		"first survivor keeps old construction checkpoint")
	t.eq(SoloSlots.stop_path(1), "user://albion_after_solo_stop.signal",
		"first survivor keeps existing graceful-stop request")
	var seen_ports := {}
	var seen_characters := {}
	var seen_worlds := {}
	var seen_signals := {}
	for slot in range(1, 4):
		t.check(SoloSlots.valid(slot), "solo slot %d exists" % slot)
		var port: int = SoloSlots.port(slot)
		var character: String = SoloSlots.character_path(slot)
		var world: String = SoloSlots.world_path(slot)
		var stop: String = SoloSlots.stop_path(slot)
		t.check(not seen_ports.has(port) and not seen_characters.has(character)
			and not seen_worlds.has(world) and not seen_signals.has(stop),
			"each survivor has isolated network/save/stop resources")
		seen_ports[port] = true
		seen_characters[character] = true
		seen_worlds[world] = true
		seen_signals[stop] = true
		t.check(character.begins_with("user://") and world.begins_with("user://")
			and stop.begins_with("user://"), "slot files are contained in local user data")
		var args: PackedStringArray = LocalServer.server_arguments("res://", port, false, slot)
		t.eq(_argument_after(args, "--solo-character"), character,
			"local server saves into the correct character slot")
		t.eq(_argument_after(args, "--world-save"), world,
			"local world checkpoint is slot-scoped")
		t.eq(_argument_after(args, "--solo-stop"), stop,
			"one solo client cannot close another slot's server")
		t.eq(_argument_after(args, "--port"), str(port),
			"every solo slot connects to its isolated loopback port")
		t.eq(_argument_after(args, "--max-clients"), "1",
			"solo slots never expose a multi-user guest server")
		t.check(not "--nakama" in args,
			"offline slot has no accidental backend identity")
		var description: String = SoloSlots.description(slot)
		t.check(description.contains("survivor") and
			description.length() > 15, "selector presents continue/new state")
	t.current = "account slot and invalid slot protection"
	var account_args: PackedStringArray = LocalServer.server_arguments(
		"res://", SoloSlots.port(1), true)
	t.check("--nakama" in account_args and not "--solo-character" in account_args,
		"legacy account-backed first slot still uses Nakama")
	t.eq(_argument_after(account_args, "--world-save"), SoloSlots.world_path(1),
		"authenticated first slot preserves its world checkpoint")
	for invalid in [-100, -1, 0, 4, 10, 999]:
		t.check(not SoloSlots.valid(invalid), "invalid slot is rejected")
		t.eq(SoloSlots.port(invalid), -1, "invalid slot has no port")
		t.eq(SoloSlots.character_path(invalid), "", "invalid slot has no save path")
		t.eq(SoloSlots.world_path(invalid), "", "invalid slot has no world checkpoint")
		t.eq(SoloSlots.stop_path(invalid), "", "invalid slot cannot send a stop request")
