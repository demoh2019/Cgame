# Reusable 3D vertical slice for Cgame.
# Uses only stock Godot runtime APIs plus the native AdaptiveResolution3D node in world.tscn.
extends Node3D

const TerrainHeight = preload("res://scripts/terrain_height.gd")
const GameSave = preload("res://scripts/game_save.gd")
const QuestNavigation = preload("res://scripts/quest_navigation.gd")
const ForestEncounters = preload("res://scripts/forest_encounters.gd")
const StreamingTravel = preload("res://scripts/streaming_travel.gd")
const AtmosphereCycle = preload("res://scripts/atmosphere_cycle.gd")
const WORLD_EXTENT: float = 64.0
const GRID_SEGMENTS: int = 112
const CHUNK_EDGE: float = 32.0
const CRYSTAL_TOTAL: int = 8

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var camera: Camera3D
var player: CharacterBody3D
var world_environment: Environment
var sky_material: ShaderMaterial
var sun_light: DirectionalLight3D
var atmosphere_clock # Script-backed Node; keep dynamic type for controller-specific API.
var hud: Label
var hint: Label
var world_partition: WorldPartition3D
var encounters: Node3D
var travel_controller # Script-backed travel node with progress/status API.
var defeated_mobs: Array[String] = []
var player_health: int = 100
var player_hit_grace: float = 0.0
var current_region: Vector2i = Vector2i.ZERO
var crystals: Array[Node3D] = []
var collected_ids: Array[int] = []
var quest_target: Node3D
var quest_marker: MeshInstance3D
var quest_target_id: int = -1

var elapsed: float = 0.0
var hud_elapsed: float = 0.0
var collected: int = 0
var high_quality: bool = true
var predictive_streaming: bool = true
var distance_lod_enabled: bool = true
var mouse_sensitivity: float = 0.0018


func _ready() -> void:
    rng.seed = 913481
    _create_environment()
    _create_sun()
    _create_atmosphere_clock()
    _create_terrain()
    _create_world_boundaries()
    _create_crystals()
    _create_camera()
    _create_hud()
    _create_streaming_world()
    _load_game()
    _create_quest_marker()
    _refresh_quest_target(true)
    _create_encounter_director()
    _create_travel_controller()
    _apply_quality(high_quality)
    _refresh_hud()


func height_at(x: float, z: float) -> float:
    return TerrainHeight.height_at(x, z)


func _normal_at(x: float, z: float) -> Vector3:
    return TerrainHeight.normal_at(x, z)


func _create_environment() -> void:
    sky_material = ShaderMaterial.new()
    sky_material.shader = preload("res://shaders/atmosphere.gdshader")

    var sky := Sky.new()
    sky.sky_material = sky_material

    world_environment = Environment.new()
    world_environment.background_mode = Environment.BG_SKY
    world_environment.sky = sky
    world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    world_environment.tonemap_mode = Environment.TONE_MAPPER_AGX
    world_environment.tonemap_agx_white = 6.0
    world_environment.glow_enabled = true
    world_environment.glow_intensity = 0.35
    world_environment.fog_enabled = true
    world_environment.fog_density = 0.009
    world_environment.volumetric_fog_density = 0.015

    var node := WorldEnvironment.new()
    node.name = "SkyAndAtmosphere"
    node.environment = world_environment
    add_child(node)

    # This sample is intended for the Forward+ rendering backend.
    get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
    get_viewport().scaling_3d_scale = 1.0


func _create_sun() -> void:
    sun_light = DirectionalLight3D.new()
    sun_light.name = "DynamicSun"
    sun_light.rotation_degrees = Vector3(-38.0, -43.0, 0.0)
    sun_light.light_color = Color(1.0, 0.78, 0.58)
    sun_light.light_energy = 1.35
    sun_light.shadow_enabled = true
    add_child(sun_light)


func _create_atmosphere_clock() -> void:
    atmosphere_clock = AtmosphereCycle.new()
    atmosphere_clock.name = "AtmosphereClock"
    add_child(atmosphere_clock)
    atmosphere_clock.configure(sun_light, world_environment, sky_material)


