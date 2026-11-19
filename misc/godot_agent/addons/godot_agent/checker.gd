extends SceneTree
## Child-process helper: loads scripts and scenes so that the engine reports parse and
## load errors with file:line. Usage: --script checker.gd -- res://a.gd res://b.tscn

func _initialize() -> void:
	var bad := 0
	for p in OS.get_cmdline_user_args():
		if p.ends_with(".gd"):
			var s := ResourceLoader.load(p, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
			if s == null or not s.can_instantiate():
				print("CHK_FAIL ", p)
				bad += 1
		elif p.ends_with(".tscn"):
			var ps := ResourceLoader.load(p, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			if ps == null or not ps.can_instantiate():
				print("CHK_FAIL ", p)
				bad += 1
	print("CHK_DONE ", bad)
	quit(1 if bad > 0 else 0)
