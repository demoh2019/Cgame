extends SkeletonModifier3D
## Procedural layer applied after the AnimationPlayer (Unity Animation Rigging / Unreal Control Rig equivalent):
## breathing, lean into turns, additive flinch, head look-at, pelvis drop and two-bone foot IK on slopes.
## Idempotent: bones it touched are restored before the next pass, so skipped frames never accumulate.

const Anim = preload("res://scripts/client/character_anim.gd")

var body: Node3D # Frame of reference: +Z forward, +Y up.
var ground_fn: Callable # (x, z) -> world ground height; invalid disables foot IK.
var look_point := Vector3.INF # World point to look at; INF = none.
var yaw_rate := 0.0
var move_speed := 0.0
var foot_ik := true
var look_at_enabled := true

var _bones: Dictionary = {} # lower-case name -> index
var _resolved := false
var _touched: Dictionary = {} # bone -> [pre local pose, post local pose]
var _t := 0.0
var _lean := Vector2.ZERO
var _look := Vector2.ZERO
var _pelvis := 0.0
var _foot := [0.0, 0.0]
var _ankle := 0.08
var _flinch := Vector2.ZERO # x pitch, y roll
var _flinch_v := Vector2.ZERO


## Additive hit reaction; `strength` ~0.5 light, ~1 heavy. `local_dir` in body space (from the attacker).
func kick(local_dir: Vector3, strength: float) -> void:
	var d := Vector3(local_dir.x, 0.0, local_dir.z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.BACK
	_flinch_v += Vector2(-d.z, d.x) * 7.0 * strength


func bone(name: String) -> int:
	return int(_bones.get(name, -1))


func is_resolved() -> bool:
	return _resolved


func _resolve(skeleton: Skeleton3D) -> void:
	_bones.clear()
	for i in skeleton.get_bone_count():
		_bones[skeleton.get_bone_name(i).to_lower()] = i
	_resolved = true
	var foot := bone("foot_l")
	if foot >= 0:
		_ankle = maxf(skeleton.get_bone_global_rest(foot).origin.y * skeleton.global_transform.basis.get_scale().y, 0.02)


func _restore(skeleton: Skeleton3D) -> void:
	for idx in _touched:
		var pair: Array = _touched[idx]
		if skeleton.get_bone_pose(idx).is_equal_approx(pair[1]):
			skeleton.set_bone_pose(idx, pair[0])
	_touched.clear()


func _set_global(skeleton: Skeleton3D, idx: int, pose: Transform3D) -> void:
	if not _touched.has(idx):
		_touched[idx] = [skeleton.get_bone_pose(idx), Transform3D()]
	skeleton.set_bone_global_pose(idx, pose)
	(_touched[idx] as Array)[1] = skeleton.get_bone_pose(idx)


## Rotates a bone around its own origin by a world-space rotation.
func _rotate_world(skeleton: Skeleton3D, idx: int, rotation: Quaternion) -> void:
	if idx < 0:
		return
	var sk := Quaternion(skeleton.global_transform.basis.orthonormalized())
	var in_skeleton := sk.inverse() * rotation * sk
	var pose := skeleton.get_bone_global_pose(idx)
	pose.basis = Basis(in_skeleton) * pose.basis
	_set_global(skeleton, idx, pose)


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or body == null or not body.is_inside_tree():
		return
	_restore(skeleton)
	if not _resolved:
		_resolve(skeleton)
	_t += delta
	var basis := body.global_transform.basis
	var moving := clampf(move_speed / 1.0, 0.0, 1.0)

	# Spine: lean + breathing + flinch spread over the chain.
	var lean_target := Anim.lean_angles(yaw_rate, move_speed)
	_lean.x = Anim.smooth(_lean.x, lean_target.x, delta, 6.0)
	_lean.y = Anim.smooth(_lean.y, lean_target.y, delta, 4.0)
	var spring_p := Anim.spring_step(_flinch.x, _flinch_v.x, 0.0, 160.0, 14.0, delta)
	var spring_r := Anim.spring_step(_flinch.y, _flinch_v.y, 0.0, 160.0, 14.0, delta)
	_flinch = Vector2(spring_p[0], spring_r[0])
	_flinch_v = Vector2(spring_p[1], spring_r[1])
	var breath := Anim.breath_angle(_t, moving)
	var spine_weights := {"spine_01": 0.3, "spine_02": 0.3, "spine_03": 0.4}
	for name in spine_weights:
		var w: float = spine_weights[name]
		var pitch := (_lean.y + _flinch.x) * w + (breath if name == "spine_03" else 0.0)
		var roll := (_lean.x + _flinch.y) * w
		if absf(pitch) + absf(roll) > 0.0001:
			_rotate_world(skeleton, bone(name), Anim.lean_rotation(basis, roll, pitch))

	if foot_ik and ground_fn.is_valid():
		_foot_ik(skeleton, delta)

	# Head look-at, last so it sees the final spine pose.
	var look_target := Vector2.ZERO
	if look_at_enabled and look_point != Vector3.INF:
		var head := bone("head")
		if head >= 0:
			var head_world := skeleton.global_transform * skeleton.get_bone_global_pose(head).origin
			look_target = Anim.look_angles(basis, look_point - head_world, 1.05, 0.5)
	_look = Vector2(Anim.smooth(_look.x, look_target.x, delta, 5.0), Anim.smooth(_look.y, look_target.y, delta, 5.0))
	if _look.length() > 0.002:
		_rotate_world(skeleton, bone("neck_01"), Anim.look_rotation(basis, _look * 0.4))
		_rotate_world(skeleton, bone("head"), Anim.look_rotation(basis, _look * 0.6))


func _foot_ik(skeleton: Skeleton3D, delta: float) -> void:
	var thigh := [bone("thigh_l"), bone("thigh_r")]
	var calf := [bone("calf_l"), bone("calf_r")]
	var foot := [bone("foot_l"), bone("foot_r")]
	for i in 2:
		if thigh[i] < 0 or calf[i] < 0 or foot[i] < 0:
			return
	var to_world := skeleton.global_transform
	var root_y := body.global_position.y
	var base := float(ground_fn.call(body.global_position.x, body.global_position.z))
	var want := [0.0, 0.0]
	var tilt: Array[Quaternion] = []
	var foot_world: Array[Vector3] = []
	for i in 2:
		var fw: Vector3 = to_world * skeleton.get_bone_global_pose(foot[i]).origin
		foot_world.append(fw)
		var ground := float(ground_fn.call(fw.x, fw.z)) - base
		var planted := Anim.contact_weight(maxf(fw.y - root_y - _ankle, 0.0))
		want[i] = ground * planted
		var h0 := float(ground_fn.call(fw.x, fw.z))
		var normal := Anim.ground_normal(h0, float(ground_fn.call(fw.x + 0.2, fw.z)), float(ground_fn.call(fw.x, fw.z + 0.2)), 0.2)
		tilt.append(Quaternion(Vector3.UP, normal).slerp(Quaternion.IDENTITY, 1.0 - planted))
	var pelvis_target := Anim.pelvis_offset(want[0], want[1])
	_pelvis = Anim.smooth(_pelvis, pelvis_target, delta, 10.0)
	for i in 2:
		_foot[i] = Anim.smooth(_foot[i], want[i], delta, 14.0)
	var inverse := to_world.basis.inverse()
	var pelvis_idx := bone("pelvis")
	if pelvis_idx >= 0 and absf(_pelvis) > 0.0005:
		var pose := skeleton.get_bone_global_pose(pelvis_idx)
		pose.origin += inverse * Vector3(0.0, _pelvis, 0.0)
		_set_global(skeleton, pelvis_idx, pose)
	for i in 2:
		var lift: float = _foot[i]
		if absf(lift) < 0.002 and absf(_pelvis) < 0.002:
			continue
		var a := skeleton.get_bone_global_pose(thigh[i]).origin
		var b := skeleton.get_bone_global_pose(calf[i]).origin
		var foot_pose := skeleton.get_bone_global_pose(foot[i])
		var c := foot_pose.origin
		var target_world: Vector3 = foot_world[i] + Vector3(0.0, lift, 0.0)
		var target := to_world.affine_inverse() * target_world
		var solved := Anim.solve_knee(a, b, c, target)
		var thigh_pose := skeleton.get_bone_global_pose(thigh[i])
		thigh_pose.basis = Basis(Quaternion((b - a).normalized(), (solved[0] - a).normalized())) * thigh_pose.basis
		_set_global(skeleton, thigh[i], thigh_pose)
		var knee: Vector3 = skeleton.get_bone_global_pose(calf[i]).origin
		var ankle: Vector3 = skeleton.get_bone_global_pose(foot[i]).origin
		var calf_pose := skeleton.get_bone_global_pose(calf[i])
		calf_pose.basis = Basis(Quaternion((ankle - knee).normalized(), (solved[1] - knee).normalized())) * calf_pose.basis
		_set_global(skeleton, calf[i], calf_pose)
		# Keep the animated foot orientation (sole stays level with the animation).
		var fixed := skeleton.get_bone_global_pose(foot[i])
		var sk_q := Quaternion(to_world.basis.orthonormalized())
		fixed.basis = Basis(sk_q.inverse() * tilt[i] * sk_q) * foot_pose.basis
		_set_global(skeleton, foot[i], fixed)


## Undoes every pose change made so far (used when the character drops to a cheap LOD tier or starts a ragdoll).
func reset() -> void:
	var skeleton := get_skeleton()
	if skeleton != null:
		_restore(skeleton)
	_pelvis = 0.0
	_foot = [0.0, 0.0]
	_look = Vector2.ZERO
