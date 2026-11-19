@tool
extends RefCounted

const Validator = preload("res://addons/ai_game_builder/validator.gd")
const Writer = preload("res://addons/ai_game_builder/writer.gd")

# Only checks specifically approved AI outputs. It never scans or executes the
# rest of the project. ResourceLoader is used for validation, not scene play.
const RESOURCE_EXTENSIONS := ["gd", "tscn", "tres", "gdshader"]
const MAX_DIAGNOSTICS := 32


static func validate_targets(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false, "error": "The approved paths must be a JSON array."}
	if value.is_empty() or value.size() > Validator.MAX_FILES:
		return {"ok": false, "error": "Approved paths must contain 1 to %d files." % Validator.MAX_FILES}

	var paths: Array[String] = []
	var seen := {}
	for raw_path in value:
		if typeof(raw_path) != TYPE_STRING:
			return {"ok": false, "error": "All approved file paths must be strings."}
		var path: String = raw_path
		if not path.begins_with(Validator.OUTPUT_PREFIX):
			return {"ok": false, "error": "Refusing to inspect a file outside ai_generated."}
		var relative := path.trim_prefix(Validator.OUTPUT_PREFIX)
		if not Validator._safe_relative_path(relative):
			return {"ok": false, "error": "Unsafe approved path: %s" % path}
		if not Validator.ALLOWED_EXTENSIONS.has(relative.get_extension().to_lower()):
			return {"ok": false, "error": "Unsupported file type: %s" % path}
		if seen.has(path.to_lower()):
			return {"ok": false, "error": "Duplicate approved path: %s" % path}
		seen[path.to_lower()] = true
		if Writer._path_has_symlink(path) or not FileAccess.file_exists(path):
			return {"ok": false, "error": "Approved file missing or symlinked: %s" % path}
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() < 1 or file.get_length() > Validator.MAX_FILE_BYTES:
			return {"ok": false, "error": "Approved file is unreadable or too large: %s" % path}
		var content := file.get_as_text()
		file.close()
		var ext := relative.get_extension().to_lower()
		if ["gd", "tscn", "tres"].has(ext) and content.contains("@tool"):
			return {"ok": false, "error": "Editor-executable generated resource is forbidden: %s" % path}
		if ext == "gd" and (content.contains("OS.execute(") or content.contains("OS.create_process(")):
			return {"ok": false, "error": "Generated process-launching script is forbidden: %s" % path}
		paths.append(path)

	if not paths.has(Validator.OUTPUT_PREFIX + "main.tscn"):
		return {"ok": false, "error": "The approved files must include ai_generated/main.tscn."}
	return {"ok": true, "paths": paths}


static func check(value: Variant) -> Dictionary:
	var validated := validate_targets(value)
	if not validated.ok:
		return {"ok": false, "checked": 0, "errors": [String(validated.error)]}

	var failures: Array[String] = []
	var checked := 0
	# Compile/load GDScript first so scenes resolve generated script classes.
	for extension_group in [["gd"], ["tscn", "tres", "gdshader"]]:
		for path in validated.paths:
			var ext := String(path).get_extension().to_lower()
			if not extension_group.has(ext):
				continue
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
			checked += 1
			if resource == null:
				failures.append("Godot could not load %s. Check the editor/headless log for parser errors." % path)
			elif ext == "gd":
				var script := resource as Script
				if script == null or not script.can_instantiate():
					failures.append("Godot could not compile %s into an instantiable script." % path)
			elif ext == "tscn" and not (resource is PackedScene):
				failures.append("Godot did not load a PackedScene from %s." % path)
			if failures.size() >= MAX_DIAGNOSTICS:
				break
		if failures.size() >= MAX_DIAGNOSTICS:
			break

	# Validate JSON game data as well.
	if failures.size() < MAX_DIAGNOSTICS:
		for path in validated.paths:
			if not String(path).ends_with(".json"):
				continue
			checked += 1
			var parser := JSON.new()
			if parser.parse(FileAccess.get_file_as_string(path)) != OK:
				failures.append("Could not decode JSON data: %s (line %d)" % [path, parser.get_error_line()])
				if failures.size() >= MAX_DIAGNOSTICS:
					break

	return {"ok": failures.is_empty(), "checked": checked, "errors": failures}
