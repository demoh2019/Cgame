extends Node3D
## The online game client (dedicated server + Nakama): connect screen, the isometric camera, controls, and the glue between the
## network state and what is drawn.

const Defs = preload("res://scripts/shared/defs.gd")
const Fishing = preload("res://scripts/shared/fishing.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Dungeon = preload("res://scripts/shared/dungeon.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Net = preload("res://scripts/shared/net.gd")
const GameClient = preload("res://scripts/client/game_client.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const EntityView = preload("res://scripts/client/entity_view.gd")
const RaidTelegraph = preload("res://scripts/client/raid_telegraph.gd")
const LightningVisual = preload("res://scripts/client/storm_lightning_visual.gd")
const Hud = preload("res://scripts/client/hud.gd")
const Meshes = preload("res://scripts/client/meshes.gd")
const CharacterModel = preload("res://scripts/client/character_model.gd")
const TrailBikeVisual = preload("res://scripts/client/trail_bike_visual.gd")
const HandFlareVisual = preload("res://scripts/client/hand_flare_visual.gd")
const HubView = preload("res://scripts/client/hub_view.gd")
const Audio = preload("res://scripts/client/audio.gd")
const Assets = preload("res://scripts/client/assets.gd")
const Social = preload("res://scripts/client/social.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const RenderBenchmark = preload("res://scripts/client/render_benchmark.gd")
const DungeonLightBudget = preload("res://scripts/client/dungeon_light_budget.gd")
const GraphicsAutoQuality = preload("res://scripts/client/graphics_auto_quality.gd")
const GraphicsDynamicResolution = preload("res://scripts/client/graphics_dynamic_resolution.gd")
const OutpostView = preload("res://scripts/client/outpost_view.gd")
const WorldMap = preload("res://scripts/client/world_map.gd")
const WorldOverlay = preload("res://scripts/client/world_overlay.gd")
const HelpPanel = preload("res://scripts/client/help_panel.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const Effects = preload("res://scripts/client/effects.gd")
const UiTheme = preload("res://scripts/client/ui_theme.gd")
const TitleBanner = preload("res://scripts/client/title_banner.gd")
const LocalServer = preload("res://scripts/client/local_server.gd")
const SoloSlots = preload("res://scripts/client/solo_slots.gd")
const SkillsPanel = preload("res://scripts/client/skills_panel.gd")
const Skills = preload("res://scripts/shared/skills.gd")

const CAMERA_OFFSET := Vector3(0.0, 17.0, 12.5)
const DAY_LENGTH := WorldCycle.DAY_LENGTH # Shared with server simulation and local client.

var net
var client
var peer: ENetMultiplayerPeer
var streamer: WorldStreamer
var chunk_root: Node3D
var entities: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var water: MeshInstance3D
var hud
var avatar: Node3D
var avatar_model
var bike_visual
var flare_visual
var audio
var hub_view
var outposts
var world_map
var overlay
var _site_id := -1
var _area_name := ""
var _place_timer := 0.0
var help_panel
var demo_phase := -1.0
var demo_storm := false
var _wind_sample_left := 0.0
var _visual_weather_wind := Vector2.ZERO
var atmosphere
var _grade_material: ShaderMaterial
var _auto_quality := GraphicsAutoQuality.new()
var _adaptive_resolution := GraphicsDynamicResolution.new()
var _auto_graphics := true
var _quality_picker: OptionButton
var effects
var skills_panel
var social
var chat_edit: LineEdit
var account := {} # Result of the Nakama sign-in, empty when playing without accounts.
var connect_panel: PanelContainer
var local_server := LocalServer.new()
var solo_slot_picker: OptionButton
var solo_slot_info: Label
var _solo_offline_account: bool = false
var _solo_attempts_left := 0
var address_edit: LineEdit
var name_edit: LineEdit
var status_label: Label
var _zoom := 1.0
var _attack_cooldown := 0.0
var _build_mode := false # U: a ghost wall follows the aim until it is placed or cancelled.
var _build_yaw := 0.0
var _build_ghost: MeshInstance3D
var _build_reason := ""
var _move_input := Vector2.ZERO # This frame's movement keys, for facing the way you walk.
var _last_attack_msec := -100000
var _fishing_line: MeshInstance3D # Line from the rod tip to the bobber while fishing.
var _bobber: MeshInstance3D
var _bobber_spot := Vector3.INF
var _last_cast_spot := Vector3.INF # Kept after the cast ends, for the splash of the catch.
var _party_rally_marker: Node3D
var _party_supply_marker: Node3D
var _raid_telegraph: Node3D
var _lightning_visual: Node3D
var _screenshot_path := ""
var _screenshot_frames := 0
var _frame_ms: Array[float] = [] # Frame times before a demo screenshot, for the median printed with it.
var _demo := ""
var _frames := 0
var _demo_frames := 0 # Frames since the first snapshot arrived.


func _exit_tree() -> void:
	CharacterModel.clear_templates() # Cached survivor models live outside the tree.
	local_server.stop() # A solo world ends with the game.


func _ready() -> void:
	Engine.physics_ticks_per_second = 30
	GraphicsQuality.load_preference()
	var graphics_config := ConfigFile.new()
	if graphics_config.load(GraphicsQuality.SETTINGS_PATH) == OK:
		_auto_graphics = bool(graphics_config.get_value("rendering", "auto", false))
	if _auto_graphics:
		GraphicsQuality.set_level(_auto_quality.level, false)
	_adaptive_resolution.configure(GraphicsQuality.level())
	_build_environment()
	_build_connect_screen()
	var args := OS.get_cmdline_user_args()
	var address := "127.0.0.1:24565"
	var player_name := "Survivor"
	var i := 0
	while i < args.size():
		match args[i]:
			"--server":
				i += 1
				address = args[i]
			"--name":
				i += 1
				player_name = args[i]
			"--screenshot":
				i += 1
				_screenshot_path = args[i]
			"--demo":
				i += 1
				_demo = args[i]
			"--phase":
				i += 1
				demo_phase = float(args[i]) # 0..1 around the day, for screenshots.
			"--storm":
				demo_storm = true
			"--connect":
				address_edit.text = address
		i += 1
	address_edit.text = address
	name_edit.text = player_name
	if _demo != "" and _screenshot_path != "":
		# A scripted screenshot run must not take the keyboard from whoever is working at this machine.
		get_window().unfocusable = true
	if "--connect" in args:
		_connect_remote()


func _make_party_rally_marker() -> void:
	_party_rally_marker = Node3D.new()
	_party_rally_marker.name = "PartyRally"
	_party_rally_marker.visible = false
	var beacon := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	beacon.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.4, 0.9, 1.0)
	beacon.material_override = material
	_party_rally_marker.add_child(beacon)
	var label := Label3D.new()
	label.name = "Label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.75
	label.text = "PARTY RALLY"
	_party_rally_marker.add_child(label)
	add_child(_party_rally_marker)


func _update_party_rally_marker() -> void:
	var rally: Dictionary = client.you.get("party", {}).get("rally", {})
	_party_rally_marker.visible = not rally.is_empty()
	if rally.is_empty():
		return
	_party_rally_marker.position = Vector3(float(rally["x"]),
			float(rally["y"]) + 1.8, float(rally["z"]))
	var label := _party_rally_marker.get_node("Label") as Label3D
	label.text = "PARTY RALLY  %ds" % int(ceil(float(rally["remaining"])))


## A short-lived help beacon is visible only to current group members.
## All its coordinates come from a previously server-authorized event.
func _make_party_supply_marker() -> void:
	_party_supply_marker = Node3D.new()
	_party_supply_marker.name = "PartySupplyHelp"
	_party_supply_marker.visible = false
	var beacon := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	beacon.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.68, 0.28)
	beacon.material_override = material
	_party_supply_marker.add_child(beacon)
	var label := Label3D.new()
	label.name = "Label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.8
	_party_supply_marker.add_child(label)
	add_child(_party_supply_marker)


func _update_party_supply_marker() -> void:
	var signal_state: Dictionary = client.active_supply_beacon()
	_party_supply_marker.visible = not signal_state.is_empty()
	if signal_state.is_empty():
		return
	var x: float = float(signal_state["x"])
	var z: float = float(signal_state["z"])
	_party_supply_marker.position = Vector3(x, client.world.height_at(x, z) + 1.8, z)
	var label := _party_supply_marker.get_node("Label") as Label3D
	label.text = "PARTY NEEDS %s (%ds)" % [
		str(signal_state["need"]).to_upper(),
		ceili(maxf(0.0, float(signal_state["expires"]) - client.server_time))]


func _build_environment() -> void:
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	environment = atmosphere.environment
	sun = atmosphere.sun
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.far = 700.0
	camera.position = CAMERA_OFFSET * 3.0
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	_make_party_rally_marker()
	_make_party_supply_marker()
	_raid_telegraph = RaidTelegraph.new()
	_raid_telegraph.name = "RaidGroundSlamWarning"
	add_child(_raid_telegraph)
	_lightning_visual = LightningVisual.new()
	_lightning_visual.name = "StormLightningWarning"
	add_child(_lightning_visual)
	camera.current = true
	# Only one light manager for every streamed underground room.
	# Nearest torches glow and flicker; distant torches contribute no GPU light passes.
	var dungeon_lights := DungeonLightBudget.new()
	dungeon_lights.name = "DungeonLightBudget"
	add_child(dungeon_lights)
	if camera.has_method("set_shake_max_offset"):
		# Trauma shake (engine feature of this fork): small offsets for a top-down view, quick decay.
		camera.set_shake_max_offset(Vector3(0.35, 0.25, 0.35))
		camera.set_shake_max_rotation(0.02)
		camera.set_shake_decay(1.6)
	chunk_root = Node3D.new()
	chunk_root.name = "Chunks"
	add_child(chunk_root)
	entities = EntityView.new()
	add_child(entities)
	# The sea: one big plane that follows the player.
	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1600, 1600)
	water.mesh = plane
	var water_material := ShaderMaterial.new()
	water_material.shader = load("res://assets/shaders/water.gdshader")
	water.material_override = water_material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position.y = Defs.WATER_LEVEL - 0.35
	add_child(water)
	effects = Effects.new()
	add_child(effects)
	# The finishing pass over the 3D view (tilt-shift, grading, vignette), drawn under every interface layer.
	var post := CanvasLayer.new()
	post.layer = -10
	add_child(post)
	var grade := ColorRect.new()
	grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade_material = ShaderMaterial.new()
	_grade_material.shader = load("res://assets/shaders/post_grade.gdshader")
	grade.material = _grade_material
	post.add_child(grade)
	GraphicsQuality.apply(get_viewport(), atmosphere, _grade_material, water,
		streamer, _adaptive_resolution.scale if _auto_graphics else -1.0, _auto_graphics)


func _build_connect_screen() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	# Title screen: the sky panorama behind a dark vignette, the name in gold, the sign-in card below it.
	var backdrop := Control.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.theme = UiTheme.get_theme()
	layer.add_child(backdrop)
	var panorama := load("res://assets/textures/sky/day_sky.jpg") as Texture2D
	if panorama != null:
		var sky := TextureRect.new()
		sky.texture = panorama
		sky.set_anchors_preset(Control.PRESET_FULL_RECT)
		sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		sky.modulate = Color(0.85, 0.8, 0.74)
		backdrop.add_child(sky)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.02, 0.03, 0.15))
	gradient.set_color(1, Color(0.02, 0.02, 0.03, 0.88))
	var fade := GradientTexture2D.new()
	fade.gradient = gradient
	fade.fill = GradientTexture2D.FILL_RADIAL
	fade.fill_from = Vector2(0.5, 0.42)
	fade.fill_to = Vector2(1.15, 1.1)
	shade.texture = fade
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.add_child(shade)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	backdrop.add_child(column)
	# The sign-in card is a hanging banner with the title woven in (title_banner.gd).
	connect_panel = PanelContainer.new()
	connect_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	connect_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(connect_panel)
	var banner := TitleBanner.new()
	banner.custom_minimum_size = Vector2(460, 0)
	connect_panel.add_child(banner)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	banner.add_child(box)
	var title := Label.new()
	title.text = "ALBION AFTER"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(0.98, 0.9, 0.74))
	title.add_theme_color_override("font_outline_color", Color(0.18, 0.03, 0.03))
	title.add_theme_constant_override("outline_size", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Gather. Craft. Survive. Lose everything."
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", UiTheme.GOLD)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	box.add_child(gap)
	var field_style := UiTheme._box(UiTheme.PAPER, 18, 2.0, Color(0.55, 0.4, 0.2), 10)
	field_style.shadow_size = 0
	var field_focus := UiTheme._box(UiTheme.CREAM, 18, 2.0, UiTheme.GOLD, 10)
	field_focus.shadow_size = 0
	for field in [["Survivor name", "Name"], ["Server", "host:port"]]:
		var caption := Label.new()
		caption.text = field[0]
		caption.add_theme_font_size_override("font_size", 14)
		caption.add_theme_color_override("font_color", Color(0.95, 0.84, 0.66))
		box.add_child(caption)
		var edit := LineEdit.new()
		edit.placeholder_text = field[1]
		edit.custom_minimum_size = Vector2(0, 40)
		edit.add_theme_stylebox_override("normal", field_style)
		edit.add_theme_stylebox_override("focus", field_focus)
		edit.add_theme_color_override("font_color", UiTheme.INK)
		edit.add_theme_color_override("font_placeholder_color", UiTheme.INK_SOFT)
		edit.add_theme_color_override("caret_color", UiTheme.INK)
		edit.text_submitted.connect(func(_text: String) -> void: _connect_remote())
		box.add_child(edit)
		if name_edit == null:
			name_edit = edit
		else:
			address_edit = edit
	var slot_caption := Label.new()
	slot_caption.text = "Solo survivor"
	slot_caption.add_theme_font_size_override("font_size", 14)
	slot_caption.add_theme_color_override("font_color", Color(0.95, 0.84, 0.66))
	box.add_child(slot_caption)
	solo_slot_picker = OptionButton.new()
	solo_slot_picker.custom_minimum_size = Vector2(0, 40)
	for state in ["normal", "hover", "pressed", "focus"]:
		solo_slot_picker.add_theme_stylebox_override(state, field_style if state != "hover" else field_focus)
	solo_slot_picker.add_theme_color_override("font_color", UiTheme.INK)
	solo_slot_picker.add_theme_color_override("font_hover_color", UiTheme.INK)
	solo_slot_picker.add_theme_color_override("font_pressed_color", UiTheme.INK)
	solo_slot_picker.add_theme_color_override("font_focus_color", UiTheme.INK)
	for slot in range(1, SoloSlots.SLOT_COUNT + 1):
		solo_slot_picker.add_item("Survivor %d" % slot, slot)
	solo_slot_picker.select(0)
	solo_slot_picker.item_selected.connect(func(_index: int) -> void: _update_solo_slot_info())
	box.add_child(solo_slot_picker)
	solo_slot_info = Label.new()
	solo_slot_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	solo_slot_info.add_theme_font_size_override("font_size", 12)
	solo_slot_info.add_theme_color_override("font_color", UiTheme.GOLD)
	box.add_child(solo_slot_info)
	_update_solo_slot_info()
	var graphics_caption := Label.new()
	graphics_caption.text = "Graphics quality (Ctrl+F11 in game)"
	graphics_caption.add_theme_font_size_override("font_size", 14)
	graphics_caption.add_theme_color_override("font_color", Color(0.95, 0.84, 0.66))
	box.add_child(graphics_caption)
	var quality_picker := OptionButton.new()
	_quality_picker = quality_picker
	quality_picker.custom_minimum_size = Vector2(0, 40)
	for state in ["normal", "hover", "pressed", "focus"]:
		quality_picker.add_theme_stylebox_override(state, field_style if state != "hover" else field_focus)
	quality_picker.add_theme_color_override("font_color", UiTheme.INK)
	quality_picker.add_theme_color_override("font_hover_color", UiTheme.INK)
	quality_picker.add_theme_color_override("font_pressed_color", UiTheme.INK)
	for quality_level in GraphicsQuality.NAMES.size():
		quality_picker.add_item(GraphicsQuality.NAMES[quality_level], quality_level)
	quality_picker.add_item("Auto (adaptive 3D + details)", GraphicsQuality.NAMES.size())
	quality_picker.select(GraphicsQuality.NAMES.size() if _auto_graphics else GraphicsQuality.level())
	quality_picker.item_selected.connect(func(index: int) -> void:
		var selected: int = quality_picker.get_item_id(index)
		_set_auto_graphics(selected == GraphicsQuality.NAMES.size())
		if _auto_graphics:
			_auto_quality.set_mode("auto")
			GraphicsQuality.set_level(_auto_quality.level, false)
		else:
			GraphicsQuality.set_level(selected)
		_adaptive_resolution.configure(GraphicsQuality.level())
		GraphicsQuality.apply(get_viewport(), atmosphere, _grade_material, water,
			streamer, _adaptive_resolution.scale if _auto_graphics else -1.0, _auto_graphics))
	box.add_child(quality_picker)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 8)
	box.add_child(gap2)
	var solo := Button.new()
	solo.text = "PLAY SOLO"
	solo.tooltip_text = "Runs the world on this computer (every system, saved between sessions) and joins it."
	solo.custom_minimum_size = Vector2(0, 50)
	solo.add_theme_font_size_override("font_size", 20)
	solo.add_theme_stylebox_override("normal", _pill(Color(0.72, 0.13, 0.1)))
	solo.add_theme_stylebox_override("hover", _pill(Color(0.84, 0.2, 0.14)))
	solo.add_theme_stylebox_override("pressed", _pill(Color(0.55, 0.08, 0.06)))
	solo.pressed.connect(_play_solo)
	box.add_child(solo)
	var button := Button.new()
	button.text = "Join server"
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_stylebox_override("normal", _pill(Color(0.3, 0.2, 0.13)))
	button.add_theme_stylebox_override("hover", _pill(Color(0.42, 0.29, 0.17)))
	button.add_theme_stylebox_override("pressed", _pill(Color(0.22, 0.14, 0.08)))
	button.pressed.connect(_connect_remote)
	box.add_child(button)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(0.95, 0.7, 0.55))
	box.add_child(status_label)
	var credits := Label.new()
	credits.text = "Models and textures: Poly Haven, Quaternius, Kenney, KayKit (CC0) and more - see docs/ASSETS.md"
	credits.add_theme_font_size_override("font_size", 12)
	credits.add_theme_color_override("font_color", Color(0.7, 0.7, 0.68, 0.8))
	credits.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	credits.grow_horizontal = Control.GROW_DIRECTION_BOTH
	credits.position.y -= 34
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	backdrop.add_child(credits)
	# The whole title screen comes and goes with the sign-in card.
	connect_panel.visibility_changed.connect(func() -> void: backdrop.visible = connect_panel.visible)


