@tool
extends VBoxContainer

const Planner = preload("res://addons/ai_game_builder/planner.gd")
const Writer = preload("res://addons/ai_game_builder/writer.gd")
const Inspector = preload("res://addons/ai_game_builder/inspector.gd")

var _http: HTTPRequest
var _endpoint: LineEdit
var _model: LineEdit
var _api_key: LineEdit
var _prompt: TextEdit
var _preview: TextEdit
var _generate_button: Button
var _repair_button: Button
var _apply_button: Button
var _cancel_button: Button
var _status: Label
var _confirmation: ConfirmationDialog
var _pending_plan: Dictionary = {}
var _last_errors: Array[String] = []
var _busy := false


func _ready() -> void:
	custom_minimum_size = Vector2(310, 400)

	var heading := Label.new()
	heading.text = "AI Game Builder"
	add_child(heading)

	_endpoint = _add_line("Chat completions endpoint", "HTTPS URL or local server", "https://api.openai.com/v1/chat/completions")
	_model = _add_line("Model", "Model identifier", "gpt-4.1-mini")
	_api_key = _add_line("API key (kept only in memory)", "Optional for local models", "")
	_api_key.secret = true

	var prompt_label := Label.new()
	prompt_label.text = "Describe the game to create"
	add_child(prompt_label)
	_prompt = TextEdit.new()
	_prompt.custom_minimum_size = Vector2(0, 105)
	_prompt.placeholder_text = "Create a 2D arcade game with movement, enemies and a score."
	add_child(_prompt)

	var controls := HBoxContainer.new()
	add_child(controls)
	_generate_button = Button.new()
	_generate_button.text = "Generate"
	_generate_button.pressed.connect(_generate)
	controls.add_child(_generate_button)
	_repair_button = Button.new()
	_repair_button.text = "Repair"
	_repair_button.tooltip_text = "Regenerate after detected dependency errors. Each attempt makes another API call."
	_repair_button.disabled = true
	_repair_button.pressed.connect(_repair)
	controls.add_child(_repair_button)
	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.disabled = true
	_cancel_button.pressed.connect(_cancel)
	controls.add_child(_cancel_button)
	_apply_button = Button.new()
	_apply_button.text = "Apply files..."
	_apply_button.disabled = true
	_apply_button.pressed.connect(_confirm_apply)
	controls.add_child(_apply_button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Generated files will appear under res://ai_generated/."
	add_child(_status)

	var preview_label := Label.new()
	preview_label.text = "Review generated files before applying"
	add_child(preview_label)
	_preview = TextEdit.new()
	_preview.editable = false
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(0, 140)
	add_child(_preview)

	_confirmation = ConfirmationDialog.new()
	_confirmation.confirmed.connect(_apply)
	add_child(_confirmation)

	_http = HTTPRequest.new()
	_http.timeout = 90
	_http.body_size_limit = 1024 * 1024
	_http.max_redirects = 0 # Do not forward authorization headers to another host.
	_http.request_completed.connect(_completed)
	add_child(_http)


func _add_line(label_text: String, hint: String, initial: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	add_child(label)
	var line := LineEdit.new()
	line.placeholder_text = hint
	line.text = initial
	add_child(line)
	return line


func _generate() -> void:
	_request_plan(_prompt.text.strip_edges(), false)


func _repair() -> void:
	if _pending_plan.is_empty() or _last_errors.is_empty() or _busy:
		return
	var repair_text := Inspector.repair_prompt(_prompt.text.strip_edges(), _pending_plan, _last_errors)
	_request_plan(repair_text, true)


func _request_plan(prompt: String, is_repair: bool) -> void:
	if _busy:
		return
	var endpoint := _endpoint.text.strip_edges()
	var model := _model.text.strip_edges()
	if prompt.is_empty() or model.is_empty():
		_status.text = "Enter a game description and model."
		return
	if not _allowed_endpoint(endpoint):
		_status.text = "Use HTTPS, or HTTP on localhost/127.0.0.1 only."
		return

	var headers := PackedStringArray(["Content-Type: application/json"])
	var key := _api_key.text.strip_edges()
	if not key.is_empty():
		headers.append("Authorization: Bearer " + key)
	var request_error := _http.request(endpoint, headers, HTTPClient.METHOD_POST, Planner.make_request(model, prompt))
	if request_error != OK:
		_status.text = "Unable to start the request (error %d)." % request_error
		return
	if not is_repair:
		_pending_plan.clear()
		_last_errors.clear()
		_preview.text = ""
	_apply_button.disabled = true
	_set_busy(true)
	_status.text = "Requesting a repaired plan..." if is_repair else "Generating a reviewable game plan..."

func _allowed_endpoint(endpoint: String) -> bool:
	var lower := endpoint.to_lower()
	if lower.begins_with("https://"):
		return true
	return lower.begins_with("http://127.0.0.1:") or lower.begins_with("http://localhost:") or lower.begins_with("http://[::1]:")


func _cancel() -> void:
	if not _busy:
		return
	_http.cancel_request()
	_set_busy(false)
	_status.text = "Generation cancelled."


func _completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _busy:
		return
	_set_busy(false)
	if result != HTTPRequest.RESULT_SUCCESS:
		_status.text = "Request failed (network result %d)." % result
		return
	if response_code != 200:
		_status.text = "Provider returned HTTP %d. Check endpoint, model and credentials." % response_code
		return
	var validated := Planner.read_response(body.get_string_from_utf8())
	if not validated.ok:
		_status.text = "Plan rejected: " + String(validated.error)
		return
	_pending_plan = validated.plan
	var inspection := Inspector.inspect(_pending_plan)
	_last_errors = inspection.errors
	_preview.text = JSON.stringify(_pending_plan, "\t")
	if not inspection.errors.is_empty():
		_preview.text = "STATIC ERRORS (not yet applied):\n" + "\n".join(PackedStringArray(inspection.errors)) + "\n\n" + _preview.text
	if not inspection.warnings.is_empty():
		_preview.text = "REVIEW WARNINGS:\n" + "\n".join(PackedStringArray(inspection.warnings)) + "\n\n" + _preview.text
	_apply_button.disabled = not inspection.ok
	_repair_button.disabled = inspection.ok
	if inspection.ok:
		_status.text = "Review passed for %d files. Inspect the code before applying." % _pending_plan.files.size()
	else:
		_status.text = "%d static errors. Click Repair for another model attempt." % inspection.errors.size()


func _set_busy(value: bool) -> void:
	_busy = value
	_generate_button.disabled = value
	_cancel_button.disabled = not value
	_repair_button.disabled = value or _last_errors.is_empty()
	_endpoint.editable = not value
	_model.editable = not value
	_prompt.editable = not value
	_api_key.editable = not value


func _confirm_apply() -> void:
	if _pending_plan.is_empty() or _busy:
		return
	if not Inspector.inspect(_pending_plan).ok:
		_status.text = "Resolve static errors before applying."
		return
	_confirmation.dialog_text = "Create %d new files under res://ai_generated/? Existing files will never be overwritten. Review the preview first." % _pending_plan.files.size()
	_confirmation.popup_centered()


func _apply() -> void:
	if _pending_plan.is_empty() or _busy:
		return
	if not Inspector.inspect(_pending_plan).ok:
		_status.text = "Resolve static errors before applying."
		return
	var result := Writer.apply(_pending_plan)
	if not result.ok:
		_status.text = String(result.error)
		return
	_status.text = "Created %d files in res://ai_generated/. Open main.tscn to play." % result.paths.size()
	_apply_button.disabled = true
	_repair_button.disabled = true
	_pending_plan.clear()
	_last_errors.clear()
	EditorInterface.get_resource_filesystem().scan()
