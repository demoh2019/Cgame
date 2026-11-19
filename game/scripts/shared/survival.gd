extends RefCounted
## A player's vital statistics and the rules that change them over time.

const Defs = preload("res://scripts/shared/defs.gd")

var health: float = Defs.MAX_HEALTH
var hunger: float = 100.0 # 100 is full.
var thirst: float = 100.0
var alive: bool = true


## Advances the clock. Returns the damage taken from hunger or thirst this step.
func tick(delta: float) -> float:
	if not alive:
		return 0.0
	hunger = maxf(hunger - Defs.HUNGER_PER_SECOND * delta, 0.0)
	thirst = maxf(thirst - Defs.THIRST_PER_SECOND * delta, 0.0)
	var damage := 0.0
	if hunger <= 0.0:
		damage += Defs.STARVE_DAMAGE_PER_SECOND * delta
	if thirst <= 0.0:
		damage += Defs.STARVE_DAMAGE_PER_SECOND * 1.5 * delta
	if damage > 0.0:
		hurt(damage)
	elif hunger > 40.0 and thirst > 40.0:
		# Well fed and watered: slow natural recovery.
		health = minf(health + 0.35 * delta, Defs.MAX_HEALTH)
	return damage


## Returns the damage that was applied (after clamping at 0 health).
func hurt(amount: float) -> float:
	if not alive or amount <= 0.0:
		return 0.0
	var applied := minf(amount, health)
	health -= applied
	if health <= 0.0:
		health = 0.0
		alive = false
	return applied


func heal(amount: float) -> void:
	if alive and amount > 0.0:
		health = minf(health + amount, Defs.MAX_HEALTH)


func eat(amount: float) -> void:
	hunger = minf(hunger + amount, 100.0)


func drink(amount: float) -> void:
	thirst = minf(thirst + amount, 100.0)


func reset() -> void:
	health = Defs.MAX_HEALTH
	hunger = 80.0
	thirst = 80.0
	alive = true


func to_dict() -> Dictionary:
	return {"health": health, "hunger": hunger, "thirst": thirst, "alive": alive}
