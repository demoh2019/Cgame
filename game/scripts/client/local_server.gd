extends RefCounted

const SoloSlots = preload("res://scripts/client/solo_slots.gd")
## "Play solo" from the title screen: starts this same engine as a headless dedicated server in the background, on the
## loopback port, so the single-player game is the real online game (every system, the same rules) with one player.
## When a Nakama backend answers on this machine, the server uses it, so the character and the guild survive restarts;
## otherwise it runs offline. The client stops the server when it quits.

const PORT := SoloSlots.BASE_PORT
const NAKAMA_PORT := 7350
const STOP_WAIT_MS := 2200

var pid := -1
var active_slot: int = 0


## Whether a Nakama backend accepts connections on this machine (a quick TCP check, no request).
static func nakama_available(port: int = NAKAMA_PORT) -> bool:
	var probe := StreamPeerTCP.new()
	if probe.connect_to_host("127.0.0.1", port) != OK:
		return false
	var deadline := Time.get_ticks_msec() + 400
	while Time.get_ticks_msec() < deadline:
		probe.poll()
		var status := probe.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			probe.disconnect_from_host()
			return true
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			return false
		OS.delay_msec(20)
	probe.disconnect_from_host()
	return false


## The arguments for the headless server process (exposed for tests).
static func server_arguments(project_path: String, port: int, with_nakama: bool,
		slot: int = 1) -> PackedStringArray:
	if not SoloSlots.valid(slot) or (with_nakama and slot != 1):
		return PackedStringArray()
	var arguments := PackedStringArray(["--headless", "--path", project_path, "--script", "res://scripts/server/server_main.gd", "--",
		"--port", str(port), "--max-clients", "1", "--world-save", SoloSlots.world_path(slot),
		"--solo-stop", SoloSlots.stop_path(slot)])
	if with_nakama:
		arguments.append_array(["--nakama", "127.0.0.1:%d" % NAKAMA_PORT])
	else:
		arguments.append_array(["--solo-character", SoloSlots.character_path(slot)])
	return arguments


## Starts the server; returns the address to connect to, or "" when the process could not start.
func start(slot: int = 1) -> String:
	if not SoloSlots.valid(slot):
		return ""
	var slot_port: int = SoloSlots.port(slot)
	if pid > 0 and OS.is_process_running(pid):
		# A live launcher cannot switch to another save while it is running.
		return "127.0.0.1:%d" % slot_port if active_slot == slot else ""
	# An old crash may have left this slot's stop request behind.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SoloSlots.stop_path(slot)))
	var project_path := ProjectSettings.globalize_path("res://")
	# Preserve the historic Nakama behaviour only for Slot 1. Additional
	# characters must never silently resolve to the same Nakama account.
	var with_nakama: bool = slot == 1 and nakama_available()
	var arguments: PackedStringArray = server_arguments(project_path, slot_port,
		with_nakama, slot)
	pid = OS.create_process(OS.get_executable_path(), arguments)
	active_slot = slot if pid > 0 else 0
	return "127.0.0.1:%d" % slot_port if pid > 0 else ""


func is_running() -> bool:
	return pid > 0 and OS.is_process_running(pid)


func stop() -> void:
	if pid > 0 and OS.is_process_running(pid):
		# The stop signal is scoped to exactly the survivor we launched.
		var stop_signal: String = SoloSlots.stop_path(active_slot)
		if not stop_signal.is_empty():
			var flag: FileAccess = FileAccess.open(stop_signal, FileAccess.WRITE)
			if flag != null:
				flag.store_string("quit")
				flag.close()
				var deadline: int = Time.get_ticks_msec() + STOP_WAIT_MS
				while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
					OS.delay_msec(20)
		if OS.is_process_running(pid):
			OS.kill(pid)
		if not stop_signal.is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(stop_signal))
	pid = -1
	active_slot = 0
