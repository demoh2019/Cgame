extends SceneTree
## Run: godot --headless --path demo/survival_mmo --script res://encumbrance_test.gd
const StateScript = preload("res://game_state.gd")
const PlayerScript = preload("res://player.gd")
var failures := 0


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var state = StateScript.new()
    _check(is_equal_approx(state.get_carry_weight(), 0.0), "Empty inventory must be weightless.")
    _check(state.can_sprint() and is_equal_approx(state.move_speed_factor(), 1.0),
        "Unencumbered survivors can sprint at full speed.")
    _check(state.add_item("stone", 100) == 16, "Heavy resource pickup must clamp to hard capacity.")
    _check(is_equal_approx(state.get_carry_weight(), 48.0), "Stone weight must sum correctly.")
    _check(state.add_item("wood", 1) == 1, "Exactly fitting item must be accepted.")
    _check(is_equal_approx(state.get_carry_weight(), 50.0), "Total mass must hit the hard limit.")
    _check(state.add_item("wood", 1) == 0, "Full pack must reject extra wood.")
    _check(state.add_item("missing", 20) == 0, "Unknown items must be rejected.")
    _check(state.add_item("stone", -2) == 0, "Invalid amounts must be rejected.")
    _check(state.is_encumbered() and not state.can_sprint(), "Hard load must disable sprint.")
    _check(is_equal_approx(state.move_speed_factor(), 0.5), "Max load should halve movement.")
    var wood_before: int = state.items["wood"]
    var xp_before: int = state.experience["logging"]
    _check(state.collect_resource("wood") == 0, "Gather must fail with full load.")
    _check(int(state.items["wood"]) == wood_before and int(state.experience["logging"]) == xp_before,
        "Rejected gathering must neither award XP nor mutate inventory.")
    _check(state.spend_recipe("barricade") == false, "Cannot craft without required ingredients.")
    _check(state.spend_recipe("spear") == false, "Cannot craft from only one wood.")
    state = StateScript.new()
    _check(state.add_item("wood", 12) == 12, "Normal gathering should accept 12 wood.")
    _check(state.can_sprint(), "Exactly 24 kg should not disable sprint.")
    _check(state.add_item("wood", 1) == 1, "A 26 kg load should be accepted.")
    _check(state.is_encumbered() and state.move_speed_factor() < 1.0,
        "Weight beyond comfort load must slow movement.")
    _check(state.add_item("stone", 8) == 8, "Can fill pack to exactly 50 kg.")
    _check(is_equal_approx(state.get_carry_weight(), 50.0), "Combined weights should be exact.")
    _check(state.spend_recipe("barricade"), "Crafting should consume resources while overloaded.")
    _check(is_equal_approx(state.get_carry_weight(), 38.0), "Crafting should free 12 kg.")
    _check(state.item_capacity("wood") == 6, "New capacity should reflect consumed ingredients.")
    _check(state.add_item("fiber", 4) == 4, "Lighter items use fractional carry weights.")
    _check(is_equal_approx(state.get_carry_weight(), 40.0), "Fractional weights should be accurate.")
    _check(state.item_capacity("missing") == 0, "Unknown item capacity must be zero.")

    var player = PlayerScript.new()
    _check(is_equal_approx(player.movement_speed(false), 5.0), "Base walk speed unchanged.")
    _check(is_equal_approx(player.movement_speed(true), 7.5), "Base sprint speed unchanged.")
    player.cargo_speed_factor = 0.5
    player.sprint_available = false
    _check(is_equal_approx(player.movement_speed(true), 2.5),
        "Encumbered sprint key must not bypass walking speed penalty.")
    player.free()

    var packed := load("res://main.tscn") as PackedScene
    _check(packed != null, "Game scene must load.")
    if packed == null:
        quit(1)
        return
    var game = packed.instantiate()
    root.add_child(game)
    await physics_frame
    await physics_frame

    var world_state = game.get("state")
    var resource = get_nodes_in_group("gatherable")[0]
    var survivor: CharacterBody3D = game.get_node("Survivor") as CharacterBody3D
    survivor.global_position = resource.global_position + Vector3(0.0, 0.6, 0.0)
    world_state.add_item("stone", 16)
    world_state.add_item("wood", 1)
    var charge_before: int = int(resource.get_meta("remaining"))
    var xp_world_before: int = int(world_state.experience["logging"])
    game.call("_harvest")
    _check(int(resource.get_meta("remaining")) == charge_before,
        "Overloaded world gathering must not deplete resource nodes.")
    _check(int(world_state.experience["logging"]) == xp_world_before,
        "Overloaded gathering must not award profession XP.")
    _check("Backpack full" in str(game.status_message), "HUD should report full backpack.")
    game._process(0.016)
    _check(is_equal_approx(survivor.cargo_speed_factor, 0.5),
        "Game loop must propagate cargo factor to character controller.")
    _check(not survivor.sprint_available, "Game loop must disallow sprint at hard load.")
    game.queue_free()
    await process_frame
    print("Survival encumbrance checks: ", "PASS" if failures == 0 else "%d failures" % failures)
    quit(0 if failures == 0 else 1)
