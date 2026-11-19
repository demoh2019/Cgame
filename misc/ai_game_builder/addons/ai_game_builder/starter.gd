@tool
extends RefCounted

## Bundled starter is the offline baseline for smoke tests and AI refinement.

const ROOT := "res://addons/ai_game_builder/templates/arcade_2d/"
const FILES := ["scenes/main.tscn", "scripts/arcade.gd", "README.md"]


static func create_draft() -> Dictionary:
	var content: Array[Dictionary] = []
	for relative_path in FILES:
		var text := FileAccess.get_file_as_string(ROOT + relative_path)
		if text.is_empty():
			return {"ok": false, "error": "Missing starter: %s" % relative_path}
		content.append({"path": relative_path, "content": text})
	return {
		"ok": true,
		"summary": "Offline 2D arcade starter (WASD/arrows to collect green squares).",
		"files": content,
	}