## A rounded pill button with a gold rim, the main action of the title screen.
static func _pill(color: Color) -> StyleBoxFlat:
	var style := UiTheme._box(color, 24, 3.0, UiTheme.GOLD, 8)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	return style


func _device_id() -> String:
	var path := "user://device_id.txt"
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path).strip_edges()
	var id := "%d-%d" % [Time.get_unix_time_from_system(), randi()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(id)
	return id


## Remote servers always use the ordinary Nakama sign-in path.
func _connect_remote() -> void:
	_solo_offline_account = false
	_solo_attempts_left = 0
	_connect()


func _connect() -> void:
	var parts := address_edit.text.split(":")
	var host := parts[0]
	var port := int(parts[1]) if parts.size() > 1 else 24565
	if net == null:
		status_label.text = "Entering offline survivor..." if _solo_offline_account else "Signing in..."
		# Additional solo slots are deliberately local even if Nakama is running.
		# Do not sign in or open a live guild/chat session for these characters.
		social = Social.new()
		add_child(social)
		account = {}
		if not _solo_offline_account:
			var nakama_port := int(OS.get_environment("NAKAMA_PORT")) if OS.get_environment("NAKAMA_PORT") != "" else 7350
			account = await social.sign_in(host, nakama_port, _device_id() + ("-" + name_edit.text if OS.get_environment("MULTI_CLIENT") != "" else ""), name_edit.text)
			if not account.get("ok", false):
				account = {}
		net = Net.new()
		net.name = "Net"
		net.role = "client"
		get_tree().root.add_child.call_deferred(net) # RPC paths must match the server: /root/Net.
		client = GameClient.new(net)
		multiplayer.connected_to_server.connect(func() -> void:
			status_label.text = "Joining..."
			client.join(name_edit.text, account.get("token", ""), account.get("refresh", "")))
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(func() -> void:
			status_label.text = "Disconnected."
			connect_panel.visible = true)
		net.welcomed.connect(_on_welcomed)
		net.join_refused.connect(func(reason: String) -> void: status_label.text = reason)
	_open_peer(host, port)


## The ENet connection alone, so a solo world that is still starting can be retried without signing in again.
func _open_peer(host: String, port: int) -> void:
	peer = ENetMultiplayerPeer.new()
	if peer.create_client(host, port) != OK:
		status_label.text = "Could not connect."
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting..." if _solo_attempts_left == 0 else "Starting your world..."


func _on_connection_failed() -> void:
	if _solo_attempts_left > 0 and local_server.is_running():
		_solo_attempts_left -= 1
		await get_tree().create_timer(1.5).timeout
		var parts := address_edit.text.split(":")
		_open_peer(parts[0], int(parts[1]))
		return
	status_label.text = "Connection failed."


## The selection changes only which local world is launched, not gameplay rules.
func _update_solo_slot_info() -> void:
	if solo_slot_picker == null or solo_slot_info == null:
		return
	var slot: int = solo_slot_picker.get_selected_id()
	solo_slot_info.text = SoloSlots.description(slot)


## Start the selected local character on its private single-player ENet port.
func _play_solo() -> void:
	var selected_slot: int = solo_slot_picker.get_selected_id() if solo_slot_picker != null else 1
	var address: String = local_server.start(selected_slot)
	if address.is_empty():
		status_label.text = "Could not start a local world."
		return
	address_edit.text = address
	_solo_offline_account = selected_slot > 1
	_solo_attempts_left = 12
	status_label.text = "Starting survivor %d..." % selected_slot
	await get_tree().create_timer(3.0).timeout # Let the server import and open its port.
	_connect()


## Chopping and harvesting loops while the server says this player is gathering.
func _gather_animation() -> String:
	var action: Dictionary = client.you.get("action", {})
	if action.is_empty():
		return ""
	if action.has("fish"):
		return "Idle_Torch_Loop" # The rod held out over the water.
	var node: Dictionary = client.node_by_id(int(action.get("node", 0)), client.predicted)
	return "TreeChopping_Loop" if node.get("kind", "") == "tree" else "Farm_Harvest"


## While a cast runs: a line from the rod tip to a bobber on the water that rides the waves and dips when a fish bites
## (the last second of the cast); a splash ring when it ends with a catch.
func _update_fishing_line(_delta: float) -> void:
	var action: Dictionary = client.you.get("action", {})
	var fishing: bool = action.has("fish") and avatar.visible
	if not fishing:
		if _fishing_line != null:
			_fishing_line.visible = false
			_bobber.visible = false
		_bobber_spot = Vector3.INF
		return
	if _fishing_line == null:
		_fishing_line = MeshInstance3D.new()
		_fishing_line.mesh = ImmediateMesh.new()
		var thread := StandardMaterial3D.new()
		thread.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		thread.albedo_color = Color(0.92, 0.92, 0.88, 0.85)
		thread.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fishing_line.material_override = thread
		add_child(_fishing_line)
		_bobber = MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.07
		ball.height = 0.14
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color(0.9, 0.15, 0.1)
		ball.material = paint
		_bobber.mesh = ball
		add_child(_bobber)
	var here: Vector3 = avatar.global_position
	if _bobber_spot == Vector3.INF:
		# The water the cast reaches: straight ahead if it is water, else the nearest water around, 2 to 3.6 m out.
		var forward := Vector2(sin(avatar.rotation.y), cos(avatar.rotation.y))
		var best := Vector2(here.x, here.z) + forward * 3.0
		if not client.world.is_water(best.x, best.y):
			for i in 16:
				var probe := Vector2(here.x, here.z) + Vector2.from_angle(float(i) * TAU / 16.0) * 3.0
				if client.world.is_water(probe.x, probe.y):
					best = probe
					break
		_bobber_spot = Vector3(best.x, Defs.WATER_LEVEL, best.y)
		_last_cast_spot = _bobber_spot
	var remaining: float = float(action.get("remaining", 1.0))
	var bite_left: float = float(action.get("bite_at", -10.0))
	var bite: bool = remaining <= bite_left and remaining > bite_left - Fishing.BITE_WINDOW and not bool(action.get("struck", false))
	var hooked: bool = bool(action.get("hooked", false))
	var time: float = Time.get_ticks_msec() / 1000.0
	var bob: Vector3 = _bobber_spot + Vector3(0, 0.03 * sin(time * 2.4) - (0.12 + 0.05 * sin(time * 30.0) if bite else 0.0), 0)
	if hooked: # The fish has it under and pulls toward the shore.
		bob = _bobber_spot.lerp(Vector3(here.x, Defs.WATER_LEVEL, here.z), 0.25) - Vector3(0, 0.25, 0)
	_bobber.visible = true
	_bobber.global_position = bob
	var forward3 := Vector3(sin(avatar.rotation.y), 0, cos(avatar.rotation.y))
	var tip: Vector3 = avatar_model.rod_tip()
	if tip == Vector3.INF:
		tip = here + Vector3(0, 2.0, 0) + forward3 * 1.4
	var mesh := _fishing_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 9: # A slight sag between tip and bobber.
		var k: float = float(i) / 8.0
		mesh.surface_add_vertex(tip.lerp(bob, k) - Vector3(0, sin(k * PI) * 0.35, 0))
	mesh.surface_end()
	_fishing_line.visible = true


var _carried_light: OmniLight3D


## A warm light around you underground (a lantern's worth), so the rooms between torches are not black.
func _set_carried_light(on: bool) -> void:
	if avatar == null:
		return
	if _carried_light == null:
		_carried_light = OmniLight3D.new()
		_carried_light.light_color = Color(1.0, 0.8, 0.55)
		_carried_light.light_energy = 1.3
		_carried_light.omni_range = 8.0
		_carried_light.position = Vector3(0, 2.4, 0)
		avatar.add_child(_carried_light)
	_carried_light.visible = on


## Where the planned wall would stand: 2.8 m out along the aim.
func _build_target() -> Vector2:
	var direction: Vector2 = _aim_direction()
	if direction.length_squared() < 0.001:
		direction = Vector2(sin(avatar.rotation.y), cos(avatar.rotation.y))
	return Vector2(client.predicted.x, client.predicted.z) + direction.normalized() * 2.8


## The ghost wall of build mode: the real tier-1 model, see-through, green where it may stand and red where not.
func _update_build_ghost() -> void:
	if not _build_mode or not bool(client.you.get("alive", false)):
		if _build_ghost != null:
			_build_ghost.visible = false
		return
	if _build_ghost == null:
		_build_ghost = MeshInstance3D.new()
		_build_ghost.mesh = EntityView.wall_mesh(1)
		var glass := StandardMaterial3D.new()
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_build_ghost.material_override = glass
		_build_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_build_ghost)
	var target: Vector2 = _build_target()
	_build_reason = Structures.placement_reason(client.world, target, Vector2(client.predicted.x, client.predicted.z))
	if _build_reason == "" and not client.inventory.has_all(Structures.COST):
		_build_reason = "missing_materials"
	_build_ghost.visible = true
	_build_ghost.global_position = Vector3(target.x, client.world.height_at(target.x, target.y), target.y)
	_build_ghost.rotation.y = _build_yaw
	(_build_ghost.material_override as StandardMaterial3D).albedo_color = \
		Color(0.35, 1.0, 0.45, 0.45) if _build_reason == "" else Color(1.0, 0.3, 0.25, 0.45)


