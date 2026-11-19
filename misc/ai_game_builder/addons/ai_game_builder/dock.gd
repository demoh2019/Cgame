@tool
extends VBoxContainer

const Planner = preload("res://addons/ai_game_builder/planner.gd")
const Writer = preload("res://addons/ai_game_builder/writer.gd")
const Inspector = preload("res://addons/ai_game_builder/inspector.gd")
const EndpointPolicy = preload("res://addons/ai_game_builder/endpoint_policy.gd")
const Starter = preload("res://addons/ai_game_builder/starter.gd")

var _http: HTTPRequest
var _endpoint: LineEdit
var _model: LineEdit
var _api_key: LineEdit
var _prompt: TextEdit
var _refinement: LineEdit
var _preview: TextEdit
var _generate_button: Button
var _quick_button: Button
var _repair_button: Button
var _refine_button: Button
var _apply_button: Button
var _cancel_button: Button
var _check_button: Button
var _check_timer: Timer
var _check_pid := -1
var _check_started_ms := 0
var _check_report_path := ""
var _approved_paths: Array[String] = []
var _checking := false
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

	var starter_row := HBoxContainer.new()
	add_child(starter_row)
	_quick_button = Button.new()
	_quick_button.text = "Instant 2D Starter (Offline)"
	_quick_button.tooltip_text = "Create an arcade game plan instantly without a model, API key, or network request. Review before applying."
	_quick_button.pressed.connect(_create_starter)
	starter_row.add_child(_quick_button)

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

	var refine_label := Label.new()
	refine_label.text = "Change the current preview (optional)"
	add_child(refine_label)
	_refinement = LineEdit.new()
	_refinement.placeholder_text = "Add a menu, jump button or another enemy..."
	_refinement.max_length = 800
	add_child(_refinement)

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

	var review_controls := HBoxContainer.new()
	add_child(review_controls)
	_refine_button = Button.new()
	_refine_button.text = "Refine"
	_refine_button.tooltip_text = "Ask the model to update the current preview. Uses another API request."
	_refine_button.disabled = true
	_refine_button.pressed.connect(_refine)
	review_controls.add_child(_refine_button)

	_apply_button = Button.new()
	_apply_button.text = "Apply files..."
	_apply_button.disabled = true
	_apply_button.pressed.connect(_confirm_apply)
	review_controls.add_child(_apply_button)

	var verify_controls := HBoxContainer.new()
	add_child(verify_controls)
	_check_button = Button.new()
	_check_button.text = "Check Game (Headless)"
	_check_button.tooltip_text = "Explicitly load approved game scripts and scenes in a separate, time-limited Godot process. Generated scenes are not instantiated."
	_check_button.disabled = true
	_check_button.pressed.connect(_check_approved_game)
	verify_controls.add_child(_check_button)

	_check_timer = Timer.new()
	_check_timer.wait_time = 0.25
	_check_timer.timeout.connect(_poll_headless_check)
	add_child(_check_timer)

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


func _create_starter() -> void:
	if _busy or _checking:
		return
	var result := Starter.create_draft()
	if not result.ok:
		_status.text = "Offline starter unavailable: " + String(result.error)
		return
	_approved_paths.clear()
	_check_button.disabled = true
	if _prompt.text.strip_edges().is_empty():
		_prompt.text = "Make a small playable 2D arcade collection game with a score and restart."
	_present_plan(result.plan)


func _generate() -> void:
	_request_plan(_prompt.text.strip_edges(), false)


func _repair() -> void:
	if _pending_plan.is_empty() or _last_errors.is_empty() or _busy:
		return
	var repair_text := Inspector.repair_prompt(_prompt.text.strip_edges(), _pending_plan, _last_errors)
	_request_plan(repair_text, true)


func _refine() -> void:
	if _pending_plan.is_empty() or _busy:
		return
	var change := _refinement.text.strip_edges()
	if change.is_empty():
		_status.text = "Describe a change to the current preview first."
		return
	var refine_text := Inspector.refine_prompt(_prompt.text.strip_edges(), change, _pending_plan)
	_request_plan(refine_text, true)


func _request_plan(prompt: String, is_repair: bool) -> void:
	if _busy or _checking:
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
	if not EndpointPolicy.is_valid_bearer_token(key):
		_status.text = "The API key contains unsupported characters."
		return
	if not key.is_empty():
		headers.append("Authorization: Bearer " + key)
	var request_error := _http.request(endpoint, headers, HTTPClient.METHOD_POST, Planner.make_request(model, prompt))
	if request_error != OK:
		_status.text = "Unable to start the request (error %d)." % request_error
		return
	if not is_repair:
		_pending_plan.clear()
		_last_errors.clear()
		_approved_paths.clear()
		_check_button.disabled = true
		_preview.text = ""
	_apply_button.disabled = true
	_refine_button.disabled = true
	_set_busy(true)
	_status.text = "Requesting revised game files..." if is_repair else "Generating a reviewable game plan..."

func _allowed_endpoint(endpoint: String) -> bool:
	return EndpointPolicy.is_allowed(endpoint)


func _cancel() -> void:
	if _checking:
		_finish_headless_check("Headless game check canceled.", true)
		return
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
	_present_plan(validated.plan)


func _present_plan(plan: Dictionary) -> void:
	_pending_plan = plan
	var inspection := Inspector.inspect(_pending_plan)
	_last_errors = inspection.errors
	_preview.text = JSON.stringify(_pending_plan, "\t")
	if not inspection.errors.is_empty():
		_preview.text = "STATIC ERRORS (not yet applied):\n" + "\n".join(PackedStringArray(inspection.errors)) + "\n\n" + _preview.text
	if not inspection.warnings.is_empty():
		_preview.text = "REVIEW WARNINGS:\n" + "\n".join(PackedStringArray(inspection.warnings)) + "\n\n" + _preview.text
	_apply_button.disabled = not inspection.ok
	_repair_button.disabled = inspection.ok
	_refine_button.disabled = false
	if inspection.ok:
		_status.text = "Review passed for %d files. Inspect the code before applying." % _pending_plan.files.size()
	else:
		_status.text = "%d static errors. Click Repair for another model attempt." % inspection.errors.size()


