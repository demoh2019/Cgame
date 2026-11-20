extends RefCounted
## Runtime ragdolls for dead infected — the equivalent of Unity ragdoll joints /
## Unreal Physics Asset death simulation, built from the engine's
## PhysicalBoneSimulator3D. Bodies are generated at runtime from whichever
## mannequin bones the model has, collide only with a small heightmap patch of
## the terrain under the corpse (own collision layer), and are capped per tier.

const LAYER := 1 << 19
const BUDGET := [0, 3, 6, 12] # Low, Medium, High, Ultra.
const SETTLE_SECONDS := 5.0
const SINK_SECONDS := 1.5
const PATCH := 9 # Heightmap samples per side, 1 m apart.

## bone -> [tip bone, radius in metres before model scale, joint type, swing/hinge span degrees]
const BONES := {
	"pelvis": ["spine_01", 0.14, PhysicalBone3D.JOINT_TYPE_NONE, 0.0],
	"spine_01": ["spine_03", 0.13, PhysicalBone3D.JOINT_TYPE_CONE, 25.0],
	"spine_03": ["neck_01", 0.15, PhysicalBone3D.JOINT_TYPE_CONE, 25.0],
	"head": ["", 0.12, PhysicalBone3D.JOINT_TYPE_CONE, 35.0],
	"upperarm_l": ["lowerarm_l", 0.06, PhysicalBone3D.JOINT_TYPE_CONE, 70.0],
	"upperarm_r": ["lowerarm_r", 0.06, PhysicalBone3D.JOINT_TYPE_CONE, 70.0],
	"lowerarm_l": ["hand_l", 0.05, PhysicalBone3D.JOINT_TYPE_HINGE, 120.0],
	"lowerarm_r": ["hand_r", 0.05, PhysicalBone3D.JOINT_TYPE_HINGE, 120.0],
	"thigh_l": ["calf_l", 0.08, PhysicalBone3D.JOINT_TYPE_CONE, 50.0],
	"thigh_r": ["calf_r", 0.08, PhysicalBone3D.JOINT_TYPE_CONE, 50.0],
	"calf_l": ["foot_l", 0.06, PhysicalBone3D.JOINT_TYPE_HINGE, 120.0],
	"calf_r": ["foot_r", 0.06, PhysicalBone3D.JOINT_TYPE_HINGE, 120.0],
}


static func budget(level: int) -> int:
	return BUDGET[clampi(level, 0, BUDGET.size() - 1)]


## Which ragdoll bones this skeleton actually has (models without a mannequin rig get none).
static func present_bones(skeleton: Skeleton3D) -> Array[String]:
	var found: Array[String] = []
	for bone in BONES:
		if skeleton.find_bone(bone) >= 0:
			found.append(bone)
	return found


## Capsule length/orientation between a bone and its tip in the bone's rest space.
static func segment(skeleton: Skeleton3D, bone: String) -> Vector3:
	var tip: String = BONES[bone][0]
	var tip_index := skeleton.find_bone(tip) if tip != "" else -1
	if tip_index < 0:
		return Vector3(0.0, 0.2, 0.0)
	var from := skeleton.get_bone_global_rest(skeleton.find_bone(bone)).origin
	var to := skeleton.get_bone_global_rest(tip_index).origin
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone)).basis.inverse() * (to - from)


## Heights (relative to `center_y`) for a PATCH×PATCH grid around (x, z).
static func patch_heights(x: float, z: float, center_y: float, height_at: Callable) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	var half := (PATCH - 1) / 2
	for j in PATCH:
		for i in PATCH:
			data.append(float(height_at.call(x + i - half, z + j - half)) - center_y)
	return data


## Builds bodies on the skeleton and a ground patch next to it; returns the simulator or null.
static func build(skeleton: Skeleton3D) -> PhysicalBoneSimulator3D:
	var bones := present_bones(skeleton)
	if not bones.has("pelvis") or bones.size() < 4:
		return null
	var simulator := PhysicalBoneSimulator3D.new()
	skeleton.add_child(simulator)
	for bone in bones:
		var spec: Array = BONES[bone]
		var body := PhysicalBone3D.new()
		body.name = "Ragdoll_" + bone
		body.bone_name = bone
		body.collision_layer = LAYER
		body.collision_mask = LAYER
		body.mass = 6.0 if bone in ["pelvis", "spine_01", "spine_03"] else 2.0
		body.linear_damp = 0.4
		body.angular_damp = 2.0
		body.joint_type = spec[2]
		if spec[2] == PhysicalBone3D.JOINT_TYPE_CONE:
			body.set("joint_constraints/swing_span", spec[3])
			body.set("joint_constraints/twist_span", spec[3] * 0.5)
		elif spec[2] == PhysicalBone3D.JOINT_TYPE_HINGE:
			body.set("joint_constraints/angular_limit_enabled", true)
			body.set("joint_constraints/angular_limit_upper", spec[3])
			body.set("joint_constraints/angular_limit_lower", 0.0)
		var v := segment(skeleton, bone)
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = spec[1]
		capsule.height = maxf(v.length(), spec[1] * 2.0 + 0.01)
		shape.shape = capsule
		shape.position = v * 0.5
		if v.length() > 0.001:
			shape.basis = Basis(Quaternion(Vector3.UP, v.normalized()))
		body.add_child(shape)
		simulator.add_child(body)
	return simulator


## A heightmap collider for the terrain under the corpse, on the ragdoll layer only.
static func ground_patch(x: float, ground_y: float, z: float, height_at: Callable) -> StaticBody3D:
	var ground := StaticBody3D.new()
	ground.name = "RagdollGround"
	ground.collision_layer = LAYER
	ground.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = PATCH
	shape.map_depth = PATCH
	shape.map_data = patch_heights(x, z, ground_y, height_at)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	ground.add_child(collider)
	ground.position = Vector3(x, ground_y, z)
	return ground
