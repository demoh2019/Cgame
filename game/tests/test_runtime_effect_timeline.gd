extends RefCounted
## Native effect timeline plus stock-Godot fallback. Combat remains server-owned.
const Features = preload("res://scripts/client/engine_features.gd")

func run(t) -> void:
	t.current = "authoritative status snapshots produce timed visual effects"
	var zombie := {"hp": 20.0, "stagger_seconds": 1.5, "snared_seconds": 0.0,
		"sunder_seconds": 3.0, "resolve_seconds": 2.0, "resolve_stacks": 3}
	var effects: Dictionary = Features.runtime_effect_snapshot("zombie", zombie)
	t.eq(effects.size(), 3, "only live statuses are mirrored")
	t.eq(int(effects[StringName("Runtime.Status.Resolve")]["stacks"]), 3, "resolve stack count preserved")
	t.eq(Features.runtime_effect_snapshot("player", zombie), {}, "no invented player status")
	zombie["stagger_seconds"] = NAN
	zombie["snared_seconds"] = INF
	effects = Features.runtime_effect_snapshot("zombie", zombie)
	t.check(not effects.has(StringName("Runtime.Status.Staggered")), "nonfinite timer rejected")
	t.check(not effects.has(StringName("Runtime.Status.Snared")), "infinite timer rejected")

	t.current = "native effects expire between snapshots, fallback remains valid"
	var actor := Node3D.new()
	Features.tag_node(actor, ["Enemy.Infected.Walker"])
	zombie["stagger_seconds"] = 1.5
	zombie["snared_seconds"] = 0.0
	Features.sync_runtime_tags(actor, "zombie", zombie)
	if ClassDB.class_exists("GameplayEffectTimeline"):
		t.near(Features.runtime_effect_remaining(actor, "Runtime.Status.Staggered"), 1.5, 0.001, "initial duration matches")
		Features.tick_runtime_effects(actor, 0.5)
		t.near(Features.runtime_effect_remaining(actor, "Runtime.Status.Staggered"), 1.0, 0.001, "explicit tick")
		Features.tick_runtime_effects(actor, 1.0)
		t.eq(Features.runtime_effect_remaining(actor, "Runtime.Status.Staggered"), 0.0, "expired visual effect cleared")
		t.near(Features.runtime_effect_remaining(actor, "Runtime.Status.Sundered"), 1.5, 0.001, "other effect unaffected")
		Features.sync_runtime_tags(actor, "zombie", zombie)
		t.near(Features.runtime_effect_remaining(actor, "Runtime.Status.Staggered"), 1.5, 0.001, "new snapshot restores timer")
		zombie["sunder_seconds"] = 0.0
		Features.sync_runtime_tags(actor, "zombie", zombie)
		t.eq(Features.runtime_effect_remaining(actor, "Runtime.Status.Sundered"), 0.0, "snapshot removes effect")
	else:
		t.eq(Features.runtime_effect_remaining(actor, "Runtime.Status.Staggered", 1.5), 1.5, "stock Godot fallback")
	if ClassDB.class_exists("GameplayEffectTimeline") and ClassDB.class_has_method(
			"GameplayEffectTimeline", "set_periodic"):
		t.current = "periodic native visual effects retain phase across snapshots"
		zombie["sunder_seconds"] = 3.0
		zombie["resolve_seconds"] = 2.0
		zombie["resolve_stacks"] = 3
		Features.sync_runtime_tags(actor, "zombie", zombie)
		t.eq(Features.tick_runtime_effects(actor, 0.4), {},
			"periodic effects do not emit before the first deadline")
		Features.sync_runtime_tags(actor, "zombie", zombie)
		var pulses: Dictionary = Features.tick_runtime_effects(actor, 0.4)
		t.eq(int(pulses.get(StringName("Runtime.Status.Sundered"), 0)), 1,
			"authoritative snapshot does not reset 0.75-second sunder phase")
		t.eq(int(pulses.get(StringName("Runtime.Status.Resolve"), 0)), 0,
			"longer resolve period remains independent")
		pulses = Features.tick_runtime_effects(actor, 0.4)
		t.eq(int(pulses.get(StringName("Runtime.Status.Resolve"), 0)), 1,
			"resolve's periodic pulse is emitted without a new packet")
		zombie["sunder_seconds"] = 0.0
		Features.sync_runtime_tags(actor, "zombie", zombie)
		t.eq(Features.tick_runtime_effects(actor, 0.8).get(StringName(
			"Runtime.Status.Sundered"), 0), 0, "expired effect produces no further pulse")
	else:
		t.eq(Features.tick_runtime_effects(actor, 0.4), {},
			"older engine binaries and stock Godot do not invent periodic triggers")
	actor.free()