func _create_terrain() -> void:
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    var uvs := PackedVector2Array()
    var indices := PackedInt32Array()

    var stride: int = GRID_SEGMENTS + 1
    var step: float = WORLD_EXTENT * 2.0 / float(GRID_SEGMENTS)
    for z in range(stride):
        for x in range(stride):
            var px: float = -WORLD_EXTENT + float(x) * step
            var pz: float = -WORLD_EXTENT + float(z) * step
            var y: float = height_at(px, pz)
            var normal: Vector3 = _normal_at(px, pz)
            vertices.push_back(Vector3(px, y, pz))
            normals.push_back(normal)
            uvs.push_back(Vector2(float(x), float(z)) * 0.08)
            var slope: float = clampf(1.0 - normal.y, 0.0, 1.0)
            var variation: float = 0.5 + 0.5 * sin(px * 0.12 + pz * 0.09)
            var soil := Color(0.21, 0.20, 0.13)
            var moss := Color(0.16, 0.27, 0.13)
            colors.push_back(moss.lerp(soil, clampf(slope * 2.8 + variation * 0.12, 0.0, 1.0)))

    for z in range(GRID_SEGMENTS):
        for x in range(GRID_SEGMENTS):
            var i: int = z * stride + x
            # Counterclockwise winding from above (+Y); normal agrees with height derivative.
            indices.push_back(i)
            indices.push_back(i + stride)
            indices.push_back(i + 1)
            indices.push_back(i + 1)
            indices.push_back(i + stride)
            indices.push_back(i + stride + 1)

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var material := StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.roughness = 0.97
    mesh.surface_set_material(0, material)

    var terrain := MeshInstance3D.new()
    terrain.name = "Terrain_Heightfield"
    terrain.mesh = mesh
    terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(terrain)

    # Use exactly the same mesh for physical ground and visible terrain.
    # Trimesh collision is appropriate for static terrain, never dynamic bodies.
    var terrain_body := StaticBody3D.new()
    terrain_body.name = "TerrainCollision"
    terrain_body.collision_layer = 1
    terrain_body.collision_mask = 0
    var terrain_shape := CollisionShape3D.new()
    terrain_shape.shape = mesh.create_trimesh_shape()
    terrain_body.add_child(terrain_shape)
    add_child(terrain_body)


func _create_world_boundaries() -> void:
    # Keep physics movement on the finite demo heightfield without teleporting.
    var boundary := StaticBody3D.new()
    boundary.name = "WorldBoundsCollision"
    boundary.collision_layer = 1
    boundary.collision_mask = 0
    var half: float = WORLD_EXTENT + 0.4
    var walls: Array[Vector3] = [
        Vector3(-half, 2.0, 0.0),
        Vector3(half, 2.0, 0.0),
        Vector3(0.0, 2.0, -half),
        Vector3(0.0, 2.0, half)
    ]
    for i in range(walls.size()):
        var shape := BoxShape3D.new()
        shape.size = Vector3(0.8, 16.0, WORLD_EXTENT * 2.0 + 2.0) if i < 2 \
            else Vector3(WORLD_EXTENT * 2.0 + 2.0, 16.0, 0.8)
        var collision := CollisionShape3D.new()
        collision.shape = shape
        collision.position = walls[i]
        boundary.add_child(collision)
    add_child(boundary)


