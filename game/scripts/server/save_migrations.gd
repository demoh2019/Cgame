extends RefCounted
## Versioned save-data migrations.
##
## A registry of single-step migrations {from_version, to_version, migrate: Callable}. migrate()
## walks the chain from data["version"] to the target, never mutating the caller's dictionary,
## refusing gaps and downgrades. verify_roundtrip() proves a sample survives migration and
## still passes a validator, so every new schema bump ships with a fixture.
##
## Pattern credit: ordered, idempotent schema-migration chains as used by Rails/ActiveRecord
## (MIT), Flyway (Apache-2.0) and SQLite "user_version" upgrade ladders (public domain).
## This file is original GDScript; no third-party code was copied.
##
## Example character-save shape (version field "version"):
##   v1: {version:1, health, money}
##   v2: money renamed to silver                      (example_v1_to_v2)
##   v3: new "focus" meter added, default 100.0       (example_v2_to_v3)
## To add a migration: write a static func taking a Dictionary (already a deep copy, mutate
## freely) and returning the upgraded dictionary WITHOUT touching "version" (the runner stamps
## it), then register it with register(from, to, Callable). Steps must be +1 and pure.

const CHARACTER_LATEST := 3

var _steps: Dictionary = {} # from_version -> {to:int, migrate:Callable}
var last_error: String = ""


## Registry preloaded with the two example character migrations.
static func character_registry():
	var script: GDScript = load("res://scripts/server/save_migrations.gd")
	var reg = script.new()
	reg.register(1, 2, Callable(script, "example_v1_to_v2"))
	reg.register(2, 3, Callable(script, "example_v2_to_v3"))
	return reg


## Returns false (and sets last_error) for non-forward steps or a duplicate from_version.
func register(from_version: int, to_version: int, migrate_fn: Callable) -> bool:
	if to_version != from_version + 1:
		last_error = "migration %d->%d must advance exactly one version" % [from_version, to_version]
		return false
	if _steps.has(from_version):
		last_error = "migration from %d already registered" % from_version
		return false
	if not migrate_fn.is_valid():
		last_error = "migration %d->%d has an invalid callable" % [from_version, to_version]
		return false
	_steps[from_version] = {"to": to_version, "migrate": migrate_fn}
	return true


## Returns the migrated deep copy, or {} with last_error set (gap, downgrade, bad version, step failure).
func migrate(data: Dictionary, target_version: int) -> Dictionary:
	last_error = ""
	if not data.has("version") or not (data["version"] is int or data["version"] is float):
		last_error = "save has no numeric version"
		return {}
	var version: int = int(data["version"])
	if version > target_version:
		last_error = "refusing downgrade from v%d to v%d" % [version, target_version]
		return {}
	var current: Dictionary = data.duplicate(true)
	while version < target_version:
		if not _steps.has(version):
			last_error = "no migration from v%d (gap before v%d)" % [version, target_version]
			return {}
		var step: Dictionary = _steps[version]
		var migrate_fn: Callable = step["migrate"]
		var result: Variant = migrate_fn.call(current.duplicate(true))
		if not (result is Dictionary):
			last_error = "migration v%d->v%d returned a non-Dictionary" % [version, int(step["to"])]
			return {}
		current = result
		version = int(step["to"])
		current["version"] = version
	return current


## Returns problems (empty = ok): migration failure, input mutated, wrong final version,
## validator rejection, or a second migrate() call that is not a no-op.
func verify_roundtrip(data: Dictionary, migrate_to: int, validate: Callable) -> Array[String]:
	var problems: Array[String] = []
	var before: Dictionary = data.duplicate(true)
	var out: Dictionary = migrate(data, migrate_to)
	if out.is_empty():
		problems.append("migration failed: " + last_error)
		return problems
	if data != before:
		problems.append("migration mutated its input")
	if int(out.get("version", -1)) != migrate_to:
		problems.append("result version is %s, expected %d" % [str(out.get("version")), migrate_to])
	if validate.is_valid():
		var verdict: Variant = validate.call(out)
		if verdict is bool and not verdict:
			problems.append("validator rejected migrated data")
		elif verdict is String and not (verdict as String).is_empty():
			problems.append("validator: " + (verdict as String))
		elif verdict is Array:
			for item in verdict:
				problems.append("validator: " + str(item))
	var again: Dictionary = migrate(out, migrate_to)
	if again != out:
		problems.append("migrating an up-to-date save changed it")
	return problems


# --- Example character migrations -------------------------------------------------------

## v1 -> v2: "money" is renamed "silver" (value preserved; an existing "silver" wins).
static func example_v1_to_v2(data: Dictionary) -> Dictionary:
	if data.has("money"):
		if not data.has("silver"):
			data["silver"] = data["money"]
		data.erase("money")
	return data


## v2 -> v3: adds the "focus" meter, defaulting to a full 100.0 when absent.
static func example_v2_to_v3(data: Dictionary) -> Dictionary:
	if not data.has("focus"):
		data["focus"] = 100.0
	return data
