extends RefCounted
## Deterministic, game-specific infection and treatment model.
## No RNG or physics dependency: works in headless and replay tests.

const MAX_INFECTION := 100.0
const SYMPTOM_THRESHOLD := 50.0
const DAMAGE_PER_SECOND := 1.25
const NATURAL_RECOVERY_PER_SECOND := 0.02
const ANTISEPTIC_REDUCTION := 55.0
const MAX_STEP_SECONDS := 1.0


static func valid_level(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= MAX_INFECTION


static func expose(current: float, dose: float) -> float:
    if not is_finite(current):
        return 0.0
    var safe_current := clampf(current, 0.0, MAX_INFECTION)
    if not is_finite(dose) or dose <= 0.0:
        return safe_current
    return minf(MAX_INFECTION, safe_current + dose)


static func advance(current: float, delta: float) -> Dictionary:
    if not is_finite(current):
        return {"infection": 0.0, "damage": 0.0}
    var bounded := clampf(current, 0.0, MAX_INFECTION)
    if not is_finite(delta) or delta <= 0.0:
        return {"infection": bounded, "damage": 0.0}
    var step := minf(delta, MAX_STEP_SECONDS)
    var next := maxf(0.0, bounded - NATURAL_RECOVERY_PER_SECOND * step)
    var damage := DAMAGE_PER_SECOND * step if next >= SYMPTOM_THRESHOLD else 0.0
    return {"infection": next, "damage": damage}


static func treat(current: float) -> float:
    if not is_finite(current):
        return 0.0
    return maxf(0.0, clampf(current, 0.0, MAX_INFECTION) - ANTISEPTIC_REDUCTION)
