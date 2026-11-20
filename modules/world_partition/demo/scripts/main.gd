extends Node3D

# Native Cgame WorldPartition3D + cell proxy HLOD composition.
# Detailed cells have a short radius; proxy cells use a wider radius.
# Loaded detailed cells always hide the corresponding distant proxy.
const CELL_SIZE := 128.0
const WORLD_HALF_EXTENT := 6
const HUB_CELL := Vector2i(0, 0)
const ARENA_CELL := Vector2i(4, 2)
const CHAMPION_CELL := Vector2i(5, 3)
const CHAMPION_LAYER := "champion_event"
const COMBAT_LAYER := "combat_event"
const COMBAT_LAYER_CELLS := [Vector2i(4, 2), Vector2i(4, 3), Vector2i(5, 2)]
const SAVE_PATH := "user://cgame_demo_checkpoint.dat"
const SAVE_VERSION := 2
const DETAIL_SCENE := "res://scenes/cell_detail.tscn"
const PROXY_SCENE := "res://scenes/cell_proxy.tscn"
const FLY_SCRIPT := preload("res://scripts/free_fly.gd")
const QUALITY_SCRIPT := preload("res://scripts/streaming_quality.gd")
const CROSSFADE_SCRIPT := preload("res://scripts/hlod_crossfade_controller.gd")
const MANIFEST_SCRIPT := preload("res://tools/hlod_bake_manifest.gd")
const EVENT_RULES := preload("res://scripts/world_event_rules.gd")
const PATROL_SCRIPT := preload("res://scripts/route_patrol_agent.gd")

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
var last_gameplay_event := "Claim the hub reward with C to unlock combat."
var last_nav_query := "N: test local nav path after physics sync"
var quest_arena_lease := 0
var manual_arena_lease := 0
var patrol_agent: CharacterBody3D
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
    if not detail.has_method("snapshot_cell_states") or not detail.has_method("load_cell_states"):
        push_error("Cgame gameplay state streaming API required (snapshot_cell_states/load_cell_states).")
        return
    if not detail.has_method("set_cell_layers") or not detail.has_method("set_layer_enabled"):
        push_error("Cgame WorldPartition3D runtime Data Layers API required.")
        return
    if not detail.has_method("acquire_cell_lease") or not detail.has_method("release_cell_lease"):
        push_error("Cgame WorldPartition3D independent cell lease API required.")
        return
    if not detail.has_method("get_cell_simulation_stats"):
        push_error("Cgame WorldPartition3D collision/navigation diagnostics required.")
        return
    if not detail.has_method("acquire_cell_route") or not detail.has_method("release_cell_route"):
        push_error("Cgame WorldPartition3D navigation route streaming API required.")
        return
    # The Combat Event is initially inactive even if a pinned gameplay cell
    # or an observer overlaps its region. The quest hub stays available.
    var combat_cells: Dictionary = {}
    for cell in COMBAT_LAYER_CELLS:
        combat_cells[cell] = COMBAT_LAYER
    combat_cells[CHAMPION_CELL] = CHAMPION_LAYER
    detail.call("set_cell_layers", combat_cells)
    detail.call("set_layer_enabled", COMBAT_LAYER, false)
    detail.call("set_layer_enabled", CHAMPION_LAYER, false)
    detail.connect("cell_state_changed", Callable(self, "_on_cell_state_changed"))
    detail.connect("layer_state_changed", Callable(self, "_on_layer_state_changed"))
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
    _spawn_patrol_agent()

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

func _sync_quest_arena_lease() -> void:
    if detail == null:
        return
    # The mission owns its own lease. A cutscene/manual owner can release its
    # token independently without disrupting this gameplay guarantee.
    var hub_claimed := bool(_stateful_progress(HUB_CELL, "reward_claimed", false))
    var victories := int(_stateful_progress(ARENA_CELL, "arena_wins", 0))
    var mission_active := hub_claimed and victories < EVENT_RULES.CHAMPION_REQUIRED_WINS
    if mission_active and quest_arena_lease == 0:
        quest_arena_lease = int(detail.call("acquire_cell_lease", ARENA_CELL))
    elif not mission_active and quest_arena_lease != 0:
        detail.call("release_cell_lease", quest_arena_lease)
        quest_arena_lease = 0

