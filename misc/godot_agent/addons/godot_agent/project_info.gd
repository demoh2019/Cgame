extends RefCounted
## Project overview, file reading and project-level settings in compact form.

const C = preload("common.gd")

const SKIP_DIRS := ["addons/godot_agent"]
const MAX_FILES_PER_DIR := 24


func overview(dir: String = "", depth: int = 3) -> String:
	var lines: PackedStringArray = []
	var name := String(ProjectSettings.get_setting("application/config/name", ""))
	var main := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	var w := int(ProjectSettings.get_setting("display/window/size/viewport_width", 1152))
	var h := int(ProjectSettings.get_setting("display/window/size/viewport_height", 648))
	var v := Engine.get_version_info()
	lines.append("%s | main=%s | %dx%d | godot %s" % [name, main if main != "" else "(none)", w, h, v.string.get_slice(".custom", 0)])
	var autoloads: PackedStringArray = []
	for p in ProjectSettings.get_property_list():
		var pn := String(p.name)
		if pn.begins_with("autoload/"):
			autoloads.append("%s=%s" % [pn.substr(9), String(ProjectSettings.get_setting(pn)).trim_prefix("*")])
	if not autoloads.is_empty():
		lines.append("autoload: " + " ".join(autoloads))
	var actions: PackedStringArray = []
	for a in InputMap.get_actions():
		if String(a).begins_with("ui_") or String(a).begins_with("spatial_editor"):
			continue
		var keys: PackedStringArray = []
		for e in InputMap.action_get_events(a):
			keys.append(e.as_text().get_slice(" (", 0).replace(" - Physical", ""))
		actions.append("%s[%s]" % [a, ",".join(keys)])
	if not actions.is_empty():
		lines.append("input: " + " ".join(actions))
	var layers: PackedStringArray = []
	for kind in ["2d_physics", "3d_physics", "2d_render"]:
		for i in range(1, 33):
			var ln := String(ProjectSettings.get_setting("layer_names/%s/layer_%d" % [kind, i], ""))
			if ln != "":
				layers.append("%s%d=%s" % [kind.substr(0, 2) + kind.get_slice("_", 1).substr(0, 1), i, ln])
	if not layers.is_empty():
		lines.append("layers: " + " ".join(layers))
	var root := C.res_path(dir) if dir != "" else "res://"
	if root == "":
		return "ERR bad dir"
	_walk(root, "", depth, lines)
	return C.trunc("\n".join(lines))


func _walk(path: String, indent: String, depth: int, lines: PackedStringArray) -> void:
	var files: PackedStringArray = []
	var dirs: PackedStringArray = []
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if not f.begins_with("."):
			if da.current_is_dir():
				var rel := path.path_join(f).trim_prefix("res://")
				if not (rel in SKIP_DIRS):
					dirs.append(f)
			elif not f.ends_with(".import") and not f.ends_with(".uid") and f != "project.godot":
				files.append(f)
		f = da.get_next()
	da.list_dir_end()
	files.sort()
	dirs.sort()
	if not files.is_empty():
		var shown := files.slice(0, MAX_FILES_PER_DIR)
		var more := "" if files.size() <= MAX_FILES_PER_DIR else " +%d" % (files.size() - MAX_FILES_PER_DIR)
		lines.append("%s%s: %s%s" % [indent, path.trim_prefix("res://") if path != "res://" else "res://", " ".join(shown), more])
	for d in dirs:
		if depth > 1:
			_walk(path.path_join(d), indent, depth - 1, lines)
		else:
			lines.append("%s%s/ (%d entries, depth limit)" % [indent, path.path_join(d).trim_prefix("res://"), _count(path.path_join(d))])


func _count(path: String) -> int:
	var n := 0
	var da := DirAccess.open(path)
	if da == null:
		return 0
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if not f.begins_with("."):
			n += 1
		f = da.get_next()
	return n


## Reads a text file. `lines` like "10-40" returns numbered lines for precise edits.
func read(path: String, lines: String = "", max_chars: int = 6000) -> String:
	var p := C.res_path(path)
	if p.is_empty() or not FileAccess.file_exists(p):
		return "ERR no file " + path
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return "ERR cannot open " + p
	var text := f.get_as_text()
	if lines == "":
		return C.trunc(text, max_chars)
	var a := lines.get_slice("-", 0).to_int()
	var b := lines.get_slice("-", 1).to_int() if lines.contains("-") else a
	var all := text.split("\n")
	a = maxi(1, a)
	b = mini(all.size(), maxi(a, b))
	var out: PackedStringArray = []
	for i in range(a, b + 1):
		out.append("%d|%s" % [i, all[i - 1]])
	return C.trunc("\n".join(out), max_chars)


