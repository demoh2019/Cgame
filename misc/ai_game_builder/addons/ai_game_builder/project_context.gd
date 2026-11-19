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
