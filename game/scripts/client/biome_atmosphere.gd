extends RefCounted
## Renderer-independent, bounded visual rules for each existing world biome.
## Uses the same Godot environment fog; never allocates a secondary fog pass.
const MIN_HEIGHT_FACTOR := 0.55
const MAX_HEIGHT_FACTOR := 1.45
const MIN_VOLUME_FACTOR := 0.65
const MAX_VOLUME_FACTOR := 1.25
const MAX_TINT_AMOUNT := 0.22
const TRANSITION_SPEED := 0.7

static func settings(biome: String) -> Dictionary:
	match biome:
		"swamp":
			return {"height_factor": 1.40, "volume_factor": 1.18,
				"tint": Color(0.32, 0.42, 0.35), "tint_amount": 0.19}
		"forest":
			return {"height_factor": 1.14, "volume_factor": 1.06,
				"tint": Color(0.42, 0.51, 0.43), "tint_amount": 0.09}
		"mountain":
			return {"height_factor": 0.60, "volume_factor": 0.75,
				"tint": Color(0.60, 0.69, 0.78), "tint_amount": 0.15}
		"beach":
			return {"height_factor": 0.88, "volume_factor": 0.91,
				"tint": Color(0.49, 0.63, 0.68), "tint_amount": 0.12}
		_:
			return {"height_factor": 1.0, "volume_factor": 1.0,
				"tint": Color(0.50, 0.55, 0.60), "tint_amount": 0.0}


## Returns new state without mutating presets or authoring GPU resources.
## One smooth lerp avoids a sudden fog-color step at biome cell boundaries.
static func advance(previous: Dictionary, biome: String, delta: float) -> Dictionary:
	var next: Dictionary = settings(biome)
	if not is_finite(delta) or delta <= 0.0:
		return previous.duplicate(true) if not previous.is_empty() else next
	if previous.is_empty():
		return next
	var factor: float = 1.0 - exp(-TRANSITION_SPEED * minf(delta, 0.25))
	return {
		"height_factor": lerpf(float(previous.get("height_factor", 1.0)),
			float(next["height_factor"]), factor),
		"volume_factor": lerpf(float(previous.get("volume_factor", 1.0)),
			float(next["volume_factor"]), factor),
		"tint": (previous.get("tint", next["tint"]) as Color).lerp(
			next["tint"], factor),
		"tint_amount": lerpf(float(previous.get("tint_amount", 0.0)),
			float(next["tint_amount"]), factor),
	}