func _set_busy(value: bool) -> void:
	_busy = value
	_quick_button.disabled = value or _checking
	_generate_button.disabled = value or _checking
	_cancel_button.disabled = not value and not _checking
	_check_button.disabled = value or _checking or _approved_paths.is_empty()
	_repair_button.disabled = value or _checking or _last_errors.is_empty()
	_refine_button.disabled = value or _checking or _pending_plan.is_empty()
	_refinement.editable = not value
	_endpoint.editable = not value
	_model.editable = not value
	_prompt.editable = not value
	_api_key.editable = not value


func _confirm_apply() -> void:
	if _pending_plan.is_empty() or _busy or _checking:
		return
	if not Inspector.inspect(_pending_plan).ok:
		_status.text = "Resolve static errors before applying."
		return
	_confirmation.dialog_text = "Create %d new files under res://ai_generated/? Existing files will never be overwritten. Review the preview first." % _pending_plan.files.size()
	_confirmation.popup_centered()


func _apply() -> void:
	if _pending_plan.is_empty() or _busy or _checking:
		return
	if not Inspector.inspect(_pending_plan).ok:
		_status.text = "Resolve static errors before applying."
		return
	var result := Writer.apply(_pending_plan)
	if not result.ok:
		_status.text = String(result.error)
		return
	_status.text = "Created %d files. You can now run Check Game (Headless) before playing." % result.paths.size()
	_approved_paths.clear()
	for path in result.paths:
		_approved_paths.append(String(path))
	_check_button.disabled = _approved_paths.is_empty()
	_apply_button.disabled = true
	_repair_button.disabled = true
	_refine_button.disabled = true
	_pending_plan.clear()
	_last_errors.clear()
	EditorInterface.get_resource_filesystem().scan()


func _check_approved_game() -> void:
	if _checking or _busy or _approved_paths.is_empty():
		return
	var report_dir := "user://ai_game_builder"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_dir)) != OK:
		_status.text = "Cannot create the headless check reports directory."
		return

	_check_report_path = "%s/report_%d_%d.json" % [report_dir, OS.get_process_id(), Time.get_ticks_usec()]
	var args := PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://addons/ai_game_builder/smoke_check.gd",
		"--", "--report", _check_report_path, "--paths", JSON.stringify(_approved_paths)
	])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		_status.text = "Could not launch a separate Godot process for verification."
		return
	_check_pid = pid
	_check_started_ms = Time.get_ticks_msec()
	_checking = true
	_check_button.disabled = true
	_quick_button.disabled = true
	_generate_button.disabled = true
	_apply_button.disabled = true
	_refine_button.disabled = true
	_repair_button.disabled = true
	_cancel_button.disabled = false
	_check_timer.start()
	_status.text = "Checking approved files with Godot. This does not run the game scene; Cancel is available."


func _poll_headless_check() -> void:
	if not _checking:
		return
	if Time.get_ticks_msec() - _check_started_ms > 30000:
		_finish_headless_check("Headless verification timed out after 30 seconds.", true)
		return
	if OS.is_process_running(_check_pid):
		return

	# On macOS the engine may not report an exit status for an .app child;
	# the presence of a successfully decoded report is authoritative.
	var exit_code := OS.get_process_exit_code(_check_pid)
	var output := ""
	if FileAccess.file_exists(_check_report_path):
		output = FileAccess.get_file_as_string(_check_report_path)
	var report: Variant = JSON.parse_string(output)
	if typeof(report) != TYPE_DICTIONARY or not report.has("ok") or not report.has("errors"):
		_finish_headless_check("Headless process stopped without a valid diagnostic report (exit %d)." % exit_code, false)
		return

	var report_errors: Variant = report.errors
	if typeof(report_errors) != TYPE_ARRAY:
		_finish_headless_check("Headless verifier returned an invalid diagnostic list.", false)
		return
	var summary := "Headless verification checked %d resources." % int(report.get("checked", 0))
	if not report.ok:
		summary += " %d errors. See below; copy them into a new repair request." % report_errors.size()
		var diagnostics := ""
		for issue in report_errors:
			diagnostics += "- " + String(issue) + "\n"
		_preview.text = ("HEADLESS GODOT ERRORS:\n" + diagnostics + "\n" + _preview.text).substr(0, 65536)
	else:
		summary += " No resource-loading errors reported. Gameplay is not tested."
	_finish_headless_check(summary, false)


func _finish_headless_check(message: String, terminate: bool) -> void:
	_check_timer.stop()
	if terminate and _check_pid > 0 and OS.is_process_running(_check_pid):
		OS.kill(_check_pid)
	_check_pid = -1
	_checking = false
	if not _check_report_path.is_empty() and FileAccess.file_exists(_check_report_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_check_report_path))
	_check_report_path = ""
	_check_button.disabled = _approved_paths.is_empty()
	_quick_button.disabled = _busy
	_generate_button.disabled = _busy
	_cancel_button.disabled = not _busy
	_refine_button.disabled = _busy or _pending_plan.is_empty()
	_repair_button.disabled = _busy or _pending_plan.is_empty() or _last_errors.is_empty()
	_status.text = message


func _exit_tree() -> void:
	if _checking:
		_finish_headless_check("Headless verification canceled because the editor dock closed.", true)
