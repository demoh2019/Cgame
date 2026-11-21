extends RefCounted
## Facade for CgameHitchCorrelator (native) with the GDScript HitchCorrelator as fallback.
## Same static API as scripts/shared/hitch_correlator.gd.

const FALLBACK_PATH := "res://scripts/shared/hitch_correlator.gd"


static func is_native() -> bool:
	return ClassDB.class_exists("CgameHitchCorrelator")


## frames: [{"ms", "scopes", "counters"}], e.g. from TraceCapture.frames().
static func correlate(frames: Array, threshold_ms: float) -> Array:
	if is_native():
		return ClassDB.instantiate("CgameHitchCorrelator").call("correlate", frames, threshold_ms)
	if ResourceLoader.exists(FALLBACK_PATH):
		return (load(FALLBACK_PATH) as GDScript).correlate(frames, threshold_ms)
	return []