func _toggle_manual_arena_lease() -> void:
    if detail == null:
        return
    if manual_arena_lease == 0:
        manual_arena_lease = int(detail.call("acquire_cell_lease", ARENA_CELL))
    else:
        detail.call("release_cell_lease", manual_arena_lease)
        manual_arena_lease = 0
    print("Arena manual lease: %s" % ("ACTIVE" if manual_arena_lease != 0 else "RELEASED"))

func _release_all_owned_leases() -> void:
    if not is_instance_valid(detail):
        quest_arena_lease = 0
        manual_arena_lease = 0
        return
    if quest_arena_lease != 0:
        detail.call("release_cell_lease", quest_arena_lease)
        quest_arena_lease = 0
    if manual_arena_lease != 0:
        detail.call("release_cell_lease", manual_arena_lease)
        manual_arena_lease = 0

func _exit_tree() -> void:
    _release_all_owned_leases()

func _toggle_combat_event() -> void:
    if detail == null:
        return
    var enabled: bool = bool(detail.call("is_layer_enabled", COMBAT_LAYER))
    detail.call("set_layer_enabled", COMBAT_LAYER, not enabled)
    detail.call("update_streaming")
    print("Combat Event layer: %s" % ("ACTIVE" if not enabled else "INACTIVE"))

func _on_cell_state_changed(cell: Vector2i, state: Dictionary) -> void:
    if detail == null:
        return
    var action: Dictionary = EVENT_RULES.next_event(cell, state)
    if not action.is_empty():
        var layer: String = str(action["layer"])
        # Idempotent: repeated snapshots/unloads never re-trigger the quest.
        if not bool(detail.call("is_layer_enabled", layer)):
            detail.call("set_layer_enabled", layer, true)
            last_gameplay_event = str(action["message"])
            print(last_gameplay_event)
    if cell == HUB_CELL or cell == ARENA_CELL:
        _sync_quest_arena_lease()

func _on_layer_state_changed(layer: String, enabled: bool) -> void:
    # Driven by native C++ notifications, not a per-frame layer poll.
    print("World event: %s %s" % [layer, "activated" if enabled else "deactivated"])

func _gameplay_cell_root(cell: Vector2i) -> Node3D:
    if detail == null:
        return null
    return detail.call("get_cell_instance", cell) as Node3D

func _spawn_patrol_agent() -> void:
    if not is_instance_valid(detail):
        return
    patrol_agent = PATROL_SCRIPT.new() as CharacterBody3D
    patrol_agent.name = "PatrolAgent"
    patrol_agent.call("configure", detail)
    add_child(patrol_agent)

func _toggle_patrol_agent() -> void:
    if is_instance_valid(patrol_agent):
        var status: Dictionary = patrol_agent.call("get_patrol_status")
        patrol_agent.call("set_patrol_enabled", not bool(status.get("enabled", false)))

func _test_navigation_path() -> void:
    if detail == null:
        return
    # Prefer the hub, which is pinned when the demo starts.
    var root := _gameplay_cell_root(HUB_CELL)
    if root == null:
        root = _gameplay_cell_root(ARENA_CELL)
    if root == null:
        last_nav_query = "No nearby detailed gameplay cell for navigation test"
        return
    var region := root.get_node_or_null("WalkableRegion") as NavigationRegion3D
    if region == null:
        last_nav_query = "Navigation region has not streamed in"
        return
    # Godot's NavigationServer3D synchronizes region registration on the
    # next physics frame, not when the scene is first added to the tree.
    await get_tree().physics_frame
    await get_tree().physics_frame
    if not is_instance_valid(root) or not is_instance_valid(region) or not region.enabled:
        last_nav_query = "Region unloaded before navigation query"
        return
    var start := root.to_global(Vector3(12, 0, 12))
    var destination := root.to_global(Vector3(CELL_SIZE - 12, 0, CELL_SIZE - 12))
    var path: PackedVector3Array = NavigationServer3D.map_get_path(
        region.get_navigation_map(), start, destination, true
    )
    last_nav_query = "Navigation path: %d points" % path.size()
    print(last_nav_query)

