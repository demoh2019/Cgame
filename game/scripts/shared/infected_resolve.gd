extends RefCounted
## Server-side diminishing returns for repeated PvE staggers.
## Native GameplayEffectStackPolicy implements the reusable GAS stacking rules.
## Stock Godot uses identical formulas, preserving existing combat and PvP isolation.

const RESET_SECONDS := 6.0
const MAX_STACKS := 3
const FACTORS := [1.0, 0.65, 0.40]

static var _native_policy: Object = null
static var _native_checked := false


static func _policy() -> Object:
	if _native_checked:
		return _native_policy
	_native_checked = true
	if not ClassDB.class_exists("GameplayEffectStackPolicy"):
		return null
	var instance: Object = ClassDB.instantiate("GameplayEffectStackPolicy")
	if instance != null and instance.has_method("configure") and instance.has_method("preview_application"):
		if bool(instance.call("configure", MAX_STACKS,
				PackedFloat32Array(FACTORS), 0, 0)):
			_native_policy = instance
	return _native_policy


## Deterministic effect duration; no authority transfer to clients.
static func duration(base: float, stacks: int, elite: bool) -> float:
	if not is_finite(base) or base <= 0.0 or base > 1.5:
		return 0.0
	var policy: Object = _policy()
	if policy != null:
		return float(policy.call("calculate_magnitude", base, stacks, 0.5 if elite else 1.0))
	var factor: float = FACTORS[clampi(stacks, 0, MAX_STACKS - 1)]
	return base * factor * (0.5 if elite else 1.0)


## Non-mutating application proposal. Only successful applications consume
## one Resolve stack and reset the six-second recovery window.
static func plan_application(base: float, stacks: int, current_remaining: float,
		elite: bool) -> Dictionary:
	var previous_stacks: int = clampi(stacks, 0, MAX_STACKS)
	var safe_remaining: float = maxf(0.0, current_remaining) if is_finite(current_remaining) else 0.0
	var rejected: Dictionary = {
		"accepted": false, "stacks": previous_stacks,
		"remaining": safe_remaining, "applied_duration": 0.0,
		"overflow": false, "reason": "invalid_input"
	}
	if not is_finite(base) or base <= 0.0 or base > 1.5 or not is_finite(current_remaining) or current_remaining < 0.0:
		return rejected
	var policy: Object = _policy()
	if policy != null:
		return policy.call("preview_application", base, maxi(stacks, 0),
			current_remaining, 0.5 if elite else 1.0) as Dictionary
	var magnitude: float = duration(base, stacks, elite)
	if magnitude <= current_remaining or magnitude <= 0.0:
		rejected["reason"] = "weaker"
		rejected["applied_duration"] = magnitude
		return rejected
	return {
		"accepted": true, "stacks": mini(previous_stacks + 1, MAX_STACKS),
		"remaining": magnitude, "applied_duration": magnitude,
		"overflow": stacks >= MAX_STACKS, "reason": "applied"
	}


static func remaining(seconds: float, delta: float) -> float:
	if not is_finite(seconds) or not is_finite(delta) or seconds <= 0.0 or delta <= 0.0:
		return maxf(0.0, seconds) if is_finite(seconds) else 0.0
	return maxf(0.0, seconds - delta)
