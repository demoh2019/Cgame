extends RefCounted
## Procedural rig toolkit: two-bone IK, FABRIK + constraints, full-body IK, aim, retargeting.

const RigIK = preload("res://scripts/client/rig_ik.gd")
const RigRetarget = preload("res://scripts/client/rig_retarget.gd")

const MIXAMO := ["mixamorig:Hips", "mixamorig:Spine", "mixamorig:Spine1", "mixamorig:Neck", "mixamorig:Head",
	"mixamorig:LeftArm", "mixamorig:LeftForeArm", "mixamorig:LeftHand",
	"mixamorig:RightArm", "mixamorig:RightForeArm", "mixamorig:RightHand",
	"mixamorig:LeftUpLeg", "mixamorig:LeftLeg", "mixamorig:LeftFoot",
	"mixamorig:RightUpLeg", "mixamorig:RightLeg", "mixamorig:RightFoot"]
const UE := ["pelvis", "spine_01", "spine_02", "neck_01", "head",
	"upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]
const QUATERNIUS := ["Hips", "Abdomen", "Torso", "Neck", "Head",
	"UpperArm.L", "LowerArm.L", "Fist.L", "UpperArm.R", "LowerArm.R", "Fist.R",
	"UpperLeg.L", "LowerLeg.L", "Foot.L", "UpperLeg.R", "LowerLeg.R", "Foot.R"]
const PARENTS := [-1, 0, 1, 2, 3, 2, 5, 6, 2, 8, 9, 0, 11, 12, 0, 14, 15]


func _rest(scale_f: float) -> PackedVector3Array:
	var base := [Vector3(0, 1.0, 0), Vector3(0, 1.2, 0), Vector3(0, 1.5, 0), Vector3(0, 1.7, 0), Vector3(0, 1.85, 0),
		Vector3(0.15, 1.5, 0), Vector3(0.45, 1.5, 0), Vector3(0.7, 1.5, 0),
		Vector3(-0.15, 1.5, 0), Vector3(-0.45, 1.5, 0), Vector3(-0.7, 1.5, 0),
		Vector3(0.1, 1.0, 0), Vector3(0.1, 0.55, 0), Vector3(0.1, 0.1, 0),
		Vector3(-0.1, 1.0, 0), Vector3(-0.1, 0.55, 0), Vector3(-0.1, 0.1, 0)]
	var out := PackedVector3Array()
	for v in base:
		var bv: Vector3 = v
		out.append(bv * scale_f)
	return out


func _parents() -> PackedInt32Array:
	return PackedInt32Array(PARENTS)


func _rig(names: Array, scale_f: float) -> Dictionary:
	return {"names": PackedStringArray(names), "parents": _parents(), "rest": _rest(scale_f)}


func _lengths_ok(pos: PackedVector3Array, rest: PackedVector3Array, parents: PackedInt32Array) -> bool:
	for i in parents.size():
		if parents[i] < 0:
			continue
		var want := rest[i].distance_to(rest[parents[i]])
		if absf(pos[i].distance_to(pos[parents[i]]) - want) > 0.0005:
			return false
	return true


func run(t) -> void:
	t.current = "two-bone IK"
	var root := Vector3.ZERO
	var mid := Vector3(0.5, 0.2, 0)
	var tip := Vector3(1.0, 0, 0)
	var l1 := root.distance_to(mid)
	var l2 := mid.distance_to(tip)
	var goal := Vector3(0.6, 0.5, 0.3)
	var r := RigIK.two_bone(root, mid, tip, goal, Vector3(0, 0, 5))
	var m: Vector3 = r["mid"]
	var tp: Vector3 = r["tip"]
	t.check(r["reached"], "reachable target is flagged reached")
	t.near(tp.distance_to(goal), 0.0, 0.0001, "tip lands on a reachable target")
	t.near(root.distance_to(m), l1, 0.0001, "upper length preserved")
	t.near(m.distance_to(tp), l2, 0.0001, "lower length preserved")
	t.check(m.z > 0.0, "mid bends toward a +Z pole")
	var r2 := RigIK.two_bone(root, mid, tip, goal, Vector3(0, 0, -5))
	var m2: Vector3 = r2["mid"]
	t.check(m2.z < 0.0, "mid bends toward a -Z pole")
	var far := RigIK.two_bone(root, mid, tip, Vector3(0, 10, 0), Vector3(0, 0, 1))
	var ftip: Vector3 = far["tip"]
	var fmid: Vector3 = far["mid"]
	t.check(not far["reached"], "unreachable target flagged")
	t.near(ftip.distance_to(Vector3(0, l1 + l2, 0)), 0.0, 0.0001, "unreachable stretches straight at the target")
	t.near(fmid.cross(ftip).length(), 0.0, 0.0001, "stretched limb is collinear")

	t.current = "fabrik chain"
	var chain := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0), Vector3(4, 0, 0)])
	var want := Vector3(1.5, 2.0, 1.0)
	var solved := RigIK.fabrik_chain(chain, want, 32, 0.0005)
	t.check(solved[4].distance_to(want) < 0.001, "FABRIK converges to a reachable target")
	t.eq(solved[0], chain[0], "root stays fixed")
	var ok := true
	for i in 4:
		if absf(solved[i].distance_to(solved[i + 1]) - 1.0) > 0.0001:
			ok = false
	t.check(ok, "FABRIK preserves bone lengths")
	var stretched := RigIK.fabrik_chain(chain, Vector3(0, 20, 0), 16, 0.001)
	t.near(stretched[4].distance_to(Vector3(0, 4, 0)), 0.0, 0.001, "unreachable chain straightens toward the target")

	# Hinge: elbow-like joint bending only around Z within [0, 150 deg]; no bending backwards.
	var arm := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])
	var cons: Array = [{}, {"type": "hinge", "axis": Vector3(0, 0, 1), "min": 0.0, "max": deg_to_rad(150.0)}]
	var hinged := RigIK.fabrik_chain(arm, Vector3(1.2, -1.5, 0.8), 40, 0.001, cons)
	var b0 := (hinged[1] - hinged[0]).normalized()
	var b1 := (hinged[2] - hinged[1]).normalized()
	t.near(b1.z * b0.length(), b1.z, 0.0001, "hinge keeps unit direction")
	t.check(absf(b1.z) < 0.001, "hinge bone stays in the hinge plane (no twist around Z axis)")
	var b0p := Vector3(b0.x, b0.y, 0.0).normalized()
	var bend := b0p.signed_angle_to(b1, Vector3(0, 0, 1))
	t.check(bend >= -0.001 and bend <= deg_to_rad(150.0) + 0.001, "hinge angle within limits")
	var coned := RigIK.fabrik_chain(arm, Vector3(1.0, 1.9, 0), 40, 0.001, [{}, {"type": "cone", "angle": deg_to_rad(30.0)}])
	var c0 := (coned[1] - coned[0]).normalized()
	var c1 := (coned[2] - coned[1]).normalized()
	t.check(c0.angle_to(c1) <= deg_to_rad(30.0) + 0.001, "cone constraint respected")

	t.current = "full-body IK"
	var rest := _rest(1.0)
	var fb := RigIK.FullBodyIK.new()
	fb.setup(_parents(), rest)
	fb.root_pin = 0.0
	var tl := Vector3(0.4, 1.2, 1.0)
	var tr_ := Vector3(-0.4, 1.2, 0.9)
	var fl := Vector3(0.1, 0.1, 0.1)
	var fr := Vector3(-0.1, 0.1, -0.05)
	fb.set_effector(7, tl)
	fb.set_effector(10, tr_)
	fb.set_effector(13, fl)
	fb.set_effector(16, fr)
	var err := fb.solve(60, 0.002)
	t.check(err < 0.005, "all four effectors satisfied (err %.4f)" % err)
	for pair in [[7, tl], [10, tr_], [13, fl], [16, fr]]:
		var bi: int = pair[0]
		var bt: Vector3 = pair[1]
		t.check(fb.positions[bi].distance_to(bt) < 0.005, "effector bone %d on target" % bi)
	t.check(fb.positions[0].distance_to(rest[0]) > 0.01, "pelvis shifted toward the effectors")
	t.check(_lengths_ok(fb.positions, rest, _parents()), "full-body solve preserves every bone length")
	# Constrained knee (hinge about X) still solves a foot lift.
	var fb2 := RigIK.FullBodyIK.new()
	fb2.setup(_parents(), rest)
	fb2.set_constraint(12, {"type": "hinge", "axis": Vector3(1, 0, 0), "min": -deg_to_rad(150.0), "max": 0.0})
	fb2.set_effector(13, Vector3(0.1, 0.3, 0.2))
	fb2.set_effector(16, Vector3(-0.1, 0.1, 0.0))
	var e2 := fb2.solve(60, 0.002)
	t.check(e2 < 0.01, "constrained-knee lift converges (err %.4f)" % e2)

	t.current = "aim"
	var q := RigIK.aim(Vector3.ZERO, Vector3.FORWARD, Vector3(1, 0, 0), PI)
	t.near((q * Vector3.FORWARD).distance_to(Vector3(1, 0, 0)), 0.0, 0.0001, "unclamped aim points at target")
	var ql := RigIK.aim(Vector3.ZERO, Vector3.FORWARD, Vector3(1, 0, 0), deg_to_rad(30.0))
	t.near(ql.get_angle(), deg_to_rad(30.0), 0.0001, "aim clamped to max angle")
	t.near((ql * Vector3.FORWARD).angle_to(Vector3.FORWARD), deg_to_rad(30.0), 0.0001, "clamped aim rotates exactly the limit")
	var qb := RigIK.aim(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, 5), PI)
	t.near((qb * Vector3.FORWARD).distance_to(Vector3.BACK), 0.0, 0.0001, "aim handles a target directly behind")
	t.eq(RigIK.aim(Vector3.ONE, Vector3.FORWARD, Vector3.ONE, PI), Quaternion.IDENTITY, "aim at own position is identity")

	t.current = "name map"
	var mix: PackedStringArray = PackedStringArray(MIXAMO)
	var ue: PackedStringArray = PackedStringArray(UE)
	var qua: PackedStringArray = PackedStringArray(QUATERNIUS)
	var map := RigRetarget.build_map(mix, ue)
	t.eq(map.size(), 17, "Mixamo -> UE maps all 17 bones")
	var good := true
	for i in 17:
		if map.get(i, -1) != i:
			good = false
	t.check(good, "Mixamo -> UE maps each bone to its counterpart (sides kept)")
	var map_q := RigRetarget.build_map(qua, mix)
	t.eq(map_q.size(), 17, "Quaternius -> Mixamo maps all 17 bones")
	t.eq(map_q.get(13, -1), 13, "Foot.L -> LeftFoot")
	t.eq(map_q.get(10, -1), 10, "Fist.R -> RightHand")
	t.eq(RigRetarget.canonical("mixamorig:LeftUpLeg"), "upperleg|l", "canonical Mixamo thigh")
	t.eq(RigRetarget.canonical("calf_r"), "lowerleg|r", "canonical UE calf")
	var custom := RigRetarget.build_map(PackedStringArray(["Weird_A"]), PackedStringArray(["hand_l"]), {"Weird_A": "hand|l"})
	t.eq(custom.get(0, -1), 0, "custom alias honoured")

	t.current = "retarget"
	var src_rig := _rig(MIXAMO, 1.0)
	var dst_rig := _rig(UE, 1.3)
	var rots: Array = []
	for i in 17:
		rots.append(Quaternion.IDENTITY)
	rots[6] = Quaternion(Vector3(0, 0, 1), 0.7)
	rots[12] = Quaternion(Vector3(1, 0, 0), -0.4)
	rots[13] = Quaternion(Vector3(1, 0, 0), 0.2)
	var src_pose := {"rot": rots, "hips": Vector3(0.2, 0.9, 0.5)}
	var out := RigRetarget.retarget_pose(src_rig, src_pose, dst_rig, map)
	var out_rot: Array = out["rot"]
	var ratio: float = out["ratio"]
	var qa: Quaternion = out_rot[6]
	var qb2: Quaternion = out_rot[12]
	t.near(ratio, 1.3, 0.0001, "ratio equals leg-length ratio")
	t.near(qa.angle_to(rots[6]), 0.0, 0.0001, "elbow rotation transferred")
	t.near(qb2.angle_to(rots[12]), 0.0, 0.0001, "knee rotation transferred")
	var hips_out: Vector3 = out["hips"]
	t.near(hips_out.distance_to(Vector3(0.26, 1.3 - 0.13, 0.65)), 0.0, 0.0001, "root translation scaled by leg ratio")

	t.current = "foot contact"
	var src_fk := RigRetarget.fk(src_rig, rots, 0, src_pose["hips"])
	var src_pos: PackedVector3Array = src_fk["pos"]
	# Planted source feet scaled to the larger target; push the left foot ahead as a stride.
	var goals := {13: src_pos[13] * ratio + Vector3(0, 0, 0.1), 16: src_pos[16] * ratio}
	var fixed := RigRetarget.ik_correct_feet(dst_rig, out, goals)
	t.check(float(fixed["error"]) < 0.002, "feet land on the source contact positions (err %.4f)" % float(fixed["error"]))
	var fpos: PackedVector3Array = fixed["pos"]
	t.near(fpos[13].distance_to(goals[13]), 0.0, 0.002, "left foot contact kept")
	t.near(fpos[16].distance_to(goals[16]), 0.0, 0.002, "right foot contact kept")
	t.near(fpos[12].distance_to(fpos[11]), dst_rig["rest"][12].distance_to(dst_rig["rest"][11]), 0.0005, "shin length preserved after correction")
	t.near(fpos[13].distance_to(fpos[12]), dst_rig["rest"][13].distance_to(dst_rig["rest"][12]), 0.0005, "thigh/foot length preserved after correction")
