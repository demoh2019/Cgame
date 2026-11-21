extends RefCounted
## Infected gap-closers. A runner (or walker) crouches and LEAPS from a few metres; a brute
## lowers its head and CHARGES from further out. Both telegraph first. At impact: a dodge makes
## it whiff and stumble, a timed parry floors it, otherwise it bowls the survivor over.

const KINDS := {
	"pounce": {"min": 3.2, "max": 7.0, "windup": 0.55, "flight": 0.38, "arc": 1.1, "damage": 1.6, "down": 1.6, "shove": 0.6, "cooldown": 6.0},
	"charge": {"min": 5.0, "max": 13.0, "windup": 0.8, "flight": 0.6, "arc": 0.0, "damage": 1.2, "down": 1.3, "shove": 2.2, "cooldown": 9.0},
}
const HIT_RANGE := 1.7
const CHANCE_PER_SECOND := 0.35
const MISS_STAGGER := 0.9


## Which gap-closer this infected type uses, or "" for none.
static func kind_for(type: String) -> String:
	match type:
		"runner", "walker":
			return "pounce"
		"brute":
			return "charge"
	return ""


static func spec(kind: String) -> Dictionary:
	return KINDS.get(kind, {})
