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
