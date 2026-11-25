@tool
extends RefCounted
## Utility AI (Dave Mark's Infinite Axis Utility System, as used by the UE5
## Utility AI plugins and Guild Wars 2): each option is scored by multiplying
## normalised considerations shaped by response curves, with a compensation
## factor so options with many considerations are not unfairly punished.

enum Response { LINEAR, QUADRATIC, INVERSE_QUADRATIC, LOGISTIC, STEP }


static func curve(kind: int, x: float, slope: float = 1.0, shift: float = 0.0) -> float:
	if not is_finite(x) or not is_finite(slope) or not is_finite(shift):
		return 0.0
	var v: float = clampf(x, 0.0, 1.0)
	match kind:
		Response.QUADRATIC:
			v = v * v
		Response.INVERSE_QUADRATIC:
			v = 1.0 - (1.0 - v) * (1.0 - v)
		Response.LOGISTIC:
			v = 1.0 / (1.0 + exp(-10.0 * slope * (v - 0.5 - shift)))
		Response.STEP:
			v = 1.0 if v >= 0.5 + shift else 0.0
		_:
			v = v * slope + shift
	return clampf(v, 0.0, 1.0) if is_finite(v) else 0.0


## Product of considerations with IAUS compensation.
static func combine(scores: PackedFloat32Array) -> float:
	if scores.is_empty():
		return 0.0
	var total := 1.0
	for s in scores:
		if not is_finite(s):
			return 0.0
		total *= clampf(s, 0.0, 1.0)
		if total <= 0.0:
			return 0.0
	var modification: float = 1.0 - 1.0 / float(scores.size())
	var make_up: float = (1.0 - total) * modification
	return total + make_up * total


## Index of the best scoring option (ties keep the earliest; -1 if all zero).
static func best(scores: PackedFloat32Array) -> int:
	var index := -1
	var top := 0.0
	for i in scores.size():
		if is_finite(scores[i]) and scores[i] > top:
			top = scores[i]
			index = i
	return index
