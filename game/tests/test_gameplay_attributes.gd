extends RefCounted
## GameplayAttributeSet native aggregation and stock-Godot parity.
## Effects alter only local visual response, not damage or server state.
const Features = preload("res://scripts/client/engine_features.gd")


func run(t) -> void:
	t.current = "Unreal-style Gameplay Attributes snapshot synthesis"
	var snapshot := {
		"hp": 75.0, "max_hp": 120.0, "elite": true,
		"sunder_seconds": 2.0, "resolve_seconds": 3.0, "resolve_stacks": 3
	}
	var data: Dictionary = Features.runtime_attribute_snapshot("zombie", snapshot)
	t.eq(data["attributes"][StringName("Vital.Health")]["base"], 75.0,
		"authoritative current health is mirrored")
	t.eq(data["attributes"][StringName("Vital.MaxHealth")]["base"], 120.0,
		"authoritative maximum health is mirrored")
	t.eq(data["modifiers"].size(), 3, "elite, sunder and resolve contribute independently")
	t.eq(Features.runtime_attribute_snapshot("bag", {})["attributes"].size(), 0,
		"non-actors never get fabricated gameplay attributes")
	snapshot["hp"] = NAN
	snapshot["max_hp"] = INF
	data = Features.runtime_attribute_snapshot("zombie", snapshot)
	t.eq(data["attributes"][StringName("Vital.Health")]["base"], 0.0,
		"nonfinite health is sanitized")
	t.eq(data["attributes"][StringName("Vital.MaxHealth")]["base"], 1.0,
		"nonfinite max health is sanitized")

	t.current = "native aggregate with status changes, or stock engine fallback"
	snapshot["hp"] = 75.0
	snapshot["max_hp"] = 120.0
	var actor := Node3D.new()
	Features.tag_node(actor, ["Enemy.Infected.Walker"])
	Features.sync_runtime_tags(actor, "zombie", snapshot)
	if ClassDB.class_exists("GameplayAttributeSet"):
		t.near(Features.runtime_attribute_value(actor, "Visual.HitResponse", 1.0),
			1.30, 0.0001, "elite + sunder - resolve yields 1.3 visual multiplier")
		t.near(Features.runtime_attribute_value(actor, "Vital.Health", -1.0),
			75.0, 0.0001, "native current health follows snapshot")
		var attrs: Object = actor.get_meta("attributes", null) as Object
		if attrs != null and attrs.has_method("replace_snapshot_branch"):
			t.current = "server snapshots preserve independent local visual modifiers"
			t.check(bool(attrs.call("set_modifier", StringName("Local.Visual.Crit"),
				StringName("Visual.HitResponse"), 0.10, 0.0)),
				"local presentation source applied independently")
			t.near(Features.runtime_attribute_value(actor, "Visual.HitResponse", 1.0),
				1.40, 0.0001, "local modifier combines with server status modifiers")
			snapshot["hp"] = 60.0
			Features.sync_runtime_tags(actor, "zombie", snapshot)
			t.near(Features.runtime_attribute_value(actor, "Vital.Health", -1.0),
				60.0, 0.0001, "authoritative base health still refreshes")
			t.near(Features.runtime_attribute_value(actor, "Visual.HitResponse", 1.0),
				1.40, 0.0001, "local source survives updated authoritative snapshot")
			t.eq(int(attrs.call("get_modifier_count")), 4,
				"server and local modifiers remain separate")
			t.check(bool(attrs.call("remove_modifier", StringName("Local.Visual.Crit"),
				StringName("Visual.HitResponse"))), "local source expires independently")
			t.near(Features.runtime_attribute_value(actor, "Visual.HitResponse", 1.0),
				1.30, 0.0001, "removing local source leaves server effects")
		snapshot["sunder_seconds"] = 0.0
		Features.sync_runtime_tags(actor, "zombie", snapshot)
		t.near(Features.runtime_attribute_value(actor, "Visual.HitResponse", 1.0),
			1.05, 0.0001, "expired sunder removes its modifier atomically")
		snapshot["resolve_seconds"] = 0.0
		Features.sync_runtime_tags(actor, "zombie", snapshot)
		t.near(Features.runtime_attribute_value(actor, "Visual.HitResponse", 1.0),
			1.20, 0.0001, "expired resolve removes its modifier atomically")
	else:
		t.eq(Features.runtime_attribute_value(actor, "Visual.HitResponse", 1.0),
			1.0, "stock Godot keeps unmodified hit presentation")
	actor.free()
