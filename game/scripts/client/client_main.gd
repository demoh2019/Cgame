extends Node3D
## Local playable client of the SAME authoritative simulation used by the dedicated server.
## Not a second set of gameplay rules: gathering, combat, loot, survival and crafting all
## call GameServer. Multiplayer transport will be wired to this presentation separately.

const Defs = preload("res://scripts/shared/defs.gd")
const AcidSpitter = preload("res://scripts/shared/acid_spitter.gd")
const EmberFlask = preload("res://scripts/shared/ember_flask.gd")
const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")
const Camouflage = preload("res://scripts/shared/camouflage.gd")
const StealthStance = preload("res://scripts/shared/stealth_stance.gd")
const FieldSmoke = preload("res://scripts/shared/field_smoke.gd")
const BloodScent = preload("res://scripts/shared/blood_scent.gd")
const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")
const QuickCooking = preload("res://scripts/shared/quick_cooking.gd")
const TrailRation = preload("res://scripts/shared/trail_ration.gd")
const FishingDisplay = preload("res://scripts/shared/fishing_display.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const InfectedWounds = preload("res://scripts/shared/infected_wounds.gd")
const RuinSurvey = preload("res://scripts/shared/ruin_survey.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const Dungeon = preload("res://scripts/shared/dungeon.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const ContactShadowBatch = preload("res://scripts/client/contact_shadow_batch.gd")
const AmbientMotes = preload("res://scripts/client/ambient_motes.gd")
const RainVfx = preload("res://scripts/client/rain_vfx.gd")
const HandFlareVisual = preload("res://scripts/client/hand_flare_visual.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const RaidWard = preload("res://scripts/shared/raid_ward.gd")
const TrailBikeVisual = preload("res://scripts/client/trail_bike_visual.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const RegionalTrade = preload("res://scripts/shared/regional_trade.gd")
const RoadTravel = preload("res://scripts/shared/road_travel.gd")
const BikeCargo = preload("res://scripts/shared/bike_cargo.gd")
const SurvivalRadar = preload("res://scripts/client/survival_radar.gd")
const Contracts = preload("res://scripts/shared/contracts.gd")
const DailyBounties = preload("res://scripts/shared/daily_bounties.gd")
const Reputation = preload("res://scripts/shared/reputation.gd")
const CampRest = preload("res://scripts/shared/camp_rest.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const WadingWetness = preload("res://scripts/shared/wading_wetness.gd")
const StormMud = preload("res://scripts/shared/storm_mud.gd")
const WindChill = preload("res://scripts/shared/wind_chill.gd")
const LightningVisual = preload("res://scripts/client/storm_lightning_visual.gd")
const StormLightning = preload("res://scripts/shared/storm_lightning.gd")
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const PortableShelter = preload("res://scripts/shared/portable_shelter.gd")
const CorpseScent = preload("res://scripts/shared/corpse_scent.gd")
const LOCAL_PLAYER_ID := 2
const TERRAIN_STEP := 8.0

var world
var sim
var survivor
var _sequence: int = 0
var _facing: Vector2 = Vector2(0.0, -1.0)
var _recipe_index: int = 0
var _recipes: Array[String] = []
var _camera: Camera3D
var _sun: DirectionalLight3D
var _world_environment: Environment
var _atmosphere # Script-backed Atmosphere instance; custom fields are not members of Node3D.
var _rain_vfx: Node3D
var _ambient_motes
var _weather_next_update: float = -1.0
var _weather_storming := false
var _visual_weather_wind := Vector2.ZERO
var _visual_biome := "plains"
var _avatar: MeshInstance3D
var _bike_visual
var _flare_visual
var _lightning_visual
var _last_bike_position: Vector3 = Vector3.INF
var _stats: Label
var _instructions: Label
var _radar
var _bank_panel: PanelContainer
var _bank_label: Label
var _bank_open: bool = false
var _selected_bank_item: String = ""
var _feedback: String = "Leave the safe hub to gather. Return to the workbench to craft."
var _last_siege_notification: int = 0
var _chunks: Dictionary = {}
var _resource_meshes: Dictionary = {}
var _crate_meshes: Dictionary = {}
var _zombie_meshes: Dictionary = {}
var _spit_warning_meshes: Dictionary = {}
var _acid_pool_meshes: Dictionary = {}
var _ember_pool_meshes: Dictionary = {}
var _barricade_bodies: Dictionary = {}
var _campfire_visuals: Dictionary = {}
var _shelter_visuals: Dictionary = {}
var _decoy_visuals: Dictionary = {}
var _fish_trap_visuals: Dictionary = {}
var _smoke_visuals: Dictionary = {}
var _materials: Dictionary = {}
var _last_center: Vector2i = Vector2i(999999, 999999)
var _hud_clock: float = 0.0


func _ready() -> void:
	_setup_actions()
	GraphicsQuality.load_preference()
	world = WorldGen.new(1337)
	sim = GameServer.new(world, 1337)
	survivor = sim.add_player(LOCAL_PLAYER_ID, "Survivor")
	var recipe_ids: Array = Defs.recipes().keys()
	recipe_ids.sort()
	for recipe_id in recipe_ids:
		_recipes.append(str(recipe_id))
	_make_light_and_camera()
	# Reuse the online mode\x27s one-draw night fireflies and sunlit pollen.
	_ambient_motes = AmbientMotes.new()
	_ambient_motes.setup(world)
	add_child(_ambient_motes)
	# The solo scene shares the same single-draw soft grounding shadows.
	var ground_shadows := ContactShadowBatch.new()
	ground_shadows.name = "GroundContactShadows"
	ground_shadows.setup(_atmosphere)
	add_child(ground_shadows)
	GraphicsQuality.apply(get_viewport(), _atmosphere, null)
	_rain_vfx = RainVfx.create(str(RenderingServer.get_current_rendering_method()))
	add_child(_rain_vfx)
	RainVfx.apply_quality(_rain_vfx, GraphicsQuality.level())
	_lightning_visual = LightningVisual.new()
	_lightning_visual.name = "StormLightningWarning"
	add_child(_lightning_visual)
	_make_avatar()
	_make_workbench()
	_make_bank_landmark()
	_make_hud()
	_stream_chunks()
	_update_hud()


func _setup_actions() -> void:
	_bind_key("survive_up", KEY_W)
	_bind_key("survive_down", KEY_S)
	_bind_key("survive_left", KEY_A)
	_bind_key("survive_right", KEY_D)
	_bind_key("survive_sprint", KEY_SHIFT)
	_bind_key("survive_crouch", KEY_CTRL)
	_bind_key("survive_gather", KEY_E)
	_bind_key("survive_fish", KEY_T)
	_bind_key("survive_place_fish_trap", KEY_F10)
	_bind_key("survive_collect_fish_trap", KEY_F12)
	_bind_key("survive_loot", KEY_Q)
	_bind_key("survive_attack", KEY_F)
	_bind_key("survive_skill", KEY_G)
	_bind_key("survive_dodge", KEY_SPACE)
	_bind_key("survive_parry", KEY_F8)
	_bind_key("survive_poultice", KEY_F11)
	_bind_key("survive_flare", KEY_F2)
	_bind_key("survive_craft", KEY_C)
	_bind_key("survive_quick_cook", KEY_0)
	_bind_key("survive_next_recipe", KEY_TAB)
	_bind_key("survive_food", KEY_1)
	_bind_key("survive_water", KEY_2)
	_bind_key("survive_bandage", KEY_3)
	_bind_key("survive_weapon", KEY_4)
	_bind_key("survive_armor", KEY_5)
	_bind_key("survive_antiseptic", KEY_6)
	_bind_key("survive_antibiotics", KEY_7)
	_bind_key("survive_warmth", KEY_8)
	_bind_key("survive_lake", KEY_R)
	_bind_key("survive_build", KEY_U)
	_bind_key("survive_campfire", KEY_O)
	_bind_key("survive_shelter", KEY_F6)
	_bind_key("survive_pack_shelter", KEY_F7)
	_bind_key("survive_decoy", KEY_COMMA)
	_bind_key("survive_ember", KEY_F5)
	_bind_key("survive_smoke", KEY_F9)
	_bind_key("survive_snare", KEY_BACKSLASH)
	_bind_key("survive_stim", KEY_PERIOD)
	_bind_key("survive_scent_mask", KEY_SLASH)
	_bind_key("survive_spore_filter", KEY_SEMICOLON)
	_bind_key("survive_refuel", KEY_9)
	_bind_key("survive_extinguish", KEY_MINUS)
	_bind_key("survive_repair", KEY_H)
	_bind_key("survive_upgrade", KEY_Y)
	_bind_key("survive_dismantle", KEY_X)
	_bind_key("survive_vendor_buy", KEY_N)
	_bind_key("survive_vendor_sell", KEY_V)
	_bind_key("survive_radar", KEY_M)
	_bind_key("survive_mount", KEY_F4)
	_bind_key("survive_bike_lamp", KEY_BRACKETLEFT)
	_bind_key("survive_bike_service", KEY_PAGEUP)
	_bind_key("survive_whetstone", KEY_END)
	_bind_key("survive_sighting_kit", KEY_DELETE)
	_bind_key("survive_armor_plate", KEY_INSERT)
	_bind_key("survive_bike_repair", KEY_PAGEDOWN)
	_bind_key("survive_survey", KEY_F3)
	_bind_key("survive_bank", KEY_B)
	_bind_key("survive_bank_next", KEY_J)
	_bind_key("survive_bank_deposit", KEY_K)
	_bind_key("survive_bank_withdraw", KEY_L)
	_bind_key("survive_contract", KEY_P)
	_bind_key("survive_rest", KEY_Z)
	_bind_key("survive_recall", KEY_HOME)


func _bind_key(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func _make_light_and_camera() -> void:
	# The same atmosphere as multiplayer: panoramic sky, changing sunlight,
	# cloud shadows and weather-aware PBR fog, with graphics presets applied
	# according to the actual renderer.
	_atmosphere = Atmosphere.new()
	add_child(_atmosphere)
	_world_environment = _atmosphere.environment
	_sun = _atmosphere.sun
	_update_world_light()
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.current = true
	_camera.fov = 58.0
	add_child(_camera)


## Keep the offline world consistent with the dedicated world's day/night
## and regional weather. Sample weather at 4 Hz, not on every render frame.
func _update_world_light(delta: float = 0.0) -> void:
	if _atmosphere == null or sim == null or world == null:
		return
	var seconds: float = sim.time
	if seconds >= _weather_next_update:
		var at: Vector3 = survivor.position if survivor != null else Vector3.ZERO
		var weather: Dictionary = Weather.conditions(world, at.x, at.z, seconds)
		_weather_storming = str(weather.get("condition", "")) == "storm"
		_visual_weather_wind = Weather.wind_at(world, at.x, at.z, seconds)
		_visual_biome = world.biome_at(at.x, at.z)
		_weather_next_update = seconds + 0.25
	_atmosphere.update(WorldCycle.daylight(seconds), WorldCycle.sun_height(seconds),
		WorldCycle.phase(seconds), _weather_storming, delta, _visual_weather_wind, _visual_biome)


func _mesh(box_size: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	instance.mesh = box
	var key := str(color)
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.96
		_materials[key] = material
	instance.material_override = _materials[key]
	return instance


func _make_avatar() -> void:
	_avatar = _mesh(Vector3(0.8, 1.7, 0.8), Color(0.25, 0.69, 0.84))
	_avatar.name = "Survivor"
	_avatar.add_to_group(ContactShadowBatch.GROUP)
	_avatar.set_meta("aa_contact_shadow_ground_offset", 0.85)
	_avatar.set_meta("aa_contact_shadow_radius", 0.88)
	add_child(_avatar)
	_bike_visual = TrailBikeVisual.new()
	_bike_visual.name = "TrailBike"
	_bike_visual.position = Vector3(0.0, -0.85, 0.0)
	_avatar.add_child(_bike_visual)
	_flare_visual = HandFlareVisual.new()
	_flare_visual.name = "HandFlare"
	_avatar.add_child(_flare_visual)


## A visible landmark for the station validation enforced by GameServer.
func _make_workbench() -> void:
	var bench := _mesh(Vector3(2.8, 1.0, 1.6), Color(0.88, 0.68, 0.26))
	bench.name = "Workbench"
	bench.position = Vector3(
			GameServer.WORKBENCH_POSITION.x,
			world.height_at(GameServer.WORKBENCH_POSITION.x, GameServer.WORKBENCH_POSITION.y) + 0.5,
			GameServer.WORKBENCH_POSITION.y)
	add_child(bench)


## The protected stash is one visible building near the hub's workbench.
## Server authority still validates the player's actual position before transfers.
func _make_bank_landmark() -> void:
	var x: float = GameServer.WORKBENCH_POSITION.x - 4.0
	var z: float = GameServer.WORKBENCH_POSITION.y
	var bank := _mesh(Vector3(2.0, 1.25, 1.6), Color(0.24, 0.47, 0.65))
	bank.name = "SafeStash"
	bank.position = Vector3(x, world.height_at(x, z) + 0.625, z)
	add_child(bank)


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	_stats = Label.new()
	_stats.name = "Stats"
	_stats.position = Vector2(18, 18)
	_stats.add_theme_font_size_override("font_size", 17)
	layer.add_child(_stats)
	var radar := SurvivalRadar.new()
	radar.name = "SurvivalRadar"
	radar.world = world
	radar.sim = sim
	radar.actor_id = LOCAL_PLAYER_ID
	layer.add_child(radar)
	radar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	radar.offset_left = -222.0
	radar.offset_top = 16.0
	radar.offset_right = -16.0
	radar.offset_bottom = 222.0
	_radar = radar
	_instructions = Label.new()
	_instructions.name = "Instructions"
	_instructions.position = Vector2(18, 202)
	_instructions.add_theme_font_size_override("font_size", 15)
	layer.add_child(_instructions)
	_bank_panel = PanelContainer.new()
	_bank_panel.name = "BankPanel"
	_bank_panel.position = Vector2(18, 378)
	_bank_panel.custom_minimum_size = Vector2(600, 165)
	_bank_panel.visible = false
	layer.add_child(_bank_panel)
	_bank_label = Label.new()
	_bank_label.name = "Contents"
	_bank_label.add_theme_font_size_override("font_size", 15)
	_bank_panel.add_child(_bank_label)


func _terrain_color(x: float, z: float) -> Color:
	if world.is_safe(x, z):
		return Color(0.32, 0.41, 0.31)
	match world.biome_at(x, z):
		"water":
			return Color(0.12, 0.3, 0.52)
		"beach":
			return Color(0.53, 0.51, 0.36)
		"mountain":
			return Color(0.42, 0.42, 0.44)
		"swamp":
			return Color(0.29, 0.38, 0.26)
		"forest":
			return Color(0.28, 0.43, 0.27)
		_:
			return Color(0.43, 0.41, 0.31)


func _terrain_vertex(surface: SurfaceTool, x: float, z: float) -> void:
	surface.set_color(_terrain_color(x, z))
	surface.add_vertex(Vector3(x, world.height_at(x, z) - 0.12, z))


func _make_terrain(cell: Vector2i) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin: Vector2 = WorldGen.cell_origin(cell)
	var steps: int = int(Defs.CHUNK_SIZE / TERRAIN_STEP)
	for ix in range(steps):
		for iz in range(steps):
			var x: float = origin.x + float(ix) * TERRAIN_STEP
			var z: float = origin.y + float(iz) * TERRAIN_STEP
			_terrain_vertex(surface, x, z)
			_terrain_vertex(surface, x, z + TERRAIN_STEP)
			_terrain_vertex(surface, x + TERRAIN_STEP, z)
			_terrain_vertex(surface, x + TERRAIN_STEP, z)
			_terrain_vertex(surface, x, z + TERRAIN_STEP)
			_terrain_vertex(surface, x + TERRAIN_STEP, z + TERRAIN_STEP)
	surface.generate_normals()
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	terrain.material_override = material
	return terrain


func _make_chunk(cell: Vector2i) -> Node3D:
	var chunk_node := Node3D.new()
	chunk_node.name = "Chunk_%d_%d" % [cell.x, cell.y]
	chunk_node.add_child(_make_terrain(cell))
	var chunk_data: Dictionary = world.chunk(cell)
	for node in chunk_data["nodes"]:
		var tint := Color(0.29, 0.62, 0.35)
		match str(node["kind"]):
			"rock", "ore":
				tint = Color(0.58, 0.6, 0.62)
			"bush", "berry":
				tint = Color(0.68, 0.72, 0.3)
		var visible_node := _mesh(Vector3(1.0, 1.25, 1.0), tint)
		visible_node.position = Vector3(node["x"], node["y"] + 0.55, node["z"])
		chunk_node.add_child(visible_node)
		_resource_meshes[int(node["id"])] = visible_node
	for crate in chunk_data["crates"]:
		var visible_crate := _mesh(Vector3(1.1, 0.7, 1.0), Color(0.67, 0.42, 0.21))
		visible_crate.position = Vector3(crate["x"], crate["y"] + 0.35, crate["z"])
		chunk_node.add_child(visible_crate)
		_crate_meshes[int(crate["id"])] = visible_crate
	return chunk_node


func _stream_chunks() -> void:
	var center: Vector2i = WorldGen.cell_of(survivor.position.x, survivor.position.z)
	if center == _last_center:
		return
	_last_center = center
	for cell in _chunks.keys():
		if abs(cell.x - center.x) > 1 or abs(cell.y - center.y) > 1:
			var old_chunk: Node3D = _chunks[cell]
			for item_id in _resource_meshes.keys():
				if old_chunk.is_ancestor_of(_resource_meshes[item_id]):
					_resource_meshes.erase(item_id)
			for item_id in _crate_meshes.keys():
				if old_chunk.is_ancestor_of(_crate_meshes[item_id]):
					_crate_meshes.erase(item_id)
			_chunks.erase(cell)
			old_chunk.queue_free()
	for cx in range(center.x - 1, center.x + 2):
		for cz in range(center.y - 1, center.y + 2):
			var cell := Vector2i(cx, cz)
			if not _chunks.has(cell):
				var chunk: Node3D = _make_chunk(cell)
				add_child(chunk)
				_chunks[cell] = chunk


func _sync_zombies() -> void:
	var active: Dictionary = {}
	for zombie in sim.zombies.values():
		if not zombie.is_alive() or zombie.position.distance_to(survivor.position) > 72.0:
			continue
		active[zombie.id] = true
		var base_tint := Color(0.98, 0.65, 0.18) if zombie.elite else (
			Color(0.4, 0.9, 0.23) if zombie.type == "spitter" else Color(0.66, 0.37, 0.35))
		if not _zombie_meshes.has(zombie.id):
			var mesh := _mesh(
				Vector3(1.05, 1.95, 1.05) if zombie.elite else Vector3(0.85, 1.6, 0.85),
				base_tint)
			# _mesh caches materials by color. Give each wounded infected its
			# own material so an individual change cannot recolor its pack.
			mesh.material_override = mesh.material_override.duplicate() as StandardMaterial3D
			mesh.add_to_group(ContactShadowBatch.GROUP)
			mesh.set_meta("aa_contact_shadow_ground_offset", 0.975 if zombie.elite else 0.8)
			mesh.set_meta("aa_contact_shadow_radius", 1.1 if zombie.elite else 0.82)
			add_child(mesh)
			_zombie_meshes[zombie.id] = mesh
		var phase: String = InfectedWounds.phase(zombie)
		var tint: Color = base_tint
		if phase == "limping":
			tint = base_tint.lerp(Color(0.54, 0.52, 0.66), 0.65)
		elif phase == "frenzied":
			tint = base_tint.lerp(Color(1.0, 0.19, 0.1), 0.78)
		elif zombie.stagger_resolve_stacks >= 2 and zombie.stagger_resolve_seconds > 0.0:
			tint = base_tint.lerp(Color(0.74, 0.42, 0.95), 0.65)
		if zombie.melee_blocked:
			tint = base_tint.lerp(Color(0.94, 0.75, 0.38), 0.62)
		var material: StandardMaterial3D = _zombie_meshes[zombie.id].material_override
		material.albedo_color = tint
		_zombie_meshes[zombie.id].position = zombie.position + Vector3(0.0, 0.975 if zombie.elite else 0.8, 0.0)
	for zombie_id in _zombie_meshes.keys():
		if not active.has(zombie_id):
			_zombie_meshes[zombie_id].queue_free()
			_zombie_meshes.erase(zombie_id)


## Local preview uses the same server-authored telegraphs as online play.
func _sync_spit_warnings() -> void:
	var visible: Dictionary = {}
	for zombie in sim.zombies.values():
		if zombie.type != "spitter" or not zombie.is_alive() or not zombie.spit_pending:
			continue
		if Vector2(survivor.position.x, survivor.position.z).distance_to(
				zombie.spit_center) > 75.0:
			continue
		visible[zombie.id] = true
		if not _spit_warning_meshes.has(zombie.id):
			var marker := MeshInstance3D.new()
			var disk := CylinderMesh.new()
			disk.top_radius = AcidSpitter.RADIUS
			disk.bottom_radius = AcidSpitter.RADIUS
			disk.height = 0.06
			marker.mesh = disk
			var chemical := StandardMaterial3D.new()
			chemical.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			chemical.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			chemical.albedo_color = Color(0.5, 1.0, 0.16, 0.42)
			marker.material_override = chemical
			add_child(marker)
			_spit_warning_meshes[zombie.id] = marker
		var at: Vector2 = zombie.spit_center
		_spit_warning_meshes[zombie.id].position = Vector3(
			at.x, world.height_at(at.x, at.y) + 0.08, at.y)
	for id in _spit_warning_meshes.keys():
		if not visible.has(id):
			_spit_warning_meshes[id].queue_free()
			_spit_warning_meshes.erase(id)


## Render the same temporary server hazards during offline preview.
func _sync_acid_pools() -> void:
	var visible: Dictionary = {}
	for pool in sim.acid_pools.values():
		if AcidSpitter.pool_remaining(pool, sim.time) <= 0.0:
			continue
		var at := Vector2(float(pool["x"]), float(pool["z"]))
		if at.distance_to(Vector2(survivor.position.x, survivor.position.z)) > 75.0:
			continue
		var id: int = int(pool["id"])
		visible[id] = true
		if not _acid_pool_meshes.has(id):
			var puddle := MeshInstance3D.new()
			var disk := CylinderMesh.new()
			disk.top_radius = AcidSpitter.RADIUS
			disk.bottom_radius = AcidSpitter.RADIUS
			disk.height = 0.04
			puddle.mesh = disk
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.55, 0.45, 0.08, 0.55)
			puddle.material_override = mat
			add_child(puddle)
			_acid_pool_meshes[id] = puddle
		_acid_pool_meshes[id].position = Vector3(at.x, float(pool["y"]) + 0.07, at.y)
	for id in _acid_pool_meshes.keys():
		if not visible.has(id):
			_acid_pool_meshes[id].queue_free()
			_acid_pool_meshes.erase(id)


## Local preview renders the same authoritative fields as online snapshots.
func _sync_ember_pools() -> void:
	var visible: Dictionary = {}
	for field in sim.ember_pools.values():
		if EmberFlask.remaining(field, sim.time) <= 0.0:
			continue
		var point := Vector2(float(field["x"]), float(field["z"]))
		if point.distance_to(Vector2(survivor.position.x, survivor.position.z)) > 75.0:
			continue
		var id: int = int(field["id"])
		visible[id] = true
		if not _ember_pool_meshes.has(id):
			var mesh := MeshInstance3D.new()
			var disk := CylinderMesh.new()
			disk.top_radius = EmberFlask.RADIUS
			disk.bottom_radius = EmberFlask.RADIUS
			disk.height = 0.06
			mesh.mesh = disk
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(1.0, 0.36, 0.07, 0.43)
			mesh.material_override = mat
			add_child(mesh)
			_ember_pool_meshes[id] = mesh
		_ember_pool_meshes[id].position = Vector3(
			point.x, float(field["y"]) + 0.1, point.y)
	for id in _ember_pool_meshes.keys():
		if not visible.has(id):
			_ember_pool_meshes[id].queue_free()
			_ember_pool_meshes.erase(id)


func _sync_barricades() -> void:
	var active: Dictionary = {}
	for id in sim.barricades:
		var wall: Dictionary = sim.barricades[id]
		var point := Vector3(float(wall["x"]), float(wall["y"]) + 0.8, float(wall["z"]))
		if survivor.position.distance_to(point) > 95.0:
			continue
		active[id] = true
		if not _barricade_bodies.has(id):
			var body := StaticBody3D.new()
			body.name = "Barricade_%d" % int(id)
			var shape_node := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1.7, 1.6, 1.7)
			shape_node.shape = box
			body.add_child(shape_node)
			var visual := _mesh(box.size, Color(0.57, 0.40, 0.23))
			visual.name = "Body"
			body.add_child(visual)
			add_child(body)
			_barricade_bodies[id] = body
		var structure: StaticBody3D = _barricade_bodies[id]
		structure.position = point
		var visual: MeshInstance3D = structure.get_node("Body")
		var wall_tier: int = Structures.tier_of(wall)
		var max_hp: float = Structures.max_health(wall_tier)
		var health_fraction := clampf(float(wall["hp"]) / maxf(max_hp, 1.0), 0.0, 1.0)
		var material: StandardMaterial3D = visual.material_override
		if material == null or material == _materials.get(str(Color(0.57, 0.40, 0.23))):
			material = StandardMaterial3D.new()
			visual.material_override = material
		material.albedo_color = Color(0.20, 0.18, 0.18).lerp(Structures.color_for_tier(wall_tier), health_fraction)
	for id in _barricade_bodies.keys():
		if not active.has(id):
			_barricade_bodies[id].queue_free()
			_barricade_bodies.erase(id)


func _sync_campfires() -> void:
	var visible: Dictionary = {}
	for id in sim.campfires:
		var fire: Dictionary = sim.campfires[id]
		var point := Vector3(float(fire["x"]), float(fire["y"]), float(fire["z"]))
		if survivor.position.distance_to(point) > 95.0:
			continue
		visible[id] = true
		if not _campfire_visuals.has(id):
			var node := Node3D.new()
			node.name = "Campfire_%d" % int(id)
			node.add_child(_mesh(Vector3(0.9, 0.28, 0.9), Color(0.4, 0.19, 0.08)))
			var flame := _mesh(Vector3(0.48, 0.65, 0.48), Color(1.0, 0.42, 0.05))
			flame.position.y = 0.4
			node.add_child(flame)
			var light := OmniLight3D.new()
			light.position.y = 0.8
			light.light_color = Color(1.0, 0.48, 0.17)
			light.omni_range = 4.0
			light.light_energy = 0.8
			node.add_child(light)
			add_child(node)
			_campfire_visuals[id] = node
		_campfire_visuals[id].position = point
	for id in _campfire_visuals.keys():
		if not visible.has(id):
			_campfire_visuals[id].queue_free()
			_campfire_visuals.erase(id)


func _sync_shelters() -> void:
	var active: Dictionary = {}
	for id in sim.shelters:
		var tarp: Dictionary = sim.shelters[id]
		var point := Vector3(float(tarp["x"]), float(tarp["y"]), float(tarp["z"]))
		if survivor.position.distance_to(point) > 95.0:
			continue
		active[id] = true
		if not _shelter_visuals.has(id):
			var node := Node3D.new()
			node.name = "Tarp_%d" % int(id)
			var roof := _mesh(Vector3(3.0, 0.13, 2.6), Color(0.31, 0.42, 0.29))
			roof.position.y = 1.8
			node.add_child(roof)
			for dx in [-1.25, 1.25]:
				for dz in [-1.08, 1.08]:
					var pole := _mesh(Vector3(0.1, 1.75, 0.1), Color(0.35, 0.24, 0.16))
					pole.position = Vector3(dx, 0.89, dz)
					node.add_child(pole)
			add_child(node)
			_shelter_visuals[id] = node
		_shelter_visuals[id].position = point
	for id in _shelter_visuals.keys():
		if not active.has(id):
			_shelter_visuals[id].queue_free()
			_shelter_visuals.erase(id)


func _sync_smoke() -> void:
	var shown: Dictionary = {}
	for id in sim.smoke_clouds:
		var cloud: Dictionary = sim.smoke_clouds[id]
		var point := Vector3(float(cloud["x"]), float(cloud["y"]), float(cloud["z"]))
		if survivor.position.distance_to(point) > 95.0:
			continue
		shown[id] = true
		if not _smoke_visuals.has(id):
			var root := Node3D.new()
			root.name = "Smoke_%d" % int(id)
			var mesh := MeshInstance3D.new()
			var shape := SphereMesh.new()
			shape.radius = FieldSmoke.RADIUS
			shape.height = 3.2
			mesh.mesh = shape
			mesh.position.y = 1.6
			var haze := StandardMaterial3D.new()
			haze.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			haze.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			haze.albedo_color = Color(0.52, 0.57, 0.58, 0.28)
			haze.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.material_override = haze
			root.add_child(mesh)
			add_child(root)
			_smoke_visuals[id] = root
		_smoke_visuals[id].position = point
	for id in _smoke_visuals.keys():
		if not shown.has(id):
			_smoke_visuals[id].queue_free()
			_smoke_visuals.erase(id)


func _sync_fish_traps() -> void:
	var seen: Dictionary = {}
	for id in sim.fish_traps:
		var trap: Dictionary = sim.fish_traps[id]
		var position := Vector3(float(trap["x"]), float(trap["y"]), float(trap["z"]))
		if survivor.position.distance_to(position) > 95.0:
			continue
		seen[id] = true
		if not _fish_trap_visuals.has(id):
			var node := Node3D.new()
			node.name = "FishTrap_%d" % int(id)
			var buoy := _mesh(Vector3(0.9, 0.22, 0.9), Color(0.83, 0.51, 0.19))
			buoy.position.y = 0.12
			node.add_child(buoy)
			var net := _mesh(Vector3(1.2, 0.08, 1.2), Color(0.30, 0.38, 0.27))
			net.position.y = 0.02
			node.add_child(net)
			add_child(node)
			_fish_trap_visuals[id] = node
		_fish_trap_visuals[id].position = position
	for id in _fish_trap_visuals.keys():
		if not seen.has(id):
			_fish_trap_visuals[id].queue_free()
			_fish_trap_visuals.erase(id)


func _sync_decoys() -> void:
	var visible: Dictionary = {}
	for id in sim.decoys:
		var lure: Dictionary = sim.decoys[id]
		var point := Vector3(float(lure["x"]), float(lure["y"]), float(lure["z"]))
		if survivor.position.distance_to(point) > 95.0:
			continue
		visible[id] = true
		if not _decoy_visuals.has(id):
			var node := Node3D.new()
			node.name = "Decoy_%d" % int(id)
			var clacker := _mesh(Vector3(0.5, 0.25, 0.5), Color(0.96, 0.72, 0.12))
			clacker.position.y = 0.18
			node.add_child(clacker)
			var marker := OmniLight3D.new()
			marker.light_color = Color(1.0, 0.78, 0.28)
			marker.light_energy = 0.45
			marker.omni_range = 3.5
			marker.position.y = 0.4
			node.add_child(marker)
			add_child(node)
			_decoy_visuals[id] = node
		_decoy_visuals[id].position = point
	for id in _decoy_visuals.keys():
		if not visible.has(id):
			_decoy_visuals[id].queue_free()
			_decoy_visuals.erase(id)


func _nearest_campfire() -> int:
	var result: int = -1
	var best_squared: float = FieldCampfire.REFUEL_RANGE * FieldCampfire.REFUEL_RANGE
	var position := Vector2(survivor.position.x, survivor.position.z)
	for fire in sim.campfires.values():
		var site := Vector2(float(fire["x"]), float(fire["z"]))
		var distance_squared: float = position.distance_squared_to(site)
		if distance_squared <= best_squared:
			result = int(fire["id"])
			best_squared = distance_squared
	return result


func _nearest_barricade() -> int:
	var nearest := -1
	var distance := 3.0
	var current := Vector2(survivor.position.x, survivor.position.z)
	for id in sim.barricades:
		var item: Dictionary = sim.barricades[id]
		var delta_position := Vector2(float(item["x"]), float(item["z"])) - current
		var d := delta_position.length()
		if d < distance and (d < 0.001 or delta_position.normalized().dot(_facing) > 0.15):
			distance = d
			nearest = int(id)
	return nearest


func _physics_process(delta: float) -> void:
	if sim == null:
		return
	sim.tick(delta)
	for game_event in sim.drain_events():
		# Offline uses the identical authoritative strike event. Flash only on
		# an actual resolved impact, never on a forecast or warning disk.
		if str(game_event.get("type", "")) == "lightning_struck" and \
				_atmosphere != null and game_event.has("x") and game_event.has("z") and \
				not Dungeon.is_underground(survivor.position.x):
			var strike_xz := Vector2(float(game_event["x"]), float(game_event["z"]))
			if strike_xz.is_finite():
				var distance_m: float = Vector2(survivor.position.x,
					survivor.position.z).distance_to(strike_xz)
				_atmosphere.trigger_lightning(distance_m)
		if str(game_event.get("type", "")) == "camp_alarm" and (
				int(game_event.get("peer", -1)) == LOCAL_PLAYER_ID):
			_feedback = "CAMP ALERT: %d infected near your fire! Prepare defenses." % int(game_event.get("count", 0))
		elif str(game_event.get("type", "")) == "ruin_ambush" and \
				int(game_event.get("peer", -1)) == LOCAL_PLAYER_ID:
			_feedback = "RUIN AMBUSH! %d infected awakened. Fight or retreat!" % [
				int(game_event.get("count", 0))]
		elif str(game_event.get("type", "")) == "ruin_ambush_cleared" and \
				int(game_event.get("peer", -1)) == LOCAL_PLAYER_ID:
			_feedback = "RUIN SECURED! All %d awakened infected defeated." % [
				int(game_event.get("count", 0))]
	if sim.siege_waves_started > _last_siege_notification:
		_last_siege_notification = sim.siege_waves_started
		_feedback = "Night siege! Infected are approaching a nearby barricade."
	_update_world_light(delta)
	_ambient_motes.update_view(survivor.position, _visual_biome,
		_atmosphere.light_level, _atmosphere.storm, _visual_weather_wind,
		GraphicsQuality.level(), delta)
	_lightning_visual.set_warning(sim.lightning_pending)
	var movement := Input.get_vector("survive_left", "survive_right", "survive_up", "survive_down")
	if movement.length_squared() > 0.001:
		_facing = movement.normalized()
	_sequence += 1
	sim.submit_input(LOCAL_PLAYER_ID, _sequence, movement.x, movement.y,
			Input.is_action_pressed("survive_sprint"), atan2(_facing.x, _facing.y), delta,
			Input.is_action_pressed("survive_crouch"))
	_avatar.position = survivor.position + Vector3(0, 0.85, 0)
	_avatar.rotation.y = atan2(_facing.x, _facing.y)
	_avatar.scale = Vector3(1.0, 0.72 if survivor.crouching else 1.0, 1.0)
	_avatar.set_meta("aa_contact_shadow_alive", survivor.survival.alive)
	_avatar.set_meta("aa_contact_shadow_riding", survivor.mounted)
	var bike_speed := 0.0
	if _last_bike_position != Vector3.INF and delta > 0.0:
		bike_speed = Vector2(survivor.position.x - _last_bike_position.x,
			survivor.position.z - _last_bike_position.z).length() / delta
	_last_bike_position = survivor.position
	_bike_visual.set_panniers(survivor.inventory.count("bike_panniers") > 0)
	_bike_visual.set_lamp(survivor.mounted and survivor.survival.alive and
		survivor.bike_lamp_enabled and WorldCycle.is_night(sim.time) and
		survivor.inventory.count("bike_dynamo_lamp") > 0)
	_bike_visual.set_riding(survivor.mounted and survivor.survival.alive, bike_speed, delta)
	_flare_visual.set_burning(survivor.survival.alive and survivor.flare_seconds > 0.0)
	_camera.position = _camera.position.lerp(survivor.position + Vector3(0, 22, 27), minf(1.0, delta * 7.0))
	_camera.look_at(survivor.position + Vector3(0, 0.7, 0), Vector3.UP)
	# The offline preview has the same rain density and storm fade as online.
	RainVfx.update(_rain_vfx, _camera.global_position + Vector3(0.0, -2.0, 0.0), _atmosphere.storm)
	_stream_chunks()
	if _bank_open and not _can_use_bank():
		_bank_open = false
		_feedback = "Safe stash closed: return to the workbench."
	for item_id in _resource_meshes:
		_resource_meshes[item_id].visible = not sim.depleted.has(item_id)
	for item_id in _crate_meshes:
		_crate_meshes[item_id].visible = not sim.opened_crates.has(item_id)
	_sync_zombies()
	_sync_spit_warnings()
	_sync_acid_pools()
	_sync_ember_pools()
	_sync_barricades()
	_sync_campfires()
	_sync_shelters()
	_sync_smoke()
	_sync_fish_traps()
	_sync_decoys()
	_hud_clock += delta
	if _hud_clock > 0.15:
		_hud_clock = 0.0
		_update_hud()


func _nearest_node() -> Dictionary:
	var found: Dictionary = {}
	var distance: float = Defs.REACH + 0.5
	var cell: Vector2i = WorldGen.cell_of(survivor.position.x, survivor.position.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for node in world.chunk(Vector2i(cell.x + dx, cell.y + dz))["nodes"]:
				if sim.depleted.has(node["id"]):
					continue
				var d := Vector2(survivor.position.x - float(node["x"]), survivor.position.z - float(node["z"])).length()
				if d < distance:
					found = node
					distance = d
	return found


func _nearest_loot() -> Dictionary:
	var found: Dictionary = {}
	var distance: float = Defs.REACH + 0.5
	for bag in sim.bags.values():
		var d := Vector2(survivor.position.x - float(bag["x"]), survivor.position.z - float(bag["z"])).length()
		if d < distance:
			found = bag
			distance = d
	var cell: Vector2i = WorldGen.cell_of(survivor.position.x, survivor.position.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for crate in world.chunk(Vector2i(cell.x + dx, cell.y + dz))["crates"]:
				if sim.opened_crates.has(crate["id"]):
					continue
				var d := Vector2(survivor.position.x - float(crate["x"]), survivor.position.z - float(crate["z"])).length()
				if d < distance:
					found = crate
					distance = d
	return found


func _result(action: String, data: Dictionary) -> void:
	if bool(data.get("ok", false)):
		_feedback = "%s: SUCCESS" % action
	elif str(data.get("reason", "")) == "guards_alive":
		_feedback = "Supply crate guarded: defeat %d infected before looting." % int(data.get("remaining", 0))
	else:
		_feedback = "%s: %s" % [action, str(data.get("reason", "failed"))]
	_update_hud()


## The menu is local presentation only; inventory/stash are changed solely
## through the same authoritative GameServer command used by multiplayer RPC.
func _can_use_bank() -> bool:
	if survivor == null or not survivor.survival.alive:
		return false
	var point := Vector2(survivor.position.x, survivor.position.z)
	return point.distance_to(GameServer.WORKBENCH_POSITION) <= GameServer.WORKBENCH_RANGE


func _bank_items() -> Array[String]:
	var names: Array[String] = []
	for storage in [survivor.inventory, survivor.stash]:
		for slot in storage.slots:
			if slot.is_empty():
				continue
			var item_id: String = str(slot["id"])
			if not names.has(item_id):
				names.append(item_id)
	names.sort()
	return names


func _current_bank_item() -> String:
	var names: Array[String] = _bank_items()
	if names.is_empty():
		_selected_bank_item = ""
	elif not names.has(_selected_bank_item):
		_selected_bank_item = names[0]
	return _selected_bank_item


func _toggle_bank() -> bool:
	if _bank_open:
		_bank_open = false
	else:
		if not _can_use_bank():
			_feedback = "Safe stash is only available beside the hub workbench."
			_update_hud()
			return false
		_bank_open = true
		_current_bank_item()
	_update_hud()
	return _bank_open


func _next_bank_item() -> void:
	if not _bank_open or not _can_use_bank():
		return
	var names: Array[String] = _bank_items()
	if names.is_empty():
		return
	var selected: String = _current_bank_item()
	_selected_bank_item = names[(names.find(selected) + 1) % names.size()]
	_update_hud()


func _bank_transfer(deposit: bool, requested_count: int = 1) -> bool:
	if not _bank_open or not _can_use_bank():
		_feedback = "Open the stash (B) beside the hub workbench."
		_update_hud()
		return false
	var item_id: String = _current_bank_item()
	if item_id.is_empty() or requested_count <= 0:
		_feedback = "Select an item before transferring."
		_update_hud()
		return false
	var source = survivor.inventory if deposit else survivor.stash
	var count: int = mini(requested_count, mini(source.count(item_id), Defs.stack_size(item_id)))
	if count < 1:
		_feedback = "No %s available to %s." % [item_id, "deposit" if deposit else "withdraw"]
		_update_hud()
		return false
	var result: Dictionary = sim.cmd_stash(LOCAL_PLAYER_ID, item_id, count, deposit)
	_result("Deposit" if deposit else "Withdraw", result)
	return bool(result.get("ok", false))


func _update_bank_hud() -> void:
	_bank_panel.visible = _bank_open
	if not _bank_open:
		return
	var item_id: String = _current_bank_item()
	var lines: PackedStringArray = []
	for name in _bank_items():
		lines.append("%s  carried:%d  stored:%d" % [
			name, survivor.inventory.count(name), survivor.stash.count(name)])
		if lines.size() >= 7:
			break
	_bank_label.text = "SAFE HUB STASH | B close, J next, K store, L take (Shift: up to 10)\nSelected: %s  | carried %d | stored %d\n%s" % [
		item_id if not item_id.is_empty() else "(empty)",
		survivor.inventory.count(item_id) if not item_id.is_empty() else 0,
		survivor.stash.count(item_id) if not item_id.is_empty() else 0,
		"\n".join(lines) if not lines.is_empty() else "No items in inventory or stash"
	]


func _unhandled_input(event: InputEvent) -> void:
	# Modifier-aware quality switch; plain F11 keeps its medical-item binding.
	if event is InputEventKey and event.pressed and not event.echo and \
			event.keycode == KEY_F11 and event.ctrl_pressed:
		GraphicsQuality.cycle()
		GraphicsQuality.apply(get_viewport(), _atmosphere, null)
		RainVfx.apply_quality(_rain_vfx, GraphicsQuality.level())
		_feedback = "Graphics: %s (Ctrl+F11 to change)." % GraphicsQuality.get_name()
		_update_hud()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("survive_bank"):
		_toggle_bank()
	elif event.is_action_pressed("survive_bank_next"):
		_next_bank_item()
	elif event.is_action_pressed("survive_bank_deposit"):
		_bank_transfer(true, 10 if Input.is_key_pressed(KEY_SHIFT) else 1)
	elif event.is_action_pressed("survive_bank_withdraw"):
		_bank_transfer(false, 10 if Input.is_key_pressed(KEY_SHIFT) else 1)
	elif event.is_action_pressed("survive_gather"):
		var target := _nearest_node()
		if target.is_empty():
			_feedback = "No resource within reach."
		else:
			_result("Gather", sim.cmd_gather(LOCAL_PLAYER_ID, target["id"]))
	elif event.is_action_pressed("survive_recall"):
		_result("Return charm", sim.cmd_use(LOCAL_PLAYER_ID, "return_charm"))
	elif event.is_action_pressed("survive_loot"):
		if Input.is_key_pressed(KEY_SHIFT):
			var sweep: Dictionary = sim.cmd_loot_sweep(LOCAL_PLAYER_ID)
			_result("Nearby PvE pickup (%d items)" % int(sweep.get("items", 0)), sweep)
		else:
			var target := _nearest_loot()
			if target.is_empty():
				_feedback = "No nearby crate or loot bag."
			else:
				_result("Loot", sim.cmd_loot(LOCAL_PLAYER_ID, target["id"]))
	elif event.is_action_pressed("survive_mount"):
		_result("Trail bike", sim.cmd_toggle_mount(LOCAL_PLAYER_ID))
	elif event.is_action_pressed("survive_bike_lamp"):
		_result("Bike lamp", sim.cmd_use(LOCAL_PLAYER_ID, "bike_dynamo_lamp"))
	elif event.is_action_pressed("survive_bike_service"):
		_result("Drive service", sim.cmd_use(LOCAL_PLAYER_ID, "bike_service_kit"))
	elif event.is_action_pressed("survive_whetstone"):
		_result("Sharpen weapon", sim.cmd_use(LOCAL_PLAYER_ID, "field_whetstone"))
	elif event.is_action_pressed("survive_sighting_kit"):
		_result("Calibrate ranged weapon", sim.cmd_use(LOCAL_PLAYER_ID, "field_sighting_kit"))
	elif event.is_action_pressed("survive_armor_plate"):
		_result("Fit armor plate", sim.cmd_use(LOCAL_PLAYER_ID, "field_armor_plate"))
	elif event.is_action_pressed("survive_bike_repair"):
		_result("Frame repair", sim.cmd_use(LOCAL_PLAYER_ID, "bike_frame_patch"))
	elif event.is_action_pressed("survive_survey"):
		var result: Dictionary = sim.cmd_survey_ruins(LOCAL_PLAYER_ID)
		_result("Survey ruins", result)
		if bool(result.get("ok", false)):
			_feedback = "Ruin cache at X:%d Z:%d. Check radar (75s)." % [
				roundi(float(result["x"])), roundi(float(result["z"]))]
			_update_hud()
	elif event.is_action_pressed("survive_attack"):
		var attack_result: Dictionary = sim.cmd_attack(
			LOCAL_PLAYER_ID, _facing.x, _facing.y)
		_result("Attack", attack_result)
		if bool(attack_result.get("ambush", false)):
			_feedback = "Silent ambush: +45% damage against unaware infected"
	elif event.is_action_pressed("survive_skill"):
		if Input.is_key_pressed(KEY_SHIFT):
			_result("Stagger finisher", sim.cmd_stagger_finisher(LOCAL_PLAYER_ID))
		else:
			_result("Weapon Skill", sim.cmd_skill(LOCAL_PLAYER_ID, _facing.x, _facing.y))
	elif event.is_action_pressed("survive_parry"):
		_result("Parry", sim.cmd_parry(LOCAL_PLAYER_ID))
	elif event.is_action_pressed("survive_dodge"):
		var movement := Input.get_vector("survive_left", "survive_right", "survive_up", "survive_down")
		var direction: Vector2 = movement.normalized() if movement.length_squared() > 0.0001 else _facing
		_result("Dodge", sim.cmd_dodge(LOCAL_PLAYER_ID, direction.x, direction.y))
	elif event.is_action_pressed("survive_next_recipe"):
		if not _recipes.is_empty():
			var step: int = -1 if Input.is_key_pressed(KEY_SHIFT) else 1
			_recipe_index = posmod(_recipe_index + step, _recipes.size())
			_update_hud()
	elif event.is_action_pressed("survive_craft"):
		if not _recipes.is_empty():
			_result("Craft", sim.cmd_craft(LOCAL_PLAYER_ID, _recipes[_recipe_index]))
	elif event.is_action_pressed("survive_quick_cook"):
		if Input.is_key_pressed(KEY_ALT):
			var smoke_recipe: String = TrailRation.best_recipe(
				survivor.inventory, survivor.progression.crafting_level())
			if smoke_recipe.is_empty():
				_feedback = "Smoking: need fish, 2 matching wood, 1 fiber and skill."
			else:
				_result("Smoke trail fish", sim.cmd_craft(LOCAL_PLAYER_ID, smoke_recipe))
		elif Input.is_key_pressed(KEY_SHIFT):
			_result("Cook fish stew", sim.cmd_craft(LOCAL_PLAYER_ID, Defs.CAMP_FISH_STEW))
		else:
			var cook_recipe: String = QuickCooking.best_recipe(
				survivor.inventory, survivor.progression.crafting_level())
			if cook_recipe.is_empty():
				_feedback = "Cooking: need fish, matching wood and crafting mastery."
			else:
				_result("Quick cook", sim.cmd_craft(LOCAL_PLAYER_ID, cook_recipe))
	elif event.is_action_pressed("survive_food"):
		if Input.is_key_pressed(KEY_ALT) and Input.is_key_pressed(KEY_SHIFT):
			var carried_ration := ""
			for tier in range(Defs.MAX_TIER, 0, -1):
				var candidate: String = "smoked_fish" if tier == 1 else "smoked_fish_%d" % tier
				if survivor.inventory.count(candidate) > 0:
					carried_ration = candidate
					break
			if carried_ration == "":
				_feedback = "No smoked fish carried. Cook one with Alt+0 at a fire."
			else:
				_result("Eat smoked travel ration", sim.cmd_use(LOCAL_PLAYER_ID, carried_ration))
		elif Input.is_key_pressed(KEY_CTRL):
			_result("Smart food", sim.cmd_smart_provision(LOCAL_PLAYER_ID, "food"))
		elif Input.is_key_pressed(KEY_ALT):
			var raw_item := ""
			for tier in range(1, 5):
				var candidate: String = "raw_fish" if tier == 1 else "raw_fish_%d" % tier
				if survivor.inventory.count(candidate) > 0:
					raw_item = candidate
					break
			if raw_item == "":
				_feedback = "No raw fish carried. Properly cooked food is safer."
			else:
				_result("Raw fish (food poisoning risk)", sim.cmd_use(LOCAL_PLAYER_ID, raw_item))
		else:
			_result("Eat stew" if Input.is_key_pressed(KEY_SHIFT) else "Eat",
				sim.cmd_use(LOCAL_PLAYER_ID,
					Defs.CAMP_FISH_STEW if Input.is_key_pressed(KEY_SHIFT) else "canned_food"))
	elif event.is_action_pressed("survive_water"):
		if Input.is_key_pressed(KEY_CTRL):
			_result("Smart hydration", sim.cmd_smart_provision(LOCAL_PLAYER_ID, "drink"))
		elif Input.is_key_pressed(KEY_SHIFT):
			_result("Collect unboiled water", sim.cmd_use(LOCAL_PLAYER_ID, "empty_water_pouch"))
		else:
			_result("Drink", sim.cmd_use(LOCAL_PLAYER_ID, "water_bottle"))
	elif event.is_action_pressed("survive_bandage"):
		if Input.is_key_pressed(KEY_CTRL):
			var treatment: Dictionary = sim.cmd_quick_medicine(LOCAL_PLAYER_ID)
			var medicine_name: String = str(Defs.item(str(treatment.get("item", ""))).get("name", "none"))
			_result("Field medicine: " + medicine_name, treatment)
		elif Input.is_key_pressed(KEY_SHIFT):
			_result("Expedition trauma kit", sim.cmd_use(LOCAL_PLAYER_ID, "expedition_trauma_kit"))
		else:
			_result("Heal", sim.cmd_use(LOCAL_PLAYER_ID, "bandage"))
	elif event.is_action_pressed("survive_weapon"):
		_cycle_owned_weapon()
	elif event.is_action_pressed("survive_armor"):
		_result("Equip armor", sim.cmd_use(LOCAL_PLAYER_ID, "jacket_1"))
	elif event.is_action_pressed("survive_antiseptic"):
		if Input.is_key_pressed(KEY_SHIFT):
			_result("Coat melee weapon", sim.cmd_use(LOCAL_PLAYER_ID, "antiseptic_edge_oil"))
		else:
			_result("Clean wound", sim.cmd_use(LOCAL_PLAYER_ID, "field_antiseptic"))
	elif event.is_action_pressed("survive_antibiotics"):
		_result("Antibiotics", sim.cmd_use(LOCAL_PLAYER_ID, "antibiotics"))
	elif event.is_action_pressed("survive_poultice"):
		if Input.is_key_pressed(KEY_SHIFT):
			_result("Food poisoning treatment", sim.cmd_use(LOCAL_PLAYER_ID, "herbal_gut_tonic"))
		else:
			_result("Herbal poultice", sim.cmd_use(LOCAL_PLAYER_ID, "herbal_poultice"))
	elif event.is_action_pressed("survive_warmth"):
		_result("Heat pack", sim.cmd_use(LOCAL_PLAYER_ID, "thermal_wrap"))
	elif event.is_action_pressed("survive_flare"):
		_result("Ignite signal flare", sim.cmd_use(LOCAL_PLAYER_ID, "signal_flare"))
	elif event.is_action_pressed("survive_stim"):
		_result("Frontier stim", sim.cmd_use(LOCAL_PLAYER_ID, "frontier_stim"))
	elif event.is_action_pressed("survive_scent_mask"):
		if Input.is_key_pressed(KEY_SHIFT):
			_result("Apply soft-sole wraps", sim.cmd_use(LOCAL_PLAYER_ID, "soft_sole_wraps"))
		else:
			_result("Apply herbal scent salve", sim.cmd_use(LOCAL_PLAYER_ID, "herbal_scent_mask"))
	elif event.is_action_pressed("survive_spore_filter"):
		_result("Apply expedition spore filter", sim.cmd_use(LOCAL_PLAYER_ID, "spore_filter"))
	elif event.is_action_pressed("survive_lake"):
		if Input.is_key_pressed(KEY_CTRL):
			var boil: bool = Input.is_key_pressed(KEY_SHIFT)
			_result("Boil water" if boil else "Fill canteen",
				sim.cmd_refill_canteen(LOCAL_PLAYER_ID, boil))
		elif Input.is_key_pressed(KEY_SHIFT):
			var result: Dictionary = sim.cmd_use(LOCAL_PLAYER_ID, "field_alkali_kit")
			_result("Neutralize acid (%d pools)" % int(result.get("neutralized", 0)),
				result)
		else:
			var drink_result: Dictionary = sim.cmd_drink_water(LOCAL_PLAYER_ID)
			_result("Filtered lake water" if bool(drink_result.get("filtered", false)) else "Lake water (infection risk)", drink_result)
	elif event.is_action_pressed("survive_extinguish"):
		var fire_id: int = _nearest_campfire()
		if fire_id == -1:
			_feedback = "Extinguish: no fire nearby."
		else:
			_result("Extinguish campfire", sim.cmd_extinguish_campfire(LOCAL_PLAYER_ID, fire_id))
	elif event.is_action_pressed("survive_refuel"):
		if Input.is_key_pressed(KEY_SHIFT):
			_result("Weatherproof campfire", sim.cmd_use(LOCAL_PLAYER_ID, "stormproof_briquette"))
		else:
			var fire_id: int = _nearest_campfire()
			if fire_id == -1:
				_feedback = "Refuel: no campfire within 3 metres."
			else:
				_result("Refuel campfire", sim.cmd_refuel_campfire(LOCAL_PLAYER_ID, fire_id))
	elif event.is_action_pressed("survive_smoke"):
		_result("Smoke charge", sim.cmd_use(LOCAL_PLAYER_ID, FieldSmoke.ITEM_ID))
	elif event.is_action_pressed("survive_decoy"):
		_result("Throw noise decoy", sim.cmd_throw_decoy(LOCAL_PLAYER_ID, _facing.x, _facing.y))
	elif event.is_action_pressed("survive_ember"):
		_result("Throw ember flask", sim.cmd_throw_ember(LOCAL_PLAYER_ID, _facing.x, _facing.y))
	elif event.is_action_pressed("survive_snare"):
		var site := Vector2(survivor.position.x, survivor.position.z) + _facing * 2.8
		_result("Place infected snare", sim.cmd_place_infected_snare(LOCAL_PLAYER_ID, site.x, site.y))
	elif event.is_action_pressed("survive_shelter"):
		var point := Vector2(survivor.position.x, survivor.position.z) + _facing * 2.8
		_result("Pitch tarp", sim.cmd_pitch_shelter(LOCAL_PLAYER_ID, point.x, point.y))
	elif event.is_action_pressed("survive_pack_shelter"):
		var nearest := -1
		var closest := PortableShelter.PACK_RANGE * PortableShelter.PACK_RANGE
		for tarp in sim.shelters.values():
			var d2: float = Vector2(survivor.position.x, survivor.position.z).distance_squared_to(
				Vector2(float(tarp["x"]), float(tarp["z"])))
			if d2 <= closest:
				closest = d2
				nearest = int(tarp["id"])
		if nearest < 0:
			_feedback = "No nearby tarp to pack."
		else:
			_result("Pack tarp", sim.cmd_pack_shelter(LOCAL_PLAYER_ID, nearest))
	elif event.is_action_pressed("survive_campfire"):
		if Input.is_key_pressed(KEY_SHIFT):
			var fire_id: int = _nearest_campfire()
			_result("Arm camp alarm",
				sim.cmd_arm_camp_alarm(LOCAL_PLAYER_ID, fire_id))
		else:
			var point := Vector2(survivor.position.x, survivor.position.z) + _facing * 2.8
			var fire_result: Dictionary = sim.cmd_light_campfire(LOCAL_PLAYER_ID, point.x, point.y)
			_result("Light campfire", fire_result)
			if bool(fire_result.get("ok", false)):
				_feedback = "Campfire lit. At night its light attracts infected. Press - to extinguish."
				_update_hud()
	elif event.is_action_pressed("survive_build"):
		var point := Vector2(survivor.position.x, survivor.position.z) + _facing * 2.8
		_result("Build barricade", sim.cmd_build(LOCAL_PLAYER_ID, point.x, point.y))
	elif event.is_action_pressed("survive_repair"):
		var wall_id := _nearest_barricade()
		if wall_id == -1:
			_feedback = "Repair: aim toward a nearby barricade"
		else:
			_result("Repair barricade", sim.cmd_repair(LOCAL_PLAYER_ID, wall_id))
	elif event.is_action_pressed("survive_upgrade"):
		var wall_id := _nearest_barricade()
		if wall_id == -1:
			_feedback = "Upgrade: aim toward your nearby barricade"
		else:
			_result("Upgrade barricade", sim.cmd_upgrade(LOCAL_PLAYER_ID, wall_id))
		_update_hud()
	elif event.is_action_pressed("survive_dismantle"):
		var wall_id := _nearest_barricade()
		if wall_id == -1:
			_feedback = "Dismantle: aim toward your nearby barricade"
		else:
			_result("Dismantle barricade", sim.cmd_dismantle(LOCAL_PLAYER_ID, wall_id))

	elif event.is_action_pressed("survive_place_fish_trap"):
		_result("Place fish trap", sim.cmd_place_fish_trap(LOCAL_PLAYER_ID))
	elif event.is_action_pressed("survive_collect_fish_trap"):
		var closest_id := -1
		var best_distance := 4.5 * 4.5
		for trap in sim.fish_traps.values():
			var d2: float = Vector2(survivor.position.x, survivor.position.z).distance_squared_to(
				Vector2(float(trap["x"]), float(trap["z"])))
			if d2 <= best_distance:
				closest_id = int(trap["id"])
				best_distance = d2
		if closest_id < 0:
			_feedback = "No shoreline fish trap within reach."
		else:
			_result("Collect fish trap", sim.cmd_collect_fish_trap(LOCAL_PLAYER_ID, closest_id))
	elif event.is_action_pressed("survive_fish"):
		var storm_mode: bool = Input.is_key_pressed(KEY_ALT)
		var wants_bait: bool = Input.is_key_pressed(KEY_SHIFT) and not storm_mode
		_result("Storm cast" if storm_mode else (
			"Baited cast" if wants_bait else "Cast fishing rod"),
			sim.cmd_fish(LOCAL_PLAYER_ID, wants_bait, storm_mode))
	elif event.is_action_pressed("survive_contract"):
		var action := "daily_claim" if Input.is_key_pressed(KEY_CTRL) else ("claim" if Input.is_key_pressed(KEY_SHIFT) else "accept")
		var response: Dictionary = sim.cmd_contract(LOCAL_PLAYER_ID, action)
		_feedback = ("Contract: %s" % str(response.get("title", response.get("reason", "updated"))))
	elif event.is_action_pressed("survive_radar"):
		_radar.visible = not _radar.visible
	elif event.is_action_pressed("survive_rest"):
		_result("Camp rest", sim.cmd_rest(LOCAL_PLAYER_ID))
	elif event.is_action_pressed("survive_vendor_buy"):
		_result("Buy water (%d silver)" % PvpInfamy.vendor_unit_price(
			Reputation.buy_price(int(Vendor.BUY_PRICES["water_bottle"]), 1,
				survivor.renown), survivor.pvp_infamy, true),
			sim.cmd_vendor(LOCAL_PLAYER_ID, "water_bottle", 1, true))
	elif event.is_action_pressed("survive_vendor_sell"):
		var fish_only: bool = Input.is_key_pressed(KEY_SHIFT)
		var salvage_id: String = Vendor.first_fish(survivor.inventory) if fish_only else Vendor.first_sellable(survivor.inventory)
		if salvage_id.is_empty():
			_feedback = "No raw fish to sell." if fish_only else "No materials for sale."
		else:
			_result("Sell %s" % salvage_id, sim.cmd_vendor(LOCAL_PLAYER_ID, salvage_id, 1, false))


## Cycle all physically carried weapons, including freshly crafted spears.
## The actual equipment change still runs through GameServer.cmd_use.
func _cycle_owned_weapon() -> void:
	var owned: Array[String] = []
	for item_id in Defs.items():
		var item: Dictionary = Defs.item(str(item_id))
		if str(item.get("kind", "")) == "weapon" and survivor.inventory.count(str(item_id)) > 0:
			owned.append(str(item_id))
	owned.sort()
	if owned.is_empty():
		_feedback = "No crafted or scavenged weapon in inventory."
		return
	var current_index: int = owned.find(survivor.inventory.weapon)
	var next_weapon: String = owned[(current_index + 1) % owned.size()]
	_result("Equip %s" % str(Defs.item(next_weapon).get("name", next_weapon)),
		sim.cmd_use(LOCAL_PLAYER_ID, next_weapon))


func _update_hud() -> void:
	if survivor == null:
		return
	var vitals = survivor.survival
	var position: Vector3 = survivor.position
	var zone: int = world.zone_at(position.x, position.z)
	var rows: PackedStringArray = []
	for slot in survivor.inventory.slots:
		if not slot.is_empty():
			rows.append("%s:%d" % [str(slot["id"]), int(slot["count"])])
	var levels: Dictionary = survivor.progression.levels()
	var weight: float = survivor.inventory.total_weight()
	var speed_pct: int = int(round(BikeCargo.movement_factor(survivor.inventory,
		survivor.skills.bonus("carry_capacity"), survivor.mounted) * 100.0))
	var risk: String = "SAFE HUB" if world.is_safe(position.x, position.z) else ZoneRisk.description(zone)
	var weather: Dictionary = Weather.conditions(world, position.x, position.z, sim.time)
	var rain_grip: float = StormMud.factor(world, position, sim.time, survivor.mounted)
	_stats.text = "ALBION AFTER | SURVIVAL SANDBOX\n%s | World clock %.0fs\nHP %d HUNGER %d THIRST %d STAMINA %d INFECTION %d BLEEDING %d EXPOSURE %d KILLS %d\nCOMBAT ENERGY %d/%d SKILL CD %.1fs DODGE CD %.1fs WEAPON %s\nWEATHER %s %.0fC %s | HEAT PACK %ds%s\nZONE %s (T%d) %s POS %d,%d ZOMBIES %d\nPROFESSIONS Wood T%d Stone T%d Ore T%d Fiber T%d Fish T%d Craft T%d Scavenge T%d\nWEAPON MASTERY Melee L%d Ranged L%d\nCARRY %.1f kg MOVEMENT %d%% SILVER %d\nCONTRACT %s\nINVENTORY %s" % [
		"NIGHT - infected notice farther" if WorldCycle.is_night(sim.time) else "DAY", sim.time,
		int(vitals.health), int(vitals.hunger), int(vitals.thirst), int(vitals.stamina),
		int(vitals.infection), int(vitals.bleeding), int(vitals.exposure), survivor.kills,
		int(survivor.combat_energy), int(Defs.COMBAT_ENERGY_MAX), survivor.skill_timer, survivor.dodge_timer,
		survivor.inventory.weapon if not survivor.inventory.weapon.is_empty() else "unarmed",
		str(weather.get("condition", "unknown")).capitalize(), float(weather.get("temperature_c", 0.0)),
		"CAMPFIRE WARMTH" if FieldCampfire.has_warmth(sim.campfires, position, sim.time) else (
			"FIELD TARP" if PortableShelter.covers(sim.shelters, position, sim.time) else (
			"SHELTERED" if bool(weather.get("sheltered", false)) else "EXPOSED")),
		int(ceil(vitals.warmth_seconds)),
		" | STORM COVER: infected sight -30%" if Weather.sight_multiplier(weather) < 1.0 else "",
		Defs.ZONE_NAMES[zone], WorldGen.tier_for_zone(zone), risk, int(position.x), int(position.z), sim.zombies.size(),
		int(levels["wood"]), int(levels["stone"]), int(levels["ore"]), int(levels["fiber"]),
		int(levels.get("fishing", 1)),
		survivor.progression.crafting_level(), survivor.progression.scavenging_level(),
		survivor.progression.combat_level("melee"), survivor.progression.combat_level("ranged"),
		weight, speed_pct, survivor.inventory.count("silver"),
		Contracts.description(survivor.contract_state), ", ".join(rows)
	]
	if survivor.rested_xp_credit > 0:
		_stats.text += "\nRESTED TRAINING: %d bonus XP left (Z to rest at camp)" % survivor.rested_xp_credit
	if survivor.sharpened_hits > 0:
		_stats.text += "\nSHARPENED: %d infected melee hits left (End)" % survivor.sharpened_hits
	if survivor.sighted_hits > 0:
		_stats.text += "\nSIGHTED: %d infected ranged hits left (Delete)" % survivor.sighted_hits
	if survivor.wedge_charges > 0:
		_stats.text += "\nMINING WEDGES: %d rich ore/stone harvests left (+2, loud)" % survivor.wedge_charges
	if survivor.plated_hits > 0:
		_stats.text += "\nARMOR PLATE: %d infected claw hits left (Insert)" % survivor.plated_hits
	if not sim.lightning_pending.is_empty():
		var strike: Dictionary = sim.lightning_pending
		var danger_at := Vector2(float(strike["x"]), float(strike["z"]))
		var personal_distance: float = Vector2(position.x, position.z).distance_to(danger_at)
		_stats.text += "\nLIGHTNING: %.1fs — %s" % [
			maxf(0.0, float(strike["at"]) - sim.time),
			"MOVE OR DODGE!" if personal_distance <= StormLightning.RADIUS else
			("strike %dm away" % roundi(personal_distance))]
	if not survivor.recall.is_empty():
		_stats.text += "\nRETURN CHARM: %.1fs — stay still" % maxf(
			0.0, float(survivor.recall["until"]) - sim.time)
	elif survivor.recall_ready_at > sim.time:
		_stats.text += "\nRETURN CHARM COOLDOWN: %.0fs" % (survivor.recall_ready_at - sim.time)
	var map_point: Dictionary = RuinSurvey.public_mark(
		survivor.ruin_survey, sim.time, sim.opened_crates)
	if not map_point.is_empty():
		var dest := Vector2(float(map_point["x"]), float(map_point["z"]))
		_stats.text += "\nRUIN CHART: X:%d Z:%d | %dm | %ds (F3)" % [
			roundi(dest.x), roundi(dest.y), roundi(Vector2(position.x, position.z).distance_to(dest)),
			ceili(float(map_point["remaining"]))]
	if RoadTravel.on_road(world, position):
		_stats.text += "\nDIRT ROAD: +8%% foot pace; stable bicycle grip"
	if survivor.inventory.count("salvage_bike") > 0:
		_stats.text += "\nBIKE SERVICE: %.0f m (PgUp applies kit on foot)" % survivor.bike_service_meters
		_stats.text += "\nBIKE FRAME: %.0f%% (PgDn to patch on foot)" % survivor.bike_integrity
		if survivor.inventory.count("bike_dynamo_lamp") > 0:
			_stats.text += "\nDYNAMO LAMP: %s | [ toggles night light" % ("ARMED" if survivor.bike_lamp_enabled else "OFF")
	_stats.text += "\nTRAIL BIKE: %s | remount %.1fs (F4)" % [
		"RIDING" if survivor.mounted else ("CARRIED" if survivor.inventory.count("salvage_bike") > 0 else "NOT OWNED"),
		survivor.mount_cooldown]
	if not survivor.mounted and survivor.inventory.count("trail_backpack_2") > 0:
		_stats.text += "\nTRAIL PACK: +14 kg on foot, still full-loot"
	if survivor.mounted:
		if survivor.inventory.count("bike_panniers") > 0:
			_stats.text += "\nBIKE PANNIERS: 28 kg supported; dismount = full load"
		_stats.text += "\nBIKE GROUND: %s | uphill slows pedaling" % world.biome_at(
			position.x, position.z).to_upper()
	if sim.raid_boss_id > 0:
		var raid_boss = sim.zombies.get(sim.raid_boss_id)
		if raid_boss != null and raid_boss.is_alive() and \
				raid_boss.position.distance_to(survivor.position) <= 72.0:
			var live_guards: int = RaidWard.living_count(raid_boss,
				sim.raid_boss_id, sim.raid_minions, sim.zombies)
			if live_guards > 0:
				_stats.text += "\nRAID WARD: %d guards alive (-%d%% boss damage)" % [
					live_guards, RaidWard.reduction_percent(live_guards)]
	if not sim.night_horde.is_empty():
		var remain: int = 0
		for enemy_id in sim.night_horde.get("ids", []):
			var member = sim.zombies.get(int(enemy_id))
			if member != null and member.is_alive():
				remain += 1
		_stats.text += "\nNIGHT HORDE: %d infected remaining; %ds left to clear" % [
			remain, ceili(maxf(0.0, float(sim.night_horde["expires"]) - sim.time))]
	_stats.text += "\nCARTOGRAPHY: %d island landmarks visited" % survivor.discovered_sites.size()
	var nearby_offer: Dictionary = RegionalTrade.public_offer(world, position)
	if not nearby_offer.is_empty():
		_stats.text += "\nREGIONAL TRADE: %s buys %s +%d%%" % [
			str(nearby_offer["name"]), str(nearby_offer["category"]),
			int(nearby_offer["premium_percent"])]
	if survivor.flare_seconds > 0.0:
		_stats.text += "\nFLARE: %ds (F2) | infected notice up to 28m" % ceili(survivor.flare_seconds)
	_stats.text += "\nWET CLOTHING: %d%% | dry under shelter or beside a lit campfire" % roundi(survivor.survival.wetness)
	var wading: float = WadingWetness.depth_at(world, position)
	if wading > 0.0:
		_stats.text += "\nWADING: %.1f m deep | slowed travel; deep water blocks sprint" % wading
	if rain_grip < 0.999:
		_stats.text += "\nSTORM MUD: ground travel -%.0f%% | follow roads for traction" % [
			(1.0 - rain_grip) * 100.0]
	if not sim.smoke_clouds.is_empty():
		var smoke_wind: Vector2 = Weather.wind_at(world, position.x, position.z, sim.time)
		_stats.text += "\nSMOKE WIND: %.1f m/s | smoke clouds drift with the wind" % smoke_wind.length()
	for bag in sim.bags.values():
		if not CorpseScent.active(bag, sim.time):
			continue
		var offset := Vector2(float(bag["x"]) - position.x,
			float(bag["z"]) - position.z)
		if offset.length_squared() <= CorpseScent.RADIUS * CorpseScent.RADIUS:
			_stats.text += "\nFRESH CORPSE: blood attracts infected within 22 m"
			break
	var equipped_ammo: String = str(Defs.item(survivor.inventory.weapon).get("ammo", ""))
	if not equipped_ammo.is_empty():
		_stats.text += "\nARROWS / AMMO: %s ×%d" % [
			str(Defs.item(equipped_ammo).get("name", equipped_ammo)),
			survivor.inventory.count(equipped_ammo)]
	if survivor.meal_seconds > 0.0:
		_stats.text += "\nPREPARED MEAL T%d: %.0fs | +%.1f stamina/s, +%.2f energy/s" % [
			survivor.meal_tier, survivor.meal_seconds,
			HeartyMeal.stamina_per_second(survivor.meal_tier),
			HeartyMeal.energy_per_second(survivor.meal_tier)]
	if survivor.edge_coating_seconds > 0.0:
		_stats.text += "\nANTISEPTIC EDGE %s: %.0fs | +20%% vs ordinary/elite infected" % [
			survivor.edge_coating_weapon, survivor.edge_coating_seconds]
	var local_armor: String = survivor.inventory.armor
	if local_armor != "" and survivor.inventory.count(local_armor) <= 0:
		local_armor = ""
	_stats.text += "\nSTORM INSULATION %d%% | %s" % [
		int(round(100.0 * Weather.protection(local_armor))),
		str(Defs.item(local_armor).get("name", "No armor"))]
	var gust: Dictionary = WindChill.visible(world, position, sim.time,
		vitals.wetness, local_armor,
		FieldCampfire.has_warmth(sim.campfires, position, sim.time),
		PortableShelter.covers(sim.shelters, position, sim.time))
	if float(gust.get("extra", 0.0)) > 0.0:
		_stats.text += "\nWIND CHILL: %.1f m/s | +%.0f%% cold exposure intensity" % [
			float(gust.get("speed", 0.0)), 100.0 * float(gust["extra"])]
	var visual: float = sim._visual_signature_for(survivor)
	if PortableShelter.camouflaged(sim.shelters, survivor.position, sim.time,
			survivor.crouching, survivor.noise_timer, vitals.alive):
		_stats.text += "\nCANOPY CAMOUFLAGE: -25% infected sight; sound and scent still reveal"
	if visual < 0.999:
		_stats.text += "\nSTEALTH STANCE / GEAR / TARP: infected vision -%d%% (noise/blood still reveal you)" % [
			int(round(100.0 * (1.0 - visual)))]
	elif float(Defs.item(local_armor).get("visual_signature", 1.0)) < 1.0 and survivor.noise_timer > 0.0:
		_stats.text += "\nCAMOUFLAGE BROKEN: your noise is attracting infected"
	_stats.text += "\nUTC DAILY BOUNTY: " + DailyBounties.description(survivor.daily_bounty, DailyBounties.utc_day())
	_stats.text += "\nSURVIVOR RENOWN %s %d / %d | Hub supply discount %d%%" % [
		Reputation.title(survivor.renown), survivor.renown,
		Reputation.next_threshold(survivor.renown),
		Reputation.discount_percent(survivor.renown)]
	var recipe_id: String = _recipes[_recipe_index] if not _recipes.is_empty() else "bandage"
	var recipe: Dictionary = Defs.recipes().get(recipe_id, {})
	var near_bench: bool = Vector2(position.x, position.z).distance_to(GameServer.WORKBENCH_POSITION) < GameServer.WORKBENCH_RANGE
	var nearby_fire: bool = FieldCampfire.has_warmth(sim.campfires, position, sim.time)
	var station_status: String = "WORKBENCH" if near_bench else "workbench at x=9, z=0"
	if recipe.get("station", "") == "campfire":
		station_status = "FIRE READY" if nearby_fire else ("WORKBENCH" if near_bench else "need lit fire or workbench")
	_instructions.text = "WASD move | Shift sprint | Ctrl crouch | F6 tarp | F7 pack tarp | E gather | Q loot / Shift+Q nearby PvE bags | F attack | G skill / Shift+G finisher | Space dodge | F8 parry | F9 smoke | U build | O campfire | , noise decoy | \\ infected snare | . stimulant | / scent salve | ; spore filter | 9 refuel | 0 cook fish / Shift+0 cook stew | Shift+1 eat stew | - extinguish | H repair | Y upgrade | X dismantle\nTab / Shift+Tab recipes | C craft | B stash | 1 food / Ctrl+1 smart food 2 water / Ctrl+2 smart drink 3 heal / Ctrl+3 smart treatment / Shift+3 trauma kit 4 cycle weapon 5 armor 6 antiseptic / Shift+6 coat melee 7 antibiotics 8 heat pack R lake / Shift+R acid neutralizer / Ctrl+R fill canteen (1 filter) / Ctrl+Shift+R boil (2 wood, live fire)\nN buy water / V sell materials / Shift+V sell fish | T fish / Shift+T baited fish near shore | F2 signal flare / F10 net / F12 collect net | P accept / Shift+P turn in / Ctrl+P daily bounty (hub)\nCRAFT %s -> %s x%d | %s | inputs %s\n%s" % [
		recipe_id, str(recipe.get("output", "")), int(recipe.get("count", 0)),
		station_status,
		str(recipe.get("inputs", {})), _feedback
	]
	var fishing_status: String = FishingDisplay.progress(survivor.action)
	if not fishing_status.is_empty():
		_instructions.text += "\n" + fishing_status
	_instructions.text += "\nM tactical radar: red infected, yellow resources, green loot, gold defenses"
	_instructions.text += "\nF11 herbal poultice: treat wounds and mild infection; herbs grow in forest/swamp"
	_instructions.text += "\nHarvest sound: trees 25m, stone 24m, ore 28m; crouched bushes/berries are quiet"
	_instructions.text += "\nF4 ride / dismount crafted Trail Bike (workbench T2; no combat or gathering while riding)"
	_instructions.text += "\nField snares active: %d | roots first non-boss infected for 3s" % sim.infected_snares.size()
	var scent_radius: float = BloodScent.detection_radius(survivor.survival.bleeding,
		survivor.survival.alive, world.is_safe(survivor.position.x, survivor.position.z),
		survivor.survival.scent_mask_seconds > 0.0)
	if survivor.survival.scent_mask_seconds > 0.0:
		_instructions.text += "\nHERBAL SCENT MASK: %.0fs remaining; infected still see and hear you" % survivor.survival.scent_mask_seconds
	if survivor.soft_sole_seconds > 0.0:
		_instructions.text += "\nSOFT-SOLE WRAPS: %.0fs; quieter sprint, gunshots and bikes stay loud (Shift+/)" % survivor.soft_sole_seconds
	if scent_radius > 0.0:
		_instructions.text += "\nBLOOD SCENT: infected may track you from %d m; use first aid" % ceili(scent_radius)
	_instructions.text += "\nZ rest at hub (2 wood + canned food + water), or by a lit field fire (cooked fish/ration + water; no nearby enemies); 90s cooldown, remaining %.0fs" % survivor.rest_cooldown
	_instructions.text += "\nStimulant recharge: %.0fs" % survivor.stim_cooldown
	if survivor.spore_filter_seconds > 0.0:
		_instructions.text += "\nSPORE FILTER: %.0fs left; protects against airborne swamp spores" % survivor.spore_filter_seconds
	_instructions.text += "\nPvP infamy: %d/100 | %s" % [
		ceili(survivor.pvp_infamy), "OUTLAW" if PvpInfamy.is_outlaw(survivor.pvp_infamy) else "neutral"]
	_update_bank_hud()
