extends Node3D

# Native Cgame WorldPartition3D + cell proxy HLOD composition.
# Detailed cells have a short radius; proxy cells use a wider radius.
# Loaded detailed cells always hide the corresponding distant proxy.
const CELL_SIZE := 128.0
const WORLD_HALF_EXTENT := 6
const DETAIL_SCENE := "res://scenes/cell_detail.tscn"
const PROXY_SCENE := "res://scenes/cell_proxy.tscn"
const FLY_SCRIPT := preload("res://scripts/free_fly.gd")
const QUALITY_SCRIPT := preload("res://scripts/streaming_quality.gd")

var camera: Camera3D
var prefetch_source: Node3D
var detail: Node3D
var distant: Node3D
var hud: Label
var prefetch_enabled := true
var proxies_enabled := true
var hud_elapsed := 0.0
var quality_controller = QUALITY_SCRIPT.new()

func _ready() -> void:
    _create_lighting_and_camera()
    if not ClassDB.class_exists("WorldPartition3D"):
        push_error("Cgame build with native world_partition module is required.")
        return
    distant = _make_streamer("DistantProxies", 4, 5, PROXY_SCENE, 1)
    detail = _make_streamer("DetailedCells", 1, 2, DETAIL_SCENE, 2)
    _apply_quality_profile()
    if not distant.has_method("get_cell_instance") or not detail.has_method("get_cell_instance"):
        push_error("Cgame get_cell_instance API required for proxy handoff.")
        return
    distant.connect("cell_loaded", Callable(self, "_on_proxy_loaded"))
    detail.connect("cell_loaded", Callable(self, "_on_detail_loaded"))
    detail.connect("cell_unloaded", Callable(self, "_on_detail_unloaded"))
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
    for x in range(-WORLD_HALF_EXTENT, WORLD_HALF_EXTENT + 1):
        for z in range(-WORLD_HALF_EXTENT, WORLD_HALF_EXTENT + 1):
            world.call("set_cell_scene", Vector2i(x, z), scene_path)
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

func _on_detail_loaded(cell: Vector2i) -> void:
    _set_proxy_visible(cell, false)

func _on_detail_unloaded(cell: Vector2i) -> void:
    _set_proxy_visible(cell, true)

func _on_proxy_loaded(cell: Vector2i) -> void:
    if detail != null:
        _set_proxy_visible(cell, not detail.call("is_cell_loaded", cell))

func _set_proxy_visible(cell: Vector2i, show: bool) -> void:
    if distant == null or not distant.has_method("get_cell_instance"):
        return
    var proxy_instance := distant.call("get_cell_instance", cell) as Node3D
    if is_instance_valid(proxy_instance):
        proxy_instance.visible = show

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
        KEY_L:
            proxies_enabled = not proxies_enabled
            if distant != null:
                distant.set("streaming_enabled", proxies_enabled)
        KEY_R:
            for partition in [detail, distant]:
                if partition != null and partition.has_method("retry_failed_cells"):
                    partition.call("retry_failed_cells")
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
    hud.text = "CGAME HLOD STREAMING  |  FPS %d\nDetail cells: %d   Distant proxy cells: %d\nQuality: %s  Q auto: %s  1/2/3 manual quality\nWASD fly  Space/Ctrl vertical  Shift fast  Esc mouse\nP prefetch: %s   L proxies: %s   R retry" % [
        Engine.get_frames_per_second(),
        detail_count,
        distant_count,
        str(quality_controller.get_profile()["name"]),
        "ON" if quality_controller.automatic else "OFF",
        "ON" if prefetch_enabled else "OFF",
        "ON" if proxies_enabled else "OFF",
    ]
