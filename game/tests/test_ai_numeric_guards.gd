extends RefCounted
## Numeric guards shared by Cgame and the stock-engine AI fallback.
const Formations = preload("res://scripts/shared/formations.gd")
const Utility = preload("res://scripts/shared/utility_ai.gd")
const Infected = preload("res://scripts/shared/infected_target_utility.gd")


func run(t) -> void:
	t.current = "formation assignment fails safely on unusable positions"
	var slots := PackedVector2Array([Vector2.ZERO, Vector2(5, 0)])
	var members := PackedVector2Array([Vector2(NAN, 0), Vector2(5, 0)])
	t.eq(Formations.assign(slots, members), PackedInt32Array([-1, -1]),
		"invalid member cannot stall Hungarian assignment")
	members[0] = Vector2(1.0e20, 0)
	t.eq(Formations.assign(slots, members), PackedInt32Array([-1, -1]),
		"extreme finite costs cannot exceed the solver sentinel")
	members[0] = Vector2.ZERO
	t.eq(Formations.assign(slots, members), PackedInt32Array([0, 1]),
		"valid members retain optimal slot assignments")
	t.eq(Formations.assignment_cost(slots, members, PackedInt32Array([0, 99, 1])),
		0.0, "out-of-range assignment entries are skipped")
	slots[0] = Vector2(INF, 0)
	t.eq(Formations.assign(slots, members), PackedInt32Array([-1, -1]),
		"invalid slot prevents unsafe movement")

	t.current = "invalid AI utility scores cannot win decisions"
	var scores := PackedFloat32Array([INF, 0.5, NAN])
	t.eq(Utility.curve(Utility.Response.LINEAR, NAN), 0.0, "invalid curve input")
	t.eq(Utility.curve(Utility.Response.LOGISTIC, 0.5, INF), 0.0, "invalid slope")
	t.eq(Utility.combine(scores), 0.0, "invalid consideration vetoes option")
	t.eq(Utility.best(scores), 1, "best ignores non-finite options")
	t.eq(Infected.score(1.0, NAN, 1.0, true, false), 0.0, "invalid leash")
	t.eq(Infected.score(-1.0, 30.0, 1.0, true, false), 0.0, "negative distance")
	t.check(Infected.score(5.0, 30.0, 0.1, false, true) >
		Infected.score(5.0, 30.0, 1.0, false, false), "valid wounded/noisy target remains preferred")
