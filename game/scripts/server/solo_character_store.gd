extends RefCounted
## One offline solo world's survivor. Never enabled for public guest ENet
## servers: only the loopback solo launcher supplies this save path.
## The same GameServer.character_data/apply_character validation as Nakama
## prevents accepting fabricated item stacks, invalid positions or counters.

const WorldPersistence = preload("res://scripts/server/world_persistence.gd")
const SaveValidation = preload("res://scripts/shared/save_validation.gd")
const VERSION := 1
const MAX_BYTES := 262144


static func load_character(sim, path: String) -> Dictionary:
	if sim == null or not WorldPersistence.valid_world_path(path):
		return {"ok": false, "reason": "invalid_path"}
	if not FileAccess.file_exists(path):
		return {"ok": true, "exists": false, "character": {}}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "read_failed"}
	var size: int = file.get_length()
	if size <= 0 or size > MAX_BYTES:
		file.close()
		return {"ok": false, "reason": "invalid_length"}
	var decoded: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(decoded) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_json"}
	if decoded.get("version") != VERSION or decoded.get("world_seed") != int(sim.world.world_seed):
		return {"ok": false, "reason": "different_world"}
	if typeof(decoded.get("character")) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_character"}
	# JSON returns whole numbers as floats; turn them back before the strict validators see them (as Nakama loads do).
	var character: Dictionary = SaveValidation.whole_numbers_as_ints(decoded["character"])
	if not sim.valid_character_data(character):
		return {"ok": false, "reason": "invalid_character"}
	return {"ok": true, "exists": true, "character": character}


## Write to a temporary file, flush, then atomically rename. The old
## committed character is never truncated before the new one is complete.
static func save_character(sim, path: String, character: Dictionary) -> bool:
	if sim == null or not WorldPersistence.valid_world_path(path) or \
			not sim.valid_character_data(character):
		return false
	# Corrupt existing saves are refused rather than silently overwritten.
	if FileAccess.file_exists(path) and not bool(load_character(sim, path).get("ok", false)):
		return false
	var payload: String = JSON.stringify({
		"version": VERSION, "world_seed": int(sim.world.world_seed),
		"character": character,
	})
	if payload.to_utf8_buffer().size() > MAX_BYTES:
		return false
	var absolute: String = ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return false
	var temp: String = absolute + ".tmp"
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(payload)
	file.flush()
	var result: Error = file.get_error()
	file.close()
	if result != OK:
		return false
	return DirAccess.rename_absolute(temp, absolute) == OK
