extends Node3D

# Native Cgame WorldPartition3D + cell proxy HLOD composition.
# Detailed cells have a short radius; proxy cells use a wider radius.
# Loaded detailed cells always hide the corresponding distant proxy.
const CELL_SIZE := 128.0
const WORLD_HALF_EXTENT := 6
const HUB_CELL := Vector2i(0, 0)
const ARENA_CELL := Vector2i(4, 2)
const DETAIL_SCENE := "res://scenes/cell_detail.tscn"
const PROXY_SCENE := "res://scenes/cell_proxy.tscn"
const FLY_SCRIPT := preload("res://scripts/free_fly.gd")
const QUALITY_SCRIPT := preload("res://scripts/streaming_quality.gd")
const CROSSFADE_SCRIPT := preload("res://scripts/hlod_crossfade_controller.gd")
const MANIFEST_SCRIPT := preload("res://tools/hlod_bake_manifest.gd")

var camera: Camera3D
var prefetch_source: Node3D
var detail: Node3D
var distant: Node3D
var hud: Label
var prefetch_enabled := true
var proxies_enabled := true
var hud_elapsed := 0.0
var baked_proxy_cell_count := 0
var baked_validation_ms := 0
var baked_manifest: Dictionary = {}
var quality_controller = QUALITY_SCRIPT.new()
var crossfade_controller: CROSSFADE_SCRIPT

func _ready() -> void:
    _create_lighting_and_camera()
    if not ClassDB.class_exists("WorldPartition3D"):
        push_error("Cgame build with native world_partition module is required.")
        return
    # The manifest is tied to the current detailed art, baking code and stride.
    # No stale or corrupted proxy file should be registered by the streamer.
    var manifest_file := MANIFEST_SCRIPT.MANIFEST_PATH
    if FileAccess.file_exists(manifest_file):
        var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_file))
        if raw is Dictionary:
            var stride: int = int(raw.get("stride", -1))
            baked_manifest = MANIFEST_SCRIPT.read_valid_manifest(stride)
    var validation_start: int = Time.get_ticks_msec()
    distant = _make_streamer("DistantProxies", 4, 5, PROXY_SCENE, 1)
    baked_validation_ms = Time.get_ticks_msec() - validation_start
    detail = _make_streamer("DetailedCells", 1, 2, DETAIL_SCENE, 2)
    _apply_quality_profile()
    if not detail.has_method("pin_cell") or not detail.has_method("get_pinned_cell_count"):
        push_error("Cgame pinned gameplay cells API required (pin_cell/get_pinned_cell_count).")
        return
    # The quest hub remains active while the player explores other regions.
    detail.call("pin_cell", HUB_CELL)
    if not distant.has_method("get_cell_instance") or not detail.has_method("get_cell_instance"):
        push_error("Cgame get_cell_instance API required for proxy handoff.")
        return
    crossfade_controller = CROSSFADE_SCRIPT.new()
    crossfade_controller.near_streamer = detail
    crossfade_controller.far_streamer = distant
    crossfade_controller.target_camera = camera
    add_child(crossfade_controller)
    _set_prefetch(true)
    _create_hud()

func _make_streamer(name: String, radius: int, unload_radius: int, scene_path: String, budget: int) -> Node3D:
    var world := ClassDB.instantiate("WorldPartition3D") as Node3D
    world.name = name
    add_child(world)
    world.set("cell_size", CELL_SIZE)
    world.set("load_radius", radius)
    world.set("unload_radius", unload_radius)
    world.set("max_instances_per_frame", budget)
    world.set("max_new_requests_per_frame", budget)
    world.set("max_concurrent_requests", 6)
    world.set("observer_path", world.get_path_to(camera))
    # Register the complete grid in one native call rather than invoking
    # ClassDB 169 times; this also keeps initialization deterministic.
    var cell_paths: Dictionary = {}
    for x in range(-WORLD_HALF_EXTENT, WORLD_HALF_EXTENT + 1):
        for z in range(-WORLD_HALF_EXTENT, WORLD_HALF_EXTENT + 1):
            var path := scene_path
            if scene_path == PROXY_SCENE:
                var cell := Vector2i(x, z)
                if MANIFEST_SCRIPT.is_cached_proxy_valid(cell, baked_manifest):
                    var baked: String = MANIFEST_SCRIPT.proxy_path(cell)
                    if ResourceLoader.exists(baked, "PackedScene"):
                        path = baked
                        baked_proxy_cell_count += 1
            cell_paths[Vector2i(x, z)] = path
    world.call("set_cell_scenes", cell_paths)
    return world

func _apply_quality_profile() -> void:
    if detail == null or distant == null:
        return
    var profile: Dictionary = quality_controller.get_profile()
    detail.set("load_radius", int(profile["detail_load"]))
    detail.set("unload_radius", int(profile["detail_unload"]))
    distant.set("load_radius", int(profile["proxy_load"]))
    distant.set("unload_radius", int(profile["proxy_unload"]))
    detail.set("max_new_requests_per_frame", int(profile["detail_budget"]))
    detail.set("max_instances_per_frame", int(profile["detail_budget"]))
    distant.set("max_new_requests_per_frame", int(profile["proxy_budget"]))
    distant.set("max_instances_per_frame", int(profile["proxy_budget"]))
    detail.set("max_unloads_per_frame", int(profile["unload_budget"]))
    distant.set("max_unloads_per_frame", int(profile["unload_budget"]))

