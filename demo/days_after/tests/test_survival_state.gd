extends SceneTree
## Run with: godot --headless --path demo/days_after --script res://tests/test_survival_state.gd

const SURVIVAL = preload("res://survival_state.gd")


func _initialize() -> void:
    var state = SURVIVAL.new()
    assert(not state.add_item("", 1))
    assert(not state.add_item("food", 0))
    assert(not state.remove_item("water"))
    assert(state.add_item("water", 2))
    assert(state.add_item("food", 1))
    assert(state.add_item("scrap", 3))
    assert(state.get_count("water") == 2)
    assert(state.use_item("water"))
    assert(state.get_count("water") == 1)
    assert(not state.use_item("scrap"))
    assert(state.get_count("scrap") == 3)
    assert(state.use_item("food"))
    assert(state.get_count("food") == 0)
    assert(not state.use_item("food"))
    assert(state.add_item("bandage"))
    assert(not state.use_item("bandage")) # Cannot waste bandages at full HP.
    assert(state.get_count("bandage") == 1)
    state.health = 60.0
    assert(state.use_item("bandage"))
    assert(is_equal_approx(state.health, 85.0))
    assert(state.get_count("bandage") == 0)

    var previous_hunger: float = state.hunger
    var previous_thirst: float = state.thirst
    state.tick(10.0)
    assert(state.hunger < previous_hunger)
    assert(state.thirst < previous_thirst)
    assert(is_equal_approx(state.health, 85.0))
    var before_invalid: float = state.hunger
    state.tick(-1.0)
    assert(is_equal_approx(before_invalid, state.hunger))

    state.hunger = 0.0
    state.thirst = 0.0
    state.health = 1.0
    state.tick(1.0)
    assert(is_equal_approx(state.health, 0.0))
    assert(not state.is_alive())
    state.tick(10.0)
    assert(is_equal_approx(state.health, 0.0))

    print("Days After survival state: PASS")
    quit(0)
