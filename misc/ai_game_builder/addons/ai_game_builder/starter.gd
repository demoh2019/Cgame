@tool
extends RefCounted

const Validator = preload("res://addons/ai_game_builder/validator.gd")

# Reuses the small self-contained arcade example from the other AI Builder
# prototype (#74), adapted to this addon's single main.tscn requirement.
const ROOT := "res://addons/ai_game_builder/templates/arcade_2d/"
const SOURCES := [
	{"source": "scenes/main.tscn", "output": "main.tscn"},
	{"source": "scripts/arcade.gd", "output": "scripts/arcade.gd"},
	{"source": "README.md", "output": "README.md"}
]


static func create_draft() -> Dictionary:
	var files: Array[Dictionary] = []
	for entry in SOURCES:
		var src: String = ROOT + String(entry.source)
		var file := FileAccess.open(src, FileAccess.READ)
		if file == null:
			return {"ok": false, "error": "Offline template file is missing: %s" % src}
		var length := file.get_length()
		if length <= 0 or length > Validator.MAX_FILE_BYTES:
			return {"ok": false, "error": "Offline template file size is invalid: %s" % src}
		var content := file.get_as_text()
		file.close()
		files.append({"path": String(entry.output), "content": content})

	var plan := {
		"summary": "Offline 2D arcade: move with WASD/arrows, collect targets, score ten points before time runs out, restart with R.",
		"files": files
	}
	return Validator.validate(plan)
