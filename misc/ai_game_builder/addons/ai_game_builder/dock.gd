@tool
extends VBoxContainer

const Plan = preload("res://addons/ai_game_builder/plan.gd")
const SYSTEM_PROMPT := """
You are a senior Godot 4 GDScript game developer.
Produce a playable, minimal, coherent implementation of the user's request.
Respond ONLY with a valid JSON object of this form:
{"summary":"What will change","files":[{"path":"res://ai_generated/main.tscn","operation":"create","content":"Full file text"}]}
Allowed operations: create (new file) and update (replace an existing generated file).
ALL paths must start with res://ai_generated/ and end in gd, tscn, tres, gdshader, json, csv, md, txt, cfg, or svg.
At most 20 files, each at most 100000 characters; total at most 400000 characters.
For new games, include res://ai_generated/main.tscn as the entry scene.
Use correct Godot 4 scene syntax, references, signals, GDScript and input APIs.
Make assets procedurally with built-in nodes when practical; do not depend on external downloads.
For revisions, preserve existing files unless explicitly changed.
Do not generate editor plugins, @tool scripts, external commands, or project.godot.
No Markdown fences, no explanations outside JSON.
"""
const DEFAULT_ENDPOINT := "https://api.openai.com/v1/chat/completions"
const MAX_CONTEXT_CHARS := 30000

var _endpoint: LineEdit
var _model: LineEdit
var _api_key: LineEdit
var _prompt: TextEdit
var _preview: TextEdit
var _status: Label
var _generate_button: Button
var _apply_button: Button
var _confirmation: ConfirmationDialog
var _http: HTTPRequest
var _pending_plan: Dictionary = {}


func _ready() -> void:
	name = "AI Game Builder"
	custom_minimum_size = Vector2(600, 320)

	var heading := Label.new()
	heading.text = "AI Game Builder — generate or improve a game from a prompt"
	add_child(heading)

	_endpoint = _input_row("API URL", DEFAULT_ENDPOINT)
	_model = _input_row("Model", "gpt-4.1-mini")
	_api_key = _input_row("API key", "")
	_api_key.secret = true
	_api_key.placeholder_text = "Not saved; optional for local servers"

	var prompt_label := Label.new()
	prompt_label.text = "What should the AI create or change?"
	add_child(prompt_label)

	_prompt = TextEdit.new()
	_prompt.custom_minimum_size = Vector2(0, 80)
	_prompt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prompt.text = "Create a small playable 2D platformer with movement, jumping, a goal and a restart action."
	add_child(_prompt)

	var actions := HBoxContainer.new()
	add_child(actions)
	_generate_button = Button.new()
	_generate_button.text = "Generate plan"
	_generate_button.pressed.connect(_generate_plan)
	actions.add_child(_generate_button)

	_apply_button = Button.new()
	_apply_button.text = "Review and apply"
	_apply_button.disabled = true
	_apply_button.pressed.connect(_request_apply)
	actions.add_child(_apply_button)

	_status = Label.new()
	_status.text = "Files are not changed until you approve the plan. Generated code is untrusted: review it."
	add_child(_status)

	_preview = TextEdit.new()
	_preview.editable = false
	_preview.custom_minimum_size = Vector2(0, 105)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_preview)

	_http = HTTPRequest.new()
	_http.timeout = 120.0
	_http.body_size_limit = 1024 * 1024
	_http.max_redirects = 0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	_confirmation = ConfirmationDialog.new()
	_confirmation.title = "Apply AI-generated files?"
	_confirmation.confirmed.connect(_apply_confirmed)
	add_child(_confirmation)


func _input_row(label_text: String, initial: String) -> LineEdit:
	var row := HBoxContainer.new()
	add_child(row)
	var caption := Label.new()
	caption.text = label_text
	caption.custom_minimum_size = Vector2(75, 0)
	row.add_child(caption)
	var field := LineEdit.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text = initial
	row.add_child(field)
	return field


