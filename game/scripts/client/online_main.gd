extends Node3D
## The online game client (dedicated server + Nakama): connect screen, the isometric camera, controls, and the glue between the
## network state and what is drawn.

const Defs = preload("res://scripts/shared/defs.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Net = preload("res://scripts/shared/net.gd")
const GameClient = preload("res://scripts/client/game_client.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const EntityView = preload("res://scripts/client/entity_view.gd")
const RaidTelegraph = preload("res://scripts/client/raid_telegraph.gd")
const Hud = preload("res://scripts/client/hud.gd")
const Meshes = preload("res://scripts/client/meshes.gd")
const CharacterModel = preload("res://scripts/client/character_model.gd")
const HubView = preload("res://scripts/client/hub_view.gd")
const Audio = preload("res://scripts/client/audio.gd")
const Social = preload("res://scripts/client/social.gd")

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
var audio
var hub_view
var social
var chat_edit: LineEdit
var account := {} # Result of the Nakama sign-in, empty when playing without accounts.
var connect_panel: PanelContainer
var address_edit: LineEdit
var name_edit: LineEdit
var status_label: Label
var _zoom := 1.0
var _attack_cooldown := 0.0
var _party_rally_marker: Node3D
var _raid_telegraph: Node3D
var _screenshot_path := ""
var _screenshot_frames := 0
var _demo := ""
var _frames := 0
var _demo_frames := 0 # Frames since the first snapshot arrived.


func _ready() -> void:
	Engine.physics_ticks_per_second = 30
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
			"--connect":
				address_edit.text = address
		i += 1
	address_edit.text = address
	name_edit.text = player_name
	if "--connect" in args:
		_connect()


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


func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.fog_enabled = true
	environment.fog_density = 0.0028
	environment.fog_light_color = Color(0.7, 0.78, 0.86)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = false
	sun.rotation_degrees = Vector3(-52, 35, 0)
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.far = 700.0
	camera.position = CAMERA_OFFSET * 3.0
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	_make_party_rally_marker()
	_raid_telegraph = RaidTelegraph.new()
	_raid_telegraph.name = "RaidGroundSlamWarning"
	add_child(_raid_telegraph)
	camera.current = true
	chunk_root = Node3D.new()
	chunk_root.name = "Chunks"
	add_child(chunk_root)
	entities = EntityView.new()
	add_child(entities)
	# The sea: one big plane that follows the player.
	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	water.mesh = plane
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.12, 0.35, 0.55, 0.72)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.roughness = 0.15
	water_material.metallic = 0.2
	water.material_override = water_material
	water.position.y = Defs.WATER_LEVEL - 0.35
	add_child(water)


func _build_connect_screen() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	connect_panel = PanelContainer.new()
	connect_panel.set_anchors_preset(Control.PRESET_CENTER)
	connect_panel.position = Vector2(-190, -110)
	layer.add_child(connect_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	connect_panel.add_child(box)
	var title := Label.new()
	title.text = "ALBION AFTER"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Gather. Craft. Survive. Lose everything."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Name"
	box.add_child(name_edit)
	address_edit = LineEdit.new()
	address_edit.placeholder_text = "host:port"
	box.add_child(address_edit)
	var button := Button.new()
	button.text = "Connect"
	button.pressed.connect(_connect)
	box.add_child(button)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status_label)


func _device_id() -> String:
	var path := "user://device_id.txt"
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path).strip_edges()
	var id := "%d-%d" % [Time.get_unix_time_from_system(), randi()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(id)
	return id


func _connect() -> void:
	var parts := address_edit.text.split(":")
	var host := parts[0]
	var port := int(parts[1]) if parts.size() > 1 else 24565
	status_label.text = "Signing in..."
	# Accounts come from Nakama on the same host. Without it we still join (servers can run offline).
	social = Social.new()
	add_child(social)
	var nakama_port := int(OS.get_environment("NAKAMA_PORT")) if OS.get_environment("NAKAMA_PORT") != "" else 7350
	account = await social.sign_in(host, nakama_port, _device_id() + ("-" + name_edit.text if OS.get_environment("MULTI_CLIENT") != "" else ""), name_edit.text)
	if not account.get("ok", false):
		account = {}
	net = Net.new()
	net.name = "Net"
	net.role = "client"
	get_tree().root.add_child.call_deferred(net) # RPC paths must match the server: /root/Net.
	client = GameClient.new(net)
	peer = ENetMultiplayerPeer.new()
	if peer.create_client(host, port) != OK:
		status_label.text = "Could not connect."
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting..."
	multiplayer.connected_to_server.connect(func() -> void:
		status_label.text = "Joining..."
		client.join(name_edit.text, account.get("token", ""), account.get("refresh", "")))
	multiplayer.connection_failed.connect(func() -> void: status_label.text = "Connection failed.")
	multiplayer.server_disconnected.connect(func() -> void:
		status_label.text = "Disconnected."
		connect_panel.visible = true)
	net.welcomed.connect(_on_welcomed)
	net.join_refused.connect(func(reason: String) -> void: status_label.text = reason)


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
	hub_view = HubView.new()
	add_child(hub_view)
	hub_view.build(client.world)
	audio = Audio.new()
	add_child(audio)
	client.event_received.connect(func(event: Dictionary) -> void: audio.on_event(event, client.peer_id, client.world.height_at))
	_raid_telegraph.clear()
	client.event_received.connect(func(event: Dictionary) -> void: _raid_telegraph.consume(event, client.world))
	avatar = Node3D.new()
	avatar_model = CharacterModel.new()
	avatar_model.setup(Color(1.0, 0.95, 0.5), 2.0, 1.0)
	avatar.add_child(avatar_model)
	var label := Label3D.new()
	label.text = name_edit.text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.009
	label.font_size = 28
	label.outline_size = 8
	label.position = Vector3(0, 2.5, 0)
	avatar.add_child(label)
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
	if alive and not _typing():
		move.x = Input.get_axis("ui_left", "ui_right") + float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
		move.y = Input.get_axis("ui_up", "ui_down") + float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
		sprint = Input.is_key_pressed(KEY_SHIFT)
	move = move.limit_length(1.0)
	var aim := _aim_direction()
	var yaw: float = atan2(aim.x, aim.y) if aim != Vector2.ZERO else float(client.yaw)
	client.send_input(move, sprint, yaw, delta)
	if alive and not hud.is_menu_open() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _attack_cooldown <= 0.0 and aim != Vector2.ZERO:
		client.attack(aim)
		_attack_cooldown = 0.18


func _process(delta: float) -> void:
	_frames += 1
	if client == null or not client.welcomed or not client.you.has("x"):
		return
	client.decay_correction(delta)
	var position: Vector3 = client.display_position()
	if avatar != null:
		avatar.position = position
		avatar.rotation.y = lerp_angle(avatar.rotation.y, client.yaw, 1.0 - exp(-16.0 * delta))
		avatar.visible = bool(client.you.get("alive", true))
		avatar_model.update_motion(delta)
		audio.set_footsteps(avatar_model._moving and avatar.visible)
	if streamer != null:
		streamer.focus_position = position
		_apply_world_state()
	entities.update_from(client)
	_update_party_rally_marker()
	# The camera glides after the player.
	var target := position + CAMERA_OFFSET * _zoom
	camera.position = camera.position.lerp(target, 1.0 - exp(-10.0 * delta))
	camera.look_at(position + Vector3(0, 0.8, 0))
	water.position.x = position.x
	water.position.z = position.z
	_update_time_of_day()
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


func _update_time_of_day() -> void:
	var day := WorldCycle.phase(client.server_time)
	var height := WorldCycle.sun_height(client.server_time) # 1 at noon, -1 at midnight.
	sun.rotation = Vector3(-deg_to_rad(lerpf(8.0, 70.0, clampf(height, 0.0, 1.0))), deg_to_rad(35.0 + day * 90.0), 0.0)
	var daylight := WorldCycle.daylight(client.server_time)
	sun.light_energy = lerpf(0.08, 1.15, daylight)
	sun.light_color = Color(1.0, 0.85, 0.65).lerp(Color(1.0, 0.98, 0.94), clampf(height * 1.5, 0.0, 1.0))
	environment.ambient_light_energy = lerpf(0.25, 1.0, daylight)
	environment.fog_light_color = Color(0.05, 0.07, 0.12).lerp(Color(0.7, 0.78, 0.86), daylight)


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
	if not loot.is_empty():
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
		text = "Gathering... %d%%" % int(100.0 * (1.0 - float(action["remaining"]) / maxf(float(action["total"]), 0.01)))
	hud.set_prompt(text)


func _near_water(p: Vector3) -> bool:
	for angle in 8:
		var spot := Vector2(p.x, p.z) + Vector2.from_angle(angle * TAU / 8.0) * 3.0
		if client.world.is_water(spot.x, spot.y):
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if client == null or not client.welcomed or hud == null:
		return
	if event is InputEventKey and event.pressed and not event.echo and not _typing():
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				if chat_edit != null:
					chat_edit.visible = true
					chat_edit.grab_focus()
			KEY_E:
				_interact()
			KEY_F:
				client.drink()
			KEY_F1:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.guardian_taunt()
			KEY_G:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
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
					hud.quick_cook()
			KEY_9:
				if bool(client.you.get("alive", false)):
					var fire_id: int = client.nearest_campfire(client.display_position())
					if fire_id == -1:
						hud.say("No burning campfire within 3 metres.")
					else:
						client.refuel_campfire(fire_id)
			KEY_I, KEY_TAB:
				hud.toggle_inventory()
			KEY_C:
				hud.toggle_crafting()
			KEY_O:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					var direction: Vector2 = _aim_direction()
					if direction == Vector2.ZERO:
						direction = Vector2(sin(client.yaw), cos(client.yaw))
					var target := Vector2(client.predicted.x, client.predicted.z) + direction * 2.8
					client.light_campfire(target)
			KEY_U:
				var direction: Vector2 = _aim_direction()
				if direction.length_squared() > 0.001:
					var target: Vector2 = Vector2(client.predicted.x, client.predicted.z) + direction * 2.8
					client.build(target)
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
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom - 0.1, 0.55, 1.8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom + 0.1, 0.55, 1.8)


func _interact() -> void:
	var p: Vector3 = client.predicted
	var loot: Dictionary = client.nearest_loot(p, Defs.REACH)
	if not loot.is_empty():
		client.loot(loot["id"])
		return
	var node: Dictionary = client.nearest_node(p, Defs.REACH)
	if not node.is_empty():
		client.gather(node["id"])


# --- Scripted demo for screenshots and videos --------------------------------------------------------------

func _run_demo() -> void:
	if _demo == "" or client == null:
		return
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
			if _demo_frames == 90:
				client.use_item("club_2")
				client.use_item("jacket_2")
		"forest":
			if _demo_frames == 40:
				var spot := _find_forest()
				net_ref.c_debug.rpc_id(1, "teleport", {"x": spot.x, "z": spot.y})
				net_ref.c_debug.rpc_id(1, "give", {"item": "axe_1", "count": 1})
		"hub":
			if _demo_frames == 40:
				net_ref.c_debug.rpc_id(1, "teleport", {"x": 14.0, "z": 6.0})
	if _screenshot_path != "":
		_screenshot_frames += 1
		if _screenshot_frames == 700:
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("CLIENT screenshot saved: ", _screenshot_path)
			get_tree().quit()


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
