extends SceneTree
## Run: godot --headless --path demo/days_after --script res://tests/test_progression.gd

const SURVIVAL = preload("res://survival_state.gd")
const PROGRESSION = preload("res://progression.gd")


func _initialize() -> void:
    var survival = SURVIVAL.new()
    var progress = PROGRESSION.new(survival)

    assert(progress.skill_level("gathering") == 1)
    assert(progress.skill_level("crafting") == 1)
    assert(progress.skill_level("unknown") == 0)
    assert(not progress.gather("unknown", 1)["ok"])
    assert(not progress.gather("wood", 2)["ok"])
    assert(not progress.gather("ore", 2)["ok"])
    assert(not progress.craft("unknown")["ok"])

    # Crafting fails atomically: no partial ingredient consumption or XP.
    assert(survival.add_item("wood", 2))
    assert(not progress.craft("pickaxe")["ok"])
    assert(survival.get_count("wood") == 2)
    assert(progress.crafting_xp == 0)
    assert(survival.add_item("scrap", 2))
    assert(progress.craft("pickaxe")["ok"])
    assert(survival.get_count("wood") == 0)
    assert(survival.get_count("scrap") == 0)
    assert(survival.get_count("pickaxe") == 1)
    assert(progress.crafting_xp == 25)

    # Tier 2 requires the gathering skill level even when the tool exists.
    assert(not progress.gather("ore", 2)["ok"])
    assert(survival.get_count("ore") == 0)
    for i in range(5):
        assert(progress.gather("wood", 1)["ok"])
    assert(progress.gathering_xp == 60)
    assert(progress.skill_level("gathering") == 2)
    assert(progress.gather("ore", 2)["ok"])
    assert(survival.get_count("ore") == 2)

    # Ore and scrap can now be crafted into higher-tier armor.
    assert(survival.add_item("scrap", 2))
    assert(progress.craft("reinforced_vest")["ok"])
    assert(survival.get_count("reinforced_vest") == 1)
    assert(survival.get_count("ore") == 0)
    assert(progress.skill_level("crafting") == 2)

    # Bandages share the existing survival inventory.
    assert(progress.gather("fiber", 1)["ok"])
    assert(progress.craft("bandage")["ok"])
    assert(survival.get_count("fiber") == 0)
    assert(survival.get_count("bandage") == 1)
    survival.health = 50.0
    assert(survival.use_item("bandage"))
    assert(is_equal_approx(survival.health, 75.0))
    assert(survival.get_count("bandage") == 0)

    # Without a pickaxe a new survivor cannot extract tier 2 ore.
    var no_tool = SURVIVAL.new()
    var no_tool_progress = PROGRESSION.new(no_tool)
    no_tool_progress.gathering_xp = 50
    assert(not no_tool_progress.gather("ore", 2)["ok"])
    assert(no_tool.get_count("ore") == 0)

    print("Days After gathering, crafting and progression: PASS")
    quit(0)
