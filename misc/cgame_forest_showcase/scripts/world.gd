# Reusable 3D vertical slice for Cgame.
# Uses only stock Godot runtime APIs plus the native AdaptiveResolution3D node in world.tscn.
extends Node3D

const TerrainHeight = preload("res://scripts/terrain_height.gd")
const TileCache = preload("res://scripts/terrain_tile_cache.gd")
const GameSave = preload("res://scripts/game_save.gd")
const WORLD_EXTENT: float = 512.0
const WORLD_CELLS_PER_SIDE: int = 32
const CHUNK_EDGE: float = 32.0
const CRYSTAL_TOTAL: int = 8

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var camera: Camera3D
var player: CharacterBody3D
var world_environment: Environment
var hud: Label
var hint: Label
var world_partition: WorldPartition3D
var distant_terrain: Node3D
var current_region: Vector2i = Vector2i.ZERO
var crystals: Array[Node3D] = []
var collected_ids: Array[int] = []

var elapsed: float = 0.0
var hud_elapsed: float = 0.0
var collected: int = 0
var high_quality: bool = true
var mouse_sensitivity: float = 0.0018


func _ready() -> void:
    rng.seed = 913481
    _create_environment()
    _create_sun()
    _create_world_boundaries()
    _create_crystals()
    _create_camera()
    _create_hud()
    _create_streaming_world()
    _create_distant_terrain()
    _load_game()
    _apply_quality(high_quality)
    _refresh_hud()


func height_at(x: float, z: float) -> float:
    return TerrainHeight.height_at(x, z)


func _normal_at(x: float, z: float) -> Vector3:
    return TerrainHeight.normal_at(x, z)


func _create_environment() -> void:
    var sky_material := ShaderMaterial.new()
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
    var sun := DirectionalLight3D.new()
    sun.name = "GoldenHourSun"
    sun.rotation_degrees = Vector3(-38.0, -43.0, 0.0)
    sun.light_color = Color(1.0, 0.78, 0.58)
    sun.light_energy = 1.35
    sun.shadow_enabled = true
    add_child(sun)



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
    world_partition.load_radius = 1
    world_partition.unload_radius = 2
    world_partition.prefetch_distance = 2  # Prefetch a two-tile corridor when running.
    world_partition.max_new_requests_per_frame = 2
    world_partition.max_instances_per_frame = 2
    world_partition.max_instantiation_time_ms = 2.0
    world_partition.max_concurrent_requests = 4
    add_child(world_partition)
    world_partition.observer_path = world_partition.get_path_to(player)
    player.set("streaming_world", world_partition)
    world_partition.cell_loaded.connect(_on_stream_cell_loaded)
    world_partition.cell_unloaded.connect(_on_stream_cell_unloaded)
    world_partition.observer_cell_changed.connect(_on_observer_cell_changed)

    var half_cells: int = WORLD_CELLS_PER_SIDE >> 1
    for cz in range(-half_cells, half_cells):
        for cx in range(-half_cells, half_cells):
            world_partition.set_cell_scene(
                Vector2i(cx, cz), "res://cells/forest_cell.tscn")
    world_partition.update_streaming()


func _update_predictive_streaming() -> void:
    if world_partition == null or player == null:
        return

    # Read physics velocity every quarter-second rather than changing the
    # streamer direction every render frame. Movements under 2 m/s do not
    # justify extra terrain loading. Diagonal movement prefetches diagonally.
    var horizontal := Vector2(player.velocity.x, player.velocity.z)
    var direction := Vector2i.ZERO
    if horizontal.length_squared() >= 4.0:
        if absf(horizontal.x) >= 2.0:
            direction.x = 1 if horizontal.x > 0.0 else -1
        if absf(horizontal.y) >= 2.0:
            direction.y = 1 if horizontal.y > 0.0 else -1

    if world_partition.prefetch_direction != direction:
        world_partition.prefetch_direction = direction


func _create_distant_terrain() -> void:
    # Lightweight distant visual proxies run alongside WorldPartition3D,
    # without retaining distant collision shapes or procedural foliage nodes.
    distant_terrain = Node3D.new()
    distant_terrain.name = "DistantTerrainHLOD"
    distant_terrain.set_script(preload("res://scripts/distant_terrain_hlod.gd"))
    distant_terrain.set("streaming_world", world_partition)
    distant_terrain.set("observer", player)
    add_child(distant_terrain)


func _on_observer_cell_changed(cell: Vector2i) -> void:
    current_region = cell
    _refresh_player_stream_safety()
    _refresh_hud()


func _on_stream_cell_loaded(cell: Vector2i) -> void:
    # Direct indexed cell lookup avoids scanning/reconfiguring every loaded
    # region each time a new region finishes its async resource load.
    var node: Node3D = world_partition.get_cell_node(cell)
    if node != null and node.has_method("set_high_quality"):
        node.call("set_high_quality", high_quality)
    _refresh_player_stream_safety()
    _refresh_hud()


func _on_stream_cell_unloaded(_cell: Vector2i) -> void:
    _refresh_player_stream_safety()


func _refresh_player_stream_safety() -> void:
    if player == null or world_partition == null:
        return
    var local: Vector3 = world_partition.to_local(player.global_position)
    var cell: Vector2i = world_partition.local_position_to_cell(local)
    player.set("movement_enabled", world_partition.are_cells_loaded(cell, 0))


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


