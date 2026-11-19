extends RefCounted
## Gameplay values are normalized to [0, 100]. The state has no scene dependencies.

const MAX_VALUE := 100.0
const FOOD_DRAIN_PER_SECOND := 0.15
const WATER_DRAIN_PER_SECOND := 0.25
const SPRINT_STAMINA_PER_SECOND := 14.0
const STAMINA_RECOVERY_PER_SECOND := 9.0
const STARVATION_DAMAGE_PER_SECOND := 2.0

var health := MAX_VALUE
var hunger := MAX_VALUE
var thirst := MAX_VALUE
var stamina := MAX_VALUE


func advance(delta: float, sprinting: bool) -> void:
    var elapsed := maxf(delta, 0.0)
    hunger = maxf(0.0, hunger - FOOD_DRAIN_PER_SECOND * elapsed)
    thirst = maxf(0.0, thirst - WATER_DRAIN_PER_SECOND * elapsed)
    if sprinting:
        stamina = maxf(0.0, stamina - SPRINT_STAMINA_PER_SECOND * elapsed)
    else:
        stamina = minf(MAX_VALUE, stamina + STAMINA_RECOVERY_PER_SECOND * elapsed)
    if hunger <= 0.0 or thirst <= 0.0:
        health = maxf(0.0, health - STARVATION_DAMAGE_PER_SECOND * elapsed)


func replenish(kind: String, amount: float) -> bool:
    if amount <= 0.0:
        return false
    match kind:
        "food":
            hunger = minf(MAX_VALUE, hunger + amount)
        "water":
            thirst = minf(MAX_VALUE, thirst + amount)
        _:
            return false
    return true