func _claim_hub_reward() -> void:
    var root := _gameplay_cell_root(HUB_CELL)
    if root != null and root.has_method("claim_hub_reward"):
        if bool(root.call("claim_hub_reward")):
            detail.call("set_cell_state", HUB_CELL, root.call("capture_streaming_state"))
    else:
        push_warning("Quest Hub not ready; H pins its scene.")

func _win_arena_round() -> void:
    var root := _gameplay_cell_root(ARENA_CELL)
    if root != null and root.has_method("win_arena_round"):
        root.call("win_arena_round")
        detail.call("set_cell_state", ARENA_CELL, root.call("capture_streaming_state"))
    else:
        push_warning("Combat Arena not ready; T enables the combat event and G pins its scene.")

func _claim_champion_reward() -> void:
    var root := _gameplay_cell_root(CHAMPION_CELL)
    if root != null and root.has_method("claim_champion_reward"):
        if bool(root.call("claim_champion_reward")):
            detail.call("set_cell_state", CHAMPION_CELL, root.call("capture_streaming_state"))
            last_gameplay_event = "Champion shrine: unique reward claimed"
    else:
        push_warning("Champion shrine not loaded. Win three arena rounds, then approach (5,3).")

func _save_checkpoint() -> void:
    if detail == null or camera == null:
        return
    # Captures even the game scenes currently loaded by WorldPartition3D.
    var snapshot: Dictionary = detail.call("snapshot_cell_states")
    var record := {
        "version": SAVE_VERSION,
        "cell_states": snapshot,
        "pinned_cells": detail.call("get_pinned_cells"),
        "layer_states": detail.call("get_layer_states"),
        "camera_transform": camera.global_transform,
        "patrol_state": patrol_agent.call("capture_patrol_state") if is_instance_valid(patrol_agent) else {},
    }
    var output := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if output == null:
        push_error("Cannot write checkpoint: " + SAVE_PATH)
        return
    output.store_var(record, false)
    output.close()
    print("Checkpoint saved with %d gameplay cell states." % snapshot.size())

func _load_checkpoint() -> void:
    if detail == null or camera == null:
        return
    var input := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if input == null:
        push_warning("Checkpoint not found: " + SAVE_PATH)
        return
    var value: Variant = input.get_var(false)
    input.close()
    if not (value is Dictionary):
        push_warning("Invalid checkpoint format.")
        return
    var record: Dictionary = value
    if record.get("version") != SAVE_VERSION:
        push_warning("Unsupported checkpoint version.")
        return
    if not (record.get("cell_states") is Dictionary) or not (record.get("pinned_cells") is Array) or not (record.get("layer_states") is Dictionary) or not (record.get("camera_transform") is Transform3D) or not (record.get("patrol_state", {}) is Dictionary):
        push_warning("Checkpoint fields are incomplete.")
        return
    var states: Dictionary = record["cell_states"]
    var pins: Array = record["pinned_cells"]
    var layers: Dictionary = record["layer_states"]
    if states.size() > 4096 or pins.size() > 128 or layers.size() > 64:
        push_warning("Checkpoint exceeds scene-state or pin limits.")
        return
    # Runtime leases are owner-owned handles, not persisted tokens. Recreate
    # the quest lease from checkpoint gameplay state after import.
    _release_all_owned_leases()
    detail.call("load_cell_states", states)
    detail.call("set_layer_states", layers)
    detail.call("set_pinned_cells", pins)
    _sync_quest_arena_lease()
    if is_instance_valid(patrol_agent):
        patrol_agent.call("restore_patrol_state", record.get("patrol_state", {}))
    camera.global_transform = record["camera_transform"]
    detail.call("update_streaming")
    print("Checkpoint restored: %d cached gameplay cell states." % int(detail.call("get_cell_state_count")))

