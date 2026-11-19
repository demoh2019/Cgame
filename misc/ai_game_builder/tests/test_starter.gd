extends SceneTree

const Starter = preload("res://addons/ai_game_builder/starter.gd")
const Validator = preload("res://addons/ai_game_builder/validator.gd")
const Quality = preload("res://addons/ai_game_builder/quality.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	var draft := Starter.create_draft()
	_check("starter present", draft["ok"])
	_check("starter three files", draft["files"].size() == 3)
	_check("starter validates", Validator.validate_payload(draft)["ok"])
	_check("starter passes quality", Quality.review_payload(draft, "2D game")["ok"])
	_check("has main scene", draft["files"][0]["path"] == "scenes/main.tscn")
	_check("has game script", draft["files"][1]["path"] == "scripts/arcade.gd")
	_check("has controls documentation", draft["files"][2]["content"].contains("WASD"))
	_check("main references generated script", draft["files"][0]["content"].contains("res://ai_generated/scripts/arcade.gd"))
	_check("script is not editor-executable", not draft["files"][1]["content"].contains("@tool"))
	_check("game includes win score", draft["files"][1]["content"].contains("WIN_SCORE"))
	_check("game includes restart", draft["files"][1]["content"].contains("reload_current_scene"))
	_check("game needs no network", not draft["files"][1]["content"].contains("HTTPRequest"))
	print("Offline starter tests: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(name: String, good: bool) -> void:
	if good:
		passed += 1
	else:
		failed += 1
		push_error("FAILED: %s" % name)
