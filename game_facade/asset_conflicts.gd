extends RefCounted
## Facade over the asset conflict tooling. Prefers the native CgameAssetConflicts (modules/cgame_platform) and
## falls back to scripts/tools/asset_conflicts.gd. The static helpers below keep the original call signatures.

const LEGACY = preload("res://scripts/tools/asset_conflicts.gd")
const NATIVE_CLASS := &"CgameAssetConflicts"

static var _native_instance: Object = null


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


# Native static methods are reachable through any instance.
static func _n() -> Object:
	if _native_instance == null:
		_native_instance = ClassDB.instantiate(NATIVE_CLASS)
	return _native_instance


## A lock table (exclusive checkout locks). Native or GDScript object with lock/unlock/owner/can_edit/active_locks.
static func create() -> Object:
	if is_native():
		return ClassDB.instantiate(NATIVE_CLASS)
	return LEGACY.new()


static func scan(dir: String) -> Dictionary:
	return _n().scan(dir) if is_native() else LEGACY.scan(dir)


static func hash_file(path: String) -> Dictionary:
	return _n().hash_file(path) if is_native() else LEGACY.hash_file(path)


static func changed_paths(a: Dictionary, b: Dictionary) -> Array:
	return _n().changed_paths(a, b) if is_native() else LEGACY.changed_paths(a, b)


static func three_way_binary(base: Dictionary, mine: Dictionary, theirs: Dictionary) -> Array:
	return _n().three_way_binary(base, mine, theirs) if is_native() else LEGACY.three_way_binary(base, mine, theirs)


static func parse_tscn(text: String) -> Dictionary:
	return _n().parse_tscn(text) if is_native() else LEGACY.parse_tscn(text)


static func flatten_scene_dict(d: Dictionary) -> Dictionary:
	return _n().flatten_scene_dict(d) if is_native() else LEGACY.flatten_scene_dict(d)


static func merge_scene(base: Dictionary, mine: Dictionary, theirs: Dictionary) -> Dictionary:
	return _n().merge_scene(base, mine, theirs) if is_native() else LEGACY.merge_scene(base, mine, theirs)


static func three_way(base: Dictionary, mine: Dictionary, theirs: Dictionary) -> Array:
	return _n().three_way(base, mine, theirs) if is_native() else LEGACY.three_way(base, mine, theirs)


static func override_conflicts(instance_overrides: Dictionary, base_changes: Dictionary) -> Array:
	if is_native():
		return _n().override_conflicts(instance_overrides, base_changes)
	return LEGACY.override_conflicts(instance_overrides, base_changes)
