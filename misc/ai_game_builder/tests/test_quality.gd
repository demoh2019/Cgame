extends SceneTree

const Quality = preload("res://addons/ai_game_builder/quality.gd")
const Repair = preload("res://addons/ai_game_builder/repair_policy.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	_check("valid scene", Quality.review_payload(_files("scenes/main.tscn", _scene()), "2D game")["ok"])
	_check("valid 3D scene", Quality.review_payload(_files("scenes/main.tscn", _scene()), "3D game")["ok"])
	_check("reject wrong scene header", not Quality.review_payload(_files("scenes/main.tscn", "extends Node"), "2D game")["ok"])
	_check("reject scene missing node", not Quality.review_payload(_files("scenes/main.tscn", "[gd_scene format=3]"), "2D game")["ok"])
	_check("reject no game entry scene", not Quality.review_payload(_files("scripts/player.gd", "extends Node"), "2D game")["ok"])
	_check("scripts mode without entry scene", Quality.review_payload(_files("scripts/player.gd", "extends Node"), "Scripts / mechanics")["ok"])
	_check("scene mode without main scene", Quality.review_payload(_files("scenes/other.tscn", _scene()), "2D scene")["ok"])
	_check("valid JSON", Quality.review_payload(_files("data/levels.json", "{\"levels\": []}"))["ok"])
	_check("valid JSON array", Quality.review_payload(_files("data/levels.json", "[1, 2]"))["ok"])
	_check("reject malformed JSON", not Quality.review_payload(_files("data/levels.json", "{\"a\": }"))["ok"])
	_check("valid resource", Quality.review_payload(_files("material.tres", "[gd_resource type=\"Resource\" format=3]\n[resource]\n"))["ok"])
	_check("reject wrong resource header", not Quality.review_payload(_files("material.tres", "[resource]\n"))["ok"])
	_check("warn missing resource section", Quality.review_payload(_files("material.tres", "[gd_resource format=3]"))["warnings"].size() == 1)
	_check("accept shader", Quality.review_payload(_files("basic.gdshader", "shader_type spatial;\n"))["ok"])
	_check("warn shader without type", Quality.review_payload(_files("basic.gdshader", "void fragment() {}"))["warnings"].size() == 1)
	_check("accept SVG", Quality.review_payload(_files("icon.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"))["ok"])
	_check("reject SVG lacking root", not Quality.review_payload(_files("icon.svg", "<path/>"))["ok"])
	_check("accept GDScript", Quality.review_payload(_files("player.gd", "extends Node"))["ok"])
	_check("warn incomplete GDScript", Quality.review_payload(_files("player.gd", "pass"))["warnings"].size() == 1)
	_check("reject unsafe output path", not Quality.review_payload(_files("../outside.gd", "extends Node"))["ok"])
	_check("reject missing dependency", not Quality.review_payload(_files("player.gd", "extends Node\nconst X = preload(\"res://ai_generated/missing.gd\")"))["ok"])
	_check("repair enabled first time", Repair.can_retry(true, 0))
	_check("repair allowed once", Repair.can_retry(true, 1))
	_check("repair capped", not Repair.can_retry(true, 2))
	_check("repair rejected negative", not Repair.can_retry(true, -1))
	_check("repair optional", not Repair.can_retry(false, 0))
	_check("repair message includes diagnostics", Repair.make_repair_message("Bad JSON", "{}").contains("Bad JSON"))
	_check("repair message includes raw draft", Repair.make_repair_message("Bad JSON", "{\"bad\":true}").contains("{\"bad\":true}"))
	_check("repair message truncates rejected reply", not Repair.make_repair_message("Bad JSON", "z".repeat(Repair.MAX_REPLY_CHARS + 30)).contains("z".repeat(Repair.MAX_REPLY_CHARS + 1)))
	_check("repair message truncates diagnostics", not Repair.make_repair_message("x".repeat(Repair.MAX_PROBLEM_CHARS + 30), "{}").contains("x".repeat(Repair.MAX_PROBLEM_CHARS + 1)))
	print("Quality checks: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _files(path: String, content: String) -> Dictionary:
	return {"summary": "test", "files": [{"path": path, "content": content}]}


func _scene() -> String:
	return "[gd_scene format=3]\n[node name=\"Main\" type=\"Node2D\"]\n"


func _check(name: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("FAILED: %s" % name)