func _create_camera() -> void:
    # Physics body owns yaw and collision, camera owns only pitch.
    # This follows the standard first-person controller hierarchy.
    player = CharacterBody3D.new()
    player.name = "ExplorerBody"
    player.set_script(preload("res://scripts/explorer_character.gd"))
    add_child(player)
    # Freeze physics until the streamed spawn tile (including its collider) is ready.
    player.set("movement_enabled", false)
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
    hint.position = Vector2(22, 254)
    hint.add_theme_font_size_override("font_size", 15)
    hint.add_theme_color_override("font_color", Color(0.76, 0.85, 0.77))
    hint.text = "WASD/стрелки: движение  •  мышь: обзор  •  Shift: бег  •  Space: прыжок  •  E: сбор\nF1: качество  •  F2: скорость  •  F5: сохранить  •  F9: загрузить  •  Esc: курсор"
    canvas.add_child(hint)


func _apply_quality(high: bool) -> void:
    high_quality = high
    world_environment.ssao_enabled = high
    world_environment.ssil_enabled = high
    world_environment.volumetric_fog_enabled = high
    if distant_terrain != null:
        distant_terrain.call("set_high_quality", high)
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
    var stream_ms: float = world_partition.get_last_streaming_update_ms() if world_partition != null else 0.0
    var created_this_frame: int = world_partition.get_last_instantiation_attempt_count() if world_partition != null else 0
    var cache: Dictionary = TileCache.get_stats()
    var far: Dictionary = distant_terrain.call("get_stats") if distant_terrain != null else {"allocated": 0, "visible": 0, "visible_canopies": 0}
    var ahead: Vector2i = world_partition.prefetch_direction if world_partition != null else Vector2i.ZERO
    hud.text = "AURORA FOREST  |  Cgame / Godot 4.8\n" \
        + "Реликвии: %d / %d    Профиль: %s\n" % [collected, CRYSTAL_TOTAL, quality] \
        + "3D scale: %.2f    FPS: %d    GPU: %s\n" % [scale, Engine.get_frames_per_second(), gpu_text] \
        + "Ячейки: %d/%d   очередь: %d   запросы: %d   ошибки: %d   область: %d,%d\n" % [loaded, configured, pending, inflight, failed, current_region.x, current_region.y] \
        + "Кэш земли: %d/%d   попадания: %d   промахи: %d\n" % [cache["entries"], cache["capacity"], cache["hits"], cache["misses"]] \
        + "Предзагрузка: X=%d Z=%d   впереди: %d ячейки\n" % [ahead.x, ahead.y, world_partition.prefetch_distance] \
        + "Дальний HLOD: %d плит / %d подготовлено, %d крон\n" % [far["visible"], far["allocated"], far["visible_canopies"]] \
        + "Стриминг CPU: %.2f ms   попыток создания: %d" % [stream_ms, created_this_frame]
    if collected >= CRYSTAL_TOTAL:
        hint.text = "Все реликвии найдены! Лес снова сияет. Нажми F1/F2, чтобы сравнить рендеринг."


func _process(delta: float) -> void:
    elapsed += delta
    hud_elapsed += delta
    if hud_elapsed >= 0.25:
        hud_elapsed = 0.0
        _update_predictive_streaming()
        _refresh_hud()

    for i in range(crystals.size()):
        var crystal: Node3D = crystals[i]
        crystal.rotation.y += delta * 0.7
        crystal.position.y = height_at(crystal.position.x, crystal.position.z) \
            + 1.2 + sin(elapsed * 1.7 + float(i)) * 0.23


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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
            KEY_F5:
                _save_game()
            KEY_F9:
                _load_game()
                _apply_quality(high_quality)
            KEY_E:
                _collect_nearest()


func _save_game() -> void:
    var saved: bool = GameSave.save_state({
        "relics": collected_ids,
        "position_xz": [player.position.x, player.position.z],
        "look": [camera.rotation.x, player.rotation.y],
        "quality": high_quality
    })
    if saved and collected < CRYSTAL_TOTAL:
        hint.text = "Прогресс сохранён локально. F9: загрузить. W/A/S/D: ходьба, E: реликвии."


func _load_game() -> void:
    var state: Dictionary = GameSave.load_state(CRYSTAL_TOTAL)
    if state.is_empty():
        return
    collected_ids = state["relics"]
    collected = collected_ids.size()
    for crystal in crystals:
        crystal.queue_free()
    crystals.clear()
    _create_crystals()

    var position: Vector2 = state["position_xz"]
    player.call("teleport_to_ground", position.x, position.y,
        height_at(position.x, position.y))
    # A saved-game teleport resets velocity and forward prefetch direction.
    world_partition.prefetch_direction = Vector2i.ZERO
    world_partition.update_streaming()
    _refresh_player_stream_safety()
    var look: Vector2 = state["look"]
    camera.rotation.x = look.x
    player.rotation.y = look.y
    high_quality = state["quality"]
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
        var id: int = nearest.name.trim_prefix("Crystal_").to_int()
        if not collected_ids.has(id):
            collected_ids.append(id)
        crystals.erase(nearest)
        nearest.queue_free()
        collected = collected_ids.size()
        _save_game()
        _refresh_hud()