func _create_lighting_and_camera() -> void:
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    sky.sky_material = ProceduralSkyMaterial.new()
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_density = 0.002
    var world_environment := WorldEnvironment.new()
    world_environment.environment = env
    add_child(world_environment)

    var sunlight := DirectionalLight3D.new()
    sunlight.rotation_degrees = Vector3(-45, -20, 0)
    sunlight.light_energy = 1.5
    sunlight.light_color = Color(1.0, 0.91, 0.78)
    sunlight.shadow_enabled = true
    add_child(sunlight)

    camera = Camera3D.new()
    camera.name = "FlyCamera"
    camera.position = Vector3(64, 18, 64)
    camera.rotation_degrees = Vector3(-14, -30, 0)
    camera.set_script(FLY_SCRIPT)
    add_child(camera)
    prefetch_source = Node3D.new()
    prefetch_source.name = "PrefetchSource"
    prefetch_source.position = Vector3(0, 0, -180)
    camera.add_child(prefetch_source)

func _set_prefetch(enabled: bool) -> void:
    prefetch_enabled = enabled
    if detail != null and detail.has_method("set_additional_observer_paths"):
        var paths: Array = [detail.get_path_to(prefetch_source)] if enabled else []
        detail.call("set_additional_observer_paths", paths)

func _toggle_gameplay_pin(cell: Vector2i) -> void:
    if detail == null:
        return
    if bool(detail.call("is_cell_pinned", cell)):
        detail.call("unpin_cell", cell)
    else:
        detail.call("pin_cell", cell)

func _create_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    hud = Label.new()
    hud.position = Vector2(20, 20)
    hud.add_theme_color_override("font_color", Color.WHITE)
    hud.add_theme_color_override("font_shadow_color", Color.BLACK)
    hud.add_theme_constant_override("shadow_offset_x", 1)
    hud.add_theme_constant_override("shadow_offset_y", 1)
    layer.add_child(hud)
    _update_hud()

func _unhandled_key_input(event: InputEvent) -> void:
    if not (event is InputEventKey):
        return
    var key := event as InputEventKey
    if not key.pressed or key.echo:
        return
    match key.keycode:
        KEY_P:
            _set_prefetch(not prefetch_enabled)
        KEY_H:
            _toggle_gameplay_pin(HUB_CELL)
        KEY_G:
            _toggle_gameplay_pin(ARENA_CELL)
        KEY_L:
            proxies_enabled = not proxies_enabled
            if distant != null:
                distant.set("streaming_enabled", proxies_enabled)
        KEY_F:
            if crossfade_controller != null:
                crossfade_controller.set_transition_enabled(not crossfade_controller.enabled)
        KEY_R:
            var retry_available := false
            for partition in [detail, distant]:
                if partition != null and partition.has_method("retry_failed_cells"):
                    partition.call("retry_failed_cells")
                    retry_available = true
            if not retry_available:
                push_warning("Retry requires the native WorldPartition3D telemetry API from PR #916.")
        KEY_Q:
            quality_controller.automatic = not quality_controller.automatic
            quality_controller.reset_sampling()
        KEY_1, KEY_2, KEY_3:
            quality_controller.automatic = false
            if quality_controller.set_level(key.keycode - KEY_1):
                _apply_quality_profile()

func _process(delta: float) -> void:
    if detail != null and quality_controller.sample(delta, float(Engine.get_frames_per_second())):
        _apply_quality_profile()
    hud_elapsed += delta
    if hud_elapsed >= 0.25:
        hud_elapsed = 0.0
        _update_hud()

func _update_hud() -> void:
    if hud == null:
        return
    var detail_count: int = int(detail.call("get_loaded_cell_count")) if detail != null else 0
    var distant_count: int = int(distant.call("get_loaded_cell_count")) if distant != null else 0
    var pin_count: int = int(detail.call("get_pinned_cell_count")) if detail != null else 0
    var hub_pinned := detail != null and bool(detail.call("is_cell_pinned", HUB_CELL))
    var arena_pinned := detail != null and bool(detail.call("is_cell_pinned", ARENA_CELL))
    var hub_loaded := detail != null and bool(detail.call("is_cell_loaded", HUB_CELL))
    var arena_loaded := detail != null and bool(detail.call("is_cell_loaded", ARENA_CELL))
    hud.text = "CGAME HLOD STREAMING  |  FPS %d\nDetail cells: %d   Distant proxy cells: %d\nVerified baked proxies: %d / 169   Checksum scan: %d ms\nGameplay pins: %d  | H Hub: %s/%s  G Arena: %s/%s\nQuality: %s  Q auto: %s  1/2/3 manual quality\nF crossfade: %s   WASD fly  Space/Ctrl vertical  Shift fast\nP prefetch: %s   L proxies: %s   R retry   Esc mouse" % [
        Engine.get_frames_per_second(),
        detail_count,
        distant_count,
        baked_proxy_cell_count,
        baked_validation_ms,
        pin_count,
        "ON" if hub_pinned else "OFF",
        "loaded" if hub_loaded else "away",
        "ON" if arena_pinned else "OFF",
        "loaded" if arena_loaded else "away",
        str(quality_controller.get_profile()["name"]),
        "ON" if quality_controller.automatic else "OFF",
        "ON" if crossfade_controller != null and crossfade_controller.enabled else "OFF",
        "ON" if prefetch_enabled else "OFF",
        "ON" if proxies_enabled else "OFF",
    ]
