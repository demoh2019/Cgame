extends RefCounted
## Utility AI curves, IAUS compensation and infected prey choice.

const UtilityAI = preload("res://scripts/shared/utility_ai.gd")
const InfectedTargetUtility = preload("res://scripts/shared/infected_target_utility.gd")


func run(t) -> void:
	t.current = "utility curves"
	t.near(UtilityAI.curve(UtilityAI.Response.LINEAR, 0.4), 0.4, 0.0001, "linear passes through")
	t.near(UtilityAI.curve(UtilityAI.Response.QUADRATIC, 0.5), 0.25, 0.0001, "quadratic eases in")
	t.near(UtilityAI.curve(UtilityAI.Response.INVERSE_QUADRATIC, 0.5), 0.75, 0.0001, "inverse quadratic eases out")
	t.near(UtilityAI.curve(UtilityAI.Response.LOGISTIC, 0.5), 0.5, 0.0001, "logistic centred at half")
	t.eq(UtilityAI.curve(UtilityAI.Response.STEP, 0.49), 0.0, "step below threshold")
	t.eq(UtilityAI.curve(UtilityAI.Response.LINEAR, 7.0), 1.0, "inputs are clamped")
	var two := UtilityAI.combine(PackedFloat32Array([0.8, 0.8]))
	t.check(two > 0.64 and two < 0.8, "compensation lifts multi-axis products")
	t.eq(UtilityAI.combine(PackedFloat32Array([0.9, 0.0])), 0.0, "any zero vetoes")
	t.eq(UtilityAI.best(PackedFloat32Array([0.2, 0.7, 0.7])), 1, "best keeps the first top score")
	t.eq(UtilityAI.best(PackedFloat32Array([0.0, 0.0])), -1, "no option above zero")

	t.current = "infected prey choice"
	var near_healthy := InfectedTargetUtility.score(5.0, 30.0, 1.0, false, false)
	var far_healthy := InfectedTargetUtility.score(12.0, 30.0, 1.0, false, false)
	t.check(near_healthy > far_healthy, "closer prey wins when equal")
	var slightly_far_wounded := InfectedTargetUtility.score(6.5, 30.0, 0.15, false, false)
	t.check(slightly_far_wounded > near_healthy, "a badly wounded straggler is worth a few extra steps")
	var much_farther_wounded := InfectedTargetUtility.score(20.0, 30.0, 0.1, false, false)
	t.check(near_healthy > much_farther_wounded, "wounds never outweigh a much closer survivor")
	t.check(InfectedTargetUtility.score(6.0, 30.0, 1.0, true, false) > InfectedTargetUtility.score(5.0, 30.0, 1.0, false, false),
		"current focus prevents flip-flopping between equally close survivors")
	t.check(InfectedTargetUtility.score(5.0, 30.0, 1.0, false, true) > near_healthy, "noise draws attention")
	t.eq(InfectedTargetUtility.score(40.0, 30.0, 1.0, false, false), 0.0, "beyond the leash a new target is ignored")
	t.check(InfectedTargetUtility.score(40.0, 30.0, 1.0, true, false) > 0.0, "an existing focus is not dropped by scoring")
