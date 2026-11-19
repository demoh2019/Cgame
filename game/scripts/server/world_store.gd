extends RefCounted
## Server-only durable world persistence. A snapshot is written to a temp
## file and atomically renamed; no client ever chooses the disk path.
## Malformed/unreadable existing files fail closed rather than being overwritten.

const WorldState = preload("res://scripts/server/world_state.gd")
const MAX_SAVE_BYTES := 262144


static func world_path(world_seed: int) -> String:
	return "user://worlds/barricades_seed_%d.json" % world_seed


static func save(server, path: String = "") -> bool:
	var destination: String = path if not path.is_empty() else world_path(server.world.world_seed)
	var payload: String = JSON.stringify(WorldState.export_state(server))
	if payload.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		return false
	var absolute: String = ProjectSettings.globalize_path(destination)
	var directory: String = absolute.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return false
	var temp: String = absolute + ".tmp"
	var handle: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if handle == null:
		return false
	handle.store_string(payload)
	handle.flush()
	var write_error: Error = handle.get_error()
	handle.close()
	if write_error != OK:
		return false
	# Never erase the old snapshot before rename: the backup remains valid
	# if the filesystem cannot replace it (e.g. certain Windows setups).
	return DirAccess.rename_absolute(temp, absolute) == OK


static func load(server, path: String = "") -> Dictionary:
	var destination: String = path if not path.is_empty() else world_path(server.world.world_seed)
	if not FileAccess.file_exists(destination):
		return {"ok": true, "exists": false, "count": 0}
	var handle: FileAccess = FileAccess.open(destination, FileAccess.READ)
	if handle == null:
		return {"ok": false, "reason": "read_error"}
	if handle.get_length() <= 0 or handle.get_length() > MAX_SAVE_BYTES:
		handle.close()
		return {"ok": false, "reason": "invalid_length"}
	var json: String = handle.get_as_text()
	handle.close()
	var parsed: Variant = JSON.parse_string(json)
	if parsed == null:
		return {"ok": false, "reason": "invalid_json"}
	var result: Dictionary = server.restore_world_state(parsed)
	if not result.get("ok", false):
		return result
	return {"ok": true, "exists": true, "count": server.barricades.size()}
