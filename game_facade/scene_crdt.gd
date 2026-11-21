extends RefCounted
## Facade over the scene CRDT. Prefers the native CgameSceneCRDT (modules/cgame_platform) and falls back to
## scripts/tools/scene_crdt.gd. Both objects have the same methods and the op_generated signal.

const LEGACY = preload("res://scripts/tools/scene_crdt.gd")
const NATIVE_CLASS := &"CgameSceneCRDT"


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## A new empty document owned by replica_id.
static func create(replica_id: String = "") -> Object:
	if is_native():
		var doc: Object = ClassDB.instantiate(NATIVE_CLASS)
		doc.replica = replica_id
		return doc
	return LEGACY.new(replica_id)


## A document filled from a nested {id?, type, name, props, children} dictionary.
static func from_packed_scene_dict(scene: Dictionary, replica_id: String = "local") -> Object:
	var doc: Object = create(replica_id)
	doc.load_scene_dict(scene)
	return doc
