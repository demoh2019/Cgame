extends SceneTree

const Events = preload("res://scripts/world_event_rules.gd")

func _initialize() -> void:
    var combat: Dictionary = Events.next_event(Vector2i(0, 0), {"reward_claimed": true})
    assert(combat["layer"] == "combat_event")
    assert(Events.next_event(Vector2i(0, 0), {"reward_claimed": false}).is_empty())
    assert(Events.next_event(Vector2i(4, 2), {"arena_wins": 2}).is_empty())
    var champion: Dictionary = Events.next_event(Vector2i(4, 2), {"arena_wins": 3})
    assert(champion["layer"] == "champion_event")
    assert(Events.next_event(Vector2i(4, 2), {"arena_wins": 10}) == champion)
    assert(Events.next_event(Vector2i(2, 2), {"reward_claimed": true}).is_empty())
    print("Quest progression event rules passed")
    quit(0)
