extends RefCounted
## A player's vital statistics and the rules that change them over time.

const Defs = preload("res://scripts/shared/defs.gd")

var health: float = Defs.MAX_HEALTH
var hunger: float = 100.0 # 100 is full.
var thirst: float = 100.0
var infection: float = 0.0
var exposure: float = 0.0 # 0..100 cumulative weather stress.
var stamina: float = Defs.MAX_STAMINA
var stamina_recovery_delay: float = 0.0
var alive: bool = true


## The same eligibility math runs on the server and client prediction.
static func can_sprint_with(value: float, hunger_value: float, thirst_value: float, seconds: float) -> bool:
	if not (is_finite(value) and is_finite(hunger_value) and is_finite(thirst_value) and is_finite(seconds)):
		return false
	if seconds <= 0.0 or seconds > 0.1:
		return false
	if hunger_value <= 5.0 or thirst_value <= 5.0:
		return false
	return value + 0.00001 >= Defs.SPRINT_STAMINA_PER_SECOND * seconds


func try_sprint(seconds: float) -> bool:
	if not alive or not can_sprint_with(stamina, hunger, thirst, seconds):
		return false
	stamina = maxf(0.0, stamina - Defs.SPRINT_STAMINA_PER_SECOND * seconds)
	stamina_recovery_delay = Defs.STAMINA_RECOVERY_DELAY
	return true


## Advances the clock. Returns the damage taken from hunger or thirst this step.
func tick(delta: float) -> float:
	if not alive:
		return 0.0
	hunger = maxf(hunger - Defs.HUNGER_PER_SECOND * delta, 0.0)
	thirst = maxf(thirst - Defs.THIRST_PER_SECOND * delta, 0.0)
	var resting := maxf(delta - stamina_recovery_delay, 0.0)
	stamina_recovery_delay = maxf(0.0, stamina_recovery_delay - delta)
	if resting > 0.0:
		var nourishment := 0.5 if hunger <= 20.0 or thirst <= 20.0 else 1.0
		stamina = minf(Defs.MAX_STAMINA, stamina + Defs.STAMINA_REGEN_PER_SECOND * resting * nourishment)
	if infection > 0.0:
		infection = minf(Defs.INFECTION_MAX,
			infection + Defs.INFECTION_GROWTH_PER_SECOND * maxf(0.0, delta))
	var damage := 0.0
	if hunger <= 0.0:
		damage += Defs.STARVE_DAMAGE_PER_SECOND * delta
	if thirst <= 0.0:
		damage += Defs.STARVE_DAMAGE_PER_SECOND * 1.5 * delta
	if infection > Defs.INFECTION_DAMAGE_START:
		var severity: float = (infection - Defs.INFECTION_DAMAGE_START) / (
			Defs.INFECTION_MAX - Defs.INFECTION_DAMAGE_START)
		damage += severity * Defs.INFECTION_DAMAGE_PER_SECOND * maxf(0.0, delta)
	if damage > 0.0:
		hurt(damage)
	elif hunger > 40.0 and thirst > 40.0:
		# Well fed and watered: slow natural recovery.
		health = minf(health + 0.35 * delta, Defs.MAX_HEALTH)
	return damage


## Called only by the server with a computed weather severity (0..1).
## Exposure decays while sheltered or when conditions improve. High sustained
## cold/wet exposure deals real health damage; zero shelter never mints health.
func weather_tick(delta: float, severity: float) -> float:
	if not alive or not is_finite(delta) or delta <= 0.0 or not is_finite(severity):
		return 0.0
	var intensity: float = clampf(severity, 0.0, 1.0)
	if intensity > 0.0:
		exposure = minf(100.0, exposure + intensity * 0.55 * delta)
	else:
		exposure = maxf(0.0, exposure - 0.9 * delta)
	if exposure <= 60.0:
		return 0.0
	var damage: float = (exposure - 60.0) / 40.0 * 0.8 * delta
	return hurt(damage)


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


func add_infection(amount: float) -> bool:
	if not alive or not is_finite(amount) or amount <= 0.0:
		return false
	var before: float = infection
	infection = minf(Defs.INFECTION_MAX, infection + amount)
	return infection > before


func treat_infection(amount: float) -> bool:
	if not alive or not is_finite(amount) or amount <= 0.0 or infection <= 0.0:
		return false
	infection = maxf(0.0, infection - amount)
	return true


func reset() -> void:
	health = Defs.MAX_HEALTH
	hunger = 80.0
	thirst = 80.0
	stamina = Defs.MAX_STAMINA
	stamina_recovery_delay = 0.0
	infection = 0.0
	exposure = 0.0
	alive = true


func to_dict() -> Dictionary:
	return {"health": health, "hunger": hunger, "thirst": thirst, "stamina": stamina, "infection": infection, "exposure": exposure, "alive": alive}
