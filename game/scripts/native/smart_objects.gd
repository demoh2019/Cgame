@tool
extends RefCounted
## Facade for the Smart Object registry: create() returns a native CgameSmartObjects
## when the engine module is available and a GDScript smart_objects.gd instance
## otherwise. Both expose the same API (register_behavior/object, unregister_object,
## find, claim, release, touch, start_interaction, interaction_state, advance,
## placement_score, auto_place and the on_effect / release_on_complete /
## default_claim_timeout properties).
##
## Usage:  var so = SmartObjectsFacade.create()

const Fallback = preload("res://scripts/shared/smart_objects.gd")
const NATIVE_CLASS := &"CgameSmartObjects"


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


static func create() -> RefCounted:
	if is_native():
		return ClassDB.instantiate(NATIVE_CLASS)
	return Fallback.new()
