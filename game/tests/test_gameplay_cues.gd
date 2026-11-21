extends RefCounted
## Lifecycle Gameplay Cues, event coalescing and older/stock Godot fallback.
const CueBridge = preload("res://scripts/client/gameplay_cues.gd")
const Features = preload("res://scripts/client/engine_features.gd")


func run(t) -> void:
	t.current = "replicated status cues synthesize exactly active statuses"
	var zombie := {
		"hp": 50.0, "stagger_seconds": 1.4, "snared_seconds": 0.0,
		"sunder_seconds": 2.8, "resolve_seconds": 3.0, "resolve_stacks": 3
	}
	var active: Dictionary = CueBridge.active_snapshot("zombie", zombie)
	t.eq(active.size(), 3, "only three active statuses produce cue tags")
	t.eq(int(active[StringName("GameplayCue.Status.Resolve")]), 3, "resolve keeps real stacks")
	t.eq(CueBridge.active_snapshot("player", zombie), {}, "no unsupported player status")
	zombie["stagger_seconds"] = INF
	zombie["snared_seconds"] = NAN
	active = CueBridge.active_snapshot("zombie", zombie)
	t.check(not active.has(StringName("GameplayCue.Status.Staggered")), "infinite timer rejected")
	t.check(not active.has(StringName("GameplayCue.Status.Snared")), "NaN timer rejected")
	t.eq(CueBridge.pulse_color("GameplayCue.Status.Sundered"), Color(1.0, 0.43, 0.15),
		"sunder has a deterministic orange visual")

	t.current = "native cue lifecycle tracks authoritative changes only"
	zombie["stagger_seconds"] = 1.4
	var actor := Node3D.new()
	Features.tag_node(actor, ["Enemy.Infected.Walker"])
	CueBridge.sync(actor, "zombie", zombie)
	var cues: Object = actor.get_meta("gameplay_cues", null) as Object
	if cues != null:
		var events: Array = CueBridge.frame_events(actor, {})
		t.eq(events.size(), 3, "initial snapshot emits one start per active status")
		for cue in events:
			t.eq(str(cue.get("event", "")), "started", "initial event is started")
		CueBridge.sync(actor, "zombie", zombie)
		t.eq(CueBridge.frame_events(actor, {}).size(), 0, "same snapshot does not replay start")
		zombie["resolve_stacks"] = 4
		CueBridge.sync(actor, "zombie", zombie)
		events = CueBridge.frame_events(actor, {})
		t.eq(events.size(), 1, "stack count change emits a single event")
		t.eq(str(events[0]["event"]), "updated", "changed stacks update persistent cue")
		zombie["sunder_seconds"] = 0.0
		CueBridge.sync(actor, "zombie", zombie)
		events = CueBridge.frame_events(actor, {})
		t.eq(events.size(), 1, "expiry produces one stop event")
		t.eq(str(events[0]["event"]), "stopped", "expired cue is stopped")
		t.eq(int(cues.call("get_active_stacks", StringName("GameplayCue.Status.Resolve"))),
			4, "independent persistent cue remains active")
		var pulse_events: Array = CueBridge.frame_events(actor, {
			"Runtime.Status.Resolve": 4
		})
		t.eq(pulse_events.size(), 1, "periodic pulses coalesce into cosmetic execute")
		t.eq(str(pulse_events[0]["event"]), "executed", "periodic pulse is executed")
		t.eq(float(pulse_events[0]["magnitude"]), 4.0, "periodic pulse magnitude retained")
	else:
		var pulse_events: Array = CueBridge.frame_events(actor, {
			"Runtime.Status.Resolve": 3
		})
		t.eq(pulse_events.size(), 1, "stock Godot still renders periodic effects")
		t.eq(str(pulse_events[0]["event"]), "executed", "stock fallback event is cosmetic")
	actor.free()
