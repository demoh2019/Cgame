extends RefCounted

# Data-only rules: native signals deliver a saved state transition and the
# game chooses the next runtime layer. Pure logic runs on stock Godot too.
const HUB_CELL := Vector2i(0, 0)
const ARENA_CELL := Vector2i(4, 2)
const COMBAT_LAYER := "combat_event"
const CHAMPION_LAYER := "champion_event"
const CHAMPION_REQUIRED_WINS := 3

static func next_event(cell: Vector2i, state: Dictionary) -> Dictionary:
    if cell == HUB_CELL and bool(state.get("reward_claimed", false)):
        return {"layer": COMBAT_LAYER, "message": "Quest reward claimed: combat event unlocked"}
    if cell == ARENA_CELL and int(state.get("arena_wins", 0)) >= CHAMPION_REQUIRED_WINS:
        return {"layer": CHAMPION_LAYER, "message": "Three arena wins: champion shrine unlocked"}
    return {}
