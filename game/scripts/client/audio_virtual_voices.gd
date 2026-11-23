extends RefCounted
## Audio source virtualization (Wwise/FMOD virtual voices, UE5 "Play When
## Silent" virtualization): a long sound refused because every voice is busy
## keeps advancing its playback time silently and is promoted into a real
## voice — at the right offset — as soon as one frees up while it still runs.

const MIN_LENGTH := 1.5 # Short one-shots are simply dropped.
const MAX_VIRTUAL := 24

var voices: Array[Dictionary] = []


func add(sound_name: String, position: Vector3, volume_db: float, now: float, length: float) -> bool:
	if sound_name.is_empty() or not is_finite(length) or length < MIN_LENGTH 			or not is_finite(now) or not is_finite(volume_db) 			or not position.is_finite():
		return false
	expire(now)
	if voices.size() >= MAX_VIRTUAL:
		# The oldest voice is not necessarily the one nearest completion:
		# long ambience may outlive a newer short warning. Preserve it.
		var victim: int = 0
		var least_remaining: float = INF
		for i in voices.size():
			var entry: Dictionary = voices[i]
			var remaining: float = float(entry["length"]) 				- maxf(0.0, now - float(entry["born"]))
			if remaining < least_remaining:
				least_remaining = remaining
				victim = i
		voices.remove_at(victim)
	voices.append({"name": sound_name, "position": position, "volume_db": volume_db,
		"born": now, "length": length})
	return true


func expire(now: float) -> void:
	if not is_finite(now):
		return
	for i in range(voices.size() - 1, -1, -1):
		var v: Dictionary = voices[i]
		if now - float(v["born"]) >= float(v["length"]) - 0.1:
			voices.remove_at(i)


## Takes the loudest still-running virtual voice for the listener; {} if none.
## The result's "offset" is where real playback must resume.
func promote(now: float, listener: Vector3) -> Dictionary:
	if not is_finite(now) or not listener.is_finite():
		return {}
	expire(now)
	var best := -1
	var best_level := -INF
	for i in voices.size():
		var v: Dictionary = voices[i]
		if now < float(v["born"]):
			continue # Scheduled sound has not begun.
		var level: float = float(v["volume_db"]) - 20.0 * log(maxf(1.0, listener.distance_to(v["position"]))) / log(10.0)
		if level > best_level:
			best_level = level
			best = i
	if best < 0:
		return {}
	var chosen: Dictionary = voices[best]
	voices.remove_at(best)
	chosen["offset"] = clampf(now - float(chosen["born"]), 0.0,
		maxf(0.0, float(chosen["length"]) - 0.1))
	return chosen
