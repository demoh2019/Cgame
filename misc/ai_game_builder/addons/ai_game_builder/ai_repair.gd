@tool
extends RefCounted

const Changes = preload("res://addons/ai_game_builder/ai_changes.gd")
const MAX_FILES := 12
const MAX_CONTEXT_CHARS := 48000
const MAX_FILE_BYTES := 12000


static func collect_context(paths: Array[String]) -> String:
	var output := ""
	var seen := {}
	var count := 0
	for path in paths:
		if count >= MAX_FILES:
			break
		if seen.has(path) or not Changes.is_safe_path(path) or Changes.has_symlink(path):
			continue
		seen[path] = true
		if not FileAccess.file_exists(path):
			continue
		var size := FileAccess.get_size(path)
		if size < 0 or size > MAX_FILE_BYTES:
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var source := file.get_as_text()
		var section := "\n--- " + path + " ---\n" + source + "\n"
		if output.length() + section.length() > MAX_CONTEXT_CHARS:
			break
		output += section
		count += 1
	return output if not output.is_empty() else "(No eligible generated files available)"