func _create_streaming_world() -> void:
    # Stream each 32m patch around the camera using the fork's native C++ module.
    # The same PackedScene path serves every cell; WorldPartition3D shares the
    # threaded resource request, sets the root offset, then triggers _ready().
    world_partition = WorldPartition3D.new()
    world_partition.name = "WorldPartition_32m"
    world_partition.cell_size = CHUNK_EDGE
    # Two rings of streamed cells: full-detail near, low-cost silhouettes far.
    world_partition.load_radius = 2
    world_partition.unload_radius = 3
    world_partition.detail_radius = 1
    world_partition.detail_hysteresis_cells = 1
    world_partition.max_detail_transitions_per_frame = 2
    # Keep distant geometry resident, but do not activate AI/simulation in
    # remote quest, fast-travel or prediction cells before the player arrives.
    world_partition.simulation_radius = 1
    world_partition.simulation_hysteresis_cells = 1
    world_partition.max_simulation_transitions_per_frame = 2
    # Stream full visual cells farther than their foliage collision radius.
    # Priority-2/3 sources activate destination collision before teleport.
    world_partition.physics_radius = 1
    world_partition.physics_hysteresis_cells = 1
    world_partition.max_physics_transitions_per_frame = 2
    world_partition.max_navigation_updates_per_physics_frame = 2 # At most two expensive NPC steering recalculations per tick.
    world_partition.min_physics_frames_after_load = 2 # Allow a physics tick barrier before F10/F11 travel.
    world_partition.max_new_requests_per_frame = 2
    world_partition.max_instances_per_frame = 1
    world_partition.max_concurrent_requests = 4
    # Preload one likely next cell while sprinting, after normal visible requests.
    world_partition.predictive_lookahead_seconds = 2.5
    world_partition.predictive_max_distance = 28.0
    add_child(world_partition)
    world_partition.observer_path = world_partition.get_path_to(player)
    world_partition.cell_loaded.connect(_on_stream_cell_loaded)
    world_partition.cell_detail_changed.connect(_on_cell_detail_changed)
    world_partition.cell_simulation_changed.connect(_on_cell_simulation_changed)
    world_partition.cell_physics_changed.connect(_on_cell_physics_changed)
    world_partition.observer_cell_changed.connect(_on_observer_cell_changed)

    for cz in range(-2, 2):
        for cx in range(-2, 2):
            world_partition.set_cell_scene(
                Vector2i(cx, cz), "res://cells/forest_cell.tscn")
    # The home-clearing cell is a persistent hub and survives camera travel.
    # One pinned cell shares the existing request/instantiation frame budgets.
    world_partition.pin_cell(Vector2i.ZERO)
    # The active objective adds one bounded remote streaming source at runtime.
    # The marker and source are initialized after the savegame is restored.
    world_partition.update_streaming()


func _on_cell_detail_changed(_cell: Vector2i, _detail_level: int) -> void:
    _refresh_hud()


func _on_cell_simulation_changed(_cell: Vector2i, _active: bool) -> void:
    if encounters != null:
        encounters.call("refresh_encounters")
    _refresh_hud()


func _on_cell_physics_changed(_cell: Vector2i, _active: bool) -> void:
    _refresh_hud()


func _on_observer_cell_changed(cell: Vector2i) -> void:
    # Event-driven region updates: other gameplay systems can subscribe here.
    current_region = cell
    _refresh_hud()


func _on_stream_cell_loaded(_cell: Vector2i) -> void:
    # Apply the active graphics profile to newly instantiated streaming cells.
    for node in world_partition.get_children():
        if node.has_method("set_high_quality"):
            node.call("set_high_quality", high_quality)
    _refresh_hud()


func _create_crystals() -> void:
    var gem := SphereMesh.new()
    gem.radius = 0.55
    gem.height = 1.1
    gem.radial_segments = 8
    gem.rings = 4
    var gem_material := StandardMaterial3D.new()
    gem_material.albedo_color = Color(0.18, 0.55, 0.95)
    gem_material.metallic = 0.12
    gem_material.roughness = 0.18
    gem_material.emission_enabled = true
    gem_material.emission = Color(0.16, 0.48, 1.0)
    gem_material.emission_energy_multiplier = 3.8
    gem.material = gem_material

    var positions: Array[Vector2] = [
        Vector2(9, -2), Vector2(24, -18), Vector2(-17, -21),
        Vector2(-32, 14), Vector2(11, 33), Vector2(-8, 45),
        Vector2(43, 22), Vector2(35, -41)
    ]
    for i in range(positions.size()):
        if collected_ids.has(i):
            continue
        var p: Vector2 = positions[i]
        var holder := Node3D.new()
        holder.name = "Crystal_%02d" % i
        holder.position = Vector3(p.x, height_at(p.x, p.y) + 1.2, p.y)
        var jewel := MeshInstance3D.new()
        jewel.mesh = gem
        jewel.scale = Vector3(0.75, 1.5, 0.75)
        holder.add_child(jewel)
        add_child(holder)
        crystals.append(holder)


