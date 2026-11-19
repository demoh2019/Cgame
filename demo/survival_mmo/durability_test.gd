extends SceneTree
## Run: godot --headless --path demo/survival_mmo --script res://durability_test.gd

const StateScript = preload("res://game_state.gd")
const SaveScript = preload("res://save_system.gd")
var failures := 0


func _check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var rules = StateScript.new()
    _check(not rules.repair_weapon(), "Unarmed characters cannot repair weapons.")
    rules.add_item("wood", 10)
    rules.add_item("stone", 10)
    rules.add_item("scrap", 10)
    _check(rules.craft_spear(), "Must be able to craft initial spear.")
    _check(rules.weapon_condition == 60, "Spear starts at 60 durability.")
    _check(not rules.repair_weapon(), "Full-condition spear cannot consume materials.")
    _check(not rules.damage_weapon(24), "A partial hit must not break spear.")
    _check(rules.weapon_condition == 36, "Wear must subtract exact durability.")
    var wood_before: int = rules.items["wood"]
    var scrap_before: int = rules.items["scrap"]
    _check(rules.repair_weapon(), "Damaged spear should be repairable.")
    _check(rules.weapon_condition == 60, "Repair must clamp at maximum durability.")
    _check(int(rules.items["wood"]) == wood_before - 1 and int(rules.items["scrap"]) == scrap_before - 1,
        "Repair materials must be consumed exactly once.")
    _check(rules.damage_weapon(60), "Weapon should break when durability reaches zero.")
    _check(rules.equipped_weapon == "hands" and rules.weapon_condition == 0,
        "Broken spear must revert to unarmed.")
    _check(not rules.repair_weapon(), "Broken weapon cannot be restored for free.")
    _check(rules.craft_spear(), "After breakage, a replacement weapon can be crafted.")
    rules.report_attack(true)
    _check(rules.craft_weapon("reinforced_spear"), "Progression should unlock upgraded spear.")
    _check(rules.weapon_condition == 100, "Reinforced spear starts at 100 durability.")
    _check(rules.damage_weapon(999), "Wear must be bounded and break weapons safely.")
    _check(rules.weapon_condition == 0, "Condition never goes negative.")

    var packed := load("res://main.tscn") as PackedScene
    _check(packed != null, "Scene must load.")
    if packed == null:
        quit(1)
        return
    var game := packed.instantiate()
    root.add_child(game)
    await physics_frame
    await physics_frame

    var world_state = game.get("state")
    var barrier := game.call("_spawn_barricade", Vector3(0, 0.72, -2.7), 0.0) as StaticBody3D
    _check(barrier != null, "Must spawn a barricade collider.")
    _check(is_equal_approx(float(barrier.get_meta("hp")), 100.0), "Barricade starts at full HP.")
    _check(not game.call("receive_barricade_hit", barrier, 40.0), "Partial damage must not destroy barricade.")
    _check(is_equal_approx(float(barrier.get_meta("hp")), 60.0), "Zombie damage must lower barricade HP.")
    _check(not game.call("_repair_barricade"), "Repair without resources must fail.")
    _check(is_equal_approx(float(barrier.get_meta("hp")), 60.0), "Failed repair must preserve HP.")
    world_state.add_item("wood", 3)
    world_state.add_item("stone", 3)
    _check(game.call("_repair_barricade"), "Barricade must be repairable when nearby.")
    _check(is_equal_approx(float(barrier.get_meta("hp")), 95.0), "Repair must restore 35 HP.")
    _check(game.call("_repair_barricade"), "Second repair must succeed.")
    _check(is_equal_approx(float(barrier.get_meta("hp")), 100.0), "Repair must clamp at full HP.")
    var remaining_wood: int = world_state.items["wood"]
    _check(not game.call("_repair_barricade"), "Full barricades cannot be repaired.")
    _check(int(world_state.items["wood"]) == remaining_wood, "Full repair must not spend resources.")
    _check(game.call("_salvage_barricade"), "Nearby barricades can be dismantled.")
    _check(get_nodes_in_group("player_building").size() == 0, "Salvaged barricades leave the world.")
    _check(int(world_state.items["wood"]) == remaining_wood + 1, "Salvage should refund some wood.")
    _check(not game.call("_salvage_barricade"), "Cannot repeatedly salvage the same structure.")

    barrier = game.call("_spawn_barricade", Vector3(0, 0.72, -2.7), 0.0, 15.0) as StaticBody3D
    _check(game.call("receive_barricade_hit", barrier, 18.0), "Lethal infected hit must destroy barricade.")
    _check(get_nodes_in_group("player_building").size() == 0, "Destroyed barricade must leave world group.")

    var snapshot: Dictionary = game.call("_make_snapshot")
    _check(SaveScript.is_valid_snapshot(snapshot), "World snapshot after destruction must validate.")
    var broken_state: Dictionary = snapshot.duplicate(true)
    broken_state["state"]["weapon_condition"] = 50
    _check(not SaveScript.is_valid_snapshot(broken_state), "Unarmed state cannot carry weapon durability.")

    game.queue_free()
    print("Durability + structures checks: ", "PASS" if failures == 0 else "%d failures" % failures)
    quit(0 if failures == 0 else 1)
