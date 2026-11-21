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
		var timeline: Object = actor.get_meta("effect_timeline", null) as Object
		if timeline != null and timeline.has_method("replace_effect_branch"):
			t.current = "native scoped timer snapshots preserve local visual effects"
			t.check(bool(timeline.call("apply_effect", StringName("Local.Visual.Hit"), 2.0)),
				"client visual effect starts independently")
			zombie["stagger_seconds"] = 1.0
			Features.sync_runtime_tags(actor, "zombie", zombie)
			t.near(Features.runtime_effect_remaining(actor, "Runtime.Status.Staggered"),
				1.0, 0.001, "runtime branch still refreshes")
			t.near(Features.runtime_effect_remaining(actor, "Local.Visual.Hit"),
				2.0, 0.001, "local visual countdown survives refresh")
			Features.tick_runtime_effects(actor, 0.4)
			t.near(Features.runtime_effect_remaining(actor, "Local.Visual.Hit"),
				1.6, 0.001, "local effect advances on frame tick")
			zombie["stagger_seconds"] = 0.0
			Features.sync_runtime_tags(actor, "zombie", zombie)
			t.eq(Features.runtime_effect_remaining(actor, "Runtime.Status.Staggered"), 0.0,
				"runtime expiry removed on subsequent snapshot")
			t.near(Features.runtime_effect_remaining(actor, "Local.Visual.Hit"),
				1.6, 0.001, "runtime expiry does not wipe client effect")
	else:
		t.eq(Features.runtime_effect_remaining(actor, "Runtime.Status.Staggered", 1.5), 1.5, "stock Godot fallback")
	actor.free()
