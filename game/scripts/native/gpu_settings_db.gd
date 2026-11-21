extends RefCounted
## Facade over the GPU settings database. Prefers the native CgameGPUSettingsDB (modules/cgame_platform) and
## falls back to scripts/client/gpu_settings_db.gd. The static helpers keep the original call signatures.

const LEGACY = preload("res://scripts/client/gpu_settings_db.gd")
const NATIVE_CLASS := &"CgameGPUSettingsDB"
const MAX_LEVEL: int = 3
const DEFAULT_PATH: String = "user://gpu_learned.json"
const TARGET_FRAME_MS: float = 1000.0 / 60.0

static var _native_instance: Object = null


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


static func _n() -> Object:
	if _native_instance == null:
		_native_instance = ClassDB.instantiate(NATIVE_CLASS)
	return _native_instance


static func match_adapter(adapter: String, vendor: String = "") -> Dictionary:
	return _n().match_adapter(adapter, vendor) if is_native() else LEGACY.match_adapter(adapter, vendor)


static func features_for(level: int) -> Dictionary:
	return _n().features_for(level) if is_native() else LEGACY.features_for(level)


static func recommend(adapter: String, vendor: String = "", target_ms: float = TARGET_FRAME_MS,
		path: String = DEFAULT_PATH) -> Dictionary:
	if is_native():
		return _n().recommend(adapter, vendor, target_ms, path)
	return LEGACY.recommend(adapter, vendor, target_ms, path)


static func learn(adapter: String, measured_frame_ms: float, level: int, path: String = DEFAULT_PATH) -> bool:
	if is_native():
		return _n().learn(adapter, measured_frame_ms, level, path)
	return LEGACY.learn(adapter, measured_frame_ms, level, path)


static func recommend_current() -> Dictionary:
	return _n().recommend_current() if is_native() else LEGACY.recommend_current()