func _create_quest_marker() -> void:
    quest_marker = MeshInstance3D.new()
    quest_marker.name = "RelicObjectiveBeacon"
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.06
    mesh.bottom_radius = 0.18
    mesh.height = 5.0
    mesh.radial_segments = 8
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(0.20, 0.82, 1.0)
    material.emission_enabled = true
    material.emission = Color(0.13, 0.58, 1.0)
    material.emission_energy_multiplier = 2.2
    mesh.material = material
    quest_marker.mesh = mesh
    quest_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    quest_marker.visible = false
    add_child(quest_marker)


func _refresh_quest_target(force: bool = false) -> void:
    if not force and is_instance_valid(quest_target) and not quest_target.is_queued_for_deletion() and crystals.has(quest_target):
        return

    quest_target = QuestNavigation.closest_relic(crystals, player.global_position)
    quest_target_id = -1
    if is_instance_valid(quest_target):
        quest_target_id = quest_target.name.trim_prefix("Crystal_").to_int()
        if is_instance_valid(quest_marker):
            quest_marker.visible = true
            var pos: Vector3 = quest_target.global_position
            quest_marker.global_position = Vector3(pos.x, pos.y + 2.2, pos.z)
    elif is_instance_valid(quest_marker):
        quest_marker.visible = false

    if is_instance_valid(world_partition):
        QuestNavigation.sync_streaming_source(world_partition, quest_target)
    _refresh_hud()


func _quest_hud_text() -> String:
    if not is_instance_valid(quest_target) or not is_instance_valid(player):
        return "Задание: все реликвии собраны"
    var distance: float = QuestNavigation.horizontal_distance(player.global_position, quest_target.global_position)
    var direction: String = QuestNavigation.heading(player, quest_target.global_position)
    return "Задание: реликвия %d   %.1f м   %s   доп. источники: %d" % [
        quest_target_id + 1, distance, direction,
        world_partition.get_streaming_source_count() if is_instance_valid(world_partition) else 0]


func _create_encounter_director() -> void:
    encounters = Node3D.new()
    encounters.name = "ForestEncounterDirector"
    encounters.set_script(ForestEncounters)
    add_child(encounters)
    encounters.connect("player_damaged", _on_player_damaged)
    encounters.connect("enemy_defeated", _on_enemy_defeated)
    encounters.call("restore_defeated", defeated_mobs)
    encounters.call("configure", world_partition, player, Callable(self, "height_at"))


func _on_player_damaged(amount: int) -> void:
    if player_hit_grace > 0.0 or amount <= 0:
        return
    player_health = maxi(player_health - amount, 0)
    player_hit_grace = 0.55
    if player_health == 0:
        if travel_controller != null:
            travel_controller.cancel_travel()
        # A safe, deterministic camp respawn instead of losing quest progress.
        player.call("teleport_to_ground", 0.0, 9.0, height_at(0.0, 9.0))
        player_health = 100
        player_hit_grace = 2.0
        hint.text = "Вы потеряли здоровье! Возрождение у лагеря. Реликвии и победы сохранены."
    _refresh_hud()


func _on_enemy_defeated(_id: String) -> void:
    defeated_mobs = encounters.call("get_defeated_ids")
    _save_game()
    _refresh_hud()


func _swing_weapon() -> void:
    if encounters == null or camera == null:
        return
    var struck: bool = encounters.call("attack_from_camera", camera)
    if struck:
        hint.text = "Попадание! Продолжайте атаковать, чтобы победить лесного охотника."
    else:
        hint.text = "Удар: подойдите ближе и наведите прицел на противника (F или ЛКМ)."


