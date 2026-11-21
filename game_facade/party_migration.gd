extends RefCounted
## Facade for CgamePartyMigration: uses the native engine class (modules/cgame_server) when the running
## engine has it and falls back to res://scripts/server/party_migration.gd otherwise. Both
## implementations share the same API and semantics, so callers never need to care which one they got.
##
## Usage: preload this file and call create() instead of Script.new():
##   const PartyMigrationFacade = preload("res://game_facade/party_migration.gd")
##   var obj = PartyMigrationFacade.create(0)

const NATIVE_CLASS := "CgamePartyMigration"
const FALLBACK_SCRIPT = preload("res://scripts/server/party_migration.gd")


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
