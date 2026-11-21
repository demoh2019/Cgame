extends RefCounted
## Memory lifetime tracker: track(obj, tag) registers an object; sample() records
## live counts per tag plus engine monitors (ObjectDB count, static memory),
## alloc/free events with lifetimes, and flags leak suspects.
## Original code (MIT-compatible).

## id -> {"tag", "born_sample", "born_usec"}
var _live: Dictionary = {}
## Events: {"type": "alloc"|"free", "tag", "sample", "usec", "lifetime_samples"}
var events: Array[Dictionary] = []
## Samples: {"index", "usec", "live": {tag: count}, "objects": int, "nodes": int, "static_mem": int}
var samples: Array[Dictionary] = []
var max_events: int = 16384
var _lifetimes: Dictionary = {}  # tag -> Array[int] of lifetimes in samples


func track(obj: Object, tag: String) -> void:
	if obj == null:
		return
	_live[obj.get_instance_id()] = {"tag": tag, "born_sample": samples.size(), "born_usec": Time.get_ticks_usec()}
	_push({"type": "alloc", "tag": tag, "sample": samples.size(), "usec": Time.get_ticks_usec(), "lifetime_samples": 0})


func tracked_count() -> int:
	return _live.size()


## Detects frees (instance ids that no longer resolve) and records a sample.
func sample() -> Dictionary:
	var idx: int = samples.size()
	var now: int = Time.get_ticks_usec()
	var live: Dictionary = {}
	for key in _live.keys():
		var id: int = int(key)
		var info: Dictionary = _live[key]
		var tag: String = str(info["tag"])
		if is_instance_valid(instance_from_id(id)):
			live[tag] = int(live.get(tag, 0)) + 1
		else:
			var life: int = idx - int(info["born_sample"])
			var arr: Array = _lifetimes.get(tag, [])
			arr.append(life)
			_lifetimes[tag] = arr
			_push({"type": "free", "tag": tag, "sample": idx, "usec": now, "lifetime_samples": life})
			_live.erase(key)
	var s: Dictionary = {
		"index": idx, "usec": now, "live": live,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"static_mem": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
	}
	samples.append(s)
	return s


## Tags whose live count never dropped over the last `window` samples, grew by at
## least `min_growth`, and still hold an object that predates the window.
## Returns [{tag, live, growth, oldest_age_samples}] sorted by growth desc.
func leak_suspects(window: int = 5, min_growth: int = 2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if samples.size() < window:
		return out
	var start: int = samples.size() - window
	var tags: Dictionary = {}
	for i in range(start, samples.size()):
		var lv: Dictionary = samples[i]["live"]
		for t in lv:
			tags[t] = true
	for t in tags:
		var tag: String = str(t)
		var prev: int = -1
		var first: int = 0
		var last: int = 0
		var monotonic: bool = true
		for i in range(start, samples.size()):
			var lv: Dictionary = samples[i]["live"]
			var c: int = int(lv.get(tag, 0))
			if i == start:
				first = c
			elif c < prev:
				monotonic = false
				break
			prev = c
			last = c
		if not monotonic or last - first < min_growth:
			continue
		var oldest: int = 0
		for key in _live:
			var info: Dictionary = _live[key]
			if str(info["tag"]) == tag:
				oldest = maxi(oldest, samples.size() - int(info["born_sample"]))
		if oldest >= window:
			out.append({"tag": tag, "live": last, "growth": last - first, "oldest_age_samples": oldest})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["growth"]) > int(b["growth"]))
	return out


## Per-tag lifetime stats (in samples) for freed objects: {tag: {count, mean, max}}.
func lifetime_stats() -> Dictionary:
	var out: Dictionary = {}
	for tag in _lifetimes:
		var arr: Array = _lifetimes[tag]
		var total: int = 0
		var mx: int = 0
		for v in arr:
			total += int(v)
			mx = maxi(mx, int(v))
		out[tag] = {"count": arr.size(), "mean": float(total) / float(arr.size()), "max": mx}
	return out


## Rows for the capture's "memory_samples" section.
func export_samples() -> Array[Dictionary]:
	return samples.duplicate(true)


func _push(ev: Dictionary) -> void:
	if events.size() >= max_events:
		events.pop_front()
	events.append(ev)
