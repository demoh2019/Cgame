extends RefCounted
## Bounded, pure, Unreal-style spatial sound obstruction probe admission.
## Returns stable input indices; caller owns the actual physics raycasts.

const MAX_VOICES := 128
const MAX_PROBES := 16
const MAX_CLOCK_SECONDS := 1000000000.0
const PRIORITY_SECONDS := 0.15


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if a["urgency"] != b["urgency"]:
		return a["urgency"] > b["urgency"]
	if a["audibility"] != b["audibility"]:
		return a["audibility"] > b["audibility"]
	if a["id"] != b["id"]:
		return a["id"] < b["id"]
	return a["index"] < b["index"]


static func select_due(next_due_seconds: PackedFloat64Array, priorities: PackedByteArray,
		audibilities: PackedFloat64Array, ids: PackedInt64Array,
		now_seconds: float, budget: int) -> PackedInt32Array:
	var empty := PackedInt32Array()
	var count: int = next_due_seconds.size()
	if count > MAX_VOICES or count != priorities.size() or count != audibilities.size() \
			or count != ids.size() or budget < 0 or budget > MAX_PROBES \
			or not is_finite(now_seconds) or now_seconds < 0.0 \
			or now_seconds > MAX_CLOCK_SECONDS:
		return empty
	var seen: Dictionary = {}
	for i in count:
		if not is_finite(next_due_seconds[i]) or next_due_seconds[i] < 0.0 \
				or next_due_seconds[i] > MAX_CLOCK_SECONDS \
				or not is_finite(audibilities[i]) or priorities[i] > 3 \
				or ids[i] <= 0 or seen.has(ids[i]):
			return empty
		seen[ids[i]] = true
	if budget == 0:
		return empty
	var best: Array[Dictionary] = []
	for i in count:
		if next_due_seconds[i] > now_seconds:
			continue
		var item: Dictionary = {
			"index": i,
			"urgency": now_seconds - next_due_seconds[i] + float(priorities[i]) * PRIORITY_SECONDS,
			"audibility": audibilities[i],
			"id": ids[i],
		}
		if best.size() == budget and not _better(item, best.back()):
			continue
		var at: int = 0
		while at < best.size() and not _better(item, best[at]):
			at += 1
		best.insert(at, item)
		if best.size() > budget:
			best.resize(budget)
	var result := PackedInt32Array()
	for item in best:
		result.append(int(item["index"]))
	return result
