extends RefCounted
## Facade for the live hitch classifier: native CgameHitchCorrelator.sample() with the GDScript
## FrameHitchAnalyzer (scripts/client/frame_hitch_analyzer.gd) as fallback.

const FALLBACK_PATH := "res://scripts/client/frame_hitch_analyzer.gd"

var _impl: Object = null
var _native: bool = false


func _init() -> void:
	if ClassDB.class_exists("CgameHitchCorrelator"):
		_impl = ClassDB.instantiate("CgameHitchCorrelator")
		_native = true
	elif ResourceLoader.exists(FALLBACK_PATH):
		_impl = (load(FALLBACK_PATH) as GDScript).new()
	else:
		push_error("FrameHitchAnalyzer facade: no backend available")


func is_native() -> bool:
	return _native


## Cheap per-frame engine counters {"compiles", "cells", "vram"}.
static func read_counters(loaded_cells: int = 0) -> Dictionary:
	if ClassDB.class_exists("CgameHitchCorrelator"):
		return ClassDB.instantiate("CgameHitchCorrelator").call("read_counters", loaded_cells)
	if ResourceLoader.exists(FALLBACK_PATH):
		return (load(FALLBACK_PATH) as GDScript).read_counters(loaded_cells)
	return {}


## Returns the hitch record when this frame was a hitch, else an empty dictionary.
func sample(delta: float, counters: Dictionary, now: float = 0.0) -> Dictionary:
	return _impl.sample(delta, counters, now) if _impl != null else {}


func describe() -> String:
	return _impl.describe() if _impl != null else ""


func median() -> float:
	return _impl.median() if _impl != null else 0.0


func get_hitches() -> Array:
	if _impl == null:
		return []
	return Array(_impl.get_hitches()) if _native else _impl.hitches


func get_counts() -> Dictionary:
	if _impl == null:
		return {}
	return _impl.get_counts() if _native else _impl.counts
