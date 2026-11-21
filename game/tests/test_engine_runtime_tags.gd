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
	else:
		t.eq(EngineFeatures.runtime_stack_count(actor, "Runtime.Status.Resolve", 3), 3,
			"stock Godot retains snapshot fallback for resolve presentation")
	actor.free()
