extends RefCounted
## Snapshot-to-native-tag bridge: data-driven, optional on stock Godot.
const EngineFeatures = preload("res://scripts/client/engine_features.gd")


func run(t) -> void:
	t.current = "runtime tag synthesis"
	var infected := {"hp": 50.0, "state": 3, "elite": true,
		"stagger_seconds": 1.25, "snared_seconds": 0.0, "sunder_seconds": 2.0}
	var tags: PackedStringArray = EngineFeatures.runtime_tags("zombie", infected)
	t.check(tags.has("Runtime.Life.Alive"), "living infected tagged")
	t.check(tags.has("Runtime.Rank.Elite"), "elite tag from server snapshot")
	t.check(tags.has("Runtime.Status.Staggered"), "stagger from authoritative timer")
	t.check(tags.has("Runtime.Status.Sundered"), "sunder from authoritative timer")
	t.check(not tags.has("Runtime.Status.Snared"), "expired snare absent")
	t.check(tags.has("Runtime.Combat.Alert"), "AI alert state tagged")
	infected["hp"] = 0.0
	infected["stagger_seconds"] = 0.0
	tags = EngineFeatures.runtime_tags("zombie", infected)
	t.check(tags.has("Runtime.Life.Dead") and not tags.has("Runtime.Life.Alive"), "death replaces life state")
	t.check(not tags.has("Runtime.Status.Staggered"), "expired status removed by tag synthesis")
	infected["resolve_seconds"] = 5.0
	infected["resolve_stacks"] = 1
	t.check(not EngineFeatures.runtime_tags("zombie", infected).has("Runtime.Status.Resolve"),
		"resolve requires both duration and minimum stacks")
	infected["resolve_stacks"] = 2
	t.check(EngineFeatures.runtime_tags("zombie", infected).has("Runtime.Status.Resolve"),
		"active resolve tag requires two stacks")

	t.current = "crowd-control cardinality shared by the native tag store and snapshot fallback"
	var stacked := {"hp": 20.0, "state": 2,
		"stagger_seconds": 1.0, "snared_seconds": 0.5, "sunder_seconds": 0.0}
	t.eq(EngineFeatures.zombie_control_count(null, stacked), 2, "stock Godot counts two distinct active controls")
	stacked["snared_seconds"] = 0.0
	t.eq(EngineFeatures.zombie_control_count(null, stacked), 1, "expired snare does not count")
	stacked["sunder_seconds"] = 2.0
	t.eq(EngineFeatures.zombie_control_count(null, stacked), 2, "a second exposure contributes one")
	stacked["stagger_seconds"] = 0.0
	stacked["sunder_seconds"] = 0.0
	t.eq(EngineFeatures.zombie_control_count(null, stacked), 0, "zero timers clear stacked visuals")
	var control_actor := Node3D.new()
	EngineFeatures.tag_node(control_actor, ["Enemy.Infected.Walker"])
	if ClassDB.class_exists("GameplayTagContainer"):
		var control_store: Object = control_actor.get_meta("tags", null) as Object
		if control_store != null and control_store.has_method("count_matching_queries"):
			stacked["stagger_seconds"] = 1.0
			stacked["snared_seconds"] = 2.0
			EngineFeatures.sync_runtime_tags(control_actor, "zombie", stacked)
			t.eq(EngineFeatures.zombie_control_count(control_actor, stacked), 2,
				"native status count matches stock snapshot fallback")
			stacked["snared_seconds"] = 0.0
			EngineFeatures.sync_runtime_tags(control_actor, "zombie", stacked)
			t.eq(EngineFeatures.zombie_control_count(control_actor, stacked), 1,
				"native status refresh removes expired control")
			var native_query: Object = ClassDB.instantiate("GameplayTagQuery")
			if native_query != null and native_query.has_method("set_min_any_matches"):
				native_query.set("any_tags", PackedStringArray([
					"Runtime.Status.Staggered", "Runtime.Status.Snared"]))
				native_query.call("set_min_any_matches", 2)
				t.check(not bool(native_query.call("matches", control_store)),
					"declarative two-status query stops matching when snare expires")
				stacked["snared_seconds"] = 1.0
				EngineFeatures.sync_runtime_tags(control_actor, "zombie", stacked)
				t.check(bool(native_query.call("matches", control_store)),
					"declarative query matches again with two active controls")
	control_actor.free()

	t.current = "player movement state tags"
	var player := {"alive": true, "mounted": true, "outlaw": true, "crouching": false}
	tags = EngineFeatures.runtime_tags("player", player)
	t.check(tags.has("Runtime.Movement.Mounted"), "mount tag")
	t.check(tags.has("Runtime.Status.Outlaw"), "outlaw tag")
	t.check(not tags.has("Runtime.Movement.Crouching"), "absent crouch tag")
	t.check(EngineFeatures.runtime_tags("bag", {}).is_empty(), "non-actors have no runtime tags")

	t.current = "optional native tag integration"
	var actor := Node3D.new()
	EngineFeatures.tag_node(actor, ["Enemy.Infected.Walker"])
	EngineFeatures.sync_runtime_tags(actor, "zombie", infected)
	if ClassDB.class_exists("GameplayTagContainer") and ClassDB.class_has_method(
			"GameplayTagContainer", "replace_tag_branch"):
		var container: Object = actor.get_meta("tags") as Object
		t.check(container != null, "native tag container available")
		if container != null:
			t.check(bool(container.call("has_tag", StringName("Enemy"), false)), "static identity preserved")
			t.check(EngineFeatures.runtime_has(actor, "Runtime.Life.Dead"), "native death tag")
			infected["hp"] = 20.0
			infected["stagger_seconds"] = 1.0
			EngineFeatures.sync_runtime_tags(actor, "zombie", infected)
			t.check(EngineFeatures.runtime_has(actor, "Runtime.Life.Alive"), "life changes after snapshot")
			t.check(not EngineFeatures.runtime_has(actor, "Runtime.Life.Dead"), "old branch cleared")
			t.check(EngineFeatures.runtime_has(actor, "Runtime.Status.Staggered"), "new status applied")
	else:
		t.check(not EngineFeatures.runtime_has(actor, "Runtime.Life.Dead"), "stock Godot skips native tags")
		t.check(EngineFeatures.runtime_has(actor, "Runtime.Status.Staggered", true), "fallback remains functional")
	if ClassDB.class_exists("GameplayTagStackContainer"):
		t.current = "native counted runtime effects"
		infected["resolve_stacks"] = 3
		infected["resolve_seconds"] = 5.0
		EngineFeatures.sync_runtime_tags(actor, "zombie", infected)
		t.eq(EngineFeatures.runtime_stack_count(actor, "Runtime.Status.Resolve"), 3,
			"native count reflects authoritative resolve stacks")
		var native_stacks: Object = actor.get_meta("tag_stacks") as Object
		t.check(native_stacks != null, "counted tag container attached to rendered actor")
		if native_stacks != null:
			t.eq(int(native_stacks.call("get_stack_count", StringName("Runtime.Status"), false)), 5,
				"parent status query sums active descendant stacks")
		infected["resolve_seconds"] = 0.0
		EngineFeatures.sync_runtime_tags(actor, "zombie", infected)
		t.eq(EngineFeatures.runtime_stack_count(actor, "Runtime.Status.Resolve"), 0,
			"expired resolve stacks disappear on the following snapshot")
		if native_stacks != null and native_stacks.has_method("replace_stack_branch"):
			t.current = "independent client effects survive runtime snapshots"
			t.check(bool(native_stacks.call("add_stacks", StringName("Local.Preview.Bleeding"), 2)),
				"create independent local effect")
			infected["resolve_seconds"] = 4.0
			EngineFeatures.sync_runtime_tags(actor, "zombie", infected)
			t.eq(EngineFeatures.runtime_stack_count(actor, "Runtime.Status.Resolve"), 3,
				"runtime branch still refreshes")
			t.eq(int(native_stacks.call("get_stack_count", StringName("Local.Preview.Bleeding"), true)), 2,
				"local bleeding survives runtime refresh")
			infected["resolve_seconds"] = 0.0
			EngineFeatures.sync_runtime_tags(actor, "zombie", infected)
			t.eq(EngineFeatures.runtime_stack_count(actor, "Runtime.Status.Resolve"), 0,
				"expired runtime stack cleared")
			t.eq(int(native_stacks.call("get_stack_count", StringName("Local.Preview.Bleeding"), true)), 2,
				"local branch still intact after expiry")
	else:
		t.eq(EngineFeatures.runtime_stack_count(actor, "Runtime.Status.Resolve", 3), 3,
			"stock Godot retains snapshot fallback for resolve presentation")
	actor.free()
