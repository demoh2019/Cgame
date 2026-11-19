@tool
extends RefCounted

# Read-only, explicitly selected project context. Nothing is auto-discovered.
const Plan = preload("res://addons/ai_game_builder/plan.gd")
const MAX_FILES := 8
const MAX_FILE_BYTES := 16384
const MAX_TOTAL_BYTES := 49152
const CONTEXT_EXTENSIONS := ["gd", "tscn", "tres", "gdshader", "shader", "json", "md", "txt", "cfg", "csv"]
const SENSITIVE_NAMES := [
	"secret", "credential", "password", "passwd", "token", "api_key",
	"private_key", "access_key", "client_secret", "authentication", "auth_key"
]
const SENSITIVE_CONTENT := [
	"-----begin private key-----", "-----begin rsa private key-----",
	"-----begin open ssh private key-----",
	"authorization: bearer ", "api_key =", "api_key=", "secret_key =",
	"secret_key=", "access_token =", "access_token=", "password =",
	"password=", "client_secret =", "client_secret="
]


static func collect(path_lines: String) -> Dictionary:
	var files: Array[Dictionary] = []
	var seen := {}
	var total_bytes := 0

	for line in path_lines.split("\n"):
		var path := line.strip_edges()
		if path.is_empty():
			continue
		if path.begins_with("res://"):
			return _error("Use relative paths without res:// prefix.")
		var invalid: String = Plan.validate_path(path)
		if not invalid.is_empty():
			return _error("Unsafe context file %s: %s" % [path, invalid])
		if not CONTEXT_EXTENSIONS.has(path.get_extension().to_lower()):
			return _error("Unsupported context type: " + path)
		var lower_path := path.to_lower()
		for keyword in SENSITIVE_NAMES:
			if lower_path.contains(keyword):
				return _error("Potentially sensitive filename, not sent: " + path)
		if seen.has(lower_path):
			return _error("Duplicate context path: " + path)
		seen[lower_path] = true
		if files.size() >= MAX_FILES:
			return _error("No more than %d context files are allowed." % MAX_FILES)
		if Plan._is_symlink_path(path):
			return _error("Refusing to read a symlink: " + path)

		var absolute := "res://" + path
		if not FileAccess.file_exists(absolute):
			return _error("Context file not found: " + path)
		var file := FileAccess.open(absolute, FileAccess.READ)
		if file == null:
			return _error("Cannot read context file: " + path)
		var length := file.get_length()
		if length > MAX_FILE_BYTES:
			file.close()
			return _error("Selected context file is larger than 16 KiB: " + path)
		if total_bytes + length > MAX_TOTAL_BYTES:
			file.close()
			return _error("Selected context exceeds 48 KiB.")
		var raw := file.get_buffer(length)
		file.close()
		if raw.has(0):
			return _error("Binary context content is not supported: " + path)
		var body := raw.get_string_from_utf8()
		if body.to_utf8_buffer() != raw:
			return _error("Context file contains invalid UTF-8: " + path)
		var lower_body := body.to_lower()
		for marker in SENSITIVE_CONTENT:
			if lower_body.contains(marker):
				return _error("Context may contain credentials; remove them before selecting: " + path)
		total_bytes += length
		files.append({"path": path, "content": body})

	return {"ok": true, "files": files, "total_bytes": total_bytes}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
