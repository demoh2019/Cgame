extends RefCounted
## "Play solo" from the title screen: starts this same engine as a headless dedicated server in the background, on the
## loopback port, so the single-player game is the real online game (every system, the same rules) with one player.
## When a Nakama backend answers on this machine, the server uses it, so the character and the guild survive restarts;
## otherwise it runs offline. The client stops the server when it quits.

const PORT := 24566 # Not the default 24565, so a solo world never collides with a dedicated server on this machine.
const NAKAMA_PORT := 7350
const CHARACTER_PATH := "user://albion_after_solo_character.json"
const STOP_PATH := "user://albion_after_solo_stop.signal"
const STOP_WAIT_MS := 2200

var pid := -1


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
static func server_arguments(project_path: String, port: int, with_nakama: bool) -> PackedStringArray:
	var arguments := PackedStringArray(["--headless", "--path", project_path, "--script", "res://scripts/server/server_main.gd", "--",
		"--port", str(port), "--max-clients", "1", "--world-save", "user://solo_world.json",
		"--solo-stop", STOP_PATH])
	if with_nakama:
		arguments.append_array(["--nakama", "127.0.0.1:%d" % NAKAMA_PORT])
	else:
		arguments.append_array(["--solo-character", CHARACTER_PATH])
	return arguments


## Starts the server; returns the address to connect to, or "" when the process could not start.
func start() -> String:
	if pid > 0 and OS.is_process_running(pid):
		return "127.0.0.1:%d" % PORT
	# A previous crash may have left the stop request behind. Never let
	# a newly spawned server interpret it as a request to exit immediately.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STOP_PATH))
	var project_path := ProjectSettings.globalize_path("res://")
	pid = OS.create_process(OS.get_executable_path(), server_arguments(project_path, PORT, nakama_available()))
	return "127.0.0.1:%d" % PORT if pid > 0 else ""


func is_running() -> bool:
	return pid > 0 and OS.is_process_running(pid)


func stop() -> void:
	if pid > 0 and OS.is_process_running(pid):
		# Request a real server shutdown: write character and world saves
		# before the child process closes. A stuck child is still bounded.
		var flag: FileAccess = FileAccess.open(STOP_PATH, FileAccess.WRITE)
		if flag != null:
			flag.store_string("quit")
			flag.close()
			var deadline: int = Time.get_ticks_msec() + STOP_WAIT_MS
			while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
				OS.delay_msec(20)
		if OS.is_process_running(pid):
			OS.kill(pid)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(STOP_PATH))
	pid = -1
