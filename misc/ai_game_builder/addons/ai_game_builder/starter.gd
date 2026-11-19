@tool
extends RefCounted

## Bundled offline starters are the baseline for smoke tests and AI refinement.
## A draft never writes files until the user reviews and applies the proposal.

const ROOT_2D := "res://addons/ai_game_builder/templates/arcade_2d/"
const ROOT_3D := "res://addons/ai_game_builder/templates/arena_3d/"
const FILES_2D := ["scenes/main.tscn", "scripts/arcade.gd", "README.md"]
const FILES_3D := ["scenes/main.tscn", "scripts/arena_3d.gd", "README.md"]


static func create_draft(mode: String = "2D game") -> Dictionary:
	var template_root := ROOT_2D
	var template_files := FILES_2D
	var summary := "Offline 2D arcade starter (WASD/arrows to collect green squares)."
	match mode:
		"2D game":
			pass
		"3D game":
			template_root = ROOT_3D
			template_files = FILES_3D
			summary = "Offline 3D arena starter (WASD/arrows, collect six green boxes)."
		_:
			return {"ok": false, "error": "Unsupported offline starter mode: %s" % mode, "files": []}

	var content: Array[Dictionary] = []
	for relative_path in template_files:
		var text := FileAccess.get_file_as_string(template_root + relative_path)
		if text.is_empty():
			return {"ok": false, "error": "Missing starter: %s" % relative_path, "files": []}
		content.append({"path": relative_path, "content": text})
	return {
		"ok": true,
		"summary": summary,
		"files": content,
	}
