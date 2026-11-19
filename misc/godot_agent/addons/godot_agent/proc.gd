extends RefCounted
## Runs Godot child processes (script checks and headless smoke runs) with a watchdog,
## and condenses their logs into a few high-signal lines.

const C = preload("common.gd")

var _dir: String
var _seq := 0


func _init(addon_dir: String) -> void:
	_dir = addon_dir


## Starts a child Godot on this project, waits up to `timeout_s`, returns its log text.
func _spawn(extra: PackedStringArray, timeout_s: float) -> String:
	_seq += 1
	var log_path := ProjectSettings.globalize_path("user://agent_child_%d.log" % _seq)
	DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", log_path])
	args.append_array(extra)
	var pid := OS.create_process(OS.get_executable_path(), args, false)
	if pid <= 0:
		return "ERR cannot start child process"
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() > deadline:
			OS.kill(pid)
			OS.delay_msec(100)
			return _read(log_path) + "\nTIMEOUT after %ds (infinite loop or too many frames?)" % int(timeout_s)
		OS.delay_msec(15)
	return _read(log_path)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var t := FileAccess.get_file_as_string(path)
	DirAccess.remove_absolute(path)
	return t


## Collapses engine log noise into deduplicated "file:line message" lines.
static func condense(log: String, max_lines: int = 25) -> PackedStringArray:
	var out: PackedStringArray = []
	var seen := {}
	var pending := ""
	for raw in log.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("Godot Engine v") or line.begins_with("Vulkan") or line.begins_with("Metal") or line.begins_with("OpenGL"):
			continue
		var msg := ""
		if line.begins_with("SCRIPT ERROR:") or line.begins_with("ERROR:") or line.begins_with("WARNING:") or line.begins_with("USER ERROR:") or line.begins_with("USER WARNING:"):
			if pending != "":
				_push(out, seen, pending)
			pending = line.get_slice(":", 0).replace("SCRIPT ", "S").replace("USER ", "U").substr(0, 1) + ": " + line.substr(line.find(":") + 1).strip_edges()
			continue
		if line.begins_with("at:"):
			var loc := ""
			var lp := line.rfind("(")
			if lp >= 0 and line.ends_with(")"):
				loc = line.substr(lp + 1, line.length() - lp - 2)
			var m := pending
			pending = ""
			if m != "":
				_push(out, seen, ("%s %s" % [loc, m]) if loc != "" else m)
			continue
		if line.begins_with("[0] "):
			# Engine-raised errors (push_error, assertions) carry an engine file:line; use the script frame.
			var bp := line.rfind("(")
			if bp >= 0 and line.ends_with(")") and not out.is_empty():
				var last := out[out.size() - 1]
				if last.begins_with("core/") or last.begins_with("modules/") or last.begins_with("scene/") or last.begins_with("servers/"):
					out[out.size() - 1] = line.substr(bp + 1, line.length() - bp - 2) + last.substr(last.find(" "))
			continue
		if line.begins_with("GDScript backtrace") or line.begins_with("[") and line.contains("] "):
			continue
		if line.begins_with("CHK_") or line.begins_with("AGENT_") or line.begins_with("TIMEOUT") or line.begins_with("PRINT "):
			if pending != "":
				_push(out, seen, pending)
				pending = ""
			_push(out, seen, line)
	if pending != "":
		_push(out, seen, pending)
	if out.size() > max_lines:
		var more := out.size() - max_lines
		out = out.slice(0, max_lines)
		out.append("...+%d more" % more)
	return out


static func _push(out: PackedStringArray, seen: Dictionary, line: String) -> void:
	if seen.has(line):
		return
	seen[line] = true
	out.append(line)


