extends RefCounted
## Shared helper for the worldgen facades: resolves the native engine class (module
## `cgame_worldgen`) when the engine was built with it, otherwise reports that the
## GDScript fallback must be used.
##
## Static methods of native classes cannot be referenced by identifier in a script
## that must still parse on an engine without the module, so the facades call them
## through a cached instance (`Object.call` works for bound static methods).

static var _instances: Dictionary = {}


## True when the native class exists in this engine build.
static func available(native_class: StringName) -> bool:
	return ClassDB.class_exists(native_class)


## Returns a cached instance of `native_class` (for calling its static methods) or null.
static func singleton(native_class: StringName) -> RefCounted:
	if _instances.has(native_class):
		return _instances[native_class]
	var inst: RefCounted = null
	if ClassDB.class_exists(native_class):
		inst = ClassDB.instantiate(native_class)
	_instances[native_class] = inst
	return inst
