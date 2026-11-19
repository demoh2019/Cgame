extends RefCounted

## Centralized offline vendor price book. No player-supplied price arguments.
## When multiplayer arrives, transactions MUST be executed by the server.
const SELL_PRICES := {
    "infected_sample": 12,
    "wood_t1": 2,
    "stone_t1": 3,
    "fiber_t1": 2,
    "wood_t2": 5,
    "stone_t2": 6,
    "fiber_t2": 5,
}

const BUY_PRICES := {
    "water": 7,
    "food": 9,
    "field_bandage": 16,
}

const MAX_TRADE_QUANTITY := 100
const MAX_CREDITS := 1000000000