func check(paths: PackedStringArray) -> String:
	if paths.is_empty():
		paths = _all_checkable("res://")
	if paths.is_empty():
		return "ok nothing to check"
	var args := PackedStringArray(["--script", _dir.path_join("checker.gd"), "--"])
	args.append_array(paths)
	var lines := condense(_spawn(args, 120.0))
	var fails := 0
	var body: PackedStringArray = []
	var fail_lines: PackedStringArray = []
	for l in lines:
		if l.begins_with("CHK_DONE"):
			continue
		if l.begins_with("CHK_FAIL"):
			fails += 1
			fail_lines.append(l.substr(9))
			continue
		if l.begins_with("modules/") or l.begins_with("core/") or l.begins_with("scene/") or l.begins_with("servers/"):
			continue  # engine-internal location, the script line above is what matters
		body.append(l)
	if body.is_empty() and fails > 0:
		body.append("failed to load: " + " ".join(fail_lines))
	if body.is_empty():
		return "ok %d files" % paths.size()
	return "%d files, %d bad\n%s" % [paths.size(), fails, "\n".join(body)]


func _all_checkable(path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var da := DirAccess.open(path)
	if da == null:
		return out
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if not f.begins_with("."):
			var full := path.path_join(f)
			if da.current_is_dir():
				if full != "res://addons/godot_agent":
					out.append_array(_all_checkable(full))
			elif f.ends_with(".gd") or f.ends_with(".tscn"):
				out.append(full)
		f = da.get_next()
	da.list_dir_end()
	return out


## Runs a scene headless for `frames` frames with scripted input and assertions.
func run(scene: String, frames: int, inputs: String, expect: String, watch: String) -> String:
	var sp := scene if scene != "" else String(ProjectSettings.get_setting("application/run/main_scene", ""))
	sp = C.res_path(sp)
	if sp.is_empty() or not FileAccess.file_exists(sp):
		return "ERR no scene (set main scene or pass scene=)"
	var cfg := {
		"scene": sp,
		"frames": clampi(frames, 1, 20000),
		"inputs": inputs,
		"expect": expect.split("\n", false),
		"watch": watch.split("\n", false),
	}
	var cfg_path := "user://agent_run.json"
	var f := FileAccess.open(cfg_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(cfg))
	f.close()
	var args := PackedStringArray(["--fixed-fps", "60", "--script", _dir.path_join("runner.gd")])
	var log := _spawn(args, 90.0 + frames / 200.0)
	var lines := condense(log)
	var result := ""
	var rest: PackedStringArray = []
	for l in lines:
		if l.begins_with("AGENT_RESULT "):
			result = l.substr(13)
		else:
			rest.append(l)
	var out: PackedStringArray = []
	if result != "":
		var parsed: Variant = JSON.parse_string(result)
		if parsed is Dictionary:
			var d: Dictionary = parsed
			out.append("ran %d frames%s" % [int(d.get("frames", 0)), "" if bool(d.get("loaded", true)) else " (scene failed to load)"])
			for r in d.get("expect", []):
				out.append(r)
			for w in d.get("watch", []):
				out.append(w)
	if rest.is_empty() and out.size() <= 1 and result != "":
		out.append("no errors")
	var prints := game_prints(log)
	if not prints.is_empty():
		out.append("print:")
		out.append_array(prints)
	if not rest.is_empty():
		out.append("log:")
		out.append_array(rest)
	if result == "" and rest.is_empty():
		out.append("no result from runner (crash?)")
	return C.trunc("\n".join(out))


## Game `print()` output from a log: everything that is not engine noise or an error block.
static func game_prints(log: String, keep: int = 8) -> PackedStringArray:
	var out: PackedStringArray = []
	var last := ""
	var repeat := 0
	for raw in log.split("\n"):
		var line := raw.strip_edges(false, true)
		if line.is_empty() or raw.begins_with(" ") or raw.begins_with("\t"):
			continue
		if line.begins_with("Godot Engine v") or line.begins_with("SCRIPT ERROR") or line.begins_with("ERROR") or line.begins_with("WARNING") or line.begins_with("USER ") or line.begins_with("AGENT_") or line.begins_with("CHK_") or line.begins_with("at:") or line.begins_with("GDScript backtrace") or line.begins_with("TIMEOUT") or line.begins_with("[") or line.begins_with("Vulkan") or line.begins_with("Metal") or line.begins_with("OpenGL"):
			continue
		if line == last:
			repeat += 1
			out[out.size() - 1] = "%s (x%d)" % [line, repeat + 1]
			continue
		last = line
		repeat = 0
		out.append(line)
	if out.size() > keep:
		out = out.slice(out.size() - keep)
	return out
