extends RefCounted
## Visual-only motion-matched locomotion for remote players and infected (character_anim.gd helpers).

const Anim = preload("res://scripts/client/character_anim.gd")
const CharacterModel = preload("res://scripts/client/character_model.gd")


func run(t) -> void:
	var native: bool = ClassDB.class_exists(&"CgameMotionMatchingDatabase") and ClassDB.class_exists(&"AnimationNodeMotionMatching")

	t.current = "quality gate"
	t.check(not Anim.motion_matching_available(0) and not Anim.motion_matching_available(1), "Performance/Balanced keep the state machine")
	t.eq(Anim.motion_matching_available(2), native, "High uses motion matching exactly when the native module exists")
	var model := CharacterModel.new()
	t.eq(model.enable_motion_matching(3), native, "CharacterModel opt-in follows availability")
	t.check(not model.enable_motion_matching(1), "lower tiers switch it off again")
	model.free()

	t.current = "clip -> pack animation mapping"
	t.eq(Anim.locomotion_animation("idle", 0.0, false)[0], "Idle_Loop", "idle survivor")
	t.eq(Anim.locomotion_animation("idle", 0.0, true)[0], "Zombie_Idle_Loop", "idle infected")
	t.eq(Anim.locomotion_animation("walk_forward", 1.6, false)[0], "Walk_Loop", "walking survivor")
	t.near(float(Anim.locomotion_animation("walk_forward", 1.6, false)[1]), 1.0, 0.001, "walk rate matches stride")
	t.eq(Anim.locomotion_animation("walk_forward", 1.1, true)[0], "Zombie_Walk_Fwd_Loop", "walking infected")
	t.eq(Anim.locomotion_animation("run_forward", 4.0, false)[0], "Jog_Fwd_Loop", "jogging survivor")
	t.eq(Anim.locomotion_animation("run_forward", 6.5, false)[0], "Sprint_Loop", "sprinting survivor")
	t.eq(Anim.locomotion_animation("run_forward", 3.6, true)[0], "Jog_Fwd_Loop", "running infected")
	t.eq(Anim.locomotion_animation("turn_left", 0.0, false)[0], "Walk_Loop", "turning on the spot shuffles")
	t.eq(Anim.locomotion_animation("strafe_left", 1.4, true)[0], "Zombie_Walk_Fwd_Loop", "other clips fall back to walking")

	if not native:
		t.current = "search (skipped: native cgame_animation missing)"
		t.eq(str(Anim.match_locomotion(2.0, 0.0)["clip"]), "", "no database -> state machine fallback")
		return

	t.current = "native search"
	t.check(Anim.motion_matching_database() != null, "default locomotion database builds once")
	t.check(Anim.motion_matching_database() == Anim.motion_matching_database(), "database is shared")
	var idle: Dictionary = Anim.match_locomotion(0.0, 0.0)
	var spin: Dictionary = Anim.match_locomotion(0.0, 2.5)
	t.check(str(spin["clip"]).begins_with("turn"), "turning on the spot matches a turn clip (got %s)" % spin["clip"])
	t.check(str(idle["clip"]) == "idle" or str(idle["clip"]).begins_with("turn"), "standing still matches idle (got %s)" % idle["clip"])
	var walk: Dictionary = Anim.match_locomotion(1.4, 0.0)
	t.eq(str(walk["clip"]), "walk_forward", "1.4 m/s matches the walk clip")
	var run: Dictionary = Anim.match_locomotion(4.0, 0.0)
	t.eq(str(run["clip"]), "run_forward", "4 m/s matches the run clip")
	var again: Dictionary = Anim.match_locomotion(4.0, 0.0)
	t.eq(again, run, "search is deterministic")
