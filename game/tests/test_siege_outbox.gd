extends RefCounted
## Durable siege outbox regression checks with real user:// files.
## No Nakama process required; the Nakama RPC integration has separate tests.

const Outbox = preload("res://scripts/server/siege_outbox.gd")
const TEST_PATH := "user://tests/siege_outbox_recovery.json"
const RAVENS := "12345678-1234-1234-1234-123456789abc"
const WOLVES := "abcdefab-1234-1234-1234-abcdefabcdef"


func _record(id: String, guild: String = RAVENS, seed: int = 205) -> Dictionary:
	return {
		"event_id": id, "guild_id": guild,
		"site": 1, "world_seed": seed,
	}


func _cleanup() -> void:
	var absolute: String = ProjectSettings.globalize_path(TEST_PATH)
	DirAccess.remove_absolute(absolute)
	DirAccess.remove_absolute(absolute + ".tmp")


func _overwrite(content: String) -> void:
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(content)
		file.flush()
		file.close()


func run(t) -> void:
	_cleanup()
	t.current = "outbox rejects unsafe paths and invalid server event metadata"
	var journal := Outbox.new()
	t.check(not journal.open_file("res://user_data/ledger.json", 205),
		"cannot persist a server journal inside the packaged resource tree")
	t.check(not journal.open_file("user://../outside.json", 205),
		"cannot escape the server's user data directory")
	t.check(journal.open_file(TEST_PATH, 205), "new outbox starts without data")
	t.eq(journal.snapshot().size(), 0, "new queue is empty")
	var id1 := "0123456789abcdef0123456789abcdef"
	var id2 := "0123456789abcdef0123456789abcdee"
	var first := _record(id1)
	var second := _record(id2, WOLVES)
	t.check(Outbox.valid_record(first, 205), "canonical event ID and Nakama guild UUID accepted")
	t.check(not Outbox.valid_record(first.merged({"event_id": "not-a-uuid"}), 205),
		"invalid event IDs rejected")
	t.check(not Outbox.valid_record(first.merged({"event_id": id1.to_upper()}), 205),
		"noncanonical upper-case event IDs rejected")
	t.check(not Outbox.valid_record(first.merged({"guild_id": "not-a-uuid"}), 205),
		"invalid guild UUID rejected")
	t.check(not Outbox.valid_record(first.merged({"site": 1.5}), 205),
		"fractional site IDs rejected")
	t.check(not Outbox.valid_record(first.merged({"world_seed": 206}), 205),
		"cross-seed event cannot enter current world queue")
	t.check(not Outbox.valid_record(first.merged({"world_seed": NAN}), 205),
		"nonfinite world seeds refused")
	t.check(not Outbox.valid_record(first.merged({"extra": 3}), 205),
		"arbitrary client-controlled record fields refused")

	t.current = "append persists to disk before acknowledging Nakama"
	t.check(journal.enqueue(first), "first event journaled synchronously")
	t.check(journal.enqueue(second), "second independent guild event journaled")
	t.eq(journal.snapshot().size(), 2, "two unacknowledged entries are retained")
	t.check(not journal.enqueue(first), "duplicate event UUID refused")
	t.check(not journal.enqueue(_record("0123456789abcdef0123456789abcdec", RAVENS, 206)),
		"the wrong world cannot enqueue a victory")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	t.eq(int(saved["version"]), Outbox.VERSION, "checkpoint version is recorded")
	t.eq(int(saved["world_seed"]), 205, "world seed is part of journal header")
	t.eq(saved["entries"].size(), 2, "both entries really exist on disk")
	var detached: Array[Dictionary] = journal.snapshot()
	detached[0]["site"] = 25
	t.eq(journal.snapshot()[0]["site"], 1, "callers cannot mutate stored records by reference")

	t.current = "restart recovers exact IDs and no acknowledgements are lost"
	var reboot := Outbox.new()
	t.check(reboot.open_file(TEST_PATH, 205), "second server loads previous checkpoint")
	t.eq(reboot.snapshot()[0]["event_id"], id1, "the oldest event UUID survives restart")
	t.eq(reboot.snapshot()[1]["event_id"], id2, "the later event UUID survives restart")
	t.check(not reboot.acknowledge(id2), "cannot acknowledge a later event out of order")
	t.eq(reboot.snapshot().size(), 2, "out-of-order ACK leaves queue and file unchanged")
	t.check(reboot.acknowledge(id1), "confirmed first receipt removed atomically")
	var next_reboot := Outbox.new()
	t.check(next_reboot.open_file(TEST_PATH, 205), "restarts after first ACK")
	t.eq(next_reboot.snapshot().size(), 1, "only one unacknowledged event recovered")
	t.eq(next_reboot.snapshot()[0]["event_id"], id2,
		"second event keeps its original immutable ID on retry")
	t.check(next_reboot.acknowledge(id2), "second confirmed receipt removed")
	var empty := Outbox.new()
	t.check(empty.open_file(TEST_PATH, 205), "restarts after all ACKs")
	t.eq(empty.snapshot().size(), 0, "confirmed events are not replayed once checkpointed")
	t.check(not empty.acknowledge(id1), "cannot double-acknowledge a removed event")

	t.current = "wrong seed, corruption and overflow fail closed without resetting state"
	t.check(empty.enqueue(first), "create durable record before corruption checks")
	var wrong_seed := Outbox.new()
	t.check(not wrong_seed.open_file(TEST_PATH, 206),
		"another world's server cannot consume this siege history")
	t.eq(wrong_seed.snapshot().size(), 0, "refused file is not partially loaded")
	_overwrite("not-json")
	var broken := Outbox.new()
	t.check(not broken.open_file(TEST_PATH, 205), "invalid JSON blocks recovery")
	t.check(not broken.enqueue(first), "rejected journal cannot silently recreate state")
	_overwrite(JSON.stringify({"version": Outbox.VERSION, "world_seed": 205,
		"entries": [first, first]}))
	var duplicated := Outbox.new()
	t.check(not duplicated.open_file(TEST_PATH, 205),
		"duplicate event IDs inside a corrupted queue refuse startup")
	var many: Array = []
	for i in range(Outbox.MAX_RECORDS + 1):
		many.append(first)
	_overwrite(JSON.stringify({"version": Outbox.VERSION, "world_seed": 205,
		"entries": many}))
	var oversized_count := Outbox.new()
	t.check(not oversized_count.open_file(TEST_PATH, 205),
		"oversized record count cannot exhaust server memory")
	_cleanup()
