class_name CgameNetcodeFacade
extends RefCounted
## Facade over the native netcode classes (CgameBitWriter, CgameNetSchema,
## CgameReplicationGraph, CgameSnapshotDelta). When the engine was built with the
## `cgame_netcode` module the native classes are used; otherwise the GDScript reference
## implementations in res://scripts/shared/ are used so gameplay code has one API.

const SCHEMA_SCRIPT := "res://scripts/shared/net_schema.gd"
const DELTA_SCRIPT := "res://scripts/shared/snapshot_delta.gd"
const GRAPH_SCRIPT := "res://scripts/shared/replication_graph.gd"


static func has_native() -> bool:
	return ClassDB.class_exists("CgameNetSchema") \
		and ClassDB.class_exists("CgameReplicationGraph") \
		and ClassDB.class_exists("CgameSnapshotDelta") \
		and ClassDB.class_exists("CgameBitWriter")


## Schema wrapper with the same surface as CgameNetSchema.
class SchemaWrapper extends RefCounted:
	var _script: GDScript
	var _schema: Dictionary = {}

	func _init(script: GDScript, schema: Dictionary) -> void:
		_script = script
		_schema = schema

	func get_schema() -> Dictionary:
		return _schema

	func get_field_count() -> int:
		return (_schema["fields"] as Array).size()

	func get_schema_hash() -> int:
		return _script.schema_hash(_schema)

	func serialize(state: Dictionary, baseline: Dictionary, is_owner: bool) -> PackedByteArray:
		return _script.serialize(_schema, state, baseline, is_owner)

	func deserialize(bytes: PackedByteArray, baseline: Dictionary) -> Dictionary:
		return _script.deserialize(_schema, bytes, baseline)

	func serialize_versioned(state: Dictionary, baseline: Dictionary, is_owner: bool) -> PackedByteArray:
		return _script.serialize_versioned(_schema, state, baseline, is_owner)

	func deserialize_versioned(bytes: PackedByteArray, baseline: Dictionary) -> Dictionary:
		return _script.deserialize_versioned(_schema, bytes, baseline)


## Builds a schema object from {"fields": [...]} (see CgameNetSchema). Returns null if invalid.
static func make_schema(schema: Dictionary) -> Object:
	if has_native():
		var native: RefCounted = ClassDB.instantiate("CgameNetSchema")
		if not native.set_schema(schema):
			return null
		return native
	if not schema.has("fields"):
		return null
	return SchemaWrapper.new(load(SCHEMA_SCRIPT), schema)


static func make_field(field_name: String, type: String, bits: int = 0, min_v: float = 0.0, max_v: float = 0.0, condition: String = "on_change") -> Dictionary:
	if has_native():
		return ClassDB.class_call_static("CgameNetSchema", "make_field", field_name, type, bits, min_v, max_v, condition)
	return load(SCHEMA_SCRIPT).make_field(field_name, type, bits, min_v, max_v, condition)


## Replication graph. The GDScript and native classes share method names
## (set_class_config, add_entity, set_position, set_dormant, wake, advance, gather_for, ...).
static func make_replication_graph(cell_size: float = 64.0) -> Object:
	var graph: Object
	if has_native():
		graph = ClassDB.instantiate("CgameReplicationGraph")
	else:
		graph = load(GRAPH_SCRIPT).new()
	graph.cell_size = cell_size
	return graph


static func delta_diff(baseline: Dictionary, current: Dictionary, tolerances: Dictionary = {}) -> Dictionary:
	if has_native():
		return ClassDB.class_call_static("CgameSnapshotDelta", "diff", baseline, current, tolerances)
	return load(DELTA_SCRIPT).diff(baseline, current, tolerances)


static func delta_apply(baseline: Dictionary, delta: Dictionary) -> Dictionary:
	if has_native():
		return ClassDB.class_call_static("CgameSnapshotDelta", "apply", baseline, delta)
	return load(DELTA_SCRIPT).apply(baseline, delta)


## Bit writer/reader exist only natively (the GDScript BitWriter lives inside net_schema.gd
## and has a different API); returns null when the module is unavailable.
static func make_bit_writer() -> RefCounted:
	if ClassDB.class_exists("CgameBitWriter"):
		return ClassDB.instantiate("CgameBitWriter")
	return null


static func make_bit_reader(bytes: PackedByteArray) -> RefCounted:
	if ClassDB.class_exists("CgameBitReader"):
		var r: RefCounted = ClassDB.instantiate("CgameBitReader")
		r.set_bytes(bytes)
		return r
	return null
