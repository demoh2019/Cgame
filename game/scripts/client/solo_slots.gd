extends RefCounted
## Three independently persisted solo survivors: each has its own character
## and world checkpoint, graceful-stop signal, and loopback ENet port.
## Slot 1 preserves all paths used by earlier one-survivor versions.

const SLOT_COUNT := 3
const BASE_PORT := 24566


static func valid(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


static func port(slot: int) -> int:
	return BASE_PORT + slot - 1 if valid(slot) else -1


static func character_path(slot: int) -> String:
	if not valid(slot):
		return ""
	return "user://albion_after_solo_character.json" if slot == 1 else \
		"user://albion_after_solo_character_%d.json" % slot


static func world_path(slot: int) -> String:
	if not valid(slot):
		return ""
	return "user://solo_world.json" if slot == 1 else "user://solo_world_%d.json" % slot


static func stop_path(slot: int) -> String:
	if not valid(slot):
		return ""
	return "user://albion_after_solo_stop.signal" if slot == 1 else \
		"user://albion_after_solo_stop_%d.signal" % slot


## The title screen never parses or trusts saved item contents.
## The authoritative solo server validates the full character on join.
static func description(slot: int) -> String:
	if not valid(slot):
		return "Invalid survivor slot."
	var existing: bool = FileAccess.file_exists(character_path(slot))
	var progress: String = "Continue saved survivor" if existing else "Create new survivor"
	if slot == 1:
		return "%s. Slot 1 also supports a local Nakama account." % progress
	return "%s. This slot always uses offline local saves." % progress
