@tool
extends VBoxContainer

const Changes = preload("res://addons/ai_game_builder/ai_changes.gd")
const Protocol = preload("res://addons/ai_game_builder/ai_protocol.gd")

var _endpoint: LineEdit
var _model: LineEdit
var _api_key: LineEdit
var _task: TextEdit
var _include_context: CheckBox
var _generate_button: Button
var _apply_button: Button
var _status: Label
var _summary: Label
var _file_list: ItemList
var _preview: TextEdit
var _http: HTTPRequest
var _confirmation: ConfirmationDialog
var _proposal: Dictionary = {}


func _ready() -> void:
	name = "AI Game Builder"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(320, 480)

	var title := Label.new()
	title.text = "Create games, scenes and scripts with AI"
	add_child(title)

	add_child(_label("Chat completions endpoint:"))
	_endpoint = LineEdit.new()
	_endpoint.text = "https://api.openai.com/v1/chat/completions"
	_endpoint.placeholder_text = "https://…/v1/chat/completions"
	add_child(_endpoint)

	add_child(_label("Model:"))
	_model = LineEdit.new()
	_model.text = "gpt-4.1-mini"
	add_child(_model)

	add_child(_label("API key (session only; or GODOT_AI_API_KEY):"))
	_api_key = LineEdit.new()
	_api_key.secret = true
	_api_key.placeholder_text = "Not needed for most local models"
	add_child(_api_key)

	add_child(_label("Describe the game or change:"))
	_task = TextEdit.new()
	_task.custom_minimum_size = Vector2(0, 115)
	_task.placeholder_text = "Create a playable 2D platformer with movement, obstacles, and a restart button."
	add_child(_task)

	_include_context = CheckBox.new()
	_include_context.text = "Share up to 8 project text files with the model"
	_include_context.button_pressed = false
	_include_context.tooltip_text = "Opt-in: sends up to 48,000 characters of scripts and scenes. Check for private data first."
	add_child(_include_context)

	_generate_button = Button.new()
	_generate_button.text = "Generate proposal"
	_generate_button.pressed.connect(_generate)
	add_child(_generate_button)

	_status = _label("No proposal yet. The AI cannot write without your approval.")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	add_child(HSeparator.new())
	_summary = _label("")
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	_file_list = ItemList.new()
	_file_list.custom_minimum_size = Vector2(0, 90)
	_file_list.item_selected.connect(_preview_file)
	add_child(_file_list)

	_preview = TextEdit.new()
	_preview.editable = false
	_preview.custom_minimum_size = Vector2(0, 110)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_preview)

	_apply_button = Button.new()
	_apply_button.text = "Apply reviewed changes"
	_apply_button.disabled = true
	_apply_button.pressed.connect(_request_apply)
	add_child(_apply_button)

	_confirmation = ConfirmationDialog.new()
	_confirmation.title = "Apply AI-generated files?"
	_confirmation.confirmed.connect(_apply)
	add_child(_confirmation)

	_http = HTTPRequest.new()
	_http.timeout = 120.0
	_http.max_redirects = 0
	_http.body_size_limit = 2 * 1024 * 1024
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


func _label(value: String) -> Label:
	var result := Label.new()
	result.text = value
	return result


