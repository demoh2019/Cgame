@tool
extends RefCounted
## Read-only, deterministic graph of static res:// references. No resource loading.

const SKIP_DIRS := [".git", ".godot", ".import", ".venv", "venv", "node_modules", "__pycache__"]
const TEXT_EXTENSIONS := ["gd", "tscn", "tres", "godot", "gdshader", "gdshaderinc", "cs", "cfg", "shader", "escn", "json"]
const MAX_TEXT_BYTES := 8 * 1024 * 1024


static func extract_references(content: String, extension: String) -> Array[Dictionary]:
	## Only complete quoted resource literals, like the offline Python audit tool.
	## No string interpolation, dynamic paths, uid:// or nonliteral dependencies.
	var refs: Array[Dictionary] = []
	var line_number := 0
	for line in content.split("\n"):
		line_number += 1
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#") and not trimmed.begins_with("#include"):
			continue
		if trimmed.begins_with("//"):
			continue
		var current_quote := ""
		var escaped := false
		var start := 0
		for i in range(line.length()):
			var ch := line[i]
			if current_quote.is_empty():
				if extension == "gd" and ch == "#":
					break
				if extension in ["cs", "gdshader", "gdshaderinc", "shader"] and ch == "/" and i + 1 < line.length() and line[i + 1] == "/":
					break
				if ch == "\"" or ch == "'":
					current_quote = ch
					start = i + 1
			elif escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == current_quote:
				var value := line.substr(start, i - start)
				if value.begins_with("res://"):
					refs.append({"line": line_number, "target": value.substr(6)})
				current_quote = ""
	return refs


static func build_from_files(files: Dictionary) -> Dictionary:
	## files: project-relative path -> text string (or null for binary assets).
	var names := PackedStringArray(files.keys())
	names.sort()
	var references: Array[Dictionary] = []
	for source in names:
		if not (source.get_extension().to_lower() in TEXT_EXTENSIONS):
			continue
		if not (files[source] is String):
			continue
		for found in extract_references(files[source], source.get_extension().to_lower()):
			var target: String = found["target"]
			# Exact key membership rejects case mismatches, traversal and bad separators.
			if files.has(target):
				references.append({"source": source, "target": target, "line": found["line"]})
	references.sort_custom(_reference_less)
	return {"nodes": names, "references": references, "errors": PackedStringArray()}


static func build_project(root: String = "res://", max_text_bytes: int = MAX_TEXT_BYTES) -> Dictionary:
	## Treat symlink aliases as untrusted: do not follow symlinked files/folders.
	var errors := PackedStringArray()
	if max_text_bytes < 1 or not root.begins_with("res://") and not root.begins_with("user://"):
		return {"nodes": PackedStringArray(), "references": [], "errors": PackedStringArray(["Invalid project root or size limit."])}
	var files := {}
	_collect_files(root, "", files, errors)
	var contents := {}
	for relative in files.keys():
		var path: String = files[relative]
		contents[relative] = null
		if not (relative.get_extension().to_lower() in TEXT_EXTENSIONS):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			errors.append("Cannot read " + relative)
			continue
		if file.get_length() > max_text_bytes:
			continue
		contents[relative] = file.get_as_text()
	var graph := build_from_files(contents)
	graph["errors"] = errors
	return graph


static func _collect_files(root: String, relative: String, files: Dictionary, errors: PackedStringArray) -> void:
	var path := root if relative.is_empty() else root.path_join(relative)
	var directory := DirAccess.open(path)
	if directory == null:
		errors.append("Cannot enumerate " + path)
		return
	directory.include_hidden = true
	for name in directory.get_files():
		if directory.is_link(name):
			continue
		var file_relative := name if relative.is_empty() else relative.path_join(name)
		files[file_relative] = path.path_join(name)
	for name in directory.get_directories():
		if name in SKIP_DIRS or directory.is_link(name):
			continue
		var child := name if relative.is_empty() else relative.path_join(name)
		_collect_files(root, child, files, errors)


static func trace(graph: Dictionary, asset: String, direction: String = "both", depth: int = 1) -> Dictionary:
	var selected := asset.substr(6) if asset.begins_with("res://") else asset
	var empty := {"nodes": PackedStringArray(), "references": [], "error": ""}
	if direction not in ["dependencies", "referencers", "both"]:
		empty["error"] = "Unknown direction: " + direction
		return empty
	if depth < -1:
		empty["error"] = "Depth must be -1 or greater."
		return empty
	if not graph.get("nodes", PackedStringArray()).has(selected):
		empty["error"] = "Asset is not indexed: res://" + selected
		return empty
	var outgoing := {}
	var incoming := {}
	for reference in graph["references"]:
		var source: String = reference["source"]
		var target: String = reference["target"]
		if not outgoing.has(source):
			outgoing[source] = []
		if not incoming.has(target):
			incoming[target] = []
		outgoing[source].append(target)
		incoming[target].append(source)
	var visited := {selected: true}
	var queue: Array[String] = [selected]
	var levels: Array[int] = [0]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		var level := levels[cursor]
		cursor += 1
		if depth != -1 and level >= depth:
			continue
		var neighbours := {}
		if direction in ["dependencies", "both"]:
			for target in outgoing.get(current, []):
				neighbours[target] = true
		if direction in ["referencers", "both"]:
			for source in incoming.get(current, []):
				neighbours[source] = true
		var ordered := PackedStringArray(neighbours.keys())
		ordered.sort()
		for neighbour in ordered:
			if not visited.has(neighbour):
				visited[neighbour] = true
				queue.append(neighbour)
				levels.append(level + 1)
	var nodes := PackedStringArray(visited.keys())
	nodes.sort()
	var references: Array[Dictionary] = []
	for reference in graph["references"]:
		if visited.has(reference["source"]) and visited.has(reference["target"]):
			references.append(reference)
	return {"nodes": nodes, "references": references, "error": ""}


static func to_dot(graph: Dictionary) -> String:
	var lines := ["digraph AssetReferences {", "  rankdir=LR;"]
	for node in graph["nodes"]:
		lines.append("  " + JSON.stringify("res://" + node) + ";")
	var seen := {}
	for reference in graph["references"]:
		var edge := JSON.stringify("res://" + reference["source"]) + " -> " + JSON.stringify("res://" + reference["target"])
		if not seen.has(edge):
			seen[edge] = true
			lines.append("  " + edge + ";")
	lines.append("}")
	return "\n".join(lines) + "\n"


static func _reference_less(a: Dictionary, b: Dictionary) -> bool:
	if a["source"] != b["source"]:
		return a["source"] < b["source"]
	if a["line"] != b["line"]:
		return a["line"] < b["line"]
	return a["target"] < b["target"]
