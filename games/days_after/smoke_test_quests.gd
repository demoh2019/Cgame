extends SceneTree
## Run with compiled Cgame:
## godot --headless --path games/days_after --script res://smoke_test_quests.gd

const JOURNAL = preload("res://quest_journal.gd")
const SAVE = preload("res://save_game.gd")
const PATH: String = "user://days_after_quest_smoke.json"


func _initialize() -> void:
    call_deferred("_run")


func _expect(condition: bool, description: String, errors: Array[String]) -> void:
    if not condition:
        errors.append(description)
        push_error(description)


func _write_json(data: Dictionary) -> bool:
    var file := FileAccess.open(PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(data))
    file.close()
    return true


func _run() -> void:
    var errors: Array[String] = []
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        push_error("Cannot load Days After mission test scene")
        quit(1)
        return
    var game := scene.instantiate() as Node3D
    root.add_child(game)
    for frame in range(3):
        await physics_frame

    var state = game.get("state")
    var journal = game.get("quests")
    _expect(game.get_node_or_null("HUD/QuestTracker") != null,
            "Missing quest tracker UI", errors)

    # Perform the final mission FIRST: forward progress must not be lost
    # when quests unlock later.
    _expect(state.add_resource("wood", 2), "Cannot seed wood", errors)
    _expect(state.add_resource("scrap", 1), "Cannot seed scrap", errors)
    _expect(game.call("craft_item", "makeshift_spear"), "Craft quest action failed", errors)
    _expect(game.call("equip_item", "makeshift_spear"), "Equip quest action failed", errors)
    var infected := game.get_node("InfectedScavenger") as CharacterBody3D
    for hit in range(3):
        game.call("_on_attack", infected)
    _expect(float(infected.get("health")) == 0.0, "Infected remains alive", errors)
    _expect(journal.objective_count("kill.infected") == 1, "Kill was not recorded", errors)
    _expect(journal.completed == 0, "Future mission completed before first one", errors)

    # First quest: scavenging food and water through the actual world.
    game.call("_on_interact", game.get_node("FoodRation"))
    game.call("_on_interact", game.get_node("WaterBottle"))
    _expect(journal.completed == 1, "First supplies quest did not complete", errors)
    _expect(int(state.inventory["scrap"]) == 1, "First quest reward incorrect", errors)
    game.call("_on_interact", game.get_node("WaterBottle"))
    _expect(journal.objective_count("pickup.water") == 1, "Replayed pickup counted twice", errors)

    # Gather materials by interacting with finite resource nodes.
    var timber := game.get_node("FallenTimber") as Area3D
    var fiber := game.get_node("DryGrass") as Area3D
    game.call("_on_interact", timber)
    game.call("_on_interact", timber)
    game.call("_on_interact", fiber)
    game.call("_on_interact", fiber)
    game.call("_on_interact", game.get_node("RockDeposit"))
    _expect(journal.completed == 3,
            "Previously performed crafting and combat should complete final mission", errors)
    _expect(int(state.inventory["food"]) == 2 and int(state.inventory["water"]) == 2,
            "Quest supplies were not granted exactly once", errors)
    var before_duplicate: Dictionary = state.inventory.duplicate(true)
    journal.record_event("pickup.food", state)
    journal.record_event("kill.infected", state)
    journal.record_event("unknown.event", state)
    _expect(before_duplicate == state.inventory, "Completed quest rewarded again", errors)
    _expect(journal.summary().contains("completed"), "Quest tracker was not finalized", errors)

    # Version 2 persists the quest journal with the rest of the running world.
    var expected: Dictionary = SAVE.capture(game)
    _expect(int(expected["version"]) == 2, "Expected version 2 snapshot", errors)
    _expect(game.call("save_game", PATH), "Quest save failed", errors)
    journal.restore_validated(JOURNAL.empty_snapshot())
    state.inventory["food"] = 0
    _expect(game.call("load_game", PATH), "Quest load failed", errors)
    _expect(SAVE.capture(game) == expected, "Journal did not round-trip", errors)

    # Corrupt mission completion must reject the ENTIRE snapshot atomically.
    var invalid: Dictionary = expected.duplicate(true)
    invalid["quests"]["counts"]["pickup.water"] = 0
    _expect(_write_json(invalid), "Cannot write invalid quest fixture", errors)
    _expect(not game.call("load_game", PATH), "Accepted incomplete claimed mission", errors)
    _expect(SAVE.capture(game) == expected, "Invalid quest save changed survivor or world", errors)

    invalid = expected.duplicate(true)
    invalid["quests"]["counts"]["kill.infected"] = 999
    _expect(_write_json(invalid), "Cannot write overflow fixture", errors)
    _expect(not game.call("load_game", PATH), "Accepted overflow mission counter", errors)

    # Old v1 checkpoints do not have quests: migrate with a fresh journal.
    var v1: Dictionary = expected.duplicate(true)
    v1["version"] = 1
    v1.erase("quests")
    _expect(_write_json(v1), "Cannot write v1 fixture", errors)
    _expect(game.call("load_game", PATH), "Legacy v1 checkpoint rejected", errors)
    _expect(journal.snapshot() == JOURNAL.empty_snapshot(),
            "Legacy checkpoint did not reset the journal", errors)

    # Rewards must not overflow the inventory stack limit.
    var fresh = JOURNAL.new()
    state.inventory["scrap"] = JOURNAL.STACK_LIMIT
    fresh.record_event("pickup.food", state)
    fresh.record_event("pickup.water", state)
    _expect(fresh.completed == 0, "Overflow reward was granted", errors)
    state.inventory["scrap"] = JOURNAL.STACK_LIMIT - 1
    fresh.record_event("pickup.food", state)
    _expect(fresh.completed == 1 and int(state.inventory["scrap"]) == JOURNAL.STACK_LIMIT,
            "Pending reward was not granted after space freed", errors)

    DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + ".tmp"))
    game.queue_free()
    await process_frame
    if errors.is_empty():
        print("PASS: missions, early objectives, exactly-once rewards, v1 migration and save guards")
    quit(0 if errors.is_empty() else 1)