func _generate_plan() -> void:
	_pending_plan.clear()
	_apply_button.disabled = true
	_preview.clear()
	var endpoint := _endpoint.text.strip_edges()
	if not _endpoint_is_allowed(endpoint):
		_status.text = "Use HTTPS, or plain HTTP only for localhost / 127.0.0.1."
		return
	if _model.text.strip_edges().is_empty() or _prompt.text.strip_edges().is_empty():
		_status.text = "Enter a model and a request."
		return
	if _prompt.text.length() > 8000:
		_status.text = "Prompt too long (max 8000 characters)."
		return

	var headers := PackedStringArray(["Content-Type: application/json"])
	if not _api_key.text.is_empty():
		headers.append("Authorization: Bearer " + _api_key.text)
	var payload := {
		"model": _model.text.strip_edges(),
		"messages": [
			{"role": "system", "content": SYSTEM_PROMPT},
			{"role": "user", "content": "Project context:\n" + _get_project_context() + "\n\nTask:\n" + _prompt.text}
		]
	}
	var error := _http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_status.text = "Could not start HTTP request (error %d)." % error
		return
	_generate_button.disabled = true
	_status.text = "Request sent to the configured provider. Awaiting a proposed file plan..."


func _endpoint_is_allowed(value: String) -> bool:
	if value.contains("\r") or value.contains("\n") or value.contains(" "):
		return false
	if value.begins_with("https://") and value.length() > "https://".length():
		return true
	for host in ["http://localhost", "http://127.0.0.1", "http://[::1]"]:
		if value == host or value.begins_with(host + "/") or value.begins_with(host + ":"):
			return true
	return false


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_generate_button.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_status.text = "Network request failed (code %d)." % result
		return
	var response: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300:
		var message := "API HTTP %d" % response_code
		if response is Dictionary and response.has("error"):
			message += ": " + str(response["error"]).left(220)
		_status.text = message
		return
	if not (response is Dictionary):
		_status.text = "API response was not a JSON object."
		return
	var choices: Variant = response.get("choices", [])
	if not (choices is Array) or choices.is_empty() or not (choices[0] is Dictionary):
		_status.text = "No choices in response (use an OpenAI-compatible chat completions endpoint)."
		return
	var message: Variant = choices[0].get("message", {})
	if not (message is Dictionary) or not (message.get("content") is String):
		_status.text = "No text content in the completion."
		return
	var parsed := Plan.parse_message(message["content"])
	if not parsed["ok"]:
		_status.text = "Rejected proposed plan: " + "; ".join(parsed["errors"])
		_preview.text = str(message["content"]).left(20000)
		return

	_pending_plan = parsed
	var proposed_files: Array = parsed["files"]
	_preview.text = "SUMMARY: " + str(parsed["summary"]) + "\n\n" + JSON.stringify({
		"files": proposed_files
	}, "\t")
	_apply_button.disabled = false
	_status.text = "Plan ready: %d file(s). Review all content below before applying." % proposed_files.size()


func _request_apply() -> void:
	if _pending_plan.is_empty():
		return
	var names: Array[String] = []
	for item in _pending_plan["files"]:
		names.append(str(item["operation"]).to_upper() + " " + str(item["path"]))
	_confirmation.dialog_text = "Apply these changes to your project?\n\n" + "\n".join(names) + "\n\nGenerated scripts may execute when your game runs. Only approve reviewed code."
	_confirmation.popup_centered()


func _apply_confirmed() -> void:
	var outcome := Plan.apply(_pending_plan)
	if not outcome["ok"]:
		_status.text = "No changes applied: " + str(outcome["error"])
		return
	EditorInterface.get_resource_filesystem().scan()
	_status.text = "Applied %d file(s). Open res://ai_generated/main.tscn to run your game." % outcome["written"].size()
	_pending_plan.clear()
	_apply_button.disabled = true


func _get_project_context() -> String:
	var result := ""
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		result = "Edited scene: %s (root type %s)\n" % [root.scene_file_path, root.get_class()]
	var files: Array[String] = []
	_collect_generated_files(Plan.ROOT, files, 0)
	files.sort()
	var count := 0
	for path in files:
		var input := FileAccess.open(path, FileAccess.READ)
		if input == null:
			continue
		var content := input.get_as_text()
		if content.length() > 12000:
			continue
		var part := "FILE " + path + ":\n" + content + "\n"
		if result.length() + part.length() > MAX_CONTEXT_CHARS:
			break
		result += part
		count += 1
	if count == 0:
		result += "No existing AI-generated game files.\n"
	return result


func _collect_generated_files(directory: String, files: Array[String], depth: int) -> void:
	if depth > 5 or files.size() >= 40:
		return
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for entry in dir.get_files():
		var path := directory.path_join(entry)
		if path.get_extension().to_lower() in Plan.ALLOWED_EXTENSIONS:
			files.append(path)
			if files.size() >= 40:
				return
	for child in dir.get_directories():
		if not child.begins_with("."):
			_collect_generated_files(directory.path_join(child), files, depth + 1)
