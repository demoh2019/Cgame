extends RefCounted
## Floating damage numbers: styling and pop animation.
const DamageNumbers = preload("res://scripts/client/damage_numbers.gd")


func run(t) -> void:
	t.current = "damage numbers style and pop"
	var heavy: Array = DamageNumbers.style(50.0, false)
	var light: Array = DamageNumbers.style(5.0, false)
	var mine: Array = DamageNumbers.style(50.0, true)
	t.check(float(heavy[1]) > float(light[1]), "heavy hits are bigger")
	t.check((mine[0] as Color).g < 0.5, "damage you take is red")
	t.check(DamageNumbers.pop(0.1) > 1.0, "numbers overshoot when they pop")
	t.near(DamageNumbers.pop(1.0), 1.0, 0.0001, "and settle at their size")
