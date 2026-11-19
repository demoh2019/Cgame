@tool
extends RefCounted

# Only file names and public project settings are sent, never file contents.
const MAX_PATHS = 80
const MAX_DEPTH = 3
const INTERESTING_EXTENSIONS = ["gd", "tscn", "tres", "gdshader"]
const SKIP_DIRS = [".git", ".godot", "addons", "ai_generated", "node_modules", "build", "bin"]


static func describe() -> String:
	var project_name := str(ProjectSettings.get_setting("application/config/name", "Unnamed project"))
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", "not set"))
	var paths: Array[String] = []
	_walk("res://", 0, paths)
	var result := "Project name: %s\nMain scene: %s\nRelevant project file paths:\n" % [project_name, main_scene]
	if paths.is_empty():
		return result + "(empty or new project)"
	return result + "\n".join(PackedStringArray(paths))


static func _walk(directory: String, depth: int, paths: Array[String]) -> void:
	if depth > MAX_DEPTH or paths.size() >= MAX_PATHS:
		return

	var files := DirAccess.get_files_at(directory)
	files.sort()
	for file_name in files:
		if paths.size() >= MAX_PATHS:
			return
		if file_name.get_extension().to_lower() in INTERESTING_EXTENSIONS:
			paths.append(directory + file_name)

	if depth == MAX_DEPTH:
		return
	var subdirectories := DirAccess.get_directories_at(directory)
	subdirectories.sort()
	for subdir in subdirectories:
		if paths.size() >= MAX_PATHS:
			return
		if subdir in SKIP_DIRS or subdir.begins_with("."):
			continue
		_walk(directory + subdir + "/", depth + 1, paths)


# File contents are shared only after explicit user opt-in in the dock.
const MAX_SELECTED_FILES = 4
const MAX_SELECTED_CHARS = 6000
const MAX_SELECTED_TOTAL_CHARS = 20000
const SELECTED_EXTENSIONS = ["gd", "tscn"]


static func describe_selected(paths: PackedStringArray) -> String:
	var snippets := PackedStringArray()
	var count := 0
	var remaining := MAX_SELECTED_TOTAL_CHARS
	for path in paths:
		if count >= MAX_SELECTED_FILES or remaining <= 0:
			break
		if not _is_selected_path_safe(path):
			continue
		if not FileAccess.file_exists(path):
			continue
		var data := FileAccess.get_file_as_string(path)
		if data.is_empty():
			continue
		var limit := mini(MAX_SELECTED_CHARS, remaining)
		var excerpt := data.left(limit)
		remaining -= excerpt.length()
		count += 1
		var truncated := " [truncated]" if data.length() > excerpt.length() else ""
		snippets.append("=== %s%s ===\n%s\n=== END ===" % [path, truncated, excerpt])

	if snippets.is_empty():
		return "(no readable selected .gd or .tscn files)"
	return "\n\n".join(snippets)


static func _is_selected_path_safe(path: String) -> bool:
	if not path.begins_with("res://") or path.contains("\\"):
		return false
	if not (path.get_extension().to_lower() in SELECTED_EXTENSIONS):
		return false
	var root := DirAccess.open("res://")
	if root == null:
		return false
	var current := ""
	for segment in path.trim_prefix("res://").split("/"):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
		current = segment if current.is_empty() else current + "/" + segment
		if root.is_link(current):
			return false
	return true
