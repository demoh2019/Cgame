@tool
extends RefCounted

## Lightweight, non-executing checks for AI-generated project files.
## This does not replace Godot's parser, scene loader or headless tests.
const Plan = preload("res://addons/ai_game_builder/plan.gd")
const MAIN_SCENE := "res://ai_generated/main.tscn"
const MAX_SCAN_FILES := 200
const MAX_SCAN_DEPTH := 8
const MAX_SCAN_CHARS := 100000


static func analyze_plan(raw: Variant) -> Dictionary:
	var validated := Plan.validate(raw)
	if not validated["ok"]:
		return {"ok": false, "errors": validated["errors"], "warnings": [], "files": 0}
	var contents := {}
	for item in validated["files"]:
		contents[item["path"]] = item["content"]
	return _analyze(contents)


static func analyze_saved() -> Dictionary:
	var paths: Array[String] = []
	_collect(Plan.ROOT, paths, 0)
	var contents := {}
	var errors: Array[String] = []
	for path in paths:
		var source := FileAccess.open(path, FileAccess.READ)
		if source == null:
			errors.append("%s: cannot read file." % path)
			continue
		if source.get_length() > MAX_SCAN_CHARS * 4:
			errors.append("%s: file is too large to inspect." % path)
			continue
		var content := source.get_as_text()
		if content.length() > MAX_SCAN_CHARS:
			errors.append("%s: file is too large to inspect." % path)
			continue
		contents[path] = content
	var result := _analyze(contents)
	result["errors"].append_array(errors)
	result["ok"] = result["errors"].is_empty()
	if paths.size() >= MAX_SCAN_FILES:
		result["warnings"].append("Scan reached the %d-file limit; some files may be unchecked." % MAX_SCAN_FILES)
	return result


static func format_report(result: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Static inspection of %d file(s). Not a script compilation or runtime test." % result.get("files", 0))
	for error in result.get("errors", []):
		lines.append("ERROR: " + str(error))
	for warning in result.get("warnings", []):
		lines.append("WARNING: " + str(warning))
	if result.get("errors", []).is_empty() and result.get("warnings", []).is_empty():
		lines.append("No problems found by static inspection.")
	return "\n".join(PackedStringArray(lines))


static func _analyze(contents: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var scene_path_regex := RegEx.create_from_string(r'\bpath\s*=\s*"(res://[^"]+)"')
	var script_path_regex := RegEx.create_from_string(r'\b(?:preload|load)\s*\(\s*"(res://[^"]+)"')
	var tool_regex := RegEx.create_from_string(r'(?m)^\s*@tool\b')
	for path in contents:
		var source: String = contents[path]
		var extension := str(path).get_extension().to_lower()
		if extension == "gd":
			if tool_regex.search(source) != null:
				errors.append("%s: @tool is not allowed in generated scripts because it can run in the editor." % path)
			_check_references(path, source, script_path_regex, contents, errors)
			if source.contains("OS.execute("):
				warnings.append("%s: OS.execute call requires careful manual review." % path)
		elif extension == "tscn" or extension == "tres":
			var expected := "[gd_scene" if extension == "tscn" else "[gd_resource"
			if not source.contains(expected):
				errors.append("%s: missing %s header." % [path, expected])
			_check_references(path, source, scene_path_regex, contents, errors)
		elif extension == "json":
			var parser := JSON.new()
			if parser.parse(source) != OK:
				errors.append("%s: invalid JSON at line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		elif extension == "gdshader" and not source.contains("shader_type "):
			warnings.append("%s: no shader_type declaration found." % path)

	if not contents.has(MAIN_SCENE) and not FileAccess.file_exists(MAIN_SCENE):
		warnings.append("No %s entry scene. A generated game may not be runnable." % MAIN_SCENE)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "files": contents.size()}


static func _check_references(path: String, source: String, regex: RegEx, contents: Dictionary, errors: Array[String]) -> void:
	var checked := {}
	for matched in regex.search_all(source):
		var referenced: String = matched.get_string(1)
		if checked.has(referenced):
			continue
		checked[referenced] = true
		if not contents.has(referenced) and not FileAccess.file_exists(referenced):
			var line := source.substr(0, matched.get_start()).count("\n") + 1
			errors.append("%s:%d: missing referenced resource %s" % [path, line, referenced])


static func _collect(directory: String, paths: Array[String], depth: int) -> void:
	if depth > MAX_SCAN_DEPTH or paths.size() >= MAX_SCAN_FILES:
		return
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for filename in dir.get_files():
		if paths.size() >= MAX_SCAN_FILES:
			return
		if filename.get_extension().to_lower() in Plan.ALLOWED_EXTENSIONS:
			paths.append(directory.path_join(filename))
	for child in dir.get_directories():
		if child.begins_with("."):
			continue
		_collect(directory.path_join(child), paths, depth + 1)