func _place_wall() -> void:
	_update_build_ghost()
	if _build_reason != "":
		hud.say("Cannot build here: %s." % _build_reason.replace("_", " "))
		return
	client.build(_build_target(), _build_yaw)
	_end_build_mode()


func _end_build_mode() -> void:
	_build_mode = false
	if _build_ghost != null:
		_build_ghost.visible = false


## Camera shake through the fork's built-in Camera3D trauma, which decays by itself.
func _shake(amount: float) -> void:
	if camera != null and camera.has_method("add_trauma"):
		camera.add_trauma(amount)


## Particles for what just happened, at the place it happened.
func _spawn_effects(event: Dictionary) -> void:
	var here: Vector3 = client.display_position() + Vector3(0, 1.0, 0)
	var at := here
	if event.has("x") and event.has("z"):
		at = Vector3(event["x"], client.world.height_at(event["x"], event["z"]) + 1.0, event["z"])
	if str(event.get("type", "")) == "fish_hooked" and int(event.get("peer", -1)) == client.peer_id and _last_cast_spot != Vector3.INF:
		effects.ring(_last_cast_spot + Vector3(0, 0.05, 0), Color(1.0, 1.0, 1.0), 0.8, 0.4)
		_shake(0.12)
	if str(event.get("type", "")) == "fished" and int(event.get("peer", -1)) == client.peer_id and _last_cast_spot != Vector3.INF:
		effects.ring(_last_cast_spot + Vector3(0, 0.05, 0), Color(0.85, 0.95, 1.0), 1.4, 0.7) # The fish breaks the surface.
	match event["type"]:
		"hit":
			if str(event.get("kind", "")) == "zombie":
				effects.hit_zombie(at)
				entities.play_hit("zombie", int(event.get("id", -1)), float(event.get("damage", 0.0)) >= 30.0)
				if at.distance_to(here) < 4.0:
					_shake(0.12) # Your own blow landing.
			else:
				effects.hit_player(at)
				if int(event.get("id", -1)) == client.peer_id:
					_shake(0.42) # You were hit.
					if avatar_model != null:
						avatar_model.play_hit(float(event.get("damage", 0.0)) >= 25.0)
				else:
					entities.play_hit("player", int(event.get("id", -1)))
		"zombie_died":
			effects.zombie_died(at)
			if at.distance_to(here) < 6.0:
				_shake(0.18)
		"restoration_pulse":
			effects.ring(at - Vector3(0, 1.0, 0), Color(0.4, 1.0, 0.55, 0.9), 6.0, 0.9)
			effects.burst(at, Color(0.5, 1.0, 0.6), 22, 2.4, 0.9, 0.1, -1.5)
		"knockback":
			effects.burst(at - Vector3(0, 0.8, 0), Color(0.62, 0.55, 0.45), 16, 3.2, 0.5, 0.14, 4.0)
			if at.distance_to(here) < 8.0:
				_shake(0.15)
		"pinning_bolt":
			effects.ring(at - Vector3(0, 1.0, 0), Color(0.45, 0.75, 1.0, 0.9), 1.6, 0.5)
		"flash_thrown":
			effects.ring(at - Vector3(0, 1.0, 0), Color(1.0, 1.0, 0.9, 1.0), 7.0, 0.45)
			effects.burst(at, Color(1.0, 1.0, 0.85), 30, 6.0, 0.35, 0.14, 0.0)
			if at.distance_to(here) < 12.0:
				_shake(0.25)
		"ember_thrown":
			effects.burst(at, Color(1.0, 0.55, 0.15), 26, 2.6, 1.0, 0.1, -0.5)
		"decoy_thrown":
			effects.ring(at - Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.35, 0.8), 3.0, 0.8)
		"snare_triggered":
			effects.burst(at - Vector3(0, 0.6, 0), Color(0.5, 0.38, 0.22), 14, 2.0, 0.5, 0.1)
		"barricade_broken":
			effects.burst(at, Color(0.55, 0.38, 0.2), 34, 5.0, 0.9, 0.16, 9.0)
			if at.distance_to(here) < 10.0:
				_shake(0.3)
		"outpost_taken", "siege_contract_result":
			if at.distance_to(here) < 60.0:
				effects.ring(at - Vector3(0, 1.0, 0), Color(1.0, 0.82, 0.35, 0.9), 14.0, 1.4)
		"finishing_strike":
			effects.burst(at, Color(0.95, 0.22, 0.38),
				20, 4.3, 0.7, 0.12)
		"armor_sunder":
			effects.burst(at, Color(0.98, 0.55, 0.2),
				16, 2.8, 0.65, 0.11)
		"attack":
			if bool(event.get("ranged", false)):
				effects.muzzle_flash(at + Vector3(0, 0.2, 0))
				if int(event.get("peer", -1)) == client.peer_id:
					_shake(0.1)
		"gathered":
			var item: String = str(event.get("item", ""))
			var chips := Color(0.4, 0.7, 0.25)
			if item.begins_with("wood"):
				chips = Color(0.55, 0.38, 0.2)
			elif item.begins_with("stone") or item.begins_with("ore"):
				chips = Color(0.6, 0.6, 0.62)
			effects.gathered(here, chips)
		"crate":
			effects.loot(here)
		"skill_up":
			effects.level_up(client.display_position() + Vector3(0, 0.6, 0))


