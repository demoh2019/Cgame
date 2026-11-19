extends SceneTree
## Headless regression:
## <cgame-editor> --headless --path demo/days_after --script res://smoke_test_durability.gd

const Durability = preload("res://equipment_durability.gd")
const SaveState = preload("res://save_state.gd")


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Durability regression: " + message)
    quit(1)


func _run() -> void:
    var packed := load("res://main.tscn") as PackedScene
    if packed == null:
        _fail("Cannot load Days After.")
        return
    var game := packed.instantiate()
    root.add_child(game)
    var player := game.get_node_or_null("Player") as Node3D
    if player == null:
        _fail("Missing survivor.")
        return

    player.call("add_item", "rusty_spear", 1)
    if not bool(player.call("equip_item", "weapon", "rusty_spear")):
        _fail("Cannot equip spear.")
        return
    if player.call("get_item_condition", "rusty_spear") != 100:
        _fail("New spear must start fully repaired.")
        return
    if not Durability.wear(player.get("durability") as Dictionary, "rusty_spear", 100):
        _fail("Wear should accept owned equipment.")
        return
    if player.call("get_attack_damage") != 12.0:
        _fail("Broken weapon must not provide combat bonus.")
        return
    if bool(player.call("repair_item", "rusty_spear")):
        _fail("Repair without resources should be rejected.")
        return
    if player.call("get_item_condition", "rusty_spear") != 0:
        _fail("Failed repair must not change condition.")
        return

    player.call("add_item", "wood_t1", 2)
    if bool(player.call("repair_item", "rusty_spear")):
        _fail("Incomplete recipe must not spend wood.")
        return
    if player.call("get_item_count", "wood_t1") != 2:
        _fail("Invalid repair consumed ingredients.")
        return
    player.call("add_item", "stone_t1", 1)
    if not bool(player.call("repair_item", "rusty_spear")):
        _fail("Valid spear repair failed.")
        return
    if player.call("get_attack_damage") != 32.0 or player.call("get_item_count", "wood_t1") != 1:
        _fail("Repair didn't restore equipment or consume exact materials.")
        return

    player.call("add_item", "scavenger_tool", 1)
    player.call("equip_item", "tool", "scavenger_tool")
    var mastery: Dictionary = player.get("gathering_xp")
    mastery["wood"] = 100
    Durability.wear(player.get("durability") as Dictionary, "scavenger_tool", 100)
    if player.call("try_gather", "wood", 2, 1):
        _fail("Broken tool must not harvest tier 2.")
        return
    if player.call("get_item_count", "wood_t2") != 0:
        _fail("Blocked harvest added tier-2 materials.")
        return
    player.call("add_item", "stone_t1", 1)
    if not bool(player.call("repair_item", "scavenger_tool")):
        _fail("Cannot repair scavenger tool.")
        return
    if not player.call("try_gather", "wood", 2, 1):
        _fail("Repaired tool must harvest tier 2.")
        return
    if player.call("get_item_condition", "scavenger_tool") != 97:
        _fail("Gathering must wear the equipped tool.")
        return

    player.call("add_item", "scrap_vest", 1)
    player.call("equip_item", "armor", "scrap_vest")
    Durability.wear(player.get("durability") as Dictionary, "scrap_vest", 99)
    player.set("health", 100.0)
    player.call("take_damage", 20.0)
    if float(player.get("health")) != 85.0 or player.call("get_item_condition", "scrap_vest") != 0:
        _fail("Armor must mitigate the final hit and then break.")
        return
    player.call("take_damage", 20.0)
    if float(player.get("health")) != 65.0:
        _fail("Broken armor must not mitigate damage.")
        return

    var data: Dictionary = SaveState.snapshot(player)
    if not SaveState.validate_snapshot(data):
        _fail("Current character snapshot rejected.")
        return
    var conditions: Dictionary = player.get("durability")
    conditions.clear()
    if not SaveState.apply_snapshot(player, data):
        _fail("Couldn't restore saved condition.")
        return
    if player.call("get_item_condition", "scrap_vest") != 0:
        _fail("Broken armor condition did not round-trip.")
        return

    var invalid: Dictionary = data.duplicate(true)
    invalid["durability"]["rusty_spear"] = -1
    if SaveState.apply_snapshot(player, invalid):
        _fail("Invalid condition must reject whole snapshot.")
        return
    if player.call("get_item_condition", "rusty_spear") != 100:
        _fail("Rejected snapshot partially mutated condition.")
        return
    var legacy: Dictionary = data.duplicate(true)
    legacy.erase("durability")
    if not SaveState.validate_snapshot(legacy):
        _fail("Existing version-1 saves must remain valid.")
        return
    if not SaveState.apply_snapshot(player, legacy) or player.call("get_item_condition", "scrap_vest") != 100:
        _fail("Legacy saves should initialize equipment at full condition.")
        return

    game.queue_free()
    await process_frame
    print("PASS: equipment durability, tiered tool wear, armor breakage, repairs and compatible saves.")
    quit(0)
