extends RefCounted
const CgameAnimNative = preload("res://scripts/native/animation_native.gd")
## Motion matching database and AnimationTree node. Native `CgameMotionMatchingDatabase` and
## `AnimationNodeMotionMatching` when available, `motion_matching.gd` otherwise. Both databases
## share the same API: add_clip(), build(), search(), brute_force_search(), query_from().


static func create_database() -> Variant:
	return CgameAnimNative.create(&"CgameMotionMatchingDatabase", "motion_matching.gd")


static func build_default_database() -> Variant:
	if CgameAnimNative.has_native(&"CgameMotionMatchingDatabase"):
		return CgameAnimNative.call_static(&"CgameMotionMatchingDatabase", "", &"build_default_database")
	# Script fallback: motion_db_builder.gd has no native counterpart name, so the key is local.
	return CgameAnimNative.call_static(&"CgameMotionDbBuilderScript", "motion_db_builder.gd", &"build_default_database")


## Returns an AnimationNodeMotionMatching using `database`, or null when the engine module is missing
## (script-only builds should call `database.search()` and drive an AnimationNodeAnimation instead).
static func create_animation_node(database: Variant, clip_animations: Dictionary = {}) -> AnimationRootNode:
	if not ClassDB.class_exists(&"AnimationNodeMotionMatching"):
		return null
	var node: AnimationRootNode = ClassDB.instantiate(&"AnimationNodeMotionMatching")
	node.set("database", database)
	node.set("clip_animations", clip_animations)
	return node
