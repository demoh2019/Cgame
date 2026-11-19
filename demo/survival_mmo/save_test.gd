extends SceneTree
## Run: godot --headless --path demo/survival_mmo --script res://save_test.gd
## This test intentionally uses a separate temporary save slot.

const SaveScript = preload("res://save_system.gd")
const TEST_PATH := "user://survival_world_smoke_test.json"
var failures := 0


func _check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)


func _clean_files() -> void:
    for suffix in ["", ".tmp", ".bak"]:
        var path := TEST_PATH + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    _clean_files()
    var scene := load("res://main.tscn") as PackedScene
    _check(scene != null, "Main scene must load.")
    if scene == null:
        quit(1)
        return
    var game := scene.instantiate()
    root.add_child(game)
    await physics_frame
    await physics_frame

    var state = game.get("state")
    state.add_item("wood", 7)
    state.add_item("stone", 3)
    state.award_experience("logging", 65)
    _check(state.craft_spear(), "Prepare crafted equipment for persistence.")
    state.damage_weapon(21)
    state.apply_damage(21.0)
    state.tick(10.0)

    var player: Node3D = game.get_node("Survivor") as Node3D
    player.global_position = Vector3(12.0, 0.95, 2.0)
    var resource: Node3D = get_nodes_in_group("gatherable")[0] as Node3D
    resource.set_meta("remaining", 2)
    var mesh := resource.get_node("Visual") as MeshInstance3D
    mesh.scale = Vector3.ONE * pow(0.83, 2)
    var barricade := game.call("_spawn_barricade", Vector3(8.0, 0.72, 0.0),
        0.0, 66.0) as StaticBody3D
    var infected = get_nodes_in_group("infected")[0]
    infected.health = 12.0

    var original: Dictionary = game.call("_make_snapshot")
    _check(SaveScript.is_valid_snapshot(original), "Game snapshot must validate.")
    _check(SaveScript.write_snapshot(original, TEST_PATH), "Initial disk write must succeed.")
    _check(SaveScript.write_snapshot(original, TEST_PATH), "Repeated disk write must preserve a valid save.")
    var read_back: Dictionary = SaveScript.read_snapshot(TEST_PATH)
    _check(not read_back.is_empty(), "Disk read must return a valid snapshot.")
    _check(int(read_back["state"]["items"]["wood"]) == 5, "Wood count must round-trip.")
    _check(int(read_back["state"]["experience"]["logging"]) == 65, "Skill XP must round-trip.")
    _check(read_back["state"]["weapon"] == "spear", "Equipment must round-trip.")
    _check(int(read_back["state"]["weapon_condition"]) == 39,
        "Weapon durability must round-trip.")
    _check(read_back["world"]["barricades"].size() == 1, "Barricade must be persisted.")
    _check(is_equal_approx(float(read_back["world"]["barricades"][0]["hp"]), 66.0),
        "Barricade health must round-trip.")
    _check(int(read_back["world"]["resources"][0]["remaining"]) == 2,
        "Depleted resources must retain remaining charges.")

    var corrupted: Dictionary = original.duplicate(true)
    corrupted["state"]["items"]["wood"] = -10
    _check(not SaveScript.is_valid_snapshot(corrupted), "Negative inventory must be rejected.")
    corrupted = original.duplicate(true)
    corrupted["world"]["resources"][0]["kind"] = "malicious_entity"
    _check(not SaveScript.is_valid_snapshot(corrupted), "Unknown resource kind must be rejected.")
    corrupted = original.duplicate(true)
    corrupted["state"]["weapon_condition"] = 1000
    _check(not SaveScript.is_valid_snapshot(corrupted), "Invalid weapon durability must be rejected.")
    corrupted = original.duplicate(true)
    corrupted["world"]["barricades"][0]["hp"] = -12.0
    _check(not SaveScript.is_valid_snapshot(corrupted), "Invalid barricade health must be rejected.")
    corrupted = original.duplicate(true)
    corrupted["version"] = 1000
    _check(not SaveScript.is_valid_snapshot(corrupted), "Future/incompatible versions must be rejected.")
    corrupted = original.duplicate(true)
    corrupted["player"] = [INF, 0.0, 0.0]
    _check(not SaveScript.is_valid_snapshot(corrupted), "Nonfinite positions must be rejected.")

    state.items["wood"] = 0
    state.experience["logging"] = 0
    state.equipped_weapon = "hands"
    state.weapon_condition = 0
    player.global_position = Vector3.ZERO
    game.call("_clear_dynamic_entities")
    _check(game.call("_load_game", TEST_PATH), "Load must restore the saved world.")
    _check(int(state.items["wood"]) == 5, "Inventory must be restored.")
    _check(int(state.experience["logging"]) == 65, "Professions must be restored.")
    _check(state.equipped_weapon == "spear", "Equipment must be restored.")
    _check(int(state.weapon_condition) == 39, "Equipment durability must be restored.")
    _check(player.global_position.distance_to(Vector3(12.0, 0.95, 2.0)) < 0.01,
        "Character position must be restored.")
    _check(get_nodes_in_group("gatherable").size() == original["world"]["resources"].size(),
        "Resource node count must be restored.")
    _check(get_nodes_in_group("infected").size() == original["world"]["infected"].size(),
        "Enemy node count must be restored.")
    _check(get_nodes_in_group("player_building").size() == 1,
        "Physical barricades must be restored.")
    var loaded_barrier: StaticBody3D = get_nodes_in_group("player_building")[0] as StaticBody3D
    _check(is_equal_approx(float(loaded_barrier.get_meta("hp")), 66.0),
        "Physical barricade health must restore.")
    var first_resource: Node3D = get_nodes_in_group("gatherable")[0] as Node3D
    _check(int(first_resource.get_meta("remaining")) == 2, "Resource charges must restore.")
    _check(not game.call("_apply_snapshot", corrupted), "Applying incompatible save must fail.")
    _check(state.equipped_weapon == "spear", "Rejected snapshot must not mutate equipment.")

    var invalid_file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
    if invalid_file != null:
        invalid_file.store_string("{ broken JSON")
        invalid_file.close()
    _check(not game.call("_load_game", TEST_PATH), "Unreadable JSON must not modify game state.")
    _check(state.equipped_weapon == "spear", "Failed load must preserve live state.")

    # The new v1 fields are optional. Older saves restore full durability.
    var legacy: Dictionary = original.duplicate(true)
    legacy["state"].erase("weapon_condition")
    legacy["world"]["barricades"][0].erase("hp")
    _check(SaveScript.is_valid_snapshot(legacy), "Existing version-1 saves must remain readable.")
    _check(game.call("_apply_snapshot", legacy), "Existing version-1 saves must restore.")
    _check(int(state.weapon_condition) == 60, "Legacy weapon condition defaults to full.")
    var legacy_barrier: StaticBody3D = get_nodes_in_group("player_building")[0] as StaticBody3D
    _check(is_equal_approx(float(legacy_barrier.get_meta("hp")), 100.0),
        "Legacy barricade HP defaults to full.")

    game.queue_free()
    await process_frame
    _clean_files()
    print("Survival world persistence smoke: ", "PASS" if failures == 0 else "%d failures" % failures)
    quit(0 if failures == 0 else 1)
