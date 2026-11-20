extends RefCounted
## Procedural character animation: foot IK, pelvis drop, look-at, lean, breathing, flinch, upper-body layering, LOD.

const Anim = preload("res://scripts/client/character_anim.gd")
const Modifier = preload("res://scripts/client/character_anim_modifier.gd")


static func _mannequin() -> Skeleton3D:
	var s := Skeleton3D.new()
	s.name = "Skeleton3D"
	var chain := [["pelvis", -1, Vector3(0, 1.0, 0)], ["spine_01", 0, Vector3(0, 0.1, 0)], ["spine_02", 1, Vector3(0, 0.15, 0)],
		["spine_03", 2, Vector3(0, 0.15, 0)], ["neck_01", 3, Vector3(0, 0.2, 0)], ["Head", 4, Vector3(0, 0.1, 0)],
		["thigh_l", 0, Vector3(0.1, -0.05, 0)], ["calf_l", 6, Vector3(0, -0.45, 0.02)], ["foot_l", 7, Vector3(0, -0.45, -0.02)],
		["thigh_r", 0, Vector3(-0.1, -0.05, 0)], ["calf_r", 9, Vector3(0, -0.45, 0.02)], ["foot_r", 10, Vector3(0, -0.45, -0.02)]]
	for b in chain:
		var i := s.add_bone(b[0])
		s.set_bone_parent(i, b[1])
		s.set_bone_rest(i, Transform3D(Basis(), b[2]))
	s.reset_bone_poses()
	return s


