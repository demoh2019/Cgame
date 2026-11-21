extends RefCounted
## Bridge to the native `cgame_animation` engine module with GDScript fallbacks.
##
## Every facade asks this helper for a "provider": an object on which a function can be called by
## name. When the engine was built with the module, the provider is an instance of the native class
## (static native functions can be called through an instance). Otherwise it is the legacy GDScript
## from `res://scripts/client/`, so game code behaves the same in both cases.

const SCRIPT_DIR := "res://scripts/client/"

static var _providers: Dictionary = {}


static func has_native(native_class: StringName) -> bool:
	return ClassDB.class_exists(native_class) and ClassDB.can_instantiate(native_class)


## Returns an Object that exposes the library functions, or null if neither implementation exists.
static func provider(native_class: StringName, fallback_script: String) -> Object:
	var key := "%s|%s" % [native_class, fallback_script]
	if _providers.has(key):
		return _providers[key]
	var result: Object = null
	if has_native(native_class):
		result = ClassDB.instantiate(native_class)
	elif not fallback_script.is_empty() and ResourceLoader.exists(SCRIPT_DIR + fallback_script):
		result = load(SCRIPT_DIR + fallback_script)
	_providers[key] = result
	return result


static func call_static(native_class: StringName, fallback_script: String, method: StringName, args: Array = []) -> Variant:
	var p := provider(native_class, fallback_script)
	if p == null:
		push_error("Cgame animation: neither native %s nor %s is available" % [native_class, fallback_script])
		return null
	return p.callv(method, args)


## Creates an instance: the native class if present, otherwise the GDScript class (`fallback_args` go to _init).
static func create(native_class: StringName, fallback_script: String, fallback_args: Array = []) -> Variant:
	if has_native(native_class):
		return ClassDB.instantiate(native_class)
	var path := SCRIPT_DIR + fallback_script
	if ResourceLoader.exists(path):
		var script: GDScript = load(path)
		return script.callv("new", fallback_args)
	push_error("Cgame animation: neither native %s nor %s is available" % [native_class, fallback_script])
	return null