func _on_skill_event(event: Dictionary) -> void:
	_spawn_effects(event)
	if event["type"] == "attack" and avatar_model != null:
		# Everyone's swings and shots: this player's own model, or the one drawn for that player.
		if int(event.get("peer", -1)) == client.peer_id:
			var mine: String = str(client.you.get("weapon", ""))
			avatar_model.play_action(EntityView.attack_animation(mine, bool(event.get("ranged", false))))
		else:
			var other: Dictionary = client.players.get(int(event.get("peer", -1)), {})
			entities.play_attack(int(event.get("peer", -1)), str(other.get("weapon", "")), bool(event.get("ranged", false)))
	# Throws show an overhand throw on whoever threw; opening a crate shows the lid going up.
	if event["type"] in ["flash_thrown", "ember_thrown", "decoy_thrown"]:
		var thrower: int = int(event.get("peer", -1))
		if thrower == client.peer_id and avatar_model != null:
			avatar_model.play_action("OverhandThrow", 1.2)
		else:
			entities.play_action_on("player", thrower, "OverhandThrow")
	elif event["type"] == "crate":
		if int(event.get("peer", -1)) == client.peer_id and avatar_model != null:
			avatar_model.play_action("Chest_Open", 1.3)
		else:
			entities.play_action_on("player", int(event.get("peer", -1)), "Chest_Open")
	match event["type"]:
		"finishing_strike":
			if int(event.get("peer", -1)) == client.peer_id:
				hud.say("FINISHING STRIKE — wounded infected!")
		"xp":
			var parts: Array[String] = []
			for skill_id in event["gains"]:
				parts.append("+%d %s" % [event["gains"][skill_id], Skills.SKILLS[skill_id]["name"] if Skills.SKILLS.has(skill_id) else skill_id])
			hud.say("  ".join(parts))
		"skill_up":
			var skill_name: String = Skills.SKILLS[event["skill"]]["name"] if Skills.SKILLS.has(event["skill"]) else str(event["skill"])
			hud.say("LEVEL UP: %s %d  (%d skill points, press K)" % [skill_name, event["level"], event["points"]])
			audio.play_ui("coin", -2.0)
		"perk":
			hud.say("Perk learned: %s" % Skills.PERKS[event["perk"]]["name"])
		"supply_drop":
			var guard_count: int = int(event.get("guards", 0))
			hud.say("SUPPLY DROP (T%d) at %.0f, %.0f — %d infected guards!" % [
				int(event.get("tier", 3)), float(event.get("x", 0)),
				float(event.get("z", 0)), guard_count])
		"supply_cleared":
			hud.say("SUPPLY CLEARED at %.0f, %.0f! The crate is public — collect it before rival parties!" % [
				float(event.get("x", 0)), float(event.get("z", 0))])
		"horde_started":
			hud.say("NIGHT HORDE (T%d): %d infected at %.0f, %.0f! Defeat them for a public trophy." % [
				int(event.get("tier", 3)), int(event.get("count", 0)),
				float(event.get("x", 0)), float(event.get("z", 0))])
		"horde_cleared":
			hud.say("HORDE DEFEATED! Public trophy at %.0f, %.0f — rival survivors can claim it!" % [
				float(event.get("x", 0)), float(event.get("z", 0))])
		"horde_expired":
			hud.say("The night horde dispersed at %.0f, %.0f." % [
				float(event.get("x", 0)), float(event.get("z", 0))])


func _setup_chat() -> void:
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "Enter to chat. /g guild text, /guild name, /guilds, /join name, /leave"
	chat_edit.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	chat_edit.position = Vector2(320, -44)
	chat_edit.size = Vector2(640, 32)
	chat_edit.visible = false
	chat_edit.text_submitted.connect(_on_chat_submitted)
	hud.add_child(chat_edit)
	if not account.is_empty():
		social.message_received.connect(func(channel: String, sender: String, text: String) -> void: hud.say("[%s] %s: %s" % [channel, sender, text]))
		var started: bool = await social.start_chat("albion-world")
		hud.say("Chat connected. Press Enter to talk." if started else "Chat is unavailable.")
	else:
		hud.say("Playing without an account: nothing is saved, no chat.")


func _on_chat_submitted(text: String) -> void:
	chat_edit.text = ""
	chat_edit.visible = false
	chat_edit.release_focus()
	text = text.strip_edges()
	if text == "" or account.is_empty():
		return
	if text.begins_with("/g "):
		if not await social.say_guild(text.substr(3)):
			hud.say("You are not in a guild.")
	elif text.begins_with("/guilds"):
		var names: Array[String] = []
		for g in await social.list_guilds():
			names.append("%s (%d)" % [g["name"], g["members"]])
		hud.say("Guilds: " + (", ".join(names) if not names.is_empty() else "none yet"))
	elif text.begins_with("/guild "):
		var result: Dictionary = await social.create_guild(text.substr(7))
		hud.say("Guild founded." if result["ok"] else "Could not found a guild: %s" % result["reason"])
	elif text.begins_with("/join "):
		var wanted := text.substr(6).strip_edges()
		var found := false
		for g in await social.list_guilds(wanted):
			if g["name"] == wanted:
				var result: Dictionary = await social.join_guild(g["id"])
				hud.say("Joined %s." % wanted if result["ok"] else "Could not join: %s" % result.get("reason", "?"))
				found = true
		if not found:
			hud.say("No guild named %s." % wanted)
	elif text.begins_with("/leave"):
		hud.say("You left the guild." if await social.leave_guild() else "You are not in a guild.")
	else:
		await social.say(text)


func _on_welcomed() -> void:
	connect_panel.visible = false
	hud = Hud.new()
	add_child(hud)
	hud.setup(client)
	hud.social = social
	skills_panel = SkillsPanel.new()
	hud.add_child(skills_panel)
	skills_panel.setup(client)
	help_panel = HelpPanel.new()
	hud.add_child(help_panel)
	world_map = WorldMap.new()
	hud.add_child(world_map)
	world_map.setup(client)
	world_map.personal_waypoint_changed.connect(hud._radar.set_personal_waypoint)
	overlay = WorldOverlay.new()
	overlay.name = "WorldOverlay"
	hud.add_child(overlay)
	hud.move_child(overlay, 0) # Under every panel and card.
	overlay.setup(client, camera)
	outposts = OutpostView.new()
	add_child(outposts)
	hud.say("F2 shows every control.")
	UiTheme.apply(hud)
	client.event_received.connect(_on_skill_event)
	_setup_chat()
	# Streaming: chunks are built from the seed as the player walks.
	streamer = WorldStreamer.new()
	streamer.cell_size = Defs.CHUNK_SIZE
	streamer.axes = WorldStreamer.AXES_XZ
	streamer.load_radius = 150.0
	streamer.unload_radius = 220.0
	streamer.update_interval = 0.15
	streamer.max_instantiations_per_frame = 1
	streamer.set_chunk_generator(_generate_chunk)
	add_child(streamer)
	# Streamer is created after the initial renderer setup; apply its draw-distance budget now.
	GraphicsQuality.apply(get_viewport(), atmosphere, _grade_material, water,
		streamer, _adaptive_resolution.scale if _auto_graphics else -1.0, _auto_graphics)
	hub_view = HubView.new()
	add_child(hub_view)
	hub_view.build(client.world)
	audio = Audio.new()
	add_child(audio)
	client.event_received.connect(func(event: Dictionary) -> void: audio.on_event(event, client.peer_id, client.world.height_at))
	_raid_telegraph.clear()
	client.event_received.connect(func(event: Dictionary) -> void: _raid_telegraph.consume(event, client.world))
	client.snapshot_received.connect(func() -> void: _raid_telegraph.update_interrupt(client.raid_interrupt))
	avatar = Node3D.new()
	avatar_model = CharacterModel.new()
	avatar_model.setup(Color(1.0, 0.95, 0.5) if not Assets.has_characters() else Color.WHITE, 2.0, 1.0, Assets.CHARACTER_NAMES[abs(hash(name_edit.text)) % Assets.CHARACTER_NAMES.size()], false, abs(hash(name_edit.text)) / Assets.CHARACTER_NAMES.size())
	avatar.add_child(avatar_model)
	bike_visual = TrailBikeVisual.new()
	bike_visual.name = "TrailBike"
	avatar.add_child(bike_visual)
	flare_visual = HandFlareVisual.new()
	flare_visual.name = "HandFlare"
	avatar.add_child(flare_visual)
	# No name over your own head: your name is on the portrait plate; other players keep theirs.
	add_child(avatar)


