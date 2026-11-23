extends CanvasLayer
## One node that owns every interface/accessibility feature that needs the scene tree: the Esc settings menu,
## colour-blind filter, FPS overlay, closed captions, device-aware prompt strip, gamepad-to-hotkey translation,
## UI scale and high contrast. online_main adds it once; the logic lives in the static ui_* helpers.

const UiSettings = preload("res://scripts/client/ui_settings.gd")
const UiLocalization = preload("res://scripts/client/ui_localization.gd")
const UiInputRebind = preload("res://scripts/client/ui_input_rebind.gd")
const UiColorblind = preload("res://scripts/client/ui_colorblind.gd")
const UiCaptions = preload("res://scripts/client/ui_captions.gd")
const UiGamepad = preload("res://scripts/client/ui_gamepad.gd")
const UiAccess = preload("res://scripts/client/ui_access.gd")
const GraphicsResolution = preload("res://scripts/client/graphics_resolution.gd")
const PauseMenu = preload("res://scripts/client/ui_pause_menu.gd")
const DisplaySettings = preload("res://scripts/client/ui_display_settings.gd")

var menu: Control
var captions
var fps_label: Label
var prompt_label: Label
var _filter_layer: CanvasLayer
var _filter_rect: ColorRect
var _client
var _camera: Camera3D
var _blocked: Callable = Callable() # Returns true while Esc belongs to something else (build mode, a window, typing).
var _fps_timer := 0.0
var _world_streamer: WorldStreamer


## Assign the native streamer after it is created; diagnostic counts are
## polled at 4 Hz only while the optional FPS overlay is visible.
func set_world_streamer(streamer: WorldStreamer) -> void:
	_world_streamer = streamer


func _init() -> void:
	name = "AccessibilityLayer"
	layer = 100


## `client` supplies event_received/peer_id/predicted; `camera` the listener orientation; `blocked` is optional.
func setup(client, camera: Camera3D, blocked: Callable = Callable()) -> void:
	_client = client
	_camera = camera
	_blocked = blocked
	if client != null and client.has_signal("event_received"):
		client.event_received.connect(_on_event)


func _ready() -> void:
	UiSettings.load_all()
	UiLocalization.apply_saved()
	UiInputRebind.install()
	menu = PauseMenu.new()
	# Apply persisted display mode, V-Sync and frame limit on first load.
	DisplaySettings.apply(get_window())
	menu.changed.connect(func(_key: String) -> void: apply_all())
	add_child(menu)
	captions = UiCaptions.CaptionView.new()
	add_child(captions)
	fps_label = _make_label(Control.PRESET_TOP_RIGHT)
	fps_label.position = Vector2(-280, 6)
	fps_label.custom_minimum_size = Vector2(270, 68)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prompt_label = _make_label(Control.PRESET_BOTTOM_LEFT)
	prompt_label.position = Vector2(12, -26)
	prompt_label.add_theme_font_size_override("font_size", 13)
	_filter_layer = CanvasLayer.new()
	_filter_layer.layer = 127 # Above the menu so the filter colours everything.
	add_child(_filter_layer)
	_filter_rect = ColorRect.new()
	_filter_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter_rect.material = UiColorblind.make_material(0)
	_filter_layer.add_child(_filter_rect)
	apply_all()


func _make_label(preset: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_KEEP_SIZE)
	add_child(label)
	return label


## Re-reads UiSettings and pushes them into the scene.
func apply_all() -> void:
	var mode := int(UiSettings.get_value("colorblind"))
	_filter_rect.visible = mode != 0
	UiColorblind.configure(_filter_rect.material, mode)
	UiAccess.apply_ui_scale(get_window())
	UiAccess.apply_high_contrast(bool(UiSettings.get_value("high_contrast")))
	fps_label.visible = bool(UiSettings.get_value("show_fps"))
	captions.visible = bool(UiSettings.get_value("captions"))
	captions.font_size = UiSettings.CAPTION_SIZES[int(UiSettings.get_value("caption_size"))]
	_update_prompt()


func is_open() -> bool:
	return menu != null and menu.is_open()


func toggle_menu() -> void:
	if menu.is_open():
		menu.close()
	else:
		menu.open()


func _input(event: InputEvent) -> void:
	if menu.is_open():
		if menu.handle_capture(event):
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("access_pause") and not event.is_echo():
			menu.close()
			get_viewport().set_input_as_handled()
		return
	if UiGamepad.observe(event):
		_update_prompt()
	if event is InputEventKey and event.is_action_pressed("access_fps") and not event.is_echo():
		UiSettings.set_value("show_fps", not bool(UiSettings.get_value("show_fps")))
		apply_all()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("access_pause") and not event.is_echo():
		if not (_blocked.is_valid() and _blocked.call()):
			menu.open()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and not (_blocked.is_valid() and _blocked.call()):
		var key_event := UiGamepad.key_event_for((event as InputEventJoypadButton).button_index, event.pressed)
		if key_event != null:
			Input.parse_input_event(key_event)


func _process(delta: float) -> void:
	if fps_label.visible:
		_fps_timer -= delta
		if _fps_timer <= 0.0:
			_fps_timer = 0.25
			var metrics: String = "%d FPS  %.1f ms  %d draws" % [Engine.get_frames_per_second(),
				1000.0 / maxf(float(Engine.get_frames_per_second()), 1.0),
				int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))]
			# Show the real upscaler, not the requested quality preset.
			# Reading viewport properties at 4Hz has no GPU work.
			var vp: Viewport = get_viewport()
			metrics += "\n3D: " + GraphicsResolution.diagnostic_label(
				int(vp.scaling_3d_mode), float(vp.scaling_3d_scale))
			if is_instance_valid(_world_streamer):
				metrics += "\nWorld: " + world_streaming_line(_world_streamer)
			fps_label.text = metrics


func _update_prompt() -> void:
	var names := Input.get_connected_joypads()
	var ps := not names.is_empty() and UiGamepad.is_playstation(Input.get_joy_name(names[0]))
	prompt_label.text = UiGamepad.prompt_line(UiGamepad.last_device, ps)
	# Prompts only help once a pad exists; keyboard players already see the hotkey buttons on the HUD.
	prompt_label.visible = not names.is_empty()


func _on_event(event: Dictionary) -> void:
	if not bool(UiSettings.get_value("captions")) or _client == null or _camera == null:
		return
	var forward := Vector2(-_camera.global_transform.basis.z.x, -_camera.global_transform.basis.z.z).normalized()
	var right := Vector2(_camera.global_transform.basis.x.x, _camera.global_transform.basis.x.z).normalized()
	var predicted: Vector3 = _client.predicted
	var line: String = UiCaptions.caption_for(event, int(_client.peer_id), Vector2(predicted.x, predicted.z), forward, right)
	if line != "":
		captions.add_caption(line)


## "N chunks | N queued | N visual | N retry" with only the counters this engine build exposes:
## WorldStreamer gains diagnostics over time, and an older editor binary must not error every refresh.
static func world_streaming_line(streamer: Object) -> String:
	var parts: PackedStringArray = []
	for entry in [["get_loaded_count", "chunks"], ["get_queued_generation_count", "queued"],
			["get_pending_visual_details_count", "visual"], ["get_retry_pending_count", "retry"]]:
		if streamer.has_method(entry[0]):
			parts.append("%d %s" % [int(streamer.call(entry[0])), entry[1]])
	return " | ".join(parts) if not parts.is_empty() else "streaming stats unavailable"
