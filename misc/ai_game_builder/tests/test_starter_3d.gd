extends SceneTree

const Starter = preload("res://addons/ai_game_builder/starter.gd")
const Validator = preload("res://addons/ai_game_builder/validator.gd")
const Quality = preload("res://addons/ai_game_builder/quality.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	var draft := Starter.create_draft("3D game")
	_check("3D starter exists", draft.get("ok", false))
	if not draft.get("ok", false):
		quit(1)
		return

	_check("3D starter has three files", draft["files"].size() == 3)
	_check("3D starter passes strict validator", Validator.validate_payload(draft)["ok"])
	_check("3D starter passes game quality gate", Quality.review_payload(draft, "3D game")["ok"])
	_check("3D summary describes template", draft["summary"].contains("3D arena"))
	_check("3D starter is deterministic", draft == Starter.create_draft("3D game"))
	_check("2D starter remains default", Starter.create_draft() == Starter.create_draft("2D game"))
	_check("unsupported game modes rejected", not Starter.create_draft("3D scene")["ok"])

	var files: Array = draft["files"]
	_check("main scene has conventional path", files[0]["path"] == "scenes/main.tscn")
	_check("script has a separate path", files[1]["path"] == "scripts/arena_3d.gd")
	_check("instructions are bundled", files[2]["path"] == "README.md")
	_check("scene is 3D", files[0]["content"].contains('type="Node3D"'))
	_check("scene links generated script", files[0]["content"].contains("res://ai_generated/scripts/arena_3d.gd"))
	_check("scene uses standard Godot scene resource format", files[0]["content"].begins_with("[gd_scene"))
	_check("script extends Node3D", files[1]["content"].begins_with("extends Node3D"))
	_check("camera generated procedurally", files[1]["content"].contains("Camera3D.new()"))
	_check("sunlight generated procedurally", files[1]["content"].contains("DirectionalLight3D.new()"))
	_check("player controls present", files[1]["content"].contains("KEY_W") and files[1]["content"].contains("KEY_RIGHT"))
	_check("arena boundaries enforced", files[1]["content"].contains("ARENA_RADIUS"))
	_check("collection and score present", files[1]["content"].contains("WIN_SCORE") and files[1]["content"].contains("_score += 1"))
	_check("game has time limit", files[1]["content"].contains("ROUND_SECONDS"))
	_check("game supports restart", files[1]["content"].contains("reload_current_scene"))
	_check("game uses no editor scripts", not files[1]["content"].contains("@tool"))
	_check("game makes no HTTP requests", not files[1]["content"].contains("HTTPRequest"))
	_check("game doesn't rely on input map changes", not files[1]["content"].contains("Input.is_action_pressed"))
	_check("documentation explains play controls", files[2]["content"].contains("WASD"))
	_check("documentation explains entry scene", files[2]["content"].contains("scenes/main.tscn"))
	_check("three files satisfy path safety", _paths_safe(files))

	var incomplete := draft.duplicate(true)
	incomplete["files"].remove_at(1)
	_check("missing 3D script rejected", not Validator.validate_payload(incomplete)["ok"])
	_check("2D game remains valid", Validator.validate_payload(Starter.create_draft("2D game"))["ok"])

	print("AI offline 3D starter: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _paths_safe(files: Array) -> bool:
	for entry in files:
		if not Validator.is_safe_relative_path(entry["path"]):
			return false
	return true


func _check(name: String, good: bool) -> void:
	if good:
		passed += 1
	else:
		failed += 1
		push_error("FAILED: %s" % name)