func _stateful_progress(cell: Vector2i, key: String, fallback: Variant) -> Variant:
    if detail == null:
        return fallback
    var loaded_root := _gameplay_cell_root(cell)
    if loaded_root != null and loaded_root.has_method("capture_streaming_state"):
        var current: Variant = loaded_root.call("capture_streaming_state")
        if current is Dictionary:
            return current.get(key, fallback)
    var cached: Dictionary = detail.call("get_cell_state", cell)
    return cached.get(key, fallback)

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
        KEY_M:
            _toggle_manual_arena_lease()
        KEY_N:
            _test_navigation_path()
        KEY_O:
            _toggle_patrol_agent()
        KEY_T:
            _toggle_combat_event()
        KEY_C:
            _claim_hub_reward()
        KEY_B:
            _win_arena_round()
        KEY_V:
            _claim_champion_reward()
        KEY_K:
            _save_checkpoint()
        KEY_J:
            _load_checkpoint()
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
    var lease_total: int = int(detail.call("get_cell_lease_count_total")) if detail != null else 0
    var arena_owners: int = int(detail.call("get_cell_lease_count", ARENA_CELL)) if detail != null else 0
    var hub_pinned := detail != null and bool(detail.call("is_cell_pinned", HUB_CELL))
    var arena_pinned := detail != null and bool(detail.call("is_cell_pinned", ARENA_CELL))
    var hub_loaded := detail != null and bool(detail.call("is_cell_loaded", HUB_CELL))
    var arena_loaded := detail != null and bool(detail.call("is_cell_loaded", ARENA_CELL))
    var combat_active := detail != null and bool(detail.call("is_layer_enabled", COMBAT_LAYER))
    var champion_active := detail != null and bool(detail.call("is_layer_enabled", CHAMPION_LAYER))
    var champion_claimed := bool(_stateful_progress(CHAMPION_CELL, "champion_reward_claimed", false))
    var reward_claimed := bool(_stateful_progress(HUB_CELL, "reward_claimed", false))
    var arena_wins: int = int(_stateful_progress(ARENA_CELL, "arena_wins", 0))
    var state_count: int = int(detail.call("get_cell_state_count")) if detail != null else 0
    var patrol_state: Dictionary = patrol_agent.call("get_patrol_status") if is_instance_valid(patrol_agent) else {}
    var patrol_text: String = str(patrol_state.get("status", "Loading patrol"))
    var patrol_crossings: int = int(patrol_state.get("crossings", 0))
    var patrol_tokens: int = int(patrol_state.get("route_tokens", 0))
    var patrol_cell: Vector2i = patrol_state.get("current_cell", Vector2i.ZERO)
    var collision_count := 0
    var navigation_count := 0
    if detail != null:
        for cell in [HUB_CELL, ARENA_CELL, CHAMPION_CELL]:
            var stats: Dictionary = detail.call("get_cell_simulation_stats", cell)
            collision_count += int(stats.get("collision_objects", 0))
            navigation_count += int(stats.get("navigation_regions", 0))
    hud.text = "CGAME HLOD STREAMING  |  FPS %d\nDetail cells: %d   Distant proxy cells: %d\nVerified baked proxies: %d / 169   Checksum scan: %d ms\nGameplay pins: %d  | H Hub: %s/%s  G Arena: %s/%s\nCell leases: %d  Arena owners: %d | Quest: %s  M Manual: %s\nT combat event: %s (3 cells)  Champion shrine: %s  V reward: %s\nEvent: %s\nO AI patrol: %s  crossings: %d  route leases: %d  cell: %s\nSimulation near landmarks: %d collision bodies, %d nav regions\n%s\nHub reward C: %s   Arena wins B: %d   Cached states: %d\nK save checkpoint   J load checkpoint\nQuality: %s  Q auto: %s  1/2/3 manual quality\nF crossfade: %s   WASD fly  Space/Ctrl vertical  Shift fast\nP prefetch: %s   L proxies: %s   R retry   Esc mouse" % [
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
        lease_total,
        arena_owners,
        "ACTIVE" if quest_arena_lease != 0 else "RELEASED",
        "ACTIVE" if manual_arena_lease != 0 else "RELEASED",
        "ON" if combat_active else "OFF",
        "ON" if champion_active else "OFF",
        "CLAIMED" if champion_claimed else "READY",
        last_gameplay_event,
        patrol_text,
        patrol_crossings,
        patrol_tokens,
        str(patrol_cell),
        collision_count,
        navigation_count,
        last_nav_query,
        "CLAIMED" if reward_claimed else "READY",
        arena_wins,
        state_count,
        str(quality_controller.get_profile()["name"]),
        "ON" if quality_controller.automatic else "OFF",
        "ON" if crossfade_controller != null and crossfade_controller.enabled else "OFF",
        "ON" if prefetch_enabled else "OFF",
        "ON" if proxies_enabled else "OFF",
    ]
