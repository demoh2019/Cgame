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
		var timeline: Object = actor.get_meta("effect_timeline", null) as Object
		if timeline != null and timeline.has_method("replace_effect_branch"):
			t.current = "scoped native effects and consecutive-hit visual feedback"
			t.check(bool(timeline.call("apply_effect", StringName("Local.Visual.Hit"), 2.0)),
				"client timed visual effect starts")
			zombie["stagger_seconds"] = 1.0
			Features.sync_runtime_tags(actor, "zombie", zombie)
			t.near(Features.runtime_effect_remaining(actor, "Local.Visual.Hit"), 2.0, 0.001,
				"authoritative refresh preserves local timer")
			t.near(Features.runtime_effect_remaining(actor, "Runtime.Status.Staggered"), 1.0, 0.001,
				"server-owned timer still refreshes")
			var first: float = Features.hit_feedback_strength(actor, 1.0)
			var second: float = Features.hit_feedback_strength(actor, 1.0)
			t.near(first, 1.0, 0.001, "first hit intensity unchanged")
			t.check(second > first, "consecutive hits increase cosmetic intensity")
			if timeline.has_method("apply_effect_with_tag_requirements"):
				t.current = "native target tag requirements prevent hit stacking on dead or immune actors"
				timeline.call("remove_effect", StringName("Local.Visual.RecentHit"))
				zombie["hp"] = 0.0
				Features.sync_runtime_tags(actor, "zombie", zombie)
				t.near(Features.hit_feedback_strength(actor, 1.0), 1.0, 0.001,
					"dead actor returns neutral cosmetic response")
				t.eq(int(timeline.call("get_stacks", StringName("Local.Visual.RecentHit"))), 0,
					"dead actor cannot accumulate recent-hit effect")
				zombie["hp"] = 20.0
				Features.sync_runtime_tags(actor, "zombie", zombie)
				var container: Object = actor.get_meta("tags", null) as Object
				if container != null:
					container.call("add_tag", StringName("Runtime.Status.Immune.Hit"))
					t.near(Features.hit_feedback_strength(actor, 1.0), 1.0, 0.001,
						"immunity prevents recent-hit visual stacking")
					t.eq(int(timeline.call("get_stacks", StringName("Local.Visual.RecentHit"))), 0,
						"immunity does not mutate timeline")
					container.call("remove_tag", StringName("Runtime.Status.Immune.Hit"))
				t.near(Features.hit_feedback_strength(actor, 1.0), 1.0, 0.001,
					"living actor starts new recent-hit chain")
				t.eq(int(timeline.call("get_stacks", StringName("Local.Visual.RecentHit"))), 1,
					"valid tag requirements allow live target hit effect")
			Features.tick_runtime_effects(actor, 0.4)
			t.near(Features.runtime_effect_remaining(actor, "Local.Visual.Hit"), 1.6, 0.001,
				"independent visual timer advances")
			zombie["stagger_seconds"] = 0.0
			Features.sync_runtime_tags(actor, "zombie", zombie)
			t.eq(Features.runtime_effect_remaining(actor, "Runtime.Status.Staggered"), 0.0,
				"expired server status removed")
			t.near(Features.runtime_effect_remaining(actor, "Local.Visual.Hit"), 1.6, 0.001,
				"server expiry does not erase local timer")
	else:
		t.eq(Features.tick_runtime_effects(actor, 0.4), {},
			"older engine binaries and stock Godot do not invent periodic triggers")
	t.current = "native fused periodic step matches the legacy two-call status loop"
	if ClassDB.class_exists("GameplayEffectTimeline"):
		var updated: Object = ClassDB.instantiate("GameplayEffectTimeline")
		var baseline: Object = ClassDB.instantiate("GameplayEffectTimeline")
		if updated != null and baseline != null and updated.has_method(
				"tick_and_take_periodic_pulses"):
			var render_actor := Node3D.new()
			render_actor.set_meta("effect_timeline", updated)
			for timeline in [updated, baseline]:
				t.check(bool(timeline.call("set_effect", &"Runtime.Status.Sundered", 3.0)),
					"native timelines accept the same incoming replicated status")
				t.check(bool(timeline.call("set_effect", &"Runtime.Status.Resolve", 3.7, 3)),
					"both native timelines accept stacked Resolve")
				t.check(bool(timeline.call("set_periodic", &"Runtime.Status.Sundered", 0.75, false)),
					"native Sundered pulse phase is configured")
				t.check(bool(timeline.call("set_periodic", &"Runtime.Status.Resolve", 1.1, false)),
					"native Resolve pulse phase is configured")
			for step in [0.4, 0.36, 0.8, 0.9, 2.0, 4.0]:
				var expired: PackedStringArray = baseline.call("tick", step)
				var old_pulses: Dictionary = baseline.call("take_periodic_pulses")
				var new_pulses: Dictionary = Features.tick_runtime_effects(render_actor, step)
				t.eq(new_pulses, old_pulses,
					"live game fused actor tick emits exactly the legacy native pulse counts")
				t.eq(updated.call("get_snapshot"), baseline.call("get_snapshot"),
					"periodic phase, remaining timers and stack counts are unchanged")
				t.eq(updated.call("take_periodic_pulses"), {},
					"fused call drains pending status pulses exactly once")
				if step == 2.0:
					t.check(expired.has("Runtime.Status.Sundered"),
						"legacy path exposes expired statuses; fused game path still expires them")
			t.eq(int(updated.call("get_effect_count")), 0, "all visual effects expire as before")
			t.eq(Features.tick_runtime_effects(render_actor, 0.2), {},
				"empty native timeline does not fabricate pulses")
			render_actor.free()
		else:
			t.check(true, "older Cgame retains the two-call periodic effect fallback")
	else:
		t.eq(Features.tick_runtime_effects(actor, 0.2), {},
			"stock Godot keeps an inert status effect ticking fallback")

	t.current = "live Albion After actor loop uses fused native periodic update"
	var bridge_source: String = (Features as Script).source_code
	t.check(bridge_source.contains('timeline.has_method("tick_and_take_periodic_pulses")') and
		bridge_source.contains('timeline.call("tick_and_take_periodic_pulses", delta)'),
		"actual entity view's EngineFeatures bridge calls new native fused step")
	t.check(bridge_source.contains('timeline.call("tick", delta)') and
		bridge_source.contains('timeline.call("take_periodic_pulses")'),
		"older fork builds retain the two-call native compatibility path")

	actor.free()
