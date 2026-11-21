extends RefCounted
## Audio source virtualization (Wwise/FMOD virtual voices, UE5 "Play When
## Silent" virtualization): a long sound refused because every voice is busy
## keeps advancing its playback time silently and is promoted into a real
## voice — at the right offset — as soon as one frees up while it still runs.

const MIN_LENGTH := 1.5 # Short one-shots are simply dropped.
const MAX_VIRTUAL := 24

var voices: Array[Dictionary] = []


func add(sound_name: String, position: Vector3, volume_db: float, now: float, length: float) -> bool:
	if not is_finite(length) or length < MIN_LENGTH or not position.is_finite():
		return false
	if voices.size() >= MAX_VIRTUAL:
		voices.pop_front() # Oldest virtual voice has the least left to play.
	voices.append({"name": sound_name, "position": position, "volume_db": volume_db,
		"born": now, "length": length})
	return true


func expire(now: float) -> void:
	for i in range(voices.size() - 1, -1, -1):
		var v: Dictionary = voices[i]
		if now - float(v["born"]) >= float(v["length"]) - 0.1:
			voices.remove_at(i)


## Takes the loudest still-running virtual voice for the listener; {} if none.
## The result's "offset" is where real playback must resume.
func promote(now: float, listener: Vector3) -> Dictionary:
	expire(now)
	var best := -1
	var best_level := -INF
	for i in voices.size():
		var v: Dictionary = voices[i]
		var level: float = float(v["volume_db"]) - 20.0 * log(maxf(1.0, listener.distance_to(v["position"]))) / log(10.0)
		if level > best_level:
			best_level = level
			best = i
	if best < 0:
		return {}
	var chosen: Dictionary = voices[best]
	voices.remove_at(best)
	chosen["offset"] = now - float(chosen["born"])
	return chosen
