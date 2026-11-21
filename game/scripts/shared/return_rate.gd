extends RefCounted
## Albion Online-style Focus: crafting or refining "with focus" at a safe
## settlement workbench spends focus points and returns part of the materials
## (the city resource return rate). Focus regenerates over a day, so it is a
## daily budget that rewards dedicated crafters. Ordinary crafting is unchanged.

const MAX_FOCUS := 10000.0
const REGEN_PER_SECOND := MAX_FOCUS / 86400.0 # Full pool in 24 h.
const FOCUS_RATE := 0.35 # Materials returned when crafting with focus.
const REFINED_OUTPUTS := ["plank_", "bar_", "cloth_"]


## Focus cost for `times` batches of a recipe producing a tier-`tier` item.
static func focus_cost(output: String, tier: int, times: int) -> int:
	var per_batch: int = 6 * maxi(1, tier) * maxi(1, tier)
	for prefix in REFINED_OUTPUTS:
		if output.begins_with(prefix):
			per_batch = 3 * maxi(1, tier) * maxi(1, tier) # Refining is cheaper per batch.
	return per_batch * maxi(1, times)


## Materials returned for `inputs` (already multiplied by batches) at `rate`.
## Whole part is guaranteed; the fraction is a fair roll, so the average is exact.
static func returned(inputs: Dictionary, rate: float, rng: RandomNumberGenerator) -> Dictionary:
	var back: Dictionary = {}
	if rate <= 0.0:
		return back
	for id in inputs:
		var expected: float = float(inputs[id]) * clampf(rate, 0.0, 0.5)
		var amount: int = int(floor(expected))
		if rng.randf() < expected - float(amount):
			amount += 1
		if amount > 0:
			back[id] = amount
	return back