func _generate_chunk(cell: Vector3i) -> Node:
	var view := ChunkView.new()
	view.build(client.world, Vector2i(cell.x, cell.z))
	return view


func _physics_process(delta: float) -> void:
	if client == null or not client.welcomed or not client.you.has("x"):
		return
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	var alive: bool = bool(client.you.get("alive", true))
	var move := Vector2.ZERO
	var sprint := false
	var crouch := false
	if alive and not _typing():
		move.x = Input.get_axis("ui_left", "ui_right") + float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
		move.y = Input.get_axis("ui_up", "ui_down") + float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
		sprint = Input.is_key_pressed(KEY_SHIFT)
		crouch = Input.is_key_pressed(KEY_CTRL)
	move = move.limit_length(1.0)
	_move_input = move
	var aim := _aim_direction()
	var yaw: float = atan2(aim.x, aim.y) if aim != Vector2.ZERO else float(client.yaw)
	client.send_input(move, sprint, yaw, delta, crouch)
	if alive and not _build_mode and not hud.is_menu_open() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _attack_cooldown <= 0.0 and aim != Vector2.ZERO:
		client.attack(aim)
		_attack_cooldown = 0.18
		_last_attack_msec = Time.get_ticks_msec()


func _process(delta: float) -> void:
	_frames += 1
	# Resize only the Forward+ 3D target before changing costly world LOD.
	if _auto_graphics and client != null and client.welcomed:
		var rd: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
		if rd and _adaptive_resolution.sample_frame(delta):
			GraphicsQuality.apply_resolution(get_viewport(), _adaptive_resolution.scale, true)
			_auto_quality.set_mode("auto")
		var quality_limit: bool = not rd or (
			(_adaptive_resolution.at_floor() and delta >= GraphicsAutoQuality.SLOW_FRAME) or
			(_adaptive_resolution.at_ceiling() and delta <= GraphicsAutoQuality.FAST_FRAME))
		if quality_limit and _auto_quality.sample_frame(delta):
			GraphicsQuality.set_level(_auto_quality.level, false)
			_adaptive_resolution.configure(GraphicsQuality.level())
			GraphicsQuality.apply(get_viewport(), atmosphere, _grade_material, water,
				streamer, _adaptive_resolution.scale if rd else -1.0, rd)
	if _demo == "title" and _screenshot_path != "" and _frames == 90: # The title screen alone (screenshots).
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		get_tree().quit()
	if client == null or not client.welcomed or not client.you.has("x"):
		return
	client.decay_correction(delta)
	var position: Vector3 = client.display_position()
	if avatar != null:
		avatar.position = position
		# The body turns where it walks; it faces the cursor while fighting, aiming (right mouse) or working, so walking
		# away from the cursor is a turn and a walk, not a moonwalk.
		var facing: float = client.yaw
		var busy: bool = not client.you.get("action", {}).is_empty() or Time.get_ticks_msec() - _last_attack_msec < 900 \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		if not busy and _move_input.length() > 0.1:
			facing = atan2(_move_input.x, _move_input.y)
		elif not busy:
			facing = avatar.rotation.y
		avatar.rotation.y = lerp_angle(avatar.rotation.y, facing, 1.0 - exp(-12.0 * delta))
		avatar.visible = bool(client.you.get("alive", true))
		avatar_model.set_stance(bool(client.you.get("crouching", false)), bool(client.you.get("mounted", false)) and avatar.visible,
			float(client.you.get("wading_depth_m", 0.0)) > 1.05)
		# Chopping shows the axe; otherwise the equipped weapon is in hand.
		var in_hand: String = str(client.you.get("weapon", ""))
		if _gather_animation() == "TreeChopping_Loop":
			in_hand = "axe_1"
		elif client.you.get("action", {}).has("fish"):
			in_hand = "fishing_rod"
		avatar_model.set_weapon(in_hand)
		_update_fishing_line(delta)
		_update_build_ghost()
		avatar_model.set_gear(client.inventory.gear)
		avatar_model.update_motion(delta)
		avatar_model.set_dead(not bool(client.you.get("alive", true)))
		avatar_model.set_action_loop(_gather_animation())
		var riding: bool = bool(client.you.get("mounted", false)) and avatar.visible
		bike_visual.set_panniers(client.inventory.count("bike_panniers") > 0)
		bike_visual.set_lamp(bool(client.you.get("bike_lamp_lit", false)))
		bike_visual.set_riding(riding, avatar_model.speed, delta)
		flare_visual.set_burning(avatar.visible and float(client.you.get("flare_seconds", 0.0)) > 0.0)
		audio.set_footsteps(avatar_model._moving and avatar.visible and not riding)
		if not riding:
			effects.footsteps(position, avatar_model.speed, delta)
	if streamer != null:
		streamer.focus_position = position
		_apply_world_state()
	entities.update_from(client)
	_lightning_visual.set_warning(client.lightning_telegraph)
	outposts.update_from(client)
	_update_party_rally_marker()
	_update_party_supply_marker()
	# The camera glides after the player.
	var target := position + CAMERA_OFFSET * _zoom
	camera.position = camera.position.lerp(target, 1.0 - exp(-10.0 * delta))
	camera.look_at(position + Vector3(0, 0.8, 0))
	if _demo == "sky":
		# A low view toward the horizon to show the sky (screenshots only).
		camera.position = position + Vector3(0.0, 14.0, 6.0)
		camera.look_at(position + Vector3(0.0, 20.0, -60.0))
	water.position.x = position.x
	water.position.z = position.z
	_update_time_of_day(delta)
	_track_places(delta)
	_update_prompt()
	_run_demo()


func _apply_world_state() -> void:
	var hidden: Dictionary = {}
	hidden.merge(client.depleted)
	hidden.merge(client.crates_used)
	for cell in streamer.get_loaded_cells():
		var chunk := streamer.get_chunk(cell)
		if chunk != null and chunk.has_method("apply_state"):
			chunk.apply_state(hidden)


## Announces the settlement or the region you walk into.
func _track_places(delta: float) -> void:
	_place_timer -= delta
	if _place_timer > 0.0 or client == null or not client.you.has("x"):
		return
	_place_timer = 0.4
	var spot: Vector3 = client.predicted
	if Vector2(spot.x, spot.z).length() < Defs.HUB_SAFE_RADIUS:
		_site_id = -1
		return
	var site: Dictionary = client.world.poi.site_at(spot.x, spot.z)
	var site_id: int = int(site.get("id", -1))
	if site_id != _site_id:
		_site_id = site_id
		if site_id != -1:
			hud.banner(str(site["display"]), WorldMap.KIND_COLORS.get(site["kind"], Color.WHITE))
			var detail := "a workbench and a trader here: crafting, vendor, contracts" if bool(site["station"]) else "loot and danger"
			hud.say("%s - %s" % [str(site["display"]), detail])
			return
	if site_id == -1:
		var area: String = client.world.area_name(spot.x, spot.z)
		if area != _area_name:
			_area_name = area
			hud.banner(area, Color(0.8, 0.9, 1.0))


func _update_time_of_day(delta: float) -> void:
	var weather: Dictionary = client.you.get("weather", {})
	# No rain under the settlement roofs, where the server also treats the player as sheltered.
	var storming: bool = demo_storm or (str(weather.get("condition", "clear")) == "storm" and not bool(weather.get("sheltered", false)))
	var clock: float = client.server_time if demo_phase < 0.0 else demo_phase * WorldCycle.DAY_LENGTH
	var underground: bool = client != null and client.you.has("x") and Dungeon.is_underground(float(client.you["x"]))
	# Stable 256m regional wind is only sampled four times per second.
	_wind_sample_left -= maxf(delta, 0.0)
	if underground:
		_visual_weather_wind = Vector2.ZERO
		_wind_sample_left = 0.0
	elif _wind_sample_left <= 0.0 and client != null and client.world != null and client.you.has("x"):
		var here: Vector3 = client.display_position()
		_visual_weather_wind = Weather.wind_at(client.world, here.x, here.z, clock)
		_wind_sample_left = 0.25
	if underground:
		# Below ground: no sky, no weather; the torches of the rooms and the light you carry.
		atmosphere.update(0.0, -0.3, WorldCycle.phase(clock), false, delta, Vector2.ZERO)
		sun.light_energy *= 0.15
		environment.ambient_light_energy = 0.32
		environment.ambient_light_color = Color(0.45, 0.4, 0.34)
		storming = false
	else:
		atmosphere.update(WorldCycle.daylight(clock), WorldCycle.sun_height(clock), WorldCycle.phase(clock), storming, delta, _visual_weather_wind)
	_set_carried_light(underground)
	if audio != null:
		audio.update_music(WorldCycle.daylight(clock), delta)
	effects.update_rain(camera.global_position + Vector3(0, -2.0, 0) if camera != null else Vector3.ZERO, atmosphere.storm)
	if client != null and client.you.has("x"):
		var here: Vector3 = client.display_position()
		effects.update_ambience(here, atmosphere.light_level, atmosphere.storm, client.world.biome_at(here.x, here.z))


func _aim_direction() -> Vector2:
	var viewport := get_viewport()
	if viewport == null or client == null or not client.you.has("x"):
		return Vector2.ZERO
	var mouse := viewport.get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, client.predicted.y + 0.5)
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null:
		return Vector2.ZERO
	var offset := Vector2(hit.x - client.predicted.x, hit.z - client.predicted.z)
	return offset.normalized() if offset.length() > 0.05 else Vector2.ZERO


