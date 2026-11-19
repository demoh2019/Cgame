@tool
extends VBoxContainer
## Editor UI for planning and reviewing a strictly file-sandboxed Godot project.

const PLAN = preload("res://addons/ai_game_builder/plan.gd")
const WRITER = preload("res://addons/ai_game_builder/writer.gd")
const DEFAULT_ENDPOINT := "https://api.openai.com/v1/chat/completions"
const DEFAULT_MODEL := "gpt-4.1-mini"

const SYSTEM_PROMPT := """You are an expert Godot 4.x game developer.
Create a playable, self-contained game prototype or implement the user's feature request.
Respond with ONLY one JSON object:
{"summary":"Short explanation","main_scene":"res://ai_generated/main.tscn","files":[{"path":"res://ai_generated/main.tscn","content":"..."},{"path":"res://ai_generated/player.gd","content":"..."}]}
Requirements:
- Use GDScript and text-based Godot 4 scenes/resources.
- All output paths MUST start with res://ai_generated/ (subfolders allowed).
- Generate everything needed to play: main .tscn, attached scripts, gameplay, input setup in code, simple primitive visuals. Do not depend on downloads or third-party assets.
- Do not write to project.godot, addons/, or any existing source files.
- Include a nonempty main_scene which points to a generated .tscn file.
- No external network calls, subprocesses, shell commands, EditorScript, @tool scripts, or privileged file access in the generated game.
- Prefer small, maintainable, correct scenes and scripts over large low-quality dumps.
- Use explicit node paths, valid .tscn format, and Godot 4 APIs. For multiplayer or advanced 3D, implement a minimal playable slice.
- Output at most 32 files, each <= 128 KiB and total <= 512 KiB.
- When following up on a previous generated plan, use DIFFERENT paths for revisions; existing files will not be overwritten.
"""

var _endpoint: LineEdit
var _model: LineEdit
var _prompt: TextEdit
var _generate: Button
var _apply: Button
var _approved: CheckBox
var _set_main: CheckBox
var _file_select: OptionButton
var _preview: TextEdit
var _status: Label
var _http: HTTPRequest
var _plan: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 5)
	var title := Label.new()
	title.text = "AI Game Builder"
	title.add_theme_font_size_override("font_size", 17)
	add_child(title)

	var warning := Label.new()
	warning.text = "Review generated GDScript before running the game."
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(warning)

	_endpoint = LineEdit.new()
	_endpoint.text = OS.get_environment("GODOT_AI_ENDPOINT") if OS.has_environment("GODOT_AI_ENDPOINT") else DEFAULT_ENDPOINT
	_endpoint.placeholder_text = DEFAULT_ENDPOINT
	_endpoint.tooltip_text = "OpenAI-compatible chat completions HTTPS endpoint; HTTP allowed only for localhost without a token."
	add_child(_endpoint)

	_model = LineEdit.new()
	_model.text = OS.get_environment("GODOT_AI_MODEL") if OS.has_environment("GODOT_AI_MODEL") else DEFAULT_MODEL
	_model.placeholder_text = "Model name"
	add_child(_model)

	_prompt = TextEdit.new()
	_prompt.custom_minimum_size = Vector2(0, 116)
	_prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prompt.placeholder_text = "Describe your game: genre, controls, victory conditions, style…"
	_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(_prompt)

	var samples := HBoxContainer.new()
	for label in ["2D Platformer", "Top-down RPG", "3D Arena"]:
		var button := Button.new()
		button.text = label
		button.pressed.connect(_sample_pressed.bind(label))
		samples.add_child(button)
	add_child(samples)

	_generate = Button.new()
	_generate.text = "1. Generate plan"
	_generate.pressed.connect(_request_plan)
	add_child(_generate)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Set GODOT_AI_API_KEY in the environment, then describe a game."
	add_child(_status)

	_file_select = OptionButton.new()
	_file_select.item_selected.connect(_select_file)
	add_child(_file_select)

	_preview = TextEdit.new()
	_preview.editable = false
	_preview.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(0, 160)
	add_child(_preview)

	_approved = CheckBox.new()
	_approved.text = "I reviewed the generated files"
	_approved.toggled.connect(_update_apply_button.unbind(1))
	add_child(_approved)

	_set_main = CheckBox.new()
	_set_main.text = "Set the generated main scene in project settings"
	_set_main.button_pressed = true
	add_child(_set_main)

	_apply = Button.new()
	_apply.text = "2. Create files (no overwrites)"
	_apply.disabled = true
	_apply.pressed.connect(_apply_plan)
	add_child(_apply)

	_http = HTTPRequest.new()
	_http.timeout = 90.0
	_http.body_size_limit = 1024 * 1024
	_http.request_completed.connect(_on_response)
	add_child(_http)


