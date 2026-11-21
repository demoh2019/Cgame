extends RefCounted
## Facade for CgameItemLedger: uses the native engine class (modules/cgame_server) when the running
## engine has it and falls back to res://scripts/server/item_ledger.gd otherwise. Both
## implementations share the same API and semantics, so callers never need to care which one they got.
##
## Usage: preload this file and call create() instead of Script.new():
##   const ItemLedgerFacade = preload("res://game_facade/item_ledger.gd")
##   var obj = ItemLedgerFacade.create(0)

const NATIVE_CLASS := "CgameItemLedger"
const FALLBACK_SCRIPT = preload("res://scripts/server/item_ledger.gd")


## True when the native C++ implementation is available in this engine build.
static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## Creates a new instance, native when possible.
static func create(server_id: int = 0) -> Variant:
	if is_native():
		var obj: Variant = ClassDB.instantiate(NATIVE_CLASS)
		obj.server_id = server_id
		return obj
	return FALLBACK_SCRIPT.new(server_id)


## {item id: [server ids]} for every id held by more than one ledger.
static func find_duplicates(ledgers: Array) -> Dictionary:
	if is_native():
		return (ClassDB.instantiate(NATIVE_CLASS) as Object).call("find_duplicates", ledgers)
	return FALLBACK_SCRIPT.find_duplicates(ledgers)


## Freezes every copy of every duplicated id; returns the sorted ids.
static func quarantine_duplicates(ledgers: Array) -> Array:
	if is_native():
		return (ClassDB.instantiate(NATIVE_CLASS) as Object).call("quarantine_duplicates", ledgers)
	return FALLBACK_SCRIPT.quarantine_duplicates(ledgers)


## Keeps the highest-epoch copy; returns the surviving server id or -1.
static func resolve_duplicate(ledgers: Array, id: String) -> int:
	if is_native():
		return (ClassDB.instantiate(NATIVE_CLASS) as Object).call("resolve_duplicate", ledgers, id)
	return FALLBACK_SCRIPT.resolve_duplicate(ledgers, id)