func _create_travel_controller() -> void:
    travel_controller = StreamingTravel.new()
    travel_controller.name = "DestinationTravel"
    add_child(travel_controller)
    travel_controller.configure(world_partition, player, Callable(self, "height_at"))
    travel_controller.travel_completed.connect(_on_travel_completed)
    travel_controller.travel_failed.connect(_on_travel_failed)


func _request_travel(to_quest: bool) -> void:
    if travel_controller == null or world_partition == null:
        return
    var arrival: Vector3 = Vector3(0.0, 0.0, 9.0)
    var label: String = "лагерь"
    if to_quest:
        if not is_instance_valid(quest_target):
            hint.text = "Нет активной реликвии для перехода."
            return
        arrival = quest_target.global_position
        label = "реликвия %d" % (quest_target_id + 1)
    # This showcase has a finite static collision terrain spanning +/-64m.
    # Do not stage travel beyond the authored heightfield.
    arrival.x = clampf(arrival.x, -60.0, 60.0)
    arrival.z = clampf(arrival.z, -60.0, 60.0)
    if not travel_controller.request_travel(arrival, label):
        hint.text = travel_controller.last_message
    _refresh_hud()


func _on_travel_completed(_destination: Vector3) -> void:
    hint.text = "Переход выполнен после готовности сцены. F10: реликвия, F11: лагерь."
    _refresh_hud()


func _on_travel_failed(reason: String) -> void:
    hint.text = reason
    _refresh_hud()


func _create_camera() -> void:
    # Physics body owns yaw and collision, camera owns only pitch.
    # This follows the standard first-person controller hierarchy.
    player = CharacterBody3D.new()
    player.name = "ExplorerBody"
    player.set_script(preload("res://scripts/explorer_character.gd"))
    add_child(player)
    player.call("teleport_to_ground", 0.0, 9.0, height_at(0.0, 9.0))

    camera = Camera3D.new()
    camera.name = "ExplorerCamera"
    camera.fov = 72.0
    camera.far = 210.0
    camera.current = true
    camera.position = Vector3(0.0, 0.76, 0.0)
    camera.rotation_degrees.x = -9.0
    player.add_child(camera)

func _create_hud() -> void:
    var canvas := CanvasLayer.new()
    canvas.name = "GameHUD"
    add_child(canvas)
    hud = Label.new()
    hud.position = Vector2(22, 20)
    hud.add_theme_font_size_override("font_size", 19)
    hud.add_theme_color_override("font_color", Color(0.92, 0.96, 0.90))
    hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.82))
    hud.add_theme_constant_override("shadow_offset_x", 2)
    hud.add_theme_constant_override("shadow_offset_y", 2)
    canvas.add_child(hud)
    hint = Label.new()
    hint.position = Vector2(22, 310)
    hint.add_theme_font_size_override("font_size", 15)
    hint.add_theme_color_override("font_color", Color(0.76, 0.85, 0.77))
    hint.text = "WASD/стрелки: ходьба  •  Shift: бег  •  Space: прыжок  •  E: реликвия\nF/ЛКМ: удар  •  F1/F2: графика  •  F3: упреждение  •  F4: LOD  •  F5/F9: сохранение\nF6: погода  •  F7: пауза дня  •  F8: +3 часа\nF10: к реликвии  •  F11: в лагерь  •  F12: отмена перехода  •  Esc: курсор"
    canvas.add_child(hint)


func _apply_quality(high: bool) -> void:
    high_quality = high
    world_environment.ssao_enabled = high
    world_environment.ssil_enabled = high
    world_environment.volumetric_fog_enabled = high
    if world_partition != null:
        for node in world_partition.get_children():
            if node.has_method("set_high_quality"):
                node.call("set_high_quality", high)
    var controller := get_node_or_null("AdaptiveResolution3D")
    if controller:
        controller.set("min_scale", 0.70 if high else 0.62)
        controller.set("target_fps", 60)
    _refresh_hud()


