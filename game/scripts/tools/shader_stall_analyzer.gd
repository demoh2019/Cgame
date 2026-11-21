extends RefCounted
## Shader compilation stall analyzer: correlates per-frame pipeline compilation
## counts with frame-time spikes and the materials first drawn that frame.
## Original code (MIT-compatible).

## Frames: {"index", "ms", "compiles", "materials": Array[String]}
var frames: Array[Dictionary] = []
var spike_factor: float = 2.0
var min_extra_ms: float = 4.0
var _last_total: int = -1


## compiles = pipelines compiled during this frame; materials = first drawn this frame.
func feed(index: int, ms: float, compiles: int, first_drawn_materials: Array = []) -> void:
	var mats: Array[String] = []
	for m in first_drawn_materials:
		mats.append(str(m))
	frames.append({"index": index, "ms": ms, "compiles": compiles, "materials": mats})


## Same, but from a cumulative compile counter (delta computed internally).
func feed_cumulative(index: int, ms: float, total_compiles: int, first_drawn_materials: Array = []) -> void:
	var delta: int = 0 if _last_total < 0 else maxi(0, total_compiles - _last_total)
	_last_total = total_compiles
	feed(index, ms, delta, first_drawn_materials)


## Sum of RenderingServer pipeline compilation counters (0 where unsupported).
static func live_compile_total() -> int:
	var total: int = 0
	for n in ["RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS", "RENDERING_INFO_PIPELINE_COMPILATIONS_MESH",
			"RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE", "RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW",
			"RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION"]:
		if ClassDB.class_has_integer_constant("RenderingServer", n):
			var c: int = ClassDB.class_get_integer_constant("RenderingServer", n)
			total += int(RenderingServer.get_rendering_info(c as RenderingServer.RenderingInfo))
	return total


func baseline_ms() -> float:
	if frames.is_empty():
		return 0.0
	var arr := PackedFloat32Array()
	for f in frames:
		arr.append(float(f["ms"]))
	arr.sort()
	return arr[arr.size() >> 1]


## {"baseline_ms", "stalls": [{index, ms, extra_ms, compiles, culprits}],
##  "unrelated_spikes": [index], "culprits": [{material, stalls, total_extra_ms}]}
func analyze() -> Dictionary:
	var base: float = baseline_ms()
	var limit: float = maxf(base * spike_factor, base + min_extra_ms)
	var stalls: Array[Dictionary] = []
	var unrelated: Array[int] = []
	var by_mat: Dictionary = {}
	for f in frames:
		var ms: float = float(f["ms"])
		if ms <= limit:
			continue
		var compiles: int = int(f["compiles"])
		if compiles <= 0:
			unrelated.append(int(f["index"]))
			continue
		var extra: float = ms - base
		var mats: Array = f["materials"]
		stalls.append({"index": int(f["index"]), "ms": ms, "extra_ms": extra, "compiles": compiles, "culprits": mats.duplicate()})
		var share: float = extra / float(maxi(1, mats.size()))
		for m in mats:
			var key: String = str(m)
			var e: Dictionary = by_mat.get(key, {"material": key, "stalls": 0, "total_extra_ms": 0.0})
			e["stalls"] = int(e["stalls"]) + 1
			e["total_extra_ms"] = float(e["total_extra_ms"]) + share
			by_mat[key] = e
	var ranked: Array[Dictionary] = []
	for k in by_mat:
		ranked.append(by_mat[k])
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["total_extra_ms"]) > float(b["total_extra_ms"]))
	return {"baseline_ms": base, "stalls": stalls, "unrelated_spikes": unrelated, "culprits": ranked}
