extends RefCounted
## Native cooldown tracker vs stock-Godot fallback, fed from server snapshots.
const Cooldowns = preload("res://scripts/client/ability_cooldowns.gd")


func run(t) -> void:
	t.current = "authority-only five-slot cooldown snapshot synthesis"
	var you := {
		"skill_cd": 3.5, "ultimate_cd": -2.0,
		"gear_cd": {"armor": 0.0, "head": 1.25, "feet": INF},
		"ability_global_cd": 0.4
	}
	var active: Dictionary = Cooldowns.snapshot(you)
	t.eq(active.size(), 3, "weapon head and explicit global group tracked")
	t.eq(active[StringName("Ability.Weapon")], 3.5, "weapon remains authoritative")
	t.eq(active[StringName("Ability.Head")], 1.25, "helmet cooldown tracked")
	t.eq(active[StringName("Ability.Global")], 0.4, "global group only from server")
	t.check(not active.has(StringName("Ability.Feet")), "nonfinite cooldown omitted")
	t.check(not active.has(StringName("Ability.Ultimate")), "negative cooldown omitted")
	t.eq(Cooldowns.display_remaining("armor", you), 0.4, "shared lock blocks ready armor")
	t.eq(Cooldowns.display_remaining("weapon", you), 3.5, "individual cooldown takes priority")
	you.erase("ability_global_cd")
	t.check(not Cooldowns.snapshot(you).has(StringName("Ability.Global")),
		"shared lock never invented if server did not send it")

	t.current = "native frame ticks and shared locks or stock fallback"
	t.eq(Cooldowns.format_remaining(0.4), "  0.4s", "short lock remains readable")
	t.eq(Cooldowns.format_remaining(2.8), "  3s", "long cooldown rounds like prior UI")
	t.eq(Cooldowns.format_remaining(-1.0), "", "expired cooldown has no suffix")
	var tracker: Object = Cooldowns.make_native()
	if tracker != null:
		t.check(bool(tracker.call("replace_snapshot", active)), "server snapshot imported")
		t.near(Cooldowns.display_remaining("armor", you, tracker), 0.4, 0.0001,
			"native group lock blocks ready armor")
		tracker.call("tick", 0.25)
		t.near(Cooldowns.display_remaining("weapon", you, tracker), 3.25, 0.0001,
			"per-ability countdown advances between packets")
		t.near(Cooldowns.display_remaining("armor", you, tracker), 0.15, 0.0001,
			"group countdown advances separately")
		tracker.call("tick", 0.2)
		t.eq(Cooldowns.display_remaining("armor", you, tracker), 0.0,
			"shared lock expires while weapon remains cooling down")
		t.check(bool(tracker.call("replace_snapshot", active)), "next server packet reconciles")
		t.eq(Cooldowns.display_remaining("weapon", you, tracker), 3.5,
			"authoritative state always wins over visual projection")
	else:
		t.eq(Cooldowns.display_remaining("weapon", you), 3.5,
			"stock Godot reads authoritative weapon cooldown")
		t.eq(Cooldowns.display_remaining("head", you), 1.25,
			"stock Godot retains gear cooldown UI")

	t.current = "scoped authoritative updates preserve independent UI effects"
	if tracker != null and tracker.has_method("replace_cooldown_branch"):
		var fresh := {
			"skill_cd": 2.0, "ultimate_cd": 0.0,
			"gear_cd": {"armor": 0.5}, "ability_global_cd": 0.0
		}
		t.check(Cooldowns.record_activation_feedback(tracker, "weapon"),
			"native visual press feedback starts independently")
		t.check(Cooldowns.activation_feedback_active(tracker, "weapon"),
			"UI press feedback is visible")
		t.check(Cooldowns.reconcile_native(tracker, fresh),
			"authoritative cooldown branch reconciles")
		t.near(float(tracker.call("get_remaining", &"Ability.Weapon")), 2.0, 0.0001,
			"new server ability cooldown replaces old value")
		t.near(float(tracker.call("get_remaining", &"Local.UI.Activation.weapon")), 0.22, 0.0001,
			"server snapshot leaves local visual pulse untouched")
		tracker.call("tick", 0.12)
		t.check(Cooldowns.reconcile_native(tracker, fresh),
			"later server packet is independent of cosmetic clock")
		t.near(float(tracker.call("get_remaining", &"Local.UI.Activation.weapon")), 0.10, 0.0001,
			"local feedback keeps its elapsed phase")
		tracker.call("tick", 0.11)
		t.check(not Cooldowns.activation_feedback_active(tracker, "weapon"),
			"local visual pulse expires on the native tick")
		t.check(not Cooldowns.record_activation_feedback(tracker, "unknown"),
			"invalid slot never creates an effect")
		t.check(Cooldowns.reconcile_native(tracker, {}),
			"empty authoritative snapshot clears only ability tags")
		t.eq(float(tracker.call("get_remaining", &"Ability.Weapon")), 0.0,
			"missing server cooldown is removed")
	else:
		t.check(not Cooldowns.record_activation_feedback(tracker, "weapon"),
			"older builds retain prior cooldown-only UI behavior")


	t.current = "five-slot gameplay HUD batch query and authoritative group lock"
	var slot_order := PackedStringArray(["weapon", "ultimate", "armor", "head", "feet"])
	var batch_you: Dictionary = {
		"skill_cd": 3.5, "ultimate_cd": 0.0,
		"gear_cd": {"head": 1.25, "armor": 0.0, "feet": 0.0},
		"ability_global_cd": 0.4
	}
	var expected_batch := PackedFloat64Array([3.5, 0.4, 0.4, 1.25, 0.4])
	t.eq(Cooldowns.display_many(slot_order, batch_you), expected_batch,
		"stock Godot reports every individual cooldown plus global lock in original order")
	t.eq(Cooldowns.display_many(PackedStringArray(["head", "weapon", "head"]), batch_you),
		PackedFloat64Array([1.25, 3.5, 1.25]),
		"duplicate or reordered known slots return matching values")
	t.eq(Cooldowns.display_many(PackedStringArray(["weapon", "unknown"]), batch_you).size(), 0,
		"unknown slot rejects the batch atomically")
	var large_slots := PackedStringArray()
	large_slots.resize(65)
	t.eq(Cooldowns.display_many(large_slots, batch_you).size(), 0,
		"unbounded client query is rejected")
	var batch_tracker: Object = Cooldowns.make_native()
	if batch_tracker != null:
		t.check(bool(batch_tracker.call("replace_snapshot", Cooldowns.snapshot(batch_you))),
			"live native tracker stores authoritative per-skill and group cooldowns")
		t.eq(Cooldowns.display_many(slot_order, batch_you, batch_tracker), expected_batch,
			"native batch and portable fallback return identical five-slot order")
		batch_tracker.call("tick", 0.25)
		var after_tick := PackedFloat64Array([3.25, 0.15, 0.15, 1.0, 0.15])
		var batch_result: PackedFloat64Array = Cooldowns.display_many(
			slot_order, batch_you, batch_tracker)
		for i in slot_order.size():
			t.near(batch_result[i], after_tick[i], 0.0001,
				"the entire bar advances from a single explicit native clock tick")
			var slot: String = slot_order[i]
			t.near(batch_result[i], Cooldowns.display_remaining(slot, batch_you, batch_tracker),
				0.0001, "batch entry matches existing per-slot native method")
		batch_tracker.call("tick", 0.2)
		t.eq(Cooldowns.display_many(slot_order, batch_you, batch_tracker),
			PackedFloat64Array([3.05, 0.0, 0.0, 0.8, 0.0]),
			"group lock expires without changing the remaining individual cooldowns")
		if batch_tracker.has_method("get_effective_remaining_batch"):
			var raw: PackedFloat64Array = batch_tracker.call(
				"get_effective_remaining_batch",
				PackedStringArray(["Ability.Head", "Ability.Weapon", "Ability.Head"]),
				&"Ability.Global")
			t.eq(raw, PackedFloat64Array([0.8, 3.05, 0.8]),
				"native batch accepts repeated exact tags and preserves ordering")
			t.eq(batch_tracker.call("get_effective_remaining_batch",
				PackedStringArray(["Ability.Head", ".invalid"]), &"Ability.Global").size(),
				0, "native API rejects invalid tag batches without partial results")
	else:
		t.eq(Cooldowns.display_many(slot_order, batch_you), expected_batch,
			"older engines still draw all five cooldown labels from server state")

	t.current = "actual ability bar consumes batch without granting actions"
	var bar_source: String = FileAccess.get_file_as_string("res://scripts/client/ability_bar.gd")
	t.check(bar_source.contains("AbilityCooldowns.display_many(") and
		bar_source.contains("_buttons[i].disabled = remaining > 0.05"),
		"real Albion After HUD uses batch display while keeping server-owned action checks")
