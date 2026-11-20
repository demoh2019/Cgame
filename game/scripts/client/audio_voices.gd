extends RefCounted
## Voice limiting and per-shot variation (Unity AudioSource priority + max voices / Unreal Sound Concurrency).

const MAX_VOICES := 24
const SAME_SOUND_MAX := 5
const ROOM := -2 # victim(): nothing to cull, the new voice may start.
const DROP_NEW := -1 # victim(): the new voice itself is the one to drop.


## Random pitch/volume jitter so repeated one-shots do not sound machine-gunned. `roll1`/`roll2` are 0..1.
static func variation(roll1: float, roll2: float, pitch_range: float = 0.08, db_range: float = 1.5) -> Dictionary:
	return {"pitch": 1.0 + (roll1 * 2.0 - 1.0) * pitch_range, "db": (roll2 * 2.0 - 1.0) * db_range}


## Loudness a voice has at the listener: volume minus a simple distance rolloff. Lower = first to be culled.
static func audibility(volume_db: float, distance: float, unit_size: float = 14.0) -> float:
	return volume_db - 20.0 * log(1.0 + distance / maxf(unit_size, 0.1)) / log(10.0)


## Index in `voices` (dicts with "name", "audibility", "age") to cull so a new voice of `name` with
## `new_audibility` may start; ROOM when nothing needs culling, DROP_NEW when the new voice is the weakest.
static func victim(voices: Array, name: String, new_audibility: float, max_voices: int = MAX_VOICES, same_max: int = SAME_SOUND_MAX) -> int:
	var pool: Array[int] = []
	for i in voices.size():
		if voices[i]["name"] == name:
			pool.append(i)
	if pool.size() < same_max:
		if voices.size() < max_voices:
			return ROOM
		pool.clear()
		for i in voices.size():
			pool.append(i)
	var worst: int = pool[0]
	for i in pool:
		if _worse(voices[i], voices[worst]):
			worst = i
	if float(voices[worst]["audibility"]) > new_audibility + 3.0:
		return DROP_NEW
	return worst


static func _worse(a: Dictionary, b: Dictionary) -> bool:
	if absf(float(a["audibility"]) - float(b["audibility"])) < 0.5:
		return float(a["age"]) > float(b["age"])
	return float(a["audibility"]) < float(b["audibility"])
