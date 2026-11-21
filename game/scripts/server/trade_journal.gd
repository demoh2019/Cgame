extends RefCounted
## Durable inventory transaction journal for two-account deals (trades and
## market sales). Redo log with after-images: the post-deal snapshots of both
## characters are fsynced to disk BEFORE the atomic Nakama pair commit, so a
## server crash between "deal done in memory" and "backend confirmed" can be
## replayed on restart with the same transaction id (the backend dedupes it).
##
## A side is "superseded" once a later save of that account succeeded: its
## snapshot is older than the backend and must never be written back. Replay
## then settles only the side(s) that are still newest.

const VERSION := 1
const MAX_ENTRIES := 256

var path: String = ""
var entries: Dictionary = {} # tx -> {"a": side, "b": side, "time": float}


static func _side(user_id: String, data: Dictionary) -> Dictionary:
	return {"user": user_id, "data": data, "superseded": false}


func open_file(journal_path: String) -> bool:
	path = journal_path
	entries.clear()
	if not FileAccess.file_exists(path):
		return _flush()
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != VERSION \
			or typeof(parsed.get("entries")) != TYPE_DICTIONARY:
		return false # Never guess at a corrupt money journal; the operator must look.
	for tx in parsed["entries"]:
		var entry: Variant = parsed["entries"][tx]
		if valid_entry(entry):
			entries[str(tx)] = entry
	return true


static func valid_entry(entry: Variant) -> bool:
	if typeof(entry) != TYPE_DICTIONARY:
		return false
	for key in ["a", "b"]:
		var side: Variant = entry.get(key)
		if typeof(side) != TYPE_DICTIONARY or typeof(side.get("user")) != TYPE_STRING \
				or str(side["user"]).is_empty() or typeof(side.get("data")) != TYPE_DICTIONARY \
				or typeof(side.get("superseded")) != TYPE_BOOL:
			return false
	return true


## Write-ahead: returns false if the deal could not be made durable.
func record(tx: String, user_a: String, data_a: Dictionary, user_b: String, data_b: Dictionary) -> bool:
	if tx.is_empty() or entries.size() >= MAX_ENTRIES:
		return false
	entries[tx] = {"a": _side(user_a, data_a.duplicate(true)), "b": _side(user_b, data_b.duplicate(true)),
		"time": Time.get_unix_time_from_system()}
	return _flush()


## The backend confirmed the deal (or a replay settled it).
func settle(tx: String) -> void:
	if entries.erase(tx):
		_flush()


## A newer single-account save landed: that side's journaled snapshot is stale.
func supersede(user_id: String) -> void:
	var changed := false
	for tx in entries.keys():
		var entry: Dictionary = entries[tx]
		for key in ["a", "b"]:
			if str(entry[key]["user"]) == user_id and not bool(entry[key]["superseded"]):
				entry[key]["superseded"] = true
				changed = true
		if bool(entry["a"]["superseded"]) and bool(entry["b"]["superseded"]):
			entries.erase(tx)
	if changed:
		_flush()


## Replay plan: "pair" when both sides are newest, else "single" for the live side.
static func replay_kind(entry: Dictionary) -> String:
	var a_live := not bool(entry["a"]["superseded"])
	var b_live := not bool(entry["b"]["superseded"])
	if a_live and b_live:
		return "pair"
	if a_live or b_live:
		return "single"
	return "none"


func accounts() -> PackedStringArray:
	var result := PackedStringArray()
	for tx in entries:
		for key in ["a", "b"]:
			var user := str(entries[tx][key]["user"])
			if not result.has(user):
				result.append(user)
	return result


func _flush() -> bool:
	if path.is_empty():
		return true # In-memory journal (tests, offline servers).
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": VERSION, "entries": entries}))
	file.flush()
	file.close()
	# Rename is atomic on the same filesystem: readers see the old or the new journal, never half.
	return DirAccess.rename_absolute(temp, path) == OK
