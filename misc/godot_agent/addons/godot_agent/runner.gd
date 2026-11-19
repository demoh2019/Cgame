extends SceneTree
## Child-process helper: runs a scene for N frames with scripted input, then evaluates
## expressions against the scene root. Config is read from user://agent_run.json.

var cfg: Dictionary
var scene_root: Node
var frame := 0
var loaded := false
var presses: Array = []  # [action, start, end]


func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://agent_run.json"))
	cfg = parsed if parsed is Dictionary else {}
	var ps := ResourceLoader.load(String(cfg.get("scene", "")), "PackedScene") as PackedScene
	if ps != null:
		scene_root = ps.instantiate()
		root.add_child(scene_root)
		loaded = scene_root != null
	for tok in String(cfg.get("inputs", "")).split(" ", false):
		# action@start-end (frames); a missing range means held for the whole run
		var act := tok.get_slice("@", 0)
		var rng := tok.get_slice("@", 1) if tok.contains("@") else ""
		var a := 0
		var b := int(cfg.get("frames", 60))
		if rng != "":
			a = rng.get_slice("-", 0).to_int()
			b = rng.get_slice("-", 1).to_int() if rng.contains("-") else a + 1
		presses.append([act, a, b])


func _process(_delta: float) -> bool:
	for p in presses:
		if frame == p[1] or frame == p[2]:
			var ev := InputEventAction.new()
			ev.action = p[0]
			ev.pressed = frame == p[1]
			Input.parse_input_event(ev)
	frame += 1
	if frame >= int(cfg.get("frames", 60)) or not loaded:
		_finish()
		return true
	return false


func _eval(expr: String) -> Array:
	var ex := Expression.new()
	if ex.parse(expr, ["root", "frame"]) != OK:
		return [false, "parse error: " + ex.get_error_text()]
	var v: Variant = ex.execute([scene_root, frame], scene_root, false)
	if ex.has_execute_failed():
		return [false, "eval error: " + ex.get_error_text()]
	return [true, v]


func _finish() -> void:
	var out := {"frames": frame, "loaded": loaded, "expect": [], "watch": []}
	var failed := 0
	if loaded:
		for e in cfg.get("expect", []):
			var r := _eval(String(e))
			if r[0] and bool(r[1]):
				out.expect.append("PASS " + String(e))
			else:
				failed += 1
				out.expect.append("FAIL %s => %s" % [e, str(r[1])])
		for w in cfg.get("watch", []):
			var r := _eval(String(w))
			out.watch.append("%s = %s" % [w, str(r[1])])
	print("AGENT_RESULT ", JSON.stringify(out))
	quit(1 if failed > 0 or not loaded else 0)