func _generate() -> void:
	_proposal = {}
	_apply_button.disabled = true
	_file_list.clear()
	_preview.text = ""
	_summary.text = ""
	var endpoint := _endpoint.text.strip_edges()
	var model := _model.text.strip_edges()
	var task := _task.text.strip_edges()
	if task.is_empty() or model.is_empty():
		_status.text = "Provide both a task and a model."
		return
	if not Protocol.is_allowed_endpoint(endpoint):
		_status.text = "Use HTTPS, or loopback HTTP for a local model."
		return
	_generate_button.disabled = true
	var secret := _api_key.text.strip_edges()
	if secret.is_empty():
		secret = OS.get_environment("GODOT_AI_API_KEY")
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not secret.is_empty():
		headers.append("Authorization: Bearer " + secret)
	var content := _project_context() if _include_context.button_pressed else "(not shared)"
	var body := Protocol.request_body(model, task, content)
	var error := _http.request(endpoint, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		_generate_button.disabled = false
		_status.text = "Could not start request (error %d)." % error
	else:
		_status.text = "Contacting the model; nothing will be written automatically."


func _on_request_completed(result: int, status_code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	_generate_button.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_status.text = "Connection failed (result %d)." % result
		return
	if status_code < 200 or status_code >= 300:
		_status.text = "Model endpoint returned HTTP %d: %s" % [status_code, bytes.get_string_from_utf8().left(300)]
		return
	var parsed := Changes.parse_chat_completion(bytes.get_string_from_utf8())
	if not parsed["ok"]:
		_status.text = "Cannot use this response: " + parsed["error"]
		return
	_proposal = parsed
	_summary.text = parsed["summary"]
	for item in _proposal["files"]:
		var path: String = item["path"]
		var status := "OVERWRITE " if FileAccess.file_exists(path) else "NEW "
		_file_list.add_item(status + path)
	_file_list.select(0)
	_preview_file(0)
	_apply_button.disabled = false
	_status.text = "%d proposed files. Review contents before applying." % _proposal["files"].size()


func _preview_file(index: int) -> void:
	if _proposal.is_empty():
		return
	var file: Dictionary = _proposal["files"][index]
	var path: String = file["path"]
	var text := "PROPOSED: " + path + "\n\n" + file["content"]
	if FileAccess.file_exists(path):
		var original := FileAccess.open(path, FileAccess.READ)
		if original != null:
			text = "EXISTING (first 10,000 chars): " + path + "\n\n" + original.get_as_text().left(10000) + "\n\n--- REPLACEMENT ---\n\n" + text
	_preview.text = text
	_preview.scroll_vertical = 0


func _request_apply() -> void:
	if _proposal.is_empty():
		return
	var overwritten := 0
	for file in _proposal["files"]:
		if FileAccess.file_exists(file["path"]):
			overwritten += 1
	var scene: String = _proposal["main_scene"]
	var scene_note := "\nSet main scene: " + scene if not scene.is_empty() else ""
	_confirmation.dialog_text = "Write %d generated files (%d overwrite existing files)?%s\n\nBackups will be saved under user://. Review the proposed GDScript before running it." % [_proposal["files"].size(), overwritten, scene_note]
	_confirmation.popup_centered()


func _apply() -> void:
	if _proposal.is_empty():
		return
	var result := Changes.apply_changes(_proposal)
	if not result["ok"]:
		_status.text = "Apply failed: " + result["error"]
		return
	_status.text = "Applied %d files. Backup folder: %s. Run and test your game." % [result["written"], result["backup_dir"] if not result["backup_dir"].is_empty() else "(no overwrites)"]
	_apply_button.disabled = true
	_proposal = {}
	EditorInterface.get_resource_filesystem().scan()


func _project_context() -> String:
	var paths: Array[String] = []
	_collect_files("res://", 0, paths)
	var context := ""
	var included := 0
	for path in paths:
		if included >= 8:
			break
		if FileAccess.get_file_as_bytes(path).size() > 10000:
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var content := file.get_as_text()
		if context.length() + content.length() > 48000:
			break
		context += "\n--- " + path + " ---\n" + content + "\n"
		included += 1
	return context if not context.is_empty() else "(no eligible text files found)"


func _collect_files(folder: String, depth: int, paths: Array[String]) -> void:
	if depth > 5 or paths.size() >= 120:
		return
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for filename in dir.get_files():
		if paths.size() >= 120:
			return
		var path := folder.path_join(filename)
		if Changes.is_safe_path(path) and not Changes.has_symlink(path):
			if filename.get_extension().to_lower() in ["gd", "tscn", "tres", "gdshader"]:
				paths.append(path)
	for subfolder in dir.get_directories():
		if subfolder.begins_with(".") or subfolder in ["addons", "node_modules", "vendor", "build"]:
			continue
		var path := folder.path_join(subfolder)
		if not Changes.has_symlink(path):
			_collect_files(path, depth + 1, paths)
