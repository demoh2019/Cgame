extends RefCounted
## Facade over the GPU compatibility matrix. Prefers the native CgameGPUMatrixDB (modules/cgame_platform) and
## falls back to scripts/tools/gpu_matrix_db.gd. Both objects have add_report, ingest_file, ingest_dir,
## set_reference, build, cells, driver_failures, regressions, learned_data, write_learned, to_csv, to_markdown and the
## tolerance / target_ms properties.

const LEGACY = preload("res://scripts/tools/gpu_matrix_db.gd")
const NATIVE_CLASS := &"CgameGPUMatrixDB"

static var _native_instance: Object = null


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


static func _n() -> Object:
	if _native_instance == null:
		_native_instance = ClassDB.instantiate(NATIVE_CLASS)
	return _native_instance


static func create() -> Object:
	return ClassDB.instantiate(NATIVE_CLASS) if is_native() else LEGACY.new()


static func validate_report(rep: Variant) -> Array:
	if is_native():
		return Array(_n().validate_report(rep))
	return LEGACY.validate_report(rep)


static func dhash(img: Image) -> String:
	return _n().dhash(img) if is_native() else LEGACY.dhash(img)


static func hash_distance(a: String, b: String) -> int:
	return _n().hash_distance(a, b) if is_native() else LEGACY.hash_distance(a, b)
