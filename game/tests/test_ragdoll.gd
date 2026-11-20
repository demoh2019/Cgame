extends RefCounted
## Runtime ragdoll generation for infected deaths (no packs or network needed).

const Ragdoll = preload("res://scripts/client/ragdoll.gd")


static func _mannequin() -> Skeleton3D:
	var s := Skeleton3D.new()
	var chain := [["pelvis", -1, Vector3(0, 1.0, 0)], ["spine_01", 0, Vector3(0, 0.15, 0)],
		["spine_03", 1, Vector3(0, 0.3, 0)], ["neck_01", 2, Vector3(0, 0.25, 0)], ["head", 3, Vector3(0, 0.1, 0)],
		["upperarm_l", 2, Vector3(0.2, 0.2, 0)], ["lowerarm_l", 5, Vector3(0, -0.3, 0)], ["hand_l", 6, Vector3(0, -0.25, 0)],
		["thigh_l", 0, Vector3(0.1, -0.05, 0)], ["calf_l", 8, Vector3(0, -0.45, 0)], ["foot_l", 9, Vector3(0, -0.42, 0)]]
	for b in chain:
		var i := s.add_bone(b[0])
		s.set_bone_parent(i, b[1])
		s.set_bone_rest(i, Transform3D(Basis(), b[2]))
	return s


func run(t) -> void:
	t.current = "ragdoll budgets"
	t.eq(Ragdoll.budget(0), 0, "Low quality keeps instant despawn")
	t.check(Ragdoll.budget(3) > Ragdoll.budget(1), "budget grows with quality")
	t.eq(Ragdoll.budget(-5), 0, "tier clamped low")

	t.current = "ragdoll bodies from mannequin bones"
	var s := _mannequin()
	t.eq(Ragdoll.present_bones(s).size(), 8, "only bones the rig has")
	t.near(Ragdoll.segment(s, "thigh_l").length(), 0.45, 0.001, "thigh capsule spans to the calf")
	var sim := Ragdoll.build(s)
	t.check(sim != null, "simulator built")
	t.eq(sim.get_child_count(), 8, "one body per present bone")
	var pelvis := sim.get_node("Ragdoll_pelvis") as PhysicalBone3D
	t.eq(pelvis.joint_type, PhysicalBone3D.JOINT_TYPE_NONE, "pelvis is the free root")
	t.eq((sim.get_node("Ragdoll_calf_l") as PhysicalBone3D).joint_type, PhysicalBone3D.JOINT_TYPE_HINGE, "knee hinges")
	t.eq(pelvis.collision_layer, Ragdoll.LAYER, "own collision layer")
	var bare := Skeleton3D.new()
	bare.add_bone("Root")
	t.check(Ragdoll.build(bare) == null, "non-mannequin rig falls back to despawn")
	s.free()
	bare.free()

	t.current = "ground patch"
	var slope := func(x: float, z: float) -> float: return x * 0.5
	var data := Ragdoll.patch_heights(10.0, 0.0, 5.0, slope)
	t.eq(data.size(), Ragdoll.PATCH * Ragdoll.PATCH, "full grid")
	t.near(data[(Ragdoll.PATCH * Ragdoll.PATCH) / 2], 0.0, 0.001, "centre at corpse height")
	t.near(data[0], -2.0, 0.001, "slope sampled 4 m to the side")
	var ground := Ragdoll.ground_patch(10.0, 5.0, 0.0, slope)
	t.eq(ground.collision_layer, Ragdoll.LAYER, "ground only on ragdoll layer")
	ground.free()
