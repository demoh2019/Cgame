extends RefCounted
## Portable fallback for Cgame's AudioMixSnapshotController.
## Profile stage dB values are independent of user volume and temporary ducking.
const MAX_MIXES := 16
const MAX_BUSES := 8
const MAX_STAGE_DB := 30.0
const MAX_FADE_SECONDS := 15.0


static func activate_mix(mixes: Dictionary, source: String, offsets: Dictionary,
		fade_seconds: float = 1.0) -> bool:
	if source.is_empty() or source.length() > 128 or offsets.is_empty() \
			or offsets.size() > MAX_BUSES or not is_finite(fade_seconds) \
			or fade_seconds < 0.0 or fade_seconds > MAX_FADE_SECONDS:
		return false
	var parsed: Dictionary = {}
	for key in offsets:
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			return false
		var bus: String = str(key)
		if bus.is_empty() or bus.length() > 128 or parsed.has(bus):
			return false
		var raw = offsets[key]
		if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
			return false
		var db: float = float(raw)
		if not is_finite(db) or db > 0.0 or db < -MAX_STAGE_DB:
			return false
		parsed[bus] = db
	if not mixes.has(source) and mixes.size() >= MAX_MIXES:
		return false
	var weight: float = float(mixes[source]["weight"]) if mixes.has(source) else 0.0
	mixes[source] = {"offsets": parsed, "weight": 1.0 if fade_seconds == 0.0 else weight,
		"target": 1.0, "fade": fade_seconds}
	return true


static func deactivate_mix(mixes: Dictionary, source: String, fade_seconds: float = 1.0) -> bool:
	if not is_finite(fade_seconds) or fade_seconds < 0.0 or fade_seconds > MAX_FADE_SECONDS \
			or not mixes.has(source):
		return false
	if fade_seconds == 0.0:
		mixes.erase(source)
		return true
	var profile: Dictionary = mixes[source]
	profile["target"] = 0.0
	profile["fade"] = fade_seconds
	return true


static func tick(mixes: Dictionary, delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	for source in mixes.keys():
		var profile: Dictionary = mixes[source]
		var target: float = float(profile["target"])
		var weight: float = float(profile["weight"])
		var fade: float = float(profile["fade"])
		if fade == 0.0:
			weight = target
		elif target > weight:
			weight = minf(target, weight + delta / fade)
		else:
			weight = maxf(target, weight - delta / fade)
		profile["weight"] = weight
		if target == 0.0 and weight <= 0.0:
			mixes.erase(source)


static func bus_offset_db(mixes: Dictionary, bus: String) -> float:
	if bus.is_empty() or bus.length() > 128:
		return 0.0
	var sum_db := 0.0
	for profile in mixes.values():
		var offsets: Dictionary = profile["offsets"]
		if offsets.has(bus):
			sum_db += float(offsets[bus]) * float(profile["weight"])
	return maxf(-60.0, sum_db)


static func mix_weight(mixes: Dictionary, source: String) -> float:
	return float(mixes[source]["weight"]) if mixes.has(source) else 0.0
