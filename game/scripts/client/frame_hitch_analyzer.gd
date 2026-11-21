extends RefCounted
## Cross-system frame hitch analyzer (Unreal Insights hitch tracks, PIX
## "PSO compile" markers): every frame stores cheap engine counters; a frame
## much slower than the recent median is attributed to the counter that
## jumped with it — pipeline compilation, world streaming or VRAM growth.

const WINDOW := 120
const MIN_HITCH := 0.05 # 50 ms is always a visible hitch.
const HITCH_FACTOR := 2.5
const VRAM_JUMP := 64.0 * 1024.0 * 1024.0
const KEEP := 32

var hitches: Array[Dictionary] = []
var counts: Dictionary = {"shader_compile": 0, "streaming": 0, "vram": 0, "cpu": 0}
var _frames: Array[float] = []
var _last: Dictionary = {}


static func read_counters(loaded_cells: int = 0) -> Dictionary:
	var compiles := 0
	for info in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		compiles += RenderingServer.get_rendering_info(info)
	return {"compiles": compiles, "cells": loaded_cells,
		"vram": float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))}


func median() -> float:
	if _frames.is_empty():
		return 0.0
	var sorted := _frames.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


static func cause(before: Dictionary, after: Dictionary) -> String:
	if int(after.get("compiles", 0)) > int(before.get("compiles", 0)):
		return "shader_compile"
	if int(after.get("cells", 0)) != int(before.get("cells", 0)):
		return "streaming"
	if float(after.get("vram", 0.0)) - float(before.get("vram", 0.0)) > VRAM_JUMP:
		return "vram"
	return "cpu"


## Returns the hitch record when this frame was a hitch, else an empty dictionary.
func sample(delta: float, counters: Dictionary, now: float = 0.0) -> Dictionary:
	if not is_finite(delta) or delta <= 0.0:
		return {}
	var typical: float = median()
	var result: Dictionary = {}
	if _frames.size() >= 30 and delta >= maxf(MIN_HITCH, typical * HITCH_FACTOR) and not _last.is_empty():
		var reason: String = cause(_last, counters)
		result = {"time": now, "ms": delta * 1000.0, "median_ms": typical * 1000.0, "cause": reason}
		counts[reason] = int(counts[reason]) + 1
		hitches.append(result)
		if hitches.size() > KEEP:
			hitches.pop_front()
	else:
		# Hitches never pollute the baseline.
		_frames.append(delta)
		if _frames.size() > WINDOW:
			_frames.pop_front()
	_last = counters
	return result


func describe() -> String:
	return "hitches: shaders %d, streaming %d, vram %d, cpu %d" % [
		counts["shader_compile"], counts["streaming"], counts["vram"], counts["cpu"]]
