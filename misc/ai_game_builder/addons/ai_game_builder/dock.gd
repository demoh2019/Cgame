@tool
extends VBoxContainer

const Validator = preload("res://addons/ai_game_builder/validator.gd")
const ENDPOINT := "https://api.openai.com/v1/chat/completions"
const GENERATED_ROOT := "res://ai_generated/"

var _api_key: LineEdit
var _model: LineEdit
var _description: TextEdit
var _mode: OptionButton
var _request: HTTPRequest
var _generate: Button
var _apply: Button
var _file_picker: OptionButton
var _preview: TextEdit
var _status: Label
var _pending_files: Array[Dictionary] = []
var _pending_summary := ""


func _ready() -> void:
	custom_minimum_size = Vector2(300, 500)
	add_theme_constant_override("separation", 6)

	var heading := Label.new()
	heading.text = "AI Game Builder"
	add_child(heading)

	var help := Label.new()
	help.text = "Create files from a prompt. Review them before applying."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)

	_mode = OptionButton.new()
	for item in ["2D game", "3D game", "2D scene", "3D scene", "Scripts / mechanics", "Game design document"]:
		_mode.add_item(item)
	add_child(_mode)

	_description = TextEdit.new()
	_description.placeholder_text = "Describe gameplay, world, controls, visual style and desired mechanics..."
	_description.custom_minimum_size.y = 110
	_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_description)

	_model = LineEdit.new()
	_model.placeholder_text = "Model"
	_model.text = "gpt-4.1-mini"
	add_child(_model)

	_api_key = LineEdit.new()
	_api_key.placeholder_text = "OpenAI API key (never saved)"
	_api_key.secret = true
	add_child(_api_key)

	_generate = Button.new()
	_generate.text = "Generate"
	_generate.pressed.connect(_generate_files)
	add_child(_generate)

	_status = Label.new()
	_status.text = "Ready. Nothing will be changed until Apply."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	_file_picker = OptionButton.new()
	_file_picker.disabled = true
	_file_picker.item_selected.connect(_show_file)
	add_child(_file_picker)

	_preview = TextEdit.new()
	_preview.editable = false
	_preview.custom_minimum_size.y = 170
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_preview)

	_apply = Button.new()
	_apply.text = "Apply reviewed files"
	_apply.disabled = true
	_apply.pressed.connect(_apply_files)
	add_child(_apply)

	_request = HTTPRequest.new()
	_request.timeout = 120.0
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)


func _system_prompt() -> String:
	return (
		"You are a senior Godot 4.8 game developer. Generate a small, playable, " +
		"coherent prototype matching the user's request. Return only a JSON object " +
		"with keys summary (string) and files (array of objects with keys path and content). " +
		"Paths are RELATIVE to res://ai_generated/, e.g. scenes/main.tscn or scripts/player.gd. " +
		"All references inside generated files must use res://ai_generated/ absolute resource paths. " +
		"Use valid Godot 4.x GDScript, .tscn scene format and built-in nodes/resources. " +
		"Do not require downloaded assets, external addons, autoloads or changes to project.godot. " +
		"Prefer procedural geometry, simple shapes and UI for a playable initial prototype. " +
		"For games, include scenes/main.tscn as the entry scene, working player controls, " +
		"win/lose feedback when relevant, and concise usage instructions in README.md. " +
		"Make no more than 20 files, each below 96 KiB, all text-only. " +
		"Allowed extensions: gd, tscn, tres, gdshader, json, md, txt, svg. " +
		"Never generate @tool scripts, editor plugins, shell commands or code that accesses " +
		"network services or arbitrary files. Use Input.is_key_pressed for simple controls " +
		"or explicitly document custom input actions. " +
		"Return a COMPLETE, syntactically consistent set of files, not markdown code fences."
	)


func _generate_files() -> void:
	var task := _description.text.strip_edges()
	var key := _api_key.text.strip_edges()
	var model_name := _model.text.strip_edges()
	if task.is_empty() or key.is_empty() or model_name.is_empty():
		_status.text = "Enter a task, model and API key."
		return
	# Never keep stale approval after a new request.
	_pending_files.clear()
	_pending_summary = ""
	_file_picker.clear()
	_file_picker.disabled = true
	_preview.text = ""
	_apply.disabled = true
	var request_data := {
		"model": model_name,
		"max_completion_tokens": 12000,
		"response_format": {"type": "json_object"},
		"messages": [
			{"role": "system", "content": _system_prompt()},
			{"role": "user", "content": "Mode: %s\nTask:\n%s" % [_mode.get_item_text(_mode.selected), task]},
		],
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + key,
	])
	_generate.disabled = true
	_status.text = "Generating… no project files have been changed."
	var error := _request.request(ENDPOINT, headers, HTTPClient.METHOD_POST, JSON.stringify(request_data))
	if error != OK:
		_generate.disabled = false
		_status.text = "Could not start request (error %d)." % error


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_generate.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_status.text = "Network request failed (result %d)." % result
		return
	if response_code < 200 or response_code >= 300:
		var failure := Validator.parse_model_response(body.get_string_from_utf8())
		_status.text = "HTTP %d: %s" % [response_code, failure.get("error", "Request rejected.")]
		return

	var parsed := Validator.parse_model_response(body.get_string_from_utf8())
	if not parsed["ok"]:
		_status.text = parsed["error"]
		return
	_pending_files = parsed["files"]
	_pending_summary = parsed["summary"]
	for entry in _pending_files:
		_file_picker.add_item(entry["path"])
	_file_picker.disabled = false
	_file_picker.select(0)
	_show_file(0)
	_apply.disabled = false
	_status.text = "Ready to review %d file(s). %s" % [_pending_files.size(), _pending_summary]


func _show_file(index: int) -> void:
	if index >= 0 and index < _pending_files.size():
		_preview.text = _pending_files[index]["content"]


func _apply_files() -> void:
	var validation := Validator.validate_payload({"summary": _pending_summary, "files": _pending_files})
	if not validation["ok"]:
		_status.text = validation["error"]
		return
	var files: Array = validation["files"]
	# Preflight every destination so applying never overwrites any existing file.
	for entry in files:
		var dest := ProjectSettings.globalize_path(GENERATED_ROOT + entry["path"])
		if FileAccess.file_exists(dest) or DirAccess.dir_exists_absolute(dest):
			_status.text = "File already exists; nothing changed: %s" % entry["path"]
			return

	var created: Array[String] = []
	for entry in files:
		var dest := ProjectSettings.globalize_path(GENERATED_ROOT + entry["path"])
		var error := DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		if error != OK:
			_rollback(created)
			_status.text = "Could not create directory for %s (error %d)." % [entry["path"], error]
			return
		var output := FileAccess.open(dest, FileAccess.WRITE)
		if output == null:
			_rollback(created)
			_status.text = "Could not write %s (error %d)." % [entry["path"], FileAccess.get_open_error()]
			return
		output.store_string(entry["content"])
		output.close()
		created.append(dest)

	_pending_files.clear()
	_pending_summary = ""
	_apply.disabled = true
	_file_picker.disabled = true
	_status.text = "Created %d file(s) in res://ai_generated/. Check scenes/main.tscn." % created.size()
	EditorInterface.get_resource_filesystem().scan()


func _rollback(paths: Array[String]) -> void:
	for path in paths:
		DirAccess.remove_absolute(path)