func _refresh_hud() -> void:
    if hud == null:
        return
    var quality: String = "CINEMATIC" if high_quality else "PERFORMANCE"
    var scale: float = get_viewport().scaling_3d_scale
    var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
    var gpu_text: String = "%.2f ms" % gpu_ms if gpu_ms > 0.0 else "N/A"
    var loaded: int = world_partition.get_loaded_cell_count() if world_partition != null else 0
    var configured: int = world_partition.get_configured_cell_count() if world_partition != null else 0
    var pending: int = world_partition.get_pending_cell_count() if world_partition != null else 0
    var inflight: int = world_partition.get_inflight_request_count() if world_partition != null else 0
    var failed: int = world_partition.get_failed_cell_count() if world_partition != null else 0
    var pinned: int = world_partition.get_pinned_cell_count() if world_partition != null else 0
    var distant: int = world_partition.get_distant_cell_count() if world_partition != null else 0
    var simulated: int = world_partition.get_simulation_active_cell_count() if world_partition != null else 0
    var collidable: int = world_partition.get_physics_active_cell_count() if world_partition != null else 0
    var nav_updates: int = world_partition.get_navigation_updates_used_this_frame() if world_partition != null else 0
    var quest_text: String = _quest_hud_text()
    var enemy_count: int = encounters.call("get_alive_count") if encounters != null else 0
    var travel_text: String = travel_controller.get_status_text() if travel_controller != null and travel_controller.active else "F10: к реликвии  F11: в лагерь"
    var predicted_text: String = "OFF" if not predictive_streaming else "—"
    if world_partition != null and world_partition.has_predicted_cell():
        var next_cell: Vector2i = world_partition.get_predicted_cell()
        predicted_text = "%d,%d" % [next_cell.x, next_cell.y]
    hud.text = "AURORA FOREST  |  Cgame / Godot 4.8\n" \
        + "Реликвии: %d / %d    Профиль: %s\n" % [collected, CRYSTAL_TOTAL, quality] \
        + "3D scale: %.2f    FPS: %d    GPU: %s\n" % [scale, Engine.get_frames_per_second(), gpu_text] \
        + "Ячейки: %d/%d   закреплено: %d   очередь: %d   запросы: %d   ошибки: %d   область: %d,%d\n" % [loaded, configured, pinned, pending, inflight, failed, current_region.x, current_region.y] \
        + "Упреждающая загрузка: %s   LOD дальних: %d   симуляция: %d   коллизии: %d   навигация: %d/%d   F3/F4: сравнение\n" % [predicted_text, distant, simulated, collidable, nav_updates, world_partition.max_navigation_updates_per_physics_frame] \
        + "Атмосфера: %02d:%02d  %s  %s (F6/F7/F8)\n" % [int(atmosphere_clock.day_hours), int(fmod(atmosphere_clock.day_hours, 1.0) * 60.0), atmosphere_clock.get_weather_name(), "ПАУЗА" if atmosphere_clock.paused else "цикл"] \
        + quest_text + "\n" \
        + "Здоровье: %d/100   Противники: %d   побеждено: %d   F/ЛКМ: удар\n" % [player_health, enemy_count, defeated_mobs.size()] \
        + travel_text
    if collected >= CRYSTAL_TOTAL:
        hint.text = "Все реликвии найдены! Лес снова сияет. Нажми F1/F2, чтобы сравнить рендеринг."


func _physics_process(delta: float) -> void:
    player_hit_grace = maxf(0.0, player_hit_grace - delta)
    # Player movement is calculated by CharacterBody3D in the physics step.
    # The streamer receives the world-space velocity from the preceding step.
    # For non-physics observers, the same API can be driven by gameplay code.
    if world_partition != null and player != null:
        world_partition.predictive_velocity = player.velocity


