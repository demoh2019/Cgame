extends SceneTree

## Use the Cgame editor executable:
## --headless --path demo/days_after --script res://smoke_test_contracts.gd

const RULES = preload("res://contract_rules.gd")
const SAVES = preload("res://save_state.gd")


func _initialize() -> void:
    call_deferred("_run")


func _expect(ok: bool, context: String) -> bool:
    if ok:
        return true
    push_error("Days After contracts: " + context)
    quit(1)
    return false


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if not _expect(scene != null, "main scene loads"):
        return
    var game := scene.instantiate() as Node3D
    root.add_child(game)
    var survivor := game.get_node_or_null("Player") as CharacterBody3D
    var board := game.get_node_or_null("CampContracts") as Area3D
    if not _expect(survivor != null and board != null,
            "survivor and contract board are in the same world"):
        return

    if not _expect(RULES.validate_state(survivor.get("contract_state")),
            "fresh journal is valid"):
        return
    if not _expect(bool(board.call("interact", survivor))
            and str((survivor.get("contract_state") as Dictionary)["active"]) == "supply_run",
            "accept first gathering delivery contract"):
        return
    if not _expect(not bool(board.call("interact", survivor)),
            "cannot claim a contract without supplies"):
        return

    survivor.call("add_item", "wood_t1", 4)
    survivor.call("add_item", "fiber_t1", 2)

    # Overflow must reject the full transaction rather than consume resources.
    survivor.call("add_item", "food", 1000000)
    if not _expect(not bool(board.call("interact", survivor))
            and int(survivor.call("get_item_count", "wood_t1")) == 4
            and int(survivor.call("get_item_count", "fiber_t1")) == 2,
            "full reward stack aborts claim without losing delivery goods"):
        return
    var stock: Dictionary = survivor.get("inventory")
    stock["food"] = 0

    if not _expect(bool(board.call("interact", survivor))
            and int(survivor.call("get_item_count", "wood_t1")) == 2
            and int(survivor.call("get_item_count", "fiber_t1")) == 0
            and int(survivor.call("get_item_count", "food")) == 1
            and int(survivor.call("get_item_count", "water")) == 2,
            "successful delivery consumes exact stacks and rewards exactly once"):
        return
    if not _expect((survivor.get("contract_state") as Dictionary)["completed"].has("supply_run"),
            "first contract is permanently recorded complete"):
        return

    if not _expect(bool(board.call("interact", survivor))
            and str((survivor.get("contract_state") as Dictionary)["active"]) == "smith_training",
            "second contract unlocks in order"):
        return
    if not _expect(not bool(board.call("interact", survivor)),
            "weapon trial requires ownership of a crafted weapon"):
        return
    survivor.call("add_item", "stone_t1", 2)
    if not _expect(bool(survivor.call("craft_recipe", "rusty_spear"))
            and str(survivor.get("equipped_weapon")) == "rusty_spear",
            "real crafting unlocks the weapon trial"):
        return
    if not _expect(bool(board.call("interact", survivor))
            and int(survivor.call("get_item_count", "rusty_spear")) == 1
            and int(survivor.call("get_item_count", "field_bandage")) == 2,
            "weapon is demonstrated, not consumed or unequipped"):
        return

    if not _expect(bool(board.call("interact", survivor))
            and str((survivor.get("contract_state") as Dictionary)["active"]) == "infected_patrol",
            "infection cleanup contract becomes active"):
        return
    if not _expect(not bool(board.call("interact", survivor)),
            "a player must kill infected AFTER accepting patrol"):
        return

    var enemy_a := game.get_node_or_null("InfectedWalker") as CharacterBody3D
    var enemy_b := game.get_node_or_null("InfectedRoad") as CharacterBody3D
    if not _expect(enemy_a != null and enemy_b != null, "two real infected exist"):
        return
    enemy_a.call("take_damage", 1000.0)
    if not _expect(int((survivor.get("contract_state") as Dictionary)["progress"]) == 1
            and not bool(board.call("interact", survivor)),
            "one kill cannot complete a two-kill patrol"):
        return
    enemy_b.call("take_damage", 1000.0)
    if not _expect(int((survivor.get("contract_state") as Dictionary)["progress"]) == 2
            and bool(board.call("interact", survivor))
            and int(survivor.call("get_item_count", "fiber_t2")) == 2,
            "two infected grant one verified patrol reward"):
        return

    var claimed: Dictionary = survivor.get("contract_state")
    if not _expect(str(claimed["active"]).is_empty()
            and (claimed["completed"] as Array).size() == 3
            and not bool(board.call("interact", survivor)),
            "all three contracts complete; board cannot farm repeat rewards"):
        return

    var snapshot: Dictionary = SAVES.snapshot(survivor)
    if not _expect(SAVES.validate_snapshot(snapshot),
            "contract progress is accepted by existing survivor persistence"):
        return
    survivor.set("contract_state", RULES.empty_state())
    if not _expect(SAVES.apply_snapshot(survivor, snapshot)
            and (survivor.get("contract_state") as Dictionary)["completed"].size() == 3,
            "contract journal survives a save/load round trip"):
        return

    var corrupt: Dictionary = SAVES.snapshot(survivor)
    corrupt["contracts"]["completed"].append("supply_run")
    if not _expect(not SAVES.apply_snapshot(survivor, corrupt)
            and (survivor.get("contract_state") as Dictionary)["completed"].size() == 3,
            "duplicate completion is rejected before any state mutation"):
        return

    var legacy: Dictionary = SAVES.snapshot(survivor)
    legacy.erase("contracts")
    if not _expect(SAVES.apply_snapshot(survivor, legacy)
            and (survivor.get("contract_state") as Dictionary)["completed"].is_empty(),
            "pre-contract v1 save is still readable and starts a fresh journal"):
        return

    game.queue_free()
    await process_frame
    print("PASS: survivor contracts, scavenging, craft trial, zombie patrol, no-duplicate rewards and journal saves.")
    quit(0)
