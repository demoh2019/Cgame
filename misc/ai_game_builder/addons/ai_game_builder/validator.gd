@tool
extends RefCounted

## Strictly validate untrusted model output before displaying or writing it.
## Files always live below res://ai_generated/; never update project.godot or addons.

const MAX_FILES := 20
const MAX_FILE_BYTES := 98304
const MAX_TOTAL_BYTES := 524288
const ALLOWED_EXTENSIONS := [
	"gd", "tscn", "tres", "gdshader", "json", "md", "txt", "svg",
]


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "error": reason, "files": [], "summary": ""}


static func is_safe_relative_path(path: String) -> bool:
	if path.is_empty() or path.length() > 180:
		return false
	if path.begins_with("/") or path.contains("\\") or path.contains(":"):
		return false
	if path.contains("//") or path.contains("\n") or path.contains("\r"):
		return false
	if path.contains("\t") or path.contains("\u0000"):
		return false
	for segment in path.split("/"):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
		if segment.begins_with(".") or segment.ends_with(".") or segment.ends_with(" "):
			return false
		if segment.contains(" "):
			return false
		for character in segment:
			var code := character.unicode_at(0)
			if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 45 or code == 46 or code == 95):
				return false
	return path.get_extension().to_lower() in ALLOWED_EXTENSIONS


static func validate_payload(payload: Variant) -> Dictionary:
	if not payload is Dictionary:
		return _failure("AI output must be a JSON object.")
	var files: Variant = payload.get("files")
	if not files is Array or files.is_empty():
		return _failure("AI output must have a nonempty files array.")
	if files.size() > MAX_FILES:
		return _failure("Too many files (maximum %d)." % MAX_FILES)
	var summary: Variant = payload.get("summary", "")
	if not summary is String:
		return _failure("Summary must be a string.")
	if summary.length() > 4000:
		return _failure("Summary is too long.")

	var checked: Array[Dictionary] = []
	var seen := {}
	var total_bytes := 0
	for entry in files:
		if not entry is Dictionary:
			return _failure("Each file must be an object.")
		var path: Variant = entry.get("path")
		var content: Variant = entry.get("content")
		if not path is String or not is_safe_relative_path(path):
			return _failure("Unsafe or unsupported relative path.")
		if not content is String or content.is_empty():
			return _failure("Each generated file must have nonempty text content.")
		if seen.has(path.to_lower()):
			return _failure("Duplicate path: %s" % path)
		seen[path.to_lower()] = true
		var file_bytes := content.to_utf8_buffer().size()
		total_bytes += file_bytes
		if file_bytes > MAX_FILE_BYTES or total_bytes > MAX_TOTAL_BYTES:
			return _failure("Generated output exceeds the size limit.")
		# Loading editor-executable scripts from model output is not allowed.
		if path.get_extension().to_lower() == "gd" and content.contains("@tool"):
			return _failure("Generated @tool scripts are not allowed.")
		checked.append({"path": path, "content": content})
	var missing_references := find_missing_generated_references(checked)
	if not missing_references.is_empty():
		return _failure("Missing generated resource: %s" % missing_references[0])
	return {"ok": true, "error": "", "files": checked, "summary": summary}


static func find_missing_generated_references(files: Array[Dictionary]) -> Array[String]:
	# Cheap deterministic consistency check, without loading or executing untrusted code.
	var present := {}
	for entry in files:
		present[entry["path"]] = true
	var expression := RegEx.create_from_string("res://ai_generated/[A-Za-z0-9_./-]+")
	var missing: Array[String] = []
	for entry in files:
		var extension: String = entry["path"].get_extension().to_lower()
		if not extension in ["gd", "tscn", "tres", "gdshader"]:
			continue
		for occurrence in expression.search_all(entry["content"]):
			var resource_path := occurrence.get_string().trim_prefix("res://ai_generated/")
			if not present.has(resource_path) and not missing.has(resource_path):
				missing.append(resource_path)
	return missing


static func parse_model_response(body: String) -> Dictionary:
	var response: Variant = JSON.parse_string(body)
	if not response is Dictionary:
		return _failure("The API did not return JSON.")
	if response.has("error"):
		var err: Variant = response["error"]
		if err is Dictionary:
			return _failure("Provider error: %s" % str(err.get("message", "Unknown error")))
		return _failure("Provider returned an error.")
	var choices: Variant = response.get("choices")
	if not choices is Array or choices.is_empty():
		return _failure("Provider response has no choices.")
	var choice: Variant = choices[0]
	if not choice is Dictionary:
		return _failure("Malformed provider response.")
	var message: Variant = choice.get("message")
	if not message is Dictionary or not message.get("content") is String:
		return _failure("Provider returned no text content.")
	var raw_payload: Variant = JSON.parse_string(message["content"])
	if raw_payload == null:
		return _failure("AI reply is not valid JSON.")
	return validate_payload(raw_payload)