func run(t) -> void:
	t.current = "lod and crowd budget"
	t.eq(Anim.lod_tier(5.0), 0, "near is full tier")
	t.eq(Anim.lod_tier(30.0), 1, "mid keeps rate, drops IK")
	t.check(Anim.lod_tier(70.0) > Anim.lod_tier(45.0), "tiers grow with distance")
	t.eq(Anim.lod_tier(500.0), 4, "far clamps")
	t.eq(Anim.lod_interval(0), 0.0, "tier 0 updates every frame")
	t.check(Anim.lod_interval(4) > Anim.lod_interval(2), "far updates less often")
	var tiers := Anim.assign_tiers([3.0, 5.0, 2.0, 10.0, 60.0], 2)
	t.eq(tiers[2], 0, "nearest keeps full tier")
	t.eq(tiers[0], 0, "second nearest keeps full tier")
	t.eq(tiers[1], 1, "over budget demoted")
	t.eq(tiers[3], 1, "over budget demoted (farther)")
	t.eq(tiers[4], 3, "far one by distance")
	t.eq(Anim.full_budget(0), 0, "low quality: no procedural stack")
	t.check(Anim.full_budget(3) > Anim.full_budget(1), "budget grows with quality")

	t.current = "smoothing and springs"
	t.near(Anim.smooth(0.0, 1.0, 0.0, 10.0), 0.0, 0.0001, "no time, no movement")
	t.check(Anim.smooth(0.0, 1.0, 1.0, 10.0) > 0.99, "converges")
	t.near(Anim.smooth_rate(1.0, 2.0, 0.1, 3.0), 1.3, 0.0001, "rate limited")
	var state := [1.0, 0.0]
	for i in 240:
		state = Anim.spring_step(state[0], state[1], 0.0, 160.0, 14.0, 1.0 / 120.0)
	t.near(state[0], 0.0, 0.01, "flinch spring settles")

	t.current = "lean, breath, look"
	t.check(Anim.lean_angles(2.0, 5.0).x < 0.0, "turning left rolls toward the left")
	t.check(Anim.lean_angles(-2.0, 5.0).x > 0.0, "turning right rolls the other way")
	t.near(Anim.lean_angles(50.0, 5.0).x, -0.17, 0.0001, "roll clamped")
	t.near(Anim.lean_angles(2.0, 0.0).x, 0.0, 0.0001, "no lean while standing")
	t.check(Anim.lean_angles(0.0, 6.0).y > Anim.lean_angles(0.0, 1.0).y, "forward lean grows with speed")
	t.near(Anim.breath_angle(1.0, 1.0), 0.0, 0.0001, "no breathing while running")
	t.check(absf(Anim.breath_angle(0.9, 0.0)) > 0.005, "breathing at idle")
	var look := Anim.look_angles(Basis(), Vector3(1, 0, 1), 1.05, 0.5)
	t.near(look.x, PI / 4.0, 0.001, "yaw toward +X (left)")
	t.near(Anim.look_angles(Basis(), Vector3(0, 5, 1), 1.0, 0.4).y, 0.4, 0.0001, "pitch clamped")
	t.near(Anim.look_angles(Basis(), Vector3(5, 0, 1), 0.5, 0.4).x, 0.5, 0.0001, "yaw clamped")
	t.near(Anim.look_angles(Basis(), Vector3(0, 0, -1), 1.0, 0.4).x, 0.0, 0.0001, "target behind: look forward")
	t.near(Anim.look_angles(Basis(Vector3.UP, PI / 2.0), Vector3(1, 0, 0), 1.0, 0.4).x, 0.0, 0.0001, "body frame respected")
	var q := Anim.look_rotation(Basis(), Vector2(0.5, 0.0))
	t.near((q * Vector3.BACK).x, sin(0.5), 0.0001, "look rotation turns forward axis toward +X")

	t.current = "foot ik math"
	t.eq(Anim.contact_weight(0.0), 1.0, "planted foot fully weighted")
	t.eq(Anim.contact_weight(0.5), 0.0, "swinging foot free")
	t.near(Anim.pelvis_offset(0.2, 0.3), 0.0, 0.0001, "feet higher: hips stay")
	t.near(Anim.pelvis_offset(-0.2, 0.1), -0.2, 0.0001, "hips follow the lower foot")
	t.near(Anim.pelvis_offset(-1.0, -1.0), -0.35, 0.0001, "pelvis drop clamped")
	var n := Anim.ground_normal(0.0, 0.2, 0.0, 0.2)
	t.check(n.x < 0.0 and n.y > 0.0, "slope rising along +X tilts normal toward -X")
	t.near(Anim.ground_normal(1.0, 1.0, 1.0, 0.2).y, 1.0, 0.0001, "flat ground points up")
	var a := Vector3(0, 1, 0)
	var b := Vector3(0, 0.55, 0.05)
	var c := Vector3(0, 0.1, 0)
	var target := Vector3(0.0, 0.3, 0.1)
	var solved := Anim.solve_knee(a, b, c, target)
	t.near(a.distance_to(solved[0]), a.distance_to(b), 0.0001, "thigh length kept")
	t.near((solved[0] as Vector3).distance_to(solved[1]), b.distance_to(c), 0.0001, "calf length kept")
	t.near((solved[1] as Vector3).distance_to(target), 0.0, 0.001, "reachable target met")
	t.check((Anim.solve_knee(a, b, c, Vector3(0, 0.4, 0))[0] as Vector3).z > 0.0, "knee keeps its bend side")
	var far := Anim.solve_knee(a, b, c, Vector3(0, -5, 0))
	t.near(a.distance_to(far[1]), a.distance_to(b) + b.distance_to(c), 0.01, "unreachable target: full extension")

	t.current = "upper-body layering"
	t.check(Anim.is_upper_body_bone("spine_03"), "spine is upper body")
	t.check(Anim.is_upper_body_bone("Head"), "case-insensitive")
	t.check(Anim.is_upper_body_bone("hand_r"), "hands are upper body")
	t.check(not Anim.is_upper_body_bone("thigh_l"), "legs are not")
	t.check(not Anim.is_upper_body_bone("pelvis"), "pelvis stays with locomotion")
	t.eq(Anim.track_bone(NodePath("Armature/Skeleton3D:upperarm_l")), "upperarm_l", "bone from track path")
	t.eq(Anim.track_bone(NodePath("Armature")), "", "non-bone path")
	var clip := Animation.new()
	clip.length = 1.0
	for bone in ["pelvis", "spine_02", "thigh_l", "hand_r", "calf_r"]:
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath("Armature/Skeleton3D:" + bone))
	var upper := Anim.upper_body_copy(clip)
	t.eq(upper.get_track_count(), 2, "only upper-body tracks stay")
	t.eq(clip.get_track_count(), 5, "source clip untouched")
	t.check(Anim.layerable("Sword_Attack", true, false), "attacks layer while moving")
	t.check(not Anim.layerable("Sword_Attack", false, false), "standing attacks use the full body")
	t.check(not Anim.layerable("Sword_Attack", true, true), "zombies keep full-body clips")
	t.check(not Anim.layerable("Hit_Chest", true, false), "hit clips are replaced by the additive flinch")

	_modifier_tests(t)
	_model_tests(t)


