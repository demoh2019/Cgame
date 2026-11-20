extends RefCounted
## Crash-recoverable write-ahead outbox for server-authoritative guild siege wins.
## Append is committed to user:// before the first Nakama RPC attempt.
## Acknowledgement removes an entry only after Nakama confirms its receipt.
## One dedicated server process must own the outbox path (no shared writers).

const WorldPersistence = preload("res://scripts/server/world_persistence.gd")
const VERSION := 1
const MAX_RECORDS := 512
const MAX_BYTES := 131072
const MAX_SITE_ID := 25

var path: String = ""
var world_seed: int = 0
var entries: Array[Dictionary] = []


static func _bounded_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var amount: float = float(value)
	return is_finite(amount) and amount == floor(amount) \
		and amount >= float(minimum) and amount <= float(maximum)


static func _hex_string(value: Variant, expected_length: int, uuid: bool) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != expected_length:
		return false
	for i in range(value.length()):
		var ch: String = value.substr(i, 1)
		if uuid and (i == 8 or i == 13 or i == 18 or i == 23):
			if ch != "-":
				return false
		elif not "0123456789abcdef".contains(ch):
			return false
	return true


static func valid_record(record: Variant, seed: int) -> bool:
	if typeof(record) != TYPE_DICTIONARY or record.size() != 4:
		return false
	if not record.has("event_id") or not record.has("guild_id") \
			or not record.has("site") or not record.has("world_seed"):
		return false
	return _hex_string(record["event_id"], 32, false) \
		and _hex_string(record["guild_id"], 36, true) \
		and _bounded_integer(record["site"], 1, MAX_SITE_ID) \
		and _bounded_integer(record["world_seed"], -2147483648, 2147483647) \
		and int(record["world_seed"]) == seed


func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in entries:
		result.append(record.duplicate(true))
	return result


## Returns false (fail closed) on malformed, oversized or cross-seed files.
## Missing file means a new clean journal. Never silently reset corruption.
func open_file(new_path: String, seed: int) -> bool:
	if not WorldPersistence.valid_world_path(new_path):
		return false
	if not FileAccess.file_exists(new_path):
		path = new_path
		world_seed = seed
		entries.clear()
		return true
	var file: FileAccess = FileAccess.open(new_path, FileAccess.READ)
	if file == null:
		return false
	var length: int = file.get_length()
	if length <= 0 or length > MAX_BYTES:
		file.close()
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY or parsed.size() != 3:
		return false
	if not _bounded_integer(parsed.get("version"), VERSION, VERSION) \
			or not _bounded_integer(parsed.get("world_seed"), -2147483648, 2147483647) \
			or int(parsed["world_seed"]) != seed:
		return false
	var stored: Variant = parsed.get("entries")
	if typeof(stored) != TYPE_ARRAY or stored.size() > MAX_RECORDS:
		return false
	var loaded: Array[Dictionary] = []
	var seen: Dictionary = {}
	for record in stored:
		if not valid_record(record, seed) or seen.has(record["event_id"]):
			return false
		seen[record["event_id"]] = true
		loaded.append(record.duplicate(true))
	path = new_path
	world_seed = seed
	entries = loaded
	return true


## Atomically replace one complete checkpoint. Do not mutate in-memory
## entries before the disk swap has succeeded.
func _write(items: Array[Dictionary]) -> bool:
	if path.is_empty() or items.size() > MAX_RECORDS:
		return false
	var data := {"version": VERSION, "world_seed": world_seed, "entries": items}
	var payload: String = JSON.stringify(data)
	if payload.to_utf8_buffer().size() > MAX_BYTES:
		return false
	var absolute: String = ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return false
	var temporary: String = absolute + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(payload)
	file.flush()
	var result: Error = file.get_error()
	file.close()
	if result != OK:
		return false
	return DirAccess.rename_absolute(temporary, absolute) == OK


func enqueue(record: Dictionary) -> bool:
	if not valid_record(record, world_seed):
		return false
	for existing in entries:
		if existing["event_id"] == record["event_id"]:
			return false # An event cannot be journaled twice.
	var updated: Array[Dictionary] = snapshot()
	updated.append(record.duplicate(true))
	if not _write(updated):
		return false
	entries = updated
	return true


## Return false on IO errors so a confirmed receipt stays on disk and is
## safely replayed with its original ID after a restart.
func acknowledge(event_id: String) -> bool:
	if entries.is_empty() or entries.front()["event_id"] != event_id:
		return false
	var updated: Array[Dictionary] = snapshot()
	updated.pop_front()
	if not _write(updated):
		return false
	entries = updated
	return true
