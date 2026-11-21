class_name CgameRigFacade
extends RefCounted
## IK helpers, retargeting and skeleton modifiers. Native classes when available, `rig_ik.gd` and
## `rig_retarget.gd` otherwise.


static func two_bone(root: Vector3, mid: Vector3, tip: Vector3, target: Vector3, pole: Vector3) -> Dictionary:
	return CgameAnimNative.call_static(&"CgameRigIK", "rig_ik.gd", &"two_bone", [root, mid, tip, target, pole])


static func fabrik_chain(positions: PackedVector3Array, target: Vector3, iterations: int = 16, tolerance: float = 0.001, constraints: Array = []) -> PackedVector3Array:
	return CgameAnimNative.call_static(&"CgameRigIK", "rig_ik.gd", &"fabrik_chain", [positions, target, iterations, tolerance, constraints])


static func aim(bone_position: Vector3, forward: Vector3, target: Vector3, max_angle: float = PI) -> Quaternion:
	return CgameAnimNative.call_static(&"CgameRigIK", "rig_ik.gd", &"aim", [bone_position, forward, target, max_angle])


static func canonical_bone(bone_name: String, aliases: Dictionary = {}) -> String:
	return CgameAnimNative.call_static(&"CgameRetargeter", "rig_retarget.gd", &"canonical", [bone_name, aliases])


static func build_bone_map(source_names: PackedStringArray, target_names: PackedStringArray, aliases: Dictionary = {}) -> Dictionary:
	return CgameAnimNative.call_static(&"CgameRetargeter", "rig_retarget.gd", &"build_map", [source_names, target_names, aliases])


## Copies the current pose of `source` to `target`. Native only; returns the transferred bone count, or -1.
static func transfer_pose(source: Skeleton3D, target: Skeleton3D, map: Dictionary = {}, scale_hips: bool = true) -> int:
	if not CgameAnimNative.has_native(&"CgameRetargeter"):
		return -1
	var bone_map: Dictionary = map
	if bone_map.is_empty():
		bone_map = CgameAnimNative.call_static(&"CgameRetargeter", "", &"build_skeleton_map", [source, target])
	return CgameAnimNative.call_static(&"CgameRetargeter", "", &"transfer_pose", [source, target, bone_map, scale_hips])


## SkeletonModifier3D nodes (native only, null otherwise). Add the result as a child of the Skeleton3D.
static func create_foot_lock_modifier() -> SkeletonModifier3D:
	return _make_modifier(&"FootLockModifier3D")


static func create_full_body_ik_modifier() -> SkeletonModifier3D:
	return _make_modifier(&"FullBodyIKModifier3D")


static func create_aim_modifier() -> SkeletonModifier3D:
	return _make_modifier(&"CgameAimModifier3D")


static func create_constraint_graph_modifier() -> SkeletonModifier3D:
	return _make_modifier(&"ConstraintGraphModifier3D")


## Script fallback for foot locking: the pure-math RefCounted from foot_locking.gd (or null).
static func create_foot_lock_solver() -> Variant:
	var path := CgameAnimNative.SCRIPT_DIR + "foot_locking.gd"
	if ResourceLoader.exists(path):
		var script: GDScript = load(path)
		return script.new()
	return null


static func _make_modifier(native_class: StringName) -> SkeletonModifier3D:
	if not CgameAnimNative.has_native(native_class):
		return null
	return ClassDB.instantiate(native_class)