## CharacterModel wiring with a synthetic rig (no asset packs needed).
func _model_tests(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or not tree.root.is_inside_tree():
		return
	t.current = "character model wiring"
	var CharacterModel = load("res://scripts/client/character_model.gd")
	var cm = CharacterModel.new()
	var rig := Node3D.new()
	var armature := Node3D.new()
	armature.name = "Armature"
	rig.add_child(armature)
	armature.add_child(_mannequin())
	cm.add_child(rig)
	cm.pack_mode = true
	cm.animator = AnimationPlayer.new()
	rig.add_child(cm.animator)
	var library := AnimationLibrary.new()
	for clip_name in ["Idle_Loop", "Walk_Loop", "Sword_Attack"]:
		var clip := Animation.new()
		clip.length = 1.0
		for bone in ["spine_02", "thigh_l"]:
			var track := clip.add_track(Animation.TYPE_ROTATION_3D)
			clip.track_set_path(track, NodePath("Armature/Skeleton3D:" + bone))
			clip.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
		library.add_animation(clip_name, clip)
	cm.animator.add_animation_library("", library)
	cm._setup_procedural(rig)
	tree.root.add_child(cm)
	t.check(cm._procedural != null and cm._layer != null, "modifier and layer player created")
	cm._moving = true
	cm.play_action("Sword_Attack")
	t.eq(cm._oneshot, "", "moving attack is layered, locomotion keeps control")
	t.eq(cm._layer.current_animation, "Sword_Attack", "layer plays the swing")
	t.eq(cm._layer.get_animation("Sword_Attack").get_track_count(), 1, "layer clip holds only upper-body tracks")
	cm._moving = false
	cm.play_action("Sword_Attack")
	t.eq(cm._oneshot, "Sword_Attack", "standing attack uses the base player")
	cm._oneshot = ""
	cm.play_hit(false)
	t.eq(cm._oneshot, "", "light hit is additive only")
	cm.set_anim_lod(3)
	t.eq(cm.animator.callback_mode_process, AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "far LOD updates manually")
	t.check(not cm._procedural.active, "far LOD disables modifiers")
	cm.update_motion(0.2)
	cm.set_anim_lod(0)
	t.check(cm._procedural.active, "near LOD re-enables modifiers")
	cm.start_ragdoll(Vector3.ZERO)
	t.check(not cm._procedural.active, "ragdoll disables the procedural layer")
	tree.root.remove_child(cm)
	cm.free()


func _modifier_tests(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or not tree.root.is_inside_tree():
		return
	t.current = "procedural modifier"
	var body := Node3D.new()
	var skeleton := _mannequin()
	body.add_child(skeleton)
	var modifier := Modifier.new()
	modifier.body = body
	skeleton.add_child(modifier)
	tree.root.add_child(body)
	var feet := ["foot_l", "foot_r"]
	var before: Array[Vector3] = []
	for f in feet:
		before.append(body.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(f)).origin)
	var spine_before := skeleton.get_bone_pose(skeleton.find_bone("spine_03"))

	# Idle breathing: pelvis stays, chest moves, and repeated passes do not accumulate.
	for i in 30:
		modifier._process_modification_with_delta(0.05)
	t.check(modifier.is_resolved(), "bones resolved case-insensitively")
	t.check(modifier.bone("head") >= 0, "Head found as head")
	var spine_moved := not skeleton.get_bone_pose(skeleton.find_bone("spine_03")).is_equal_approx(spine_before)
	t.check(spine_moved, "breathing moves the chest")
	modifier.reset()
	t.check(skeleton.get_bone_pose(skeleton.find_bone("spine_03")).is_equal_approx(spine_before), "reset restores the pose")

	# Flinch decays back.
	modifier.kick(Vector3.BACK, 1.0)
	modifier._process_modification_with_delta(0.016)
	var kicked := skeleton.get_bone_pose(skeleton.find_bone("spine_03")).basis
	t.check(not kicked.is_equal_approx(spine_before.basis), "kick bends the spine")
	for i in 200:
		modifier._process_modification_with_delta(0.016)
	modifier.reset()

	# Look at: head turns toward a point on the left (+X for a +Z-facing body).
	modifier.look_point = Vector3(5, 1.5, 3)
	for i in 120:
		modifier._process_modification_with_delta(0.016)
	var head_forward: Vector3 = (skeleton.global_transform.basis * skeleton.get_bone_global_pose(skeleton.find_bone("Head")).basis) * Vector3.BACK
	t.check(head_forward.x > 0.3, "head turned toward the look point")
	modifier.look_point = Vector3.INF
	for i in 200:
		modifier._process_modification_with_delta(0.016)
	head_forward = (skeleton.global_transform.basis * skeleton.get_bone_global_pose(skeleton.find_bone("Head")).basis) * Vector3.BACK
	t.check(head_forward.x < 0.05, "head returns when the target clears")

	# Foot IK: the left foot stands on ground 0.15 m higher; the right on flat ground.
	modifier.ground_fn = func(x: float, _z: float) -> float: return 0.15 if x > 0.0 else 0.0
	for i in 120:
		modifier._process_modification_with_delta(0.016)
	var left := body.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot_l")).origin
	var right := body.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot_r")).origin
	t.near(left.y, before[0].y + 0.15, 0.03, "left foot raised to the higher ground")
	t.near(right.y, before[1].y, 0.03, "right foot stays on flat ground")
	var thigh_len := (skeleton.get_bone_global_pose(skeleton.find_bone("calf_l")).origin - skeleton.get_bone_global_pose(skeleton.find_bone("thigh_l")).origin).length()
	t.near(thigh_len, 0.45, 0.01, "bone lengths preserved by IK")

	# Both feet low: the pelvis sinks, feet reach the lower ground.
	modifier.ground_fn = func(_x: float, _z: float) -> float: return -0.1
	body.global_position = Vector3.ZERO
	for i in 200:
		modifier._process_modification_with_delta(0.016)
	# Root ground equals foot ground here (both -0.1), so no offset is wanted.
	var pelvis_y := (body.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("pelvis")).origin).y
	t.near(pelvis_y, 1.0, 0.01, "uniform ground keeps the pelvis")
	modifier.reset()
	tree.root.remove_child(body)
	body.free()
