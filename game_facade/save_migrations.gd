extends RefCounted
## Facade for CgameSaveMigrations: uses the native engine class (modules/cgame_server) when the running
## engine has it and falls back to res://scripts/server/save_migrations.gd otherwise. Both
## implementations share the same API and semantics, so callers never need to care which one they got.
##
## Usage: preload this file and call create() instead of Script.new():
##   const SaveMigrationsFacade = preload("res://game_facade/save_migrations.gd")
##   var obj = SaveMigrationsFacade.create()

const NATIVE_CLASS := "CgameSaveMigrations"
const FALLBACK_SCRIPT = preload("res://scripts/server/save_migrations.gd")


## True when the native C++ implementation is available in this engine build.
static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## Creates a new instance, native when possible.
static func create() -> Variant:
	if is_native():
		var obj: Variant = ClassDB.instantiate(NATIVE_CLASS)
		return obj
	return FALLBACK_SCRIPT.new()


## Registry preloaded with the two example character migrations (v1 -> v2 -> v3).
static func character_registry() -> Variant:
	if is_native():
		return (ClassDB.instantiate(NATIVE_CLASS) as Object).call("character_registry")
	return FALLBACK_SCRIPT.character_registry()
