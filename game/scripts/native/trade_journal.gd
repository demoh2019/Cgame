extends RefCounted
## Facade for CgameTradeJournal: uses the native engine class (modules/cgame_server) when the running
## engine has it and falls back to res://scripts/server/trade_journal.gd otherwise. Both
## implementations share the same API and semantics, so callers never need to care which one they got.
##
## Usage: preload this file and call create() instead of Script.new():
##   const TradeJournalFacade = preload("res://scripts/native/trade_journal.gd")
##   var obj = TradeJournalFacade.create()

const NATIVE_CLASS := "CgameTradeJournal"
const FALLBACK_SCRIPT = preload("res://scripts/server/trade_journal.gd")


## True when the native C++ implementation is available in this engine build.
static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## Creates a new instance, native when possible.
static func create() -> Variant:
	if is_native():
		var obj: Variant = ClassDB.instantiate(NATIVE_CLASS)
		return obj
	return FALLBACK_SCRIPT.new()


## Whether the value has the shape of a journal entry.
static func valid_entry(entry: Variant) -> bool:
	if is_native():
		return (ClassDB.instantiate(NATIVE_CLASS) as Object).call("valid_entry", entry)
	return FALLBACK_SCRIPT.valid_entry(entry)


## "pair", "single" or "none" for a journal entry.
static func replay_kind(entry: Dictionary) -> String:
	if is_native():
		return (ClassDB.instantiate(NATIVE_CLASS) as Object).call("replay_kind", entry)
	return FALLBACK_SCRIPT.replay_kind(entry)
