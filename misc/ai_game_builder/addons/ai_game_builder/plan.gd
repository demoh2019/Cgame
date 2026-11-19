@tool
extends RefCounted
## Pure validation for the small, deliberately sandboxed AI plan format.
## All output paths must live under res://ai_generated/.

const ROOT := "res://ai_generated/"
const MAX_FILES := 32
const MAX_FILE_BYTES := 131072
const MAX_TOTAL_BYTES := 524288
const VALID_EXTENSIONS := ["gd", "tscn", "tres", "gdshader", "json", "csv", "txt", "md"]


static func validate(plan: Variant) -> Dictionary:
	if not (plan is Dictionary):
		return {"ok": false, "error": "AI output must be a JSON object."}
	if not (plan.get("files") is Array):
		return {"ok": false, "error": "Missing files array."}
	var files: Array = plan["files"]
	if files.is_empty() or files.size() > MAX_FILES:
		return {"ok": false, "error": "A plan must contain 1 to %d files." % MAX_FILES}

	var seen := {}
	var total_bytes := 0
	for entry in files:
		if not (entry is Dictionary):
			return {"ok": false, "error": "Each file must be a JSON object."}
		var path: Variant = entry.get("path")
		var content: Variant = entry.get("content")
		if not (path is String) or not (content is String):
			return {"ok": false, "error": "Every file needs string path and content fields."}
		var path_error := path_error_message(path)
		if not path_error.is_empty():
			return {"ok": false, "error": path_error}
		var canonical: String = path.to_lower()
		if seen.has(canonical):
			return {"ok": false, "error": "Duplicate destination: " + path}
		seen[canonical] = true
		var bytes := content.to_utf8_buffer().size()
		if bytes > MAX_FILE_BYTES:
			return {"ok": false, "error": "File is too large: " + path}
		total_bytes += bytes
		if total_bytes > MAX_TOTAL_BYTES:
			return {"ok": false, "error": "Plan exceeds the total size limit."}
		# A generated tool script could run immediately inside the editor.
		if path.get_extension().to_lower() == "gd" and _has_tool_annotation(content):
			return {"ok": false, "error": "Editor-executed @tool scripts are not allowed: " + path}

	var scene: Variant = plan.get("main_scene", "")
	if not (scene is String):
		return {"ok": false, "error": "main_scene must be a string."}
	if not scene.is_empty():
		if path_error_message(scene) != "" or scene.get_extension().to_lower() != "tscn":
			return {"ok": false, "error": "main_scene must be a generated .tscn file."}
		if not seen.has(scene.to_lower()):
			return {"ok": false, "error": "main_scene is missing from files."}

	var summary: Variant = plan.get("summary", "")
	if not (summary is String) or summary.length() > 4096:
		return {"ok": false, "error": "summary must be text shorter than 4096 characters."}
	return {"ok": true, "error": "", "count": files.size(), "bytes": total_bytes}


static func path_error_message(path: String) -> String:
	if not path.begins_with(ROOT):
		return "Files must be inside " + ROOT
	if path.length() <= ROOT.length() or path.length() > 240:
		return "Invalid file path length: " + path
	if path.contains("\\") or path.substr(ROOT.length()).contains(":") or path.contains("\n") or path.contains("\r") or path.contains("\t"):
		return "Invalid characters in file path: " + path
	if path.get_extension().to_lower() not in VALID_EXTENSIONS:
		return "Unsupported file extension: " + path
	var relative := path.substr(ROOT.length())
	for segment in relative.split("/", true):
		if segment.is_empty() or segment == "." or segment == ".." or segment.begins_with("."):
			return "Unsafe file path component: " + path
		if segment.ends_with(" ") or segment.ends_with("."):
			return "Unsafe trailing character in file path: " + path
		for disallowed in ["<", ">", "\"", "|", "?", "*", "\u0000"]:
			if segment.contains(disallowed):
				return "Unsupported character in file path: " + path
		var stem := segment.get_basename().to_upper()
		if stem in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "LPT1", "LPT2", "LPT3"]:
			return "Reserved filename: " + path
	return ""


static func _has_tool_annotation(content: String) -> bool:
	for line in content.split("\n"):
		var stripped := line.strip_edges()
		if stripped == "@tool" or stripped.begins_with("@tool "):
			return true
	return false


static func parse_response(text: String) -> Dictionary:
	var cleaned := text.strip_edges()
	# Some compatible providers wrap JSON in a Markdown code fence.
	if cleaned.begins_with("```"):
		var first_newline := cleaned.find("\n")
		if first_newline == -1 or not cleaned.ends_with("```"):
			return {"ok": false, "error": "Incomplete JSON code fence."}
		cleaned = cleaned.substr(first_newline + 1, cleaned.length() - first_newline - 4).strip_edges()
	var parsed: Variant = JSON.parse_string(cleaned)
	var verdict := validate(parsed)
	if verdict.ok:
		verdict["plan"] = parsed
	return verdict
