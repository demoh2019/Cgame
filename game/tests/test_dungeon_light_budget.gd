extends RefCounted
## Proximity-based torch lighting is render-only and respects hard global light budgets.

const DungeonLightBudget = preload("res://scripts/client/dungeon_light_budget.gd")


func run(t) -> void:
	t.current = "dungeon torch light quality budgets"
	var low: Dictionary = DungeonLightBudget.settings(0)
	var balanced: Dictionary = DungeonLightBudget.settings(1)
	var high: Dictionary = DungeonLightBudget.settings(2)
	var ultra: Dictionary = DungeonLightBudget.settings(3)
	t.eq(DungeonLightBudget.settings(-30), low, "negative preset clamps to Performance")
	t.eq(DungeonLightBudget.settings(90), ultra, "large preset clamps to Ultra")
	t.check(int(low["max_lights"]) < int(balanced["max_lights"]) and
		int(balanced["max_lights"]) < int(high["max_lights"]) and
		int(high["max_lights"]) < int(ultra["max_lights"]),
		"higher quality allows a bounded number of more local lights")
	t.check(float(low["radius"]) < float(ultra["radius"]),
		"Ultra illuminates more distant rooms")
	t.eq(int(low["shadow_lights"]), 0, "Performance avoids torch shadow maps")
	t.eq(int(balanced["shadow_lights"]), 0, "Balanced avoids torch shadow maps")
	t.eq(int(high["shadow_lights"]), 1, "High allows one cinematic torch shadow")
	t.eq(int(ultra["shadow_lights"]), 2, "Ultra allows two cinematic torch shadows")
	t.eq(DungeonLightBudget.effective_max(3, "gl_compatibility"), 8,
		"Compatibility caps local torches at eight")
	t.eq(DungeonLightBudget.effective_max(3, "forward_plus"), 16,
		"Forward+ retains Ultra clustered-light count")
	low["max_lights"] = 100000
	t.check(int(DungeonLightBudget.settings(0)["max_lights"]) < 10,
		"callers cannot mutate the profile constants")

	t.current = "closest lights survive global budget"
	var candidates: Array = [
		{"id": 9, "distance_sq": 121.0},
		{"id": 4, "distance_sq": 4.0},
		{"id": 5, "distance_sq": 4.0},
		{"id": 3, "distance_sq": 16.0},
		{"id": 8, "distance_sq": 81.0},
	]
	var selected: Array = DungeonLightBudget.nearest(candidates, 2, 8.0)
	t.eq(selected.size(), 2, "only two torch lights are selected")
	t.eq(selected[0]["id"], 4, "equal-distance lights have stable ordering")
	t.eq(selected[1]["id"], 5, "tie-break is deterministic")
	t.eq(candidates.size(), 5, "selector never removes candidate lights")
	t.eq(DungeonLightBudget.nearest(candidates, 0, 50.0).size(), 0,
		"zero budget never activates lights")
	t.eq(DungeonLightBudget.nearest(candidates, 10, 0.0).size(), 0,
		"zero range never activates lights")
	t.eq(DungeonLightBudget.nearest(candidates, 10, 8.0).size(), 3,
		"out-of-range torches are excluded even with spare slots")

	t.current = "warm flicker fades before lights disappear"
	var near: float = DungeonLightBudget.intensity(2.0, 44.0, 12.0, 1.7, 0.11)
	var edge: float = DungeonLightBudget.intensity(43.8, 44.0, 12.0, 1.7, 0.11)
	t.check(near > 0.8 and near <= 1.2, "near lights flicker gently")
	t.check(edge > 0.0 and edge < near, "edge lights fade smoothly")
	t.eq(DungeonLightBudget.intensity(44.0, 44.0, 12.0, 1.7, 0.11), 0.0,
		"lighting cuts off outside influence radius")
	t.eq(DungeonLightBudget.intensity(2.0, 0.0, 12.0, 1.7, 0.11), 0.0,
		"invalid influence radius never lights anything")
