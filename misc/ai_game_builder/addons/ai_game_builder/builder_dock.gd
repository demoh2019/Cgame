@tool
extends VBoxContainer

const AIClient = preload("res://addons/ai_game_builder/ai_client.gd")
const ProjectContext = preload("res://addons/ai_game_builder/project_context.gd")
const Plan = preload("res://addons/ai_game_builder/plan.gd")

var _client
var _endpoint: LineEdit
var _model: LineEdit
var _key: LineEdit
var _prompt: TextEdit
var _include_selected_files: CheckBox
var _preview: TextEdit
var _status: Label
var _generate_button: Button
var _apply_button: Button
var _open_button: Button
var _last_scene := ""
var _pending_plan: Dictionary = {}


func _ready() -> void:
	_client = AIClient.new()
	add_child(_client)
	_client.completed.connect(_on_generated)
	_client.failed.connect(_on_failed)

	_add_label("AI Game Builder — генерация игр и сцен")
	_add_label("OpenAI-compatible API (облачный или локальный)")
	_endpoint = LineEdit.new()
	_endpoint.placeholder_text = "Chat Completions API URL"
	_endpoint.text = "https://api.openai.com/v1/chat/completions"
	add_child(_endpoint)

	_model = LineEdit.new()
	_model.placeholder_text = "Model ID"
	_model.text = "gpt-4.1-mini"
	add_child(_model)

	_key = LineEdit.new()
	_key.placeholder_text = "API key (пусто для локальной модели)"
	_key.secret = true
	add_child(_key)

	_add_label("Что создать? Например: 2D-платформер с меню, счетом и врагами.")
	_prompt = TextEdit.new()
	_prompt.custom_minimum_size = Vector2(0, 120)
	_prompt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_prompt)

	_include_selected_files = CheckBox.new()
	_include_selected_files.text = "Отправить содержимое выбранных .gd/.tscn файлов модели"
	_include_selected_files.button_pressed = false
	_include_selected_files.tooltip_text = "Необязательно: только выбранные файлы, до 4 файлов и 20 000 символов суммарно. Код уходит выбранному API-провайдеру."
	add_child(_include_selected_files)

	var actions := HBoxContainer.new()
	add_child(actions)
	_generate_button = Button.new()
	_generate_button.text = "Сгенерировать"
	_generate_button.pressed.connect(_on_generate_pressed)
	actions.add_child(_generate_button)
	_apply_button = Button.new()
	_apply_button.text = "Применить"
	_apply_button.disabled = true
	_apply_button.pressed.connect(_on_apply_pressed)
	actions.add_child(_apply_button)
	_open_button = Button.new()
	_open_button.text = "Открыть сцену"
	_open_button.disabled = true
	_open_button.pressed.connect(_on_open_pressed)
	actions.add_child(_open_button)

	_status = _add_label("Сначала создайте план. Применение требует подтверждения.")
	_add_label("Предпросмотр: содержимое всех создаваемых файлов")
	_preview = TextEdit.new()
	_preview.editable = false
	_preview.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_preview.custom_minimum_size = Vector2(0, 180)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_preview)
	_add_label("Файлы создаются только в res://ai_generated/; существующие файлы не меняются. Проверьте код перед применением.")


func _add_label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label


func _on_generate_pressed() -> void:
	if _prompt.text.strip_edges().is_empty():
		_status.text = "Введите описание игры или функции."
		return
	_pending_plan = {}
	_apply_button.disabled = true
	_open_button.disabled = true
	_last_scene = ""
	_preview.text = ""
	_generate_button.disabled = true
	_status.text = "Генерация... Запрос отправлен модели."
	var context := ProjectContext.describe()
	if _include_selected_files.button_pressed:
		context += "\nSelected source files (explicitly shared by the user):\n"
		context += ProjectContext.describe_selected(EditorInterface.get_selected_paths())
	_client.generate(_endpoint.text, _model.text, _key.text, _prompt.text, context)


func _on_generated(response: String) -> void:
	_generate_button.disabled = false
	var parsed := Plan.parse_response(response)
	if not parsed["ok"]:
		_status.text = "Ответ не принят: %s" % parsed["error"]
		_preview.text = "Модель не вернула корректный план. Уточните запрос или повторите генерацию."
		return

	_pending_plan = parsed
	var parts := PackedStringArray()
	parts.append(parsed["summary"])
	for entry in parsed["files"]:
		parts.append("\n=== %s ===\n%s" % [entry["path"], entry["content"]])
	_preview.text = "\n".join(parts)
	_status.text = "Готово: %d файлов. Проверьте предпросмотр и нажмите «Применить»." % parsed["files"].size()
	_apply_button.disabled = false


func _on_failed(message: String) -> void:
	_generate_button.disabled = false
	_apply_button.disabled = true
	_pending_plan = {}
	_status.text = message


func _on_apply_pressed() -> void:
	if _pending_plan.is_empty():
		return
	var result := Plan.apply(_pending_plan)
	if not result["ok"]:
		_apply_button.disabled = true
		_status.text = "Не удалось применить: %s" % result["error"]
		return
	_apply_button.disabled = true
	_pending_plan = {}
	EditorInterface.get_resource_filesystem().scan()
	_last_scene = ""
	for path in result["paths"]:
		if str(path).ends_with(".tscn"):
			_last_scene = path
			break
	_open_button.disabled = _last_scene.is_empty()
	_status.text = "Создано файлов: %d. Можно открыть сгенерированную сцену." % result["paths"].size()


func _on_open_pressed() -> void:
	if _last_scene.is_empty() or not FileAccess.file_exists(_last_scene):
		_open_button.disabled = true
		return
	EditorInterface.open_scene_from_path(_last_scene)
