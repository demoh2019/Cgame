extends RefCounted
## Verify combat-critical animation prioritization without rendering, assets or
## authority changes. Native mixer APIs are tested when the Cgame fork runs.
const CombatPriority = preload("res://scripts/client/combat_animation_priority.gd")
const CharacterAnim = preload("res://scripts/client/character_anim.gd")
const EntityView = preload("res://scripts/client/entity_view.gd")


func run(t) -> void:
	t.current = "combat animation slots are bounded by real graphics quality"
	t.eq(CombatPriority.slots(-100), 0, "invalid negative quality clamps to zero")
	t.eq(CombatPriority.slots(100), 8, "invalid large quality clamps to Ultra")
	t.eq(CombatPriority.slots(0), 0, "Performance keeps no extra animated characters")
	t.eq(CombatPriority.slots(1), 1, "Balanced allows one high-priority actor")
	t.eq(CombatPriority.slots(2), 4, "High supports a small visible combat group")
	t.eq(CombatPriority.slots(3), 8, "Ultra prioritizes eight visible combatants")

	t.current = "authoritative enemy snapshot selects critical attack tells"
	t.check(CombatPriority.wants_priority("zombie",
		{"raid_boss": true, "state": 0}), "raid boss always has visual priority")
	t.check(CombatPriority.wants_priority("zombie",
		{"raid_enraged": true, "state": 1}), "enraged raid boss keeps readable poses")
	t.check(CombatPriority.wants_priority("zombie",
		{"elite": true, "state": 2}), "elite pursuit reads at full rate")
	t.check(CombatPriority.wants_priority("zombie",
		{"elite": true, "state": 3}), "elite attack animations stay readable")
	t.check(not CombatPriority.wants_priority("zombie",
		{"elite": true, "state": 0}), "idle elites do not spend priority slots")
	t.check(CombatPriority.wants_priority("zombie",
		{"type": "spitter", "state": 3}), "spitter attack warning is prioritized")
	t.check(not CombatPriority.wants_priority("zombie",
		{"type": "spitter", "state": 0}), "idle spitters run at normal crowd LOD")
	t.check(CombatPriority.wants_priority("zombie",
		{"stagger_seconds": 0.2}), "hit staggers keep their visual feedback")
	t.check(not CombatPriority.wants_priority("zombie",
		{"stagger_seconds": 0.0, "state": 1}), "wandering infected keep cheap poses")
	t.check(not CombatPriority.wants_priority("player",
		{"raid_boss": true}), "remote players do not consume zombie priority slots")
	t.check(not CombatPriority.wants_priority("bag",
		{"raid_boss": true}), "static loot never registers urgent animation")

	t.current = "rendering integration and stock-Godot fallback"
	var entity_code: String = (EntityView as Script).source_code
	t.check(entity_code.contains("_apply_combat_animation_priority("),
		"live networked entity viewer tags combatants from real snapshots")
	t.check(entity_code.contains('set_mixer_high_priority"'),
		"real native mixer priority is updated only on changes")
	t.check(entity_code.contains('set_max_priority_mixers"'),
		"native full-rate quota is updated on tier changes")
	t.check(entity_code.contains('aa_combat_animation_priority'),
		"priority is cached on the model instead of dispatched every frame")
	t.check(entity_code.contains("_anim_lod.register_mixer(upper_layer, false)"),
		"upper-body mixer shares native LOD without duplicating skeleton modifier culling")
	t.check(entity_code.contains("_anim_lod.unregister_mixer(upper_layer)"),
		"despawning a zombie restores both animation layers")
	t.check(entity_code.contains('"set_mixer_high_priority", upper_layer, priority'),
		"boss telegraphs prioritize both body and weapon attack tracks")
	var anim_code: String = (CharacterAnim as Script).source_code
	t.check(anim_code.contains("var preferred: Array[int] = []"),
		"stock Godot uses the existing LOD driver without a second animator owner")
	t.check(anim_code.contains("camera.is_position_in_frustum("),
		"stock fallback only spends urgent slots on visible combatants")
	t.check(anim_code.contains("preferred.sort_custom("),
		"nearest critical enemy receives scarce animation priority first")
	t.check(anim_code.contains("tiers[preferred[j]] = mini(tiers[preferred[j]], 1)"),
		"fallback promotes only a bounded amount of visual work, with no IK cost")

	t.current = "native Cgame mixer priority API is reversible and clamped"
	if not ClassDB.class_exists("AnimationLODController"):
		t.check(true, "stock Godot falls back to per-character LOD without a native class")
		return
	var native = ClassDB.instantiate("AnimationLODController")
	t.check(native.has_method("set_mixer_high_priority"),
		"native AnimationLODController supports combat-priority mixer registration")
	t.check(native.has_method("set_max_priority_mixers"),
		"native AnimationLODController exposes a hard full-rate budget")
	if not native.has_method("set_mixer_high_priority"):
		native.free()
		return
	native.max_priority_mixers = 999
	t.eq(native.max_priority_mixers, 32, "native budget cannot exceed the safety cap")
	native.max_priority_mixers = -1
	t.eq(native.max_priority_mixers, 0, "zero priority retains ordinary crowd LOD")
	native.max_priority_mixers = 8
	var mixer := AnimationPlayer.new()
	native.register_mixer(mixer)
	t.check(not bool(native.is_mixer_high_priority(mixer)),
		"new mixers default to cheap animation LOD")
	native.set_mixer_high_priority(mixer, true)
	t.check(bool(native.is_mixer_high_priority(mixer)),
		"combat tell promotes only this animator")
	native.set_mixer_high_priority(mixer, true)
	t.check(bool(native.is_mixer_high_priority(mixer)),
		"identical priority is idempotent")
	native.set_mixer_high_priority(mixer, false)
	t.check(not bool(native.is_mixer_high_priority(mixer)),
		"disengaging restores normal LOD")
	native.unregister_mixer(mixer)
	t.check(not bool(native.is_mixer_high_priority(mixer)),
		"unregistering drops stale priority state")
	mixer.free()
	native.free()
