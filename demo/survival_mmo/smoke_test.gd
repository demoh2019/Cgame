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
    _check(rules.get_level("logging") == 1, "Gathering starts at level one.")
    _check(rules.get_level("unknown") == 0, "Unknown skill has no level.")
    _check(rules.collect_resource("unknown") == 0, "Unknown resources must not spawn items.")
    _check(rules.collect_resource("wood") == 1, "Basic gathering grants one resource.")
    _check(rules.experience["logging"] == 5, "Gathering must award profession XP.")
    # Level three starts at 40 XP. The ninth collection benefits from its yield bonus.
    for i in range(7):
        rules.collect_resource("wood")
    _check(rules.get_level("logging") == 3, "XP must unlock higher gathering tiers.")
    _check(rules.collect_resource("wood") == 2, "Level-three logging must yield two wood.")
    _check(rules.get_level("mining") == 1, "Skills must progress independently.")

    _check(not rules.has_cost("spear"), "Cannot craft a spear for free.")
    rules.add_item("wood", 3)
    rules.add_item("stone", 4)
    _check(rules.craft_spear(), "Spear must be craftable with required resources.")
    _check(rules.equipped_weapon == "spear", "Crafted spear must become equipped.")
    _check(not rules.craft_spear(), "Cannot equip duplicate starter spears.")
    _check(is_equal_approx(rules.weapon_damage(), 26.0), "Spear damage must come from equipment.")
    _check(not rules.craft_weapon("reinforced_spear"), "Combat level gates upgraded weapons.")
    _check(not rules.spend_recipe("missing"), "Unknown recipes must be rejected.")
    rules.report_attack(true)
    _check(rules.get_level("combat") == 2, "Combat kills must increase combat level.")
    _check(is_equal_approx(rules.weapon_damage(), 28.0), "Combat skill grants a small damage bonus.")
    _check(not rules.craft_weapon("reinforced_spear"), "Upgrade must not ignore missing scrap.")
    rules.add_item("scrap", 2)
    _check(rules.craft_weapon("reinforced_spear"), "Upgraded spear should craft after unlock.")
    _check(rules.equipped_weapon == "reinforced_spear", "Upgrade must replace the equipped weapon.")
    _check(is_equal_approx(rules.weapon_damage(), 42.0), "Upgraded spear must change combat damage.")
    _check(rules.items["scrap"] == 0, "Upgrades must consume loot.")
    _check(not rules.craft_weapon("reinforced_spear"), "Cannot recraft the same equipped weapon.")

    rules.apply_damage(22.0)
    rules.heal(10.0)
    _check(is_equal_approx(rules.health, 88.0), "Damage and healing must be bounded.")
    rules.add_item("herb")
    rules.tick(50.0)
    _check(rules.eat_herb(), "Herb should replenish hunger.")
    _check(rules.items["herb"] == 0, "Eating must consume the herb.")

    var packed := load("res://main.tscn") as PackedScene
    _check(packed != null, "Prototype scene must load.")
    if packed == null:
        quit(1)
        return
    var game := packed.instantiate()
    root.add_child(game)
    await physics_frame
    await physics_frame
    _check(game.get_node_or_null("Survivor") != null, "Missing controllable survivor.")
    _check(game.get_node_or_null("Ground") != null, "Missing physical terrain.")
    _check(get_nodes_in_group("gatherable").size() >= 12, "Missing resource locations.")
    _check(get_nodes_in_group("infected").size() == 3, "Missing infected encounters.")

    var survivor := game.get_node("Survivor") as CharacterBody3D
    var resource: Node3D = get_nodes_in_group("gatherable")[0] as Node3D
    survivor.global_position = resource.global_position + Vector3(0, 0.6, 0)
    game.call("_harvest")
    var state = game.get("state")
    _check(int(state.items["wood"]) == 1, "Nearby gathering should award wood.")
    _check(int(state.experience["logging"]) == 5, "World gathering must award logging XP.")

    state.add_item("wood", 6)
    state.add_item("stone", 4)
    survivor.global_position = Vector3(-10.0, 0.95, -4.3)
    survivor.set("facing", Vector3(0.0, 0.0, -1.0))
    _check(not bool(game.call("_can_place_barricade", Vector3(-10.0, 0.72, -7.0), 0.0)),
        "Ruined walls should block building placement.")
    var wood_before: int = state.items["wood"]
    game.call("_build")
    _check(int(state.items["wood"]) == wood_before, "Blocked construction must not consume wood.")
    _check(get_nodes_in_group("player_building").size() == 0, "Blocked construction must not spawn a barrier.")

    survivor.global_position = Vector3(0.0, 0.95, 0.0)
    _check(bool(game.call("_can_place_barricade", Vector3(0.0, 0.72, -2.7), 0.0)),
        "Empty terrain should accept a barricade.")
    game.call("_build")
    _check(get_nodes_in_group("player_building").size() == 1, "Valid build must create a barricade.")
    _check(int(state.items["wood"]) == wood_before - 3, "Valid build must consume the recipe.")
    _check(int(state.experience["crafting"]) == 10, "Building must grant crafting XP.")

    var zombie = get_nodes_in_group("infected")[0]
    survivor.global_position = zombie.global_position
    var before: float = zombie.health
    game.call("_attack")
    _check(zombie.health < before, "Melee must damage nearby infected.")
    _check(int(state.experience["combat"]) >= 3, "World combat must grant combat XP.")

    await physics_frame
    game.queue_free()
    print("Survival MMO progression smoke checks: ", "PASS" if failures == 0 else "%d failures" % failures)
    quit(0 if failures == 0 else 1)
