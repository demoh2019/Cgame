extends RefCounted
## Facade over the platform services. Prefers the native CgamePlatformServices engine singleton and its
## backends (modules/cgame_platform) and falls back to scripts/shared/platform_services.gd when the engine was
## built without the module.
##
## Both implementations expose the same facade methods (save_game, load_game, unlock_achievement, start_session,
## should_pause, ...) and signals, so game code only needs the objects returned here. The enum values match
## (SaveResult / RecoverSource); read them from the object's script constants or from the native class.

const LEGACY = preload("res://scripts/shared/platform_services.gd")
const NATIVE_CLASS := &"CgamePlatformServices"

static var _legacy_default: RefCounted = null


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## The shared services object. Native: the engine singleton. Fallback: one lazily created GDScript instance.
static func get_services() -> Object:
	if is_native() and Engine.has_singleton(NATIVE_CLASS):
		return Engine.get_singleton(NATIVE_CLASS)
	if _legacy_default == null:
		_legacy_default = LEGACY.new()
	return _legacy_default


## A separate services object with its own backend (tests, secondary sessions).
static func create_services(backend: Object = null) -> Object:
	if is_native():
		var services: Object = ClassDB.instantiate(NATIVE_CLASS)
		services.set_backend(backend if backend != null else desktop_backend())
		return services
	return LEGACY.new(backend)


static func desktop_backend(root: String = "user://platform") -> RefCounted:
	if is_native():
		var backend: RefCounted = ClassDB.instantiate(&"CgameDesktopPlatformBackend")
		backend.set_root(root)
		return backend
	return LEGACY.DesktopBackend.new(root)


static func mock_backend() -> RefCounted:
	if is_native():
		return ClassDB.instantiate(&"CgameMockPlatformBackend")
	return LEGACY.MockConsoleBackend.new()


## Integrity envelope helpers ("CGS1:<hash>:<json>"), identical in both implementations.
static func encode_save(data: Dictionary) -> PackedByteArray:
	if is_native():
		return get_services().encode_save(data)
	return LEGACY.encode_save(data)


static func decode_save(bytes: PackedByteArray) -> Dictionary:
	if is_native():
		return get_services().decode_save(bytes)
	return LEGACY.decode_save(bytes)