func _process(delta: float) -> void:
    elapsed += delta
    hud_elapsed += delta
    if hud_elapsed >= 0.25:
        hud_elapsed = 0.0
        _refresh_hud()

    for i in range(crystals.size()):
        var crystal: Node3D = crystals[i]
        crystal.rotation.y += delta * 0.7
        crystal.position.y = height_at(crystal.position.x, crystal.position.z) \
            + 1.2 + sin(elapsed * 1.7 + float(i)) * 0.23


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
            _swing_weapon()
        else:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        get_viewport().set_input_as_handled()
    elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        player.rotation.y -= event.relative.x * mouse_sensitivity
        camera.rotation.x = clampf(camera.rotation.x - event.relative.y * mouse_sensitivity, -1.42, 1.42)
        get_viewport().set_input_as_handled()
    elif event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_ESCAPE:
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
            KEY_F1:
                _apply_quality(true)
            KEY_F2:
                _apply_quality(false)
            KEY_F3:
                predictive_streaming = not predictive_streaming
                if world_partition != null:
                    world_partition.predictive_lookahead_seconds = 2.5 if predictive_streaming else 0.0
                _refresh_hud()
            KEY_F4:
                distance_lod_enabled = not distance_lod_enabled
                if world_partition != null:
                    world_partition.detail_radius = 1 if distance_lod_enabled else -1
                    world_partition.update_streaming()
                _refresh_hud()
            KEY_F5:
                _save_game()
            KEY_F6:
                atmosphere_clock.cycle_weather()
                _refresh_hud()
            KEY_F7:
                atmosphere_clock.paused = not atmosphere_clock.paused
                _refresh_hud()
            KEY_F8:
                atmosphere_clock.skip_hours(3.0)
                _refresh_hud()
            KEY_F9:
                _load_game()
                _apply_quality(high_quality)
            KEY_F10:
                _request_travel(true)
            KEY_F11:
                _request_travel(false)
            KEY_F12:
                if travel_controller != null:
                    travel_controller.cancel_travel()
            KEY_E:
                _collect_nearest()
            KEY_F:
                _swing_weapon()


func _save_game() -> void:
    var saved: bool = GameSave.save_state({
        "relics": collected_ids,
        "position_xz": [player.position.x, player.position.z],
        "look": [camera.rotation.x, player.rotation.y],
        "quality": high_quality,
        "time_of_day": atmosphere_clock.day_hours,
        "weather": atmosphere_clock.weather_mode,
        "defeated_enemies": encounters.call("get_defeated_ids") if encounters != null else defeated_mobs
    })
    if saved and collected < CRYSTAL_TOTAL:
        hint.text = "Прогресс сохранён локально. F9: загрузить. W/A/S/D: ходьба, E: реликвии."


func _load_game() -> void:
    if travel_controller != null:
        travel_controller.cancel_travel()
    var state: Dictionary = GameSave.load_state(CRYSTAL_TOTAL)
    if state.is_empty():
        return
    collected_ids = state["relics"]
    collected = collected_ids.size()
    defeated_mobs = state.get("defeated_enemies", [])
    if encounters != null:
        encounters.call("restore_defeated", defeated_mobs)
    for crystal in crystals:
        crystal.queue_free()
    crystals.clear()
    quest_target = null
    quest_target_id = -1
    _create_crystals()

    var position: Vector2 = state["position_xz"]
    player.call("teleport_to_ground", position.x, position.y,
        height_at(position.x, position.y))
    var look: Vector2 = state["look"]
    camera.rotation.x = look.x
    player.rotation.y = look.y
    high_quality = state["quality"]
    atmosphere_clock.set_weather(state.get("weather", 0))
    atmosphere_clock.set_clock(state.get("time_of_day", 17.25))
    if is_instance_valid(quest_marker):
        _refresh_quest_target(true)
    _refresh_hud()


func _collect_nearest() -> void:
    if camera == null:
        return
    var nearest: Node3D = null
    var distance: float = 3.2
    for candidate in crystals:
        var dist: float = Vector2(player.global_position.x - candidate.position.x,
            player.global_position.z - candidate.position.z).length()
        if dist < distance:
            distance = dist
            nearest = candidate
    if nearest:
        if travel_controller != null and travel_controller.active and nearest == quest_target:
            travel_controller.cancel_travel()
        var id: int = nearest.name.trim_prefix("Crystal_").to_int()
        if not collected_ids.has(id):
            collected_ids.append(id)
        crystals.erase(nearest)
        nearest.queue_free()
        collected = collected_ids.size()
        _save_game()
        _refresh_quest_target(true)
        _refresh_hud()