func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit


func _update_prompt() -> void:
	var text := ""
	var p: Vector3 = client.predicted
	var loot: Dictionary = client.nearest_loot(p, Defs.REACH)
	var node: Dictionary = client.nearest_node(p, Defs.REACH)
	var below: bool = Dungeon.is_underground(p.x)
	if below and Dungeon.at_stairs(p.x, p.z):
		text = "[E] Climb the stairs back to the surface"
	elif not below and not Dungeon.bunker_at(client.world, p.x, p.z).is_empty():
		var depth_zone: int = client.world.dungeon_zone(Dungeon.region_of_site(Dungeon.bunker_at(client.world, p.x, p.z)))
		text = "[E] Climb down the hatch into the bunker dungeon (%s zone)" % ["green", "yellow", "red", "black"][clampi(depth_zone, 0, 3)]
	elif not loot.is_empty():
		text = "[E] Loot" if loot["kind"] == "bag" else "[E] Search the crate"
	elif not node.is_empty():
		text = "[E] Gather %s (tier %d)" % [node["kind"], node["tier"]]
		var needed := Defs.tool_tier_for_node(node["kind"])
		if needed != "":
			var tool_id: String = client.inventory.best_tool(needed)
			if Defs.tier_of(tool_id) < int(node["tier"]) and not (tool_id == "" and node["tier"] == 1):
				text = "Needs a tier %d %s" % [node["tier"], needed]
	elif client.nearest_barricade(p) != -1:
		var wall: Dictionary = client.barricades[client.nearest_barricade(p)]
		var level: int = Structures.tier_of(wall)
		var hp: int = roundi(float(wall["hp"]))
		var max_hp: int = roundi(Structures.max_health(level))
		text = "Wall T%d (%d/%d HP) | H repair | Y upgrade | X dismantle" % [level, hp, max_hp]
		if level < Structures.MAX_TIER:
			text += " | next: " + str(Structures.upgrade_cost(level + 1))
	elif Vector2(p.x, p.z).distance_to(Vector2(9.0, 0.0)) < 6.0:
		text = "Workbench: press C to craft"
	elif _near_water(p):
		text = "[F] Drink"
	if not client.you.get("action", {}).is_empty():
		var action: Dictionary = client.you["action"]
		var progress: int = int(100.0 * (1.0 - float(action["remaining"]) / maxf(float(action.get("total", action["remaining"])), 0.01)))
		text = ("Fishing... %d%%  (moving reels in)" if action.has("fish") else "Gathering... %d%%") % progress
		if action.has("fish"):
			var left: float = float(action.get("remaining", 0.0))
			var bite_left: float = float(action.get("bite_at", -10.0))
			if bool(action.get("hooked", false)):
				text = "Hooked! Reeling in... %d%%" % progress
			elif left <= bite_left and left > bite_left - Fishing.BITE_WINDOW and not bool(action.get("struck", false)):
				text = "BITE!  Press T to strike"
	if bool(client.you.get("mounted", false)):
		text += " | RIDING (F4 dismount)"
	elif client.inventory.count("salvage_bike") > 0:
		text += " | F4 ride bike"
	if int(client.you.get("sharpened_hits", 0)) > 0:
		text += " | SHARPENED: %d infected melee hits (End)" % int(client.you["sharpened_hits"])
	if int(client.you.get("sighted_hits", 0)) > 0:
		text += " | SIGHTED: %d infected ranged hits (Delete)" % int(client.you["sighted_hits"])
	if int(client.you.get("plated_hits", 0)) > 0:
		text += " | ARMOR PLATE: %d claw hits (Ins)" % int(client.you["plated_hits"])
	if float(client.you.get("soft_sole_seconds", 0.0)) > 0.0:
		text += " | QUIET SPRINT: %.0fs (Shift+/)" % float(client.you["soft_sole_seconds"])
	var nearby_fire_id: int = client.nearest_campfire(client.display_position())
	if nearby_fire_id >= 0 and client.campfires.has(nearby_fire_id):
		var protection: float = float(client.campfires[nearby_fire_id].get("stormproof_seconds", 0.0))
		if protection > 0.0:
			text += " | STORMPROOF FIRE: %.0fs" % protection
	if _build_mode:
		text = "BUILD WALL  (4 wood, 2 stone)   wheel: turn   click or U: place   right click: cancel"
		if _build_reason != "":
			text += "   -   " + {"out_of_range": "too near or too far", "safe_zone": "not in the settlement",
				"bad_terrain": "ground too steep or wet", "blocked": "something is in the way",
				"missing_materials": "not enough wood and stone"}.get(_build_reason, _build_reason)
	hud.set_prompt(text)


func _near_water(p: Vector3) -> bool:
	for angle in 8:
		var spot := Vector2(p.x, p.z) + Vector2.from_angle(angle * TAU / 8.0) * 3.0
		if client.world.is_water(spot.x, spot.y):
			return true
	return false