func _sample_pressed(which: String) -> void:
	match which:
		"2D Platformer":
			_prompt.text = "Create a playable 2D platformer with moving character, jump, platforms, hazards and a win area. Use built-in shapes and colors."
		"Top-down RPG":
			_prompt.text = "Create a top-down 2D mini RPG with movement, dialogue, interactable NPC and one collectable quest."
		"3D Arena":
			_prompt.text = "Create a simple 3D arena game with player movement, third-person camera, obstacles, enemies, score and restart."


func _request_plan() -> void:
	var prompt_text := _prompt.text.strip_edges()
	if prompt_text.is_empty():
		_set_status("Describe the game or feature first.")
		return
	if prompt_text.length() > 12000:
		_set_status("Prompt exceeds 12,000 characters.")
		return
	var endpoint := _endpoint.text.strip_edges()
	var is_local := endpoint.begins_with("http://127.0.0.1:") or endpoint.begins_with("http://localhost:")
	if not endpoint.begins_with("https://") and not is_local:
		_set_status("Only HTTPS endpoints or local HTTP on loopback are allowed.")
		return
	if endpoint.contains("@") or endpoint.contains("#") or endpoint.contains(" ") or endpoint.contains("?"):
		_set_status("Endpoint URL contains unsupported characters.")
		return
	var model := _model.text.strip_edges()
	if model.is_empty() or model.length() > 128:
		_set_status("Enter a valid model identifier.")
		return
	var token := OS.get_environment("GODOT_AI_API_KEY").strip_edges()
	if token.is_empty() and not is_local:
		_set_status("Set GODOT_AI_API_KEY in the environment before starting Godot.")
		return
	if is_local and not token.is_empty():
		_set_status("Local HTTP requires an empty token; do not send API credentials in plaintext.")
		return

	_plan.clear()
	_file_select.clear()
	_preview.text = ""
	_approved.button_pressed = false
	_update_apply_button()
	_generate.disabled = true
	_set_status("Generating a reviewable plan…")

	var headers := PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var body := JSON.stringify({
		"model": model,
		"messages": [
			{"role": "system", "content": SYSTEM_PROMPT},
			{"role": "user", "content": prompt_text}
		]
	})
	var error := _http.request(endpoint, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		_generate.disabled = false
		_set_status("HTTP request could not be started: " + error_string(error))


func _on_response(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_generate.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("Request failed (network code %d)." % result)
		return
	if status < 200 or status >= 300:
		_set_status("Provider returned HTTP %d. Check endpoint and model." % status)
		return
	var decoded: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (decoded is Dictionary):
		_set_status("Provider response is not valid JSON.")
		return
	var choices: Variant = decoded.get("choices", [])
	if not (choices is Array) or choices.is_empty() or not (choices[0] is Dictionary):
		_set_status("Provider response has no chat completion choice.")
		return
	var message: Variant = choices[0].get("message", {})
	if not (message is Dictionary) or not (message.get("content") is String):
		_set_status("Provider returned an empty or unsupported message.")
		return
	var verdict: Dictionary = PLAN.parse_response(message["content"])
	if not verdict.ok:
		_set_status("Unsafe or invalid generation: " + str(verdict.error))
		return
	_plan = verdict.plan
	var available: Dictionary = WRITER.preflight(_plan)
	if not available.ok:
		_plan.clear()
		_set_status("Cannot apply this plan: " + str(available.error) + ". Ask for different filenames.")
		return
	for entry in _plan["files"]:
		_file_select.add_item(entry["path"])
	_file_select.select(0)
	_select_file(0)
	_set_status("Plan: %s (%d files, %d bytes). Inspect files and approve before applying." % [_plan.get("summary", ""), verdict.count, verdict.bytes])


func _select_file(index: int) -> void:
	if _plan.is_empty() or index < 0 or index >= _plan["files"].size():
		return
	var entry: Dictionary = _plan["files"][index]
	_preview.text = entry["content"]


func _update_apply_button() -> void:
	if _apply != null:
		_apply.disabled = _plan.is_empty() or not _approved.button_pressed


func _apply_plan() -> void:
	if _plan.is_empty() or not _approved.button_pressed:
		return
	var result: Dictionary = WRITER.apply(_plan, _set_main.button_pressed)
	if not result.ok:
		_set_status("Failed: " + result.error)
		return
	_set_status("Created %d files. Review scripts and run your new game." % result.created.size())
	_plan.clear()
	_approved.button_pressed = false
	_update_apply_button()
	EditorInterface.get_resource_filesystem().scan()


func _set_status(message: String) -> void:
	_status.text = message
