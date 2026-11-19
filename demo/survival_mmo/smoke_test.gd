extends SceneTree
## Cgame --headless --path demo/survival_mmo --script res://smoke_test.gd

const StateScript = preload("res://game_state.gd")
var failures := 0


func _check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        push_error(message)


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var rules = StateScript.new()
    _check(not rules.has_cost("spear"), "Cannot craft a spear for free.")
    rules.add_item("wood", 3)
    rules.add_item("stone", 2)
    _check(rules.craft_spear(), "Spear must be craftable with required resources.")
    _check(rules.has_spear and rules.items["wood"] == 1 and rules.items["stone"] == 1,
        "Crafting must consume exact costs.")
    _check(not rules.craft_spear(), "One survivor should not craft duplicate spear equipment.")
    _check(not rules.spend_recipe("missing"), "Unknown recipes must be rejected.")
    rules.apply_damage(22.0)
    rules.heal(10.0)
    _check(is_equal_approx(rules.health, 88.0), "Damage and healing must be bounded.")
    rules.add_item("herb")
    rules.tick(50.0)
    _check(rules.eat_herb(), "Herb should replenish hunger.")
    _check(rules.items["herb"] == 0, "Eating must consume the herb.")

    var packed := load("res://main.tscn") as PackedScene
    _check(packed != null, "Prototype main scene must load.")
    if packed == null:
        quit(1)
        return
    var game := packed.instantiate()
    root.add_child(game)
    await process_frame
    _check(game.get_node_or_null("Survivor") != null, "Missing controllable survivor.")
    _check(game.get_node_or_null("Ground") != null, "Missing physical terrain.")
    _check(get_nodes_in_group("gatherable").size() >= 12, "Missing resource locations.")
    _check(get_nodes_in_group("infected").size() == 3, "Missing zombie encounters.")
    var survivor := game.get_node("Survivor") as CharacterBody3D
    var resource = get_nodes_in_group("gatherable")[0]
    survivor.global_position = resource.global_position + Vector3(0, 0.6, 0)
    game.call("_harvest")
    var state = game.get("state")
    _check(int(state.items["wood"]) == 1, "Nearby gathering must award a resource.")

    state.add_item("wood", 3)
    state.add_item("stone", 2)
    game.call("_build")
    _check(get_nodes_in_group("player_building").size() == 1, "Barricade must create a world collider.")
    var zombie = get_nodes_in_group("infected")[0]
    survivor.global_position = zombie.global_position
    var before: float = zombie.health
    game.call("_attack")
    _check(zombie.health < before, "Melee must damage a nearby zombie.")
    await physics_frame
    game.queue_free()
    print("Survival MMO prototype smoke checks: ", "PASS" if failures == 0 else "%d failures" % failures)
    quit(0 if failures == 0 else 1)