func _set_auto_graphics(enabled: bool) -> void:
	_auto_graphics = enabled
	# Preserve the other rendering preferences in the same config file.
	var config := ConfigFile.new()
	config.load(GraphicsQuality.SETTINGS_PATH)
	config.set_value("rendering", "auto", enabled)
	var error := config.save(GraphicsQuality.SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save auto graphics mode: %d" % error)


func _unhandled_input(event: InputEvent) -> void:
	# Ctrl+F11 cycles graphics quality without consuming the existing F11 medicine shortcut.
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode == KEY_F11:
		_set_auto_graphics(false)
		GraphicsQuality.cycle()
		_adaptive_resolution.configure(GraphicsQuality.level())
		GraphicsQuality.apply(get_viewport(), atmosphere, _grade_material, water,
		streamer, _adaptive_resolution.scale if _auto_graphics else -1.0, _auto_graphics)
		if is_instance_valid(_quality_picker):
			_quality_picker.select(GraphicsQuality.level())
		var message := "Graphics: %s (Ctrl+F11 to change)" % GraphicsQuality.get_name()
		if hud != null:
			hud.say(message)
		else:
			print(message)
		get_viewport().set_input_as_handled()
		return
	if client == null or not client.welcomed or hud == null:
		return
	if event is InputEventKey and event.pressed and not event.echo and not _typing():
		match event.keycode:
			KEY_K:
				skills_panel.toggle()
			KEY_F2:
				help_panel.toggle()
			KEY_J:
				world_map.toggle()
			KEY_F4:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.toggle_mount()
			KEY_BRACKETLEFT:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.use_item("bike_dynamo_lamp")
			KEY_PAGEUP:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.use_item("bike_service_kit")
			KEY_END:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					_quick_use("field_whetstone")
			KEY_DELETE:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					_quick_use("field_sighting_kit")
			KEY_INSERT:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					_quick_use("field_armor_plate")
			KEY_PAGEDOWN:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.use_item("bike_frame_patch")
			KEY_F5:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					var direction: Vector2 = _aim_direction()
					if direction.length_squared() < 0.0001:
						direction = Vector2(sin(client.yaw), cos(client.yaw))
					client.throw_ember(direction)
			KEY_F3:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.survey_ruins()
			KEY_F10:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.place_fish_trap()
			KEY_F6:
				# Pitch a field tarp a few steps ahead (it used to be a button only).
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					var standing: Vector3 = client.display_position()
					client.pitch_shelter(Vector2(standing.x, standing.z) + Vector2(sin(client.yaw), cos(client.yaw)) * 2.8)
			KEY_F7:
				var shelter_id: int = client.nearest_shelter(client.display_position())
				if shelter_id < 0:
					hud.say("No field tarp within reach.")
				else:
					client.pack_shelter(shelter_id)
			KEY_HOME:
				if not hud.is_menu_open():
					client.use_item("return_charm")
			KEY_F12:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					var fish_trap_id: int = client.nearest_fish_trap(client.display_position())
					if fish_trap_id < 0:
						hud.say("No shoreline fish trap within reach.")
					else:
						client.collect_fish_trap(fish_trap_id)
			KEY_Q:
				if Input.is_key_pressed(KEY_SHIFT) and not hud.is_menu_open():
					client.loot_sweep()
				else:
					_interact()
			KEY_1:
				if Input.is_key_pressed(KEY_ALT) and Input.is_key_pressed(KEY_SHIFT):
					hud.eat_smoked()
				elif Input.is_key_pressed(KEY_CTRL):
					if not hud.is_menu_open() and bool(client.you.get("alive", false)):
						client.smart_provision("food")
				elif Input.is_key_pressed(KEY_ALT):
					var raw_item := ""
					for tier in range(1, 5):
						var candidate: String = "raw_fish" if tier == 1 else "raw_fish_%d" % tier
						if client.inventory.count(candidate) > 0:
							raw_item = candidate
							break
					if raw_item != "":
						_quick_use(raw_item)
					else:
						hud.say("No raw fish carried. Properly cooked food is safer.")
				else:
					_quick_use(Defs.CAMP_FISH_STEW if Input.is_key_pressed(KEY_SHIFT) else "canned_food")
			KEY_2:
				if Input.is_key_pressed(KEY_CTRL):
					if not hud.is_menu_open() and bool(client.you.get("alive", false)):
						client.smart_provision("drink")
				else:
					_quick_use("empty_water_pouch" if Input.is_key_pressed(KEY_SHIFT) else "water_bottle")
			KEY_3:
				if Input.is_key_pressed(KEY_CTRL):
					if not hud.is_menu_open() and bool(client.you.get("alive", false)):
						client.quick_medicine()
				else:
					_quick_use("expedition_trauma_kit" if Input.is_key_pressed(KEY_SHIFT) else "bandage")
			KEY_4:
				_cycle_weapon()
			KEY_5:
				_quick_use("jacket_1")
			KEY_6:
				_quick_use("antiseptic_edge_oil" if Input.is_key_pressed(KEY_SHIFT)
					else "field_antiseptic")
			KEY_7:
				_quick_use("antibiotics")
			KEY_F11:
				_quick_use("herbal_gut_tonic" if Input.is_key_pressed(KEY_SHIFT) else "herbal_poultice")
			KEY_8:
				_quick_use("thermal_wrap")
			KEY_PERIOD:
				_quick_use("frontier_stim")
			KEY_SLASH:
				_quick_use("soft_sole_wraps" if Input.is_key_pressed(KEY_SHIFT) else "herbal_scent_mask")
			KEY_SEMICOLON:
				_quick_use("spore_filter")
			KEY_R:
				if Input.is_key_pressed(KEY_CTRL):
					if not hud.is_menu_open() and bool(client.you.get("alive", false)):
						client.refill_canteen(Input.is_key_pressed(KEY_SHIFT))
				elif Input.is_key_pressed(KEY_SHIFT):
					if not hud.is_menu_open() and bool(client.you.get("alive", false)):
						_quick_use("field_alkali_kit")
				else:
					client.drink()
			KEY_T:
				if Input.is_key_pressed(KEY_ALT):
					client.fish(false, true) # Storm cast.
				else:
					client.fish(Input.is_key_pressed(KEY_SHIFT))
			KEY_Z:
				client.rest()
			KEY_B:
				hud.toggle_inventory()
			KEY_N:
				client.vendor("water_bottle", 1, true)
			KEY_V:
				var sell_id: String = Vendor.first_fish(client.inventory) if Input.is_key_pressed(KEY_SHIFT) else Vendor.first_sellable(client.inventory)
				if sell_id.is_empty():
					hud.say("Nothing to sell.")
				else:
					client.vendor(sell_id, 1, false)
			KEY_P:
				client.contract("daily_claim" if Input.is_key_pressed(KEY_CTRL) else ("claim" if Input.is_key_pressed(KEY_SHIFT) else "accept"))
			KEY_ENTER, KEY_KP_ENTER:
				if chat_edit != null:
					chat_edit.visible = true
					chat_edit.grab_focus()
			KEY_E:
				if Input.is_key_pressed(KEY_SHIFT) and not hud.is_menu_open():
					client.loot_sweep()
				else:
					_interact()
			KEY_F:
				client.drink()
			KEY_F1:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.guardian_taunt()
			KEY_F8:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.parry()
			KEY_F9:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.use_item("smoke_charge")
			KEY_G:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					if Input.is_key_pressed(KEY_SHIFT):
						client.stagger_finisher()
					else:
						var skill_direction: Vector2 = _aim_direction()
						if skill_direction == Vector2.ZERO:
							skill_direction = Vector2(sin(client.yaw), cos(client.yaw))
						client.skill(skill_direction)
			KEY_SPACE:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					# Move-direction dodge, or current aim/facing when stationary.
					var dodge_direction := Vector2(
						Input.get_axis("ui_left", "ui_right") + float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
						Input.get_axis("ui_up", "ui_down") + float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
					if dodge_direction.length_squared() < 0.0001:
						dodge_direction = _aim_direction()
					if dodge_direction.length_squared() < 0.0001:
						dodge_direction = Vector2(sin(client.yaw), cos(client.yaw))
					client.dodge(dodge_direction.normalized())
			KEY_MINUS:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					var fire_id: int = client.nearest_campfire(client.display_position())
					if fire_id != -1:
						client.extinguish_campfire(fire_id)
			KEY_0:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					if Input.is_key_pressed(KEY_ALT):
						hud.quick_smoke()
					else:
						hud.quick_cook(Input.is_key_pressed(KEY_SHIFT))
			KEY_9:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					if Input.is_key_pressed(KEY_SHIFT):
						_quick_use("stormproof_briquette")
					else:
						var fire_id: int = client.nearest_campfire(client.display_position())
						if fire_id == -1:
							hud.say("No burning campfire within 3 metres.")
						else:
							client.refuel_campfire(fire_id)
			KEY_I, KEY_TAB:
				hud.toggle_inventory()
			KEY_C:
				hud.toggle_crafting()
			KEY_BACKSLASH:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					var dir: Vector2 = _aim_direction()
					if dir.length_squared() < 0.0001:
						dir = Vector2(sin(client.yaw), cos(client.yaw))
					var site := Vector2(client.predicted.x, client.predicted.z) + dir * 2.8
					client.place_infected_snare(site)
			KEY_COMMA:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					var decoy_direction: Vector2 = _aim_direction()
					if decoy_direction.length_squared() < 0.0001:
						decoy_direction = Vector2(sin(client.yaw), cos(client.yaw))
					client.throw_decoy(decoy_direction)
			KEY_O:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					if Input.is_key_pressed(KEY_SHIFT):
						var fire_id: int = client.nearest_campfire(client.display_position())
						if fire_id < 0:
							hud.say("Camp alarm: stand within 3m of an active campfire.")
						else:
							client.arm_camp_alarm(fire_id)
					else:
						var direction: Vector2 = _aim_direction()
						if direction == Vector2.ZERO:
							direction = Vector2(sin(client.yaw), cos(client.yaw))
						var target := Vector2(client.predicted.x, client.predicted.z) + direction * 2.8
						client.light_campfire(target)
						hud.say("At night, campfire light attracts infected. Press - to extinguish.")
			KEY_U:
				if _build_mode:
					_place_wall()
				else:
					_build_mode = true
			KEY_ESCAPE:
				if _build_mode:
					_end_build_mode()
			KEY_H:
				var id: int = client.nearest_barricade(client.predicted)
				if id != -1:
					client.repair(id)
			KEY_Y:
				var id: int = client.nearest_barricade(client.predicted)
				if id != -1:
					client.upgrade(id)
			KEY_X:
				var id: int = client.nearest_barricade(client.predicted)
				if id != -1:
					client.dismantle(id)
	if event is InputEventMouseButton and event.pressed and _build_mode:
		# Build mode: the wheel turns the wall, a left click places it, a right click puts the plan away.
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_build_yaw = fposmod(_build_yaw + Structures.ROTATION_STEP, TAU)
			MOUSE_BUTTON_WHEEL_DOWN:
				_build_yaw = fposmod(_build_yaw - Structures.ROTATION_STEP, TAU)
			MOUSE_BUTTON_LEFT:
				_place_wall()
			MOUSE_BUTTON_RIGHT:
				_end_build_mode()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom - 0.1, 0.55, 1.8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom + 0.1, 0.55, 1.8)


## Uses or equips an item you carry; the server decides whether it works.
func _quick_use(item_id: String) -> void:
	if client.inventory.count(item_id) < 1:
		hud.say("You do not carry %s." % str(Defs.item(item_id).get("name", item_id)))
		return
	client.use_item(item_id)


## Equips the next weapon in the backpack (crafted spears and bows included).
func _cycle_weapon() -> void:
	var owned: Array[String] = []
	for item_id in Defs.items():
		if str(Defs.item(str(item_id)).get("kind", "")) == "weapon" and client.inventory.count(str(item_id)) > 0:
			owned.append(str(item_id))
	owned.sort()
	if owned.is_empty():
		hud.say("No weapon in the backpack.")
		return
	var current: int = owned.find(client.inventory.weapon)
	client.use_item(owned[(current + 1) % owned.size()])


func _interact() -> void:
	var p: Vector3 = client.predicted
	# The hatch of a bunker leads down into its dungeon; the stairs of the first room lead back up.
	if Dungeon.is_underground(p.x) and Dungeon.at_stairs(p.x, p.z):
		client.dungeon(false)
		return
	if not Dungeon.is_underground(p.x) and not Dungeon.bunker_at(client.world, p.x, p.z).is_empty():
		client.dungeon(true)
		return
	var loot: Dictionary = client.nearest_loot(p, Defs.REACH)
	if not loot.is_empty():
		client.loot(loot["id"])
		return
	var node: Dictionary = client.nearest_node(p, Defs.REACH)
	if not node.is_empty():
		client.gather(node["id"])


# --- Scripted demo for screenshots and videos --------------------------------------------------------------

func _run_demo() -> void:
	if _demo == "" or client == null or not client.you.has("x"):
		return # Wait for the server's welcome and first snapshot.
	_demo_frames += 1
	var net_ref = net
	match _demo:
		"ruins":
			if _demo_frames == 40:
				var site := _find_ruin()
				net_ref.c_debug.rpc_id(1, "teleport", {"x": site.x - 16.0, "z": site.y + 10.0})
				net_ref.c_debug.rpc_id(1, "give", {"item": "club_2", "count": 1})
				net_ref.c_debug.rpc_id(1, "give", {"item": "jacket_2", "count": 1})
				net_ref.c_debug.rpc_id(1, "zombie", {"type": "walker", "x": site.x - 8.0, "z": site.y + 12.0})
				net_ref.c_debug.rpc_id(1, "zombie", {"type": "runner", "x": site.x - 4.0, "z": site.y + 6.0})
				net_ref.c_debug.rpc_id(1, "zombie", {"type": "brute", "x": site.x, "z": site.y + 14.0})
				_screenshot_frames = 600 # Shoot while the fight is on, before the brute wins it.
			if _demo_frames == 90:
				client.use_item("club_2")
				client.use_item("jacket_2")
		"vista":
			if _demo_frames == 40:
				# A wide view over open country (screenshots of the landscape: grass, cloud shadows, light).
				var spot := _find_forest()
				net_ref.c_debug.rpc_id(1, "teleport", {"x": spot.x + 40.0, "z": spot.y + 30.0})
				_zoom = 2.2
		"forest":
			if _demo_frames == 40:
				var spot := _find_forest()
				net_ref.c_debug.rpc_id(1, "teleport", {"x": spot.x, "z": spot.y})
				net_ref.c_debug.rpc_id(1, "give", {"item": "axe_1", "count": 1})
		"skills":
			if _demo_frames == 30:
				for entry in [["woodcutting", 4200], ["mining", 1600], ["melee", 9000], ["slayer", 2600], ["athletics", 5200], ["toughness", 3000], ["crafting", 900], ["explorer", 2200], ["survivalist", 700]]:
					net_ref.c_debug.rpc_id(1, "xp", {"skill": entry[0], "amount": entry[1]})
			if _demo_frames == 80:
				client.buy_perk("sharp_axe")
				client.buy_perk("heavy_hands")
				client.buy_perk("swift_feet")
			if _demo_frames == 120 and skills_panel != null:
				skills_panel.toggle()
				skills_panel._tabs.current_tab = 1
		"village", "city", "farm", "camp", "outpost_site", "lighthouse", "dock", "bunker":
			if _demo_frames == 40:
				var wanted: String = "outpost" if _demo == "outpost_site" else _demo
				var site := _nearest_site(wanted)
				if not site.is_empty():
					net_ref.c_debug.rpc_id(1, "teleport", {"x": float(site["x"]) - 3.0, "z": float(site["z"]) + 7.0})
					_zoom = 1.8
					_screenshot_frames = 480
		"stones", "crystals", "greattree", "shrine", "battlefield":
			if _demo_frames == 40:
				var title: String = {"stones": "Stone Circle", "crystals": "Crystal Grove", "greattree": "Great Tree", "shrine": "Old Shrine", "battlefield": "Battlefield"}[_demo]
				var landmark := _nearest_site("landmark", title)
				if not landmark.is_empty():
					net_ref.c_debug.rpc_id(1, "teleport", {"x": float(landmark["x"]) - 4.0, "z": float(landmark["z"]) + 14.0})
					_zoom = 1.8
					_screenshot_frames = 480
		"road":
			if _demo_frames == 40:
				var spot := _nearest_signpost()
				net_ref.c_debug.rpc_id(1, "teleport", {"x": spot.x + 3.0, "z": spot.y + 5.0})
				_zoom = 1.5
				_screenshot_frames = 480
		"inventory":
			if _demo_frames == 30:
				for entry in [["club_2", 1], ["pistol", 1], ["ammo_9mm", 24], ["jacket_2", 1], ["axe_2", 1], ["canned_food", 4], ["water_bottle", 3], ["bandage", 5], ["wood_3", 12], ["ore_4", 6], ["silver", 240], ["hood_2", 1], ["cloak_3", 1], ["gloves_2", 1], ["boots_2", 1]]:
					net_ref.c_debug.rpc_id(1, "give", {"item": entry[0], "count": entry[1]})
			if _demo_frames == 70:
				for worn in ["club_2", "jacket_2", "hood_2", "cloak_3", "gloves_2", "boots_2"]:
					client.use_item(worn)
			if _demo_frames == 110:
				hud.toggle_inventory()
				# CGAME_DEMO_TAB=n opens another tab of the window for its screenshot.
				if OS.get_environment("CGAME_DEMO_TAB").is_valid_int() and hud._inventory_tabs != null:
					hud._inventory_tabs.current_tab = int(OS.get_environment("CGAME_DEMO_TAB"))
				if OS.get_environment("CGAME_DEMO_CRAFT") == "1":
					hud.toggle_crafting()
				if OS.get_environment("CGAME_DEMO_SOCIAL") == "1": # The community window instead of the bag.
					hud.toggle_inventory()
					hud.toggle_social()
				if OS.get_environment("CGAME_DEMO_FILTER") == "1": # Only gear in the bag and the workshop.
					for key in hud._bag_filter:
						hud._bag_filter[key] = key == "gear"
						hud._craft_filter[key] = key == "gear"
				if OS.get_environment("CGAME_DEMO_QUICK") == "1": # Fill the quick-use sockets as a double click would.
					hud._put_in_doll("canned_food")
					hud._put_in_doll("bandage")
		"dungeon":
			if _demo_frames == 30:
				var best: Dictionary = {}
				for rx in range(-4, 5):
					for rz in range(-4, 5):
						for site in client.world.poi.sites_in_region(rx, rz):
							if str(site.get("kind", "")) == "bunker" and (best.is_empty() or Vector2(site["x"], site["z"]).length() < Vector2(best["x"], best["z"]).length()):
								best = site
				if not best.is_empty():
					var hatch: Vector2 = Dungeon.hatch(client.world, best)
					net_ref.c_debug.rpc_id(1, "teleport", {"x": hatch.x, "z": hatch.y})
			if _demo_frames == 80:
				client.dungeon(true)
			if _demo_frames == 120:
				# Step into the room beyond the first doorway for the picture.
				var here := Vector2(client.predicted.x, client.predicted.z)
				var region: Vector2i = Dungeon.region_of(here.x, here.y)
				var layout: Dictionary = Dungeon.layout(client.world.world_seed, region)
				var target: Vector2 = Dungeon.origin(region)
				for room in layout["rooms"]:
					if room != Vector2i.ZERO and Dungeon.linked(layout, Vector2i.ZERO, room):
						target = Dungeon.room_center(region, room).lerp(Dungeon.origin(region), 0.55)
						break
				net_ref.c_debug.rpc_id(1, "teleport", {"x": target.x, "z": target.y})
		"build":
			if _demo_frames == 30:
				for entry in [["wood_1", 20], ["stone_1", 10], ["plank_2", 8], ["stone_2", 4]]:
					net_ref.c_debug.rpc_id(1, "give", {"item": entry[0], "count": entry[1]})
				net_ref.c_debug.rpc_id(1, "teleport", {"x": 72.0, "z": 20.0})
			if _demo_frames == 70:
				var here := Vector2(client.predicted.x, client.predicted.z)
				client.build(here + Vector2(2.5, 1.2), 0.0)
				client.build(here + Vector2(-0.4, 2.8), PI / 4.0)
			if _demo_frames == 95:
				var id: int = client.nearest_barricade(client.predicted)
				if id != -1:
					client.upgrade(id)
				_build_mode = true
				_build_yaw = PI / 2.0
		"fish":
			if _demo_frames == 30:
				net_ref.c_debug.rpc_id(1, "give", {"item": "fishing_rod", "count": 1})
				var shore := _open_shore()
				net_ref.c_debug.rpc_id(1, "teleport", {"x": shore.x, "z": shore.y})
			if _demo_frames == 70:
				# Step to the water's edge: dry ground with water about three metres out.
				var here := Vector2(client.predicted.x, client.predicted.z)
				for radius in range(0, 60, 2):
					var found := false
					for step in 24:
						var spot := here + Vector2.from_angle(float(step) * TAU / 24.0) * float(radius)
						if client.world.is_water(spot.x, spot.y):
							continue
						for look in 16:
							var probe := spot + Vector2.from_angle(float(look) * TAU / 16.0) * 3.0
							if client.world.is_water(probe.x, probe.y):
								net_ref.c_debug.rpc_id(1, "teleport", {"x": spot.x, "z": spot.y})
								found = true
								break
						if found:
							break
					if found:
						break
			if _demo_frames == 110:
				client.fish()
				_screenshot_frames = 640 # Shoot while the cast is out.
		"sky":
			if _demo_frames == 40:
				var vista := _open_shore()
				net_ref.c_debug.rpc_id(1, "teleport", {"x": vista.x, "z": vista.y})
		"map":
			if _demo_frames == 60:
				world_map.toggle()
				_screenshot_frames = 640
		"outpost":
			if _demo_frames == 40 and not client.outposts.is_empty():
				var post: Dictionary = client.outposts[0]
				net_ref.c_debug.rpc_id(1, "teleport", {"x": float(post["x"]) - 9.0, "z": float(post["z"]) + 4.0})
				_zoom = 1.7
				_screenshot_frames = 560 # Shoot before the zombies out there finish the visitor.
		"help":
			if _demo_frames == 60:
				help_panel.toggle()
		"hub":
			if _demo_frames == 40:
				net_ref.c_debug.rpc_id(1, "teleport", {"x": 14.0, "z": 6.0})
	if _screenshot_path != "":
		_screenshot_frames += 1
		if _screenshot_frames > 540:
			_frame_ms.append(get_process_delta_time() * 1000.0)
		if _screenshot_frames == 700:
			# The window may be hidden behind others, in which case the last drawn frame would be stale: draw now.
			RenderingServer.force_draw()
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			# Report tail-frame stutters instead of hiding them behind one median.
			# These are CPU process deltas, NOT real GPU timer measurements.
			var pace: Dictionary = RenderBenchmark.summarize(_frame_ms)
			print(RenderBenchmark.describe(pace))
			print("CLIENT frame: %d fps, %d draw calls, %d primitives, %d objects" % [Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
			print("CLIENT screenshot saved: ", _screenshot_path)
			get_tree().quit()


## The site of a kind closest to the hub (demos and screenshots).
## A beach facing open sea toward -z, for a clear view of the sky (demo).
func _open_shore() -> Vector2:
	var world = client.world
	for radius in range(200, 2400, 40):
		for step in 24:
			var spot := Vector2.from_angle(float(step) * TAU / 24.0) * float(radius)
			if world.is_water(spot.x, spot.y) or world.biome_at(spot.x, spot.y) != "beach":
				continue
			var open := true
			for ahead in range(10, 140, 10):
				if not world.is_water(spot.x, spot.y - float(ahead)):
					open = false
					break
			if open:
				return spot
	return Vector2(0.0, 40.0)


func _nearest_signpost() -> Vector2:
	var best := Vector2(60.0, 60.0)
	var best_distance := INF
	for cx in range(-10, 11):
		for cz in range(-10, 11):
			for sign in client.world.roads.signs_in_cell(Vector2i(cx, cz)):
				var spot := Vector2(float(sign["x"]), float(sign["z"]))
				if spot.length() > 70.0 and spot.length() < best_distance:
					best = spot
					best_distance = spot.length()
	return best


func _nearest_site(kind: String, title: String = "") -> Dictionary:
	var best := {}
	var best_distance := INF
	for rx in range(-14, 14):
		for rz in range(-14, 14):
			for site in client.world.poi.sites_in_region(rx, rz):
				var distance: float = Vector2(float(site["x"]), float(site["z"])).length()
				if site["kind"] == kind and (title == "" or str(site.get("title", "")) == title) and distance < best_distance:
					best = site
					best_distance = distance
	return best


func _find_ruin() -> Vector2:
	for radius in range(5, 14):
		for cx in range(-radius, radius + 1):
			for cz in range(-radius, radius + 1):
				if client.world.chunk(Vector2i(cx, cz))["ruin"] and max(abs(cx), abs(cz)) == radius:
					return WorldGen.cell_origin(Vector2i(cx, cz)) + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	return Vector2(120, 120)


func _find_forest() -> Vector2:
	for radius in range(3, 12):
		for cx in range(-radius, radius + 1):
			for cz in range(-radius, radius + 1):
				if max(abs(cx), abs(cz)) != radius:
					continue
				var center := WorldGen.cell_origin(Vector2i(cx, cz)) + Vector2.ONE * 32.0
				if client.world.biome_at(center.x, center.y) == "forest" and not client.world.is_water(center.x, center.y):
					return center
	return Vector2(100, 100)
