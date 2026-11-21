@tool
extends RefCounted
## Facade for the EQS-style spatial query graph: create() returns a native
## CgameSpatialQuery when the engine module is available and a GDScript
## spatial_query_graph.gd instance otherwise. The static asset helpers
## (new_asset, make_generator, make_test, add_generator, add_test, validate)
## are forwarded to the same implementation. Result entries share the
## position / index / score keys with EnvironmentQuery3D.
##
## Differences of the native class: debug() and results() are identical in shape;
## validate() returns a PackedStringArray; results() is an untyped Array;
## get_candidates() (native only) exports the generated positions.

const Fallback = preload("res://scripts/shared/spatial_query_graph.gd")
const NATIVE_CLASS := &"CgameSpatialQuery"

static var _native: RefCounted = null


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


static func _impl() -> RefCounted:
	if _native == null:
		_native = ClassDB.instantiate(NATIVE_CLASS)
	return _native


static func create() -> RefCounted:
	if is_native():
		return ClassDB.instantiate(NATIVE_CLASS)
	return Fallback.new()


static func new_asset(asset_name: String = "query") -> Dictionary:
	if is_native():
		return _impl().new_asset(asset_name)
	return Fallback.new_asset(asset_name)


static func make_generator(type: String, params: Dictionary = {}) -> Dictionary:
	if is_native():
		return _impl().make_generator(type, params)
	return Fallback.make_generator(type, params)


static func make_test(type: String, params: Dictionary = {}) -> Dictionary:
	if is_native():
		return _impl().make_test(type, params)
	return Fallback.make_test(type, params)


static func add_generator(asset: Dictionary, gen: Dictionary) -> int:
	if is_native():
		return _impl().add_generator(asset, gen)
	return Fallback.add_generator(asset, gen)


static func add_test(asset: Dictionary, test: Dictionary) -> int:
	if is_native():
		return _impl().add_test(asset, test)
	return Fallback.add_test(asset, test)


static func validate(asset: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if is_native():
		out = _impl().validate(asset)
	else:
		out.append_array(Fallback.validate(asset))
	return out
