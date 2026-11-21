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

	t.current = "Niagara-style critical cue admission when visual backlog is full"
	var pressure_actor := Node3D.new()
	CueBridge.attach(pressure_actor)
	var busy_queue: Object = pressure_actor.get_meta("gameplay_cues", null) as Object
	if busy_queue != null and busy_queue.has_method("get_evicted_transient_count"):
		var accepted := 0
		for i in 128:
			if bool(busy_queue.call("emit_cue", StringName("GameplayCue.Ambient.%d" % i), 1.0, 0)):
				accepted += 1
		t.eq(accepted, 128, "entire native transient cue queue filled with low-priority ambience")
		var critical: Array = CueBridge.frame_events(pressure_actor, {
			"Runtime.Status.Sundered": 2.0,
			"Runtime.Status.Resolve": 4.0,
		})
		t.eq(critical.size(), 8, "per-frame cue draw cap respected even when saturated")
		t.eq(str(critical[0].get("tag", "")), "GameplayCue.Status.Resolve",
			"resolve cue at priority 6 survives and drains before minor effects")
		t.eq(str(critical[1].get("tag", "")), "GameplayCue.Status.Sundered",
			"sunder cue at priority 4 also survives the ambient queue")
		t.eq(int(critical[0].get("priority", -1)), 6, "resolve critical priority mapped")
		t.eq(int(critical[1].get("priority", -1)), 4, "sunder ordinary priority mapped")
		t.eq(int(busy_queue.call("get_evicted_transient_count")), 2,
			"two low-priority effects evicted with hard queue size preserved")
		t.eq(int(busy_queue.call("get_pending_count")), 120,
			"overflow admission does not grow bounded engine allocation")
	else:
		var normal: Array = CueBridge.frame_events(pressure_actor, {
			"Runtime.Status.Sundered": 2.0,
			"Runtime.Status.Resolve": 4.0,
		})
		t.eq(normal.size(), 2, "older native or stock engine keeps visual pulses")
		var priority_by_tag := {}
		for entry in normal:
			priority_by_tag[str(entry.get("tag", ""))] = int(entry.get("priority", -1))
		t.eq(int(priority_by_tag.get("GameplayCue.Status.Resolve", -1)), 6,
			"stock fallback preserves critical Resolve priority")
		t.eq(int(priority_by_tag.get("GameplayCue.Status.Sundered", -1)), 4,
			"stock fallback preserves normal Sunder priority")
	pressure_actor.free()

	t.current = "replicated status transitions survive saturated transient cue budgets"
	var lifecycle_actor := Node3D.new()
	CueBridge.attach(lifecycle_actor)
	var status_queue: Object = lifecycle_actor.get_meta("gameplay_cues", null) as Object
	if status_queue != null and status_queue.has_method("replace_active_resilient"):
		for i in 128:
			t.check(bool(status_queue.call("emit_cue",
				StringName("GameplayCue.Background.%d" % i), 1.0, 0)),
				"native cue prefill accepts bounded background pulses")
		CueBridge.sync(lifecycle_actor, "zombie", {
			"stagger_seconds": 1.0, "sunder_seconds": 2.0
		})
		t.eq(int(status_queue.call("get_active_count")), 2,
			"two replicated debuffs enter persistent cue state despite full backlog")
		t.eq(int(status_queue.call("get_evicted_transient_count")), 2,
			"only two expendable ambient pulses displaced to preserve lifecycle")
		var lifecycle_events: Array = CueBridge.frame_events(lifecycle_actor, {})
		t.eq(lifecycle_events.size(), 8, "render frame still respects fixed cue draw budget")
		var started: Dictionary = {}
		for item in lifecycle_events:
			if str(item.get("event", "")) == "started":
				started[str(item.get("tag", ""))] = true
		t.check(started.has("GameplayCue.Status.Staggered") and
			started.has("GameplayCue.Status.Sundered"),
			"status starts survive saturation and drain before ambient visuals")
		CueBridge.sync(lifecycle_actor, "zombie", {})
		t.eq(int(status_queue.call("get_active_count")), 0,
			"replicated expiration clears native persistent cue state")
		var stopped_events: Array = CueBridge.frame_events(lifecycle_actor, {})
		var stopped: Dictionary = {}
		for item in stopped_events:
			if str(item.get("event", "")) == "stopped":
				stopped[str(item.get("tag", ""))] = true
		t.check(stopped.has("GameplayCue.Status.Staggered") and
			stopped.has("GameplayCue.Status.Sundered"),
			"status stop events reliably clean up effects after backlog")
	else:
		t.check(status_queue == null or not status_queue.has_method("replace_active_resilient"),
			"stock Godot and older binaries retain compatible cue handling")
	lifecycle_actor.free()