## Writes (or patches) a text file inside the project.
func write(path: String, content: String, old: String = "", new_text: String = "") -> String:
	var p := C.res_path(path)
	if p.is_empty() or p == "res://project.godot":
		return "ERR bad path (project.godot: use the setting tool)"
	if old != "":
		if not FileAccess.file_exists(p):
			return "ERR no file " + p
		var src := FileAccess.get_file_as_string(p)
		var cnt := src.count(old)
		if cnt == 0:
			return "ERR old text not found"
		if cnt > 1:
			return "ERR old text matches %d places; make it unique" % cnt
		content = src.replace(old, new_text)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p.get_base_dir()))
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return "ERR cannot write %s (%s)" % [p, error_string(FileAccess.get_open_error())]
	f.store_string(content)
	f.close()
	return "ok %s %dB" % [p, content.length()]


## Project settings DSL, one op per line:
##   set section/key value        autoload Name res://x.gd      action name Key1 Key2 ...
##   main res://scene.tscn        layer 2d_physics 1 name        unaction name
func setting(ops: String) -> String:
	var errs: PackedStringArray = []
	var n := 0
	for raw in ops.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var t := C.tokenize(line)
		n += 1
		var e := _setting_op(t)
		if e != "":
			errs.append("%s: %s" % [line.substr(0, 40), e])
	var err := ProjectSettings.save()
	if err != OK:
		errs.append("save failed: " + error_string(err))
	var out := "ok %d ops" % n
	if not errs.is_empty():
		out += "\n%d failed:\n%s" % [errs.size(), "\n".join(errs)]
	return out


func _setting_op(t: PackedStringArray) -> String:
	match t[0]:
		"set":
			if t.size() < 3:
				return "usage: set section/key value"
			var key := t[1]
			var cur: Variant = ProjectSettings.get_setting(key, null)
			var val: Variant
			if cur != null:
				var res := C.coerce({"type": typeof(cur)}, t[2])
				if not res[0]:
					return res[1]
				val = res[1]
			else:
				val = C.parse_value(t[2])
			ProjectSettings.set_setting(key, val)
			return ""
		"main":
			if t.size() < 2:
				return "usage: main res://scene.tscn"
			var p := C.res_path(t[1])
			if p.is_empty() or not FileAccess.file_exists(p):
				return "no scene " + t[1]
			ProjectSettings.set_setting("application/run/main_scene", p)
			return ""
		"autoload":
			if t.size() < 3:
				return "usage: autoload Name res://x.gd"
			var p := C.res_path(t[2])
			if p.is_empty() or not FileAccess.file_exists(p):
				return "no file " + t[2]
			ProjectSettings.set_setting("autoload/" + t[1], "*" + p)
			return ""
		"action":
			if t.size() < 3:
				return "usage: action name Key [Key...]"
			var events: Array = []
			for i in range(2, t.size()):
				var ev := _event_from(t[i])
				if ev == null:
					return "unknown key/button '%s'" % t[i]
				events.append(ev)
			ProjectSettings.set_setting("input/" + t[1], {"deadzone": 0.2, "events": events})
			if InputMap.has_action(t[1]):
				InputMap.erase_action(t[1])
			InputMap.add_action(t[1], 0.2)
			for ev in events:
				InputMap.action_add_event(t[1], ev)
			return ""
		"unaction":
			if t.size() < 2:
				return "usage: unaction name"
			ProjectSettings.clear("input/" + t[1])
			if InputMap.has_action(t[1]):
				InputMap.erase_action(t[1])
			return ""
		"layer":
			if t.size() < 4:
				return "usage: layer 2d_physics 1 Name"
			ProjectSettings.set_setting("layer_names/%s/layer_%s" % [t[1], t[2]], t[3])
			return ""
	return "unknown op '%s'" % t[0]


static func _event_from(name: String) -> InputEvent:
	if name.begins_with("Mouse"):
		var ev := InputEventMouseButton.new()
		ev.button_index = {"MouseLeft": MOUSE_BUTTON_LEFT, "MouseRight": MOUSE_BUTTON_RIGHT, "MouseMiddle": MOUSE_BUTTON_MIDDLE}.get(name, 0)
		return ev if ev.button_index != 0 else null
	if name.begins_with("Pad"):
		var jb := InputEventJoypadButton.new()
		var idx := {"PadA": JOY_BUTTON_A, "PadB": JOY_BUTTON_B, "PadX": JOY_BUTTON_X, "PadY": JOY_BUTTON_Y, "PadStart": JOY_BUTTON_START}.get(name, -1) as int
		if idx < 0:
			return null
		jb.button_index = idx as JoyButton
		return jb
	var code := OS.find_keycode_from_string(name)
	if code == KEY_NONE:
		return null
	var k := InputEventKey.new()
	k.physical_keycode = code
	return k
