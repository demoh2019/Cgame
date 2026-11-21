extends RefCounted
## Server-owned Cgame status effect immunity + stock Godot parity.
const Rules = preload("res://scripts/shared/effect_application_rules.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "hierarchical status application requirements"
	t.check(Rules.can_apply(Rules.STAGGER, true, false), "alive infected can be staggered")
	t.check(Rules.can_apply(Rules.SNARE, true, false), "alive infected can be snared")
	t.check(Rules.can_apply(Rules.SUNDER, true, true), "raid bosses may still be sundered")
	t.check(not Rules.can_apply(Rules.STAGGER, true, true), "bosses immune to stagger")
	t.check(not Rules.can_apply(Rules.SNARE, true, true), "bosses immune to snares")
	t.check(not Rules.can_apply(Rules.STAGGER, false, false), "dead targets are immune")
	t.check(not Rules.can_apply("Effect.CrowdControls.Stagger", true, false),
		"unknown/sibling effects fail closed")
	t.check(not Rules.can_apply(Rules.STAGGER, true, false,
		PackedStringArray(["Immunity.CrowdControl.Enhanced"])),
		"hierarchical crowd-control immunity blocks exact and child effects")
	t.check(not Rules.can_apply(Rules.SUNDER, true, true,
		PackedStringArray(["Immunity.Sunder.Magical"])),
		"sunder-specific immunity blocks boss armor breaks")
	t.check(Rules.can_apply(Rules.SUNDER, true, false,
		PackedStringArray(["Immunity.CrowdControl"])),
		"unrelated immunities do not block Sunder")
	if ClassDB.class_exists("GameplayEffectApplicationGate"):
		t.eq(Rules.native_reason(Rules.STAGGER, true, true), "blocked",
			"native rules expose a clear boss immunity reason")
		t.eq(Rules.native_reason(Rules.SUNDER, true, true), "allowed",
			"native gate accepts boss Sunder")

	t.current = "real server zombie methods honor engine status policy"
	var walker := Zombie.new(87001, "walker", Vector3.ZERO)
	t.check(walker.apply_stagger(1.0), "stagger applies to living normal infected")
	t.check(walker.stagger_seconds > 0.0, "stagger mutates server-owned timer")
	t.check(walker.apply_snare(1.0), "snare applies to living normal infected")
	t.check(walker.snared_seconds > 0.0, "snare mutates server-owned timer")
	t.check(walker.apply_sunder(10.0, 2.0), "sunder applies to living normal infected")
	t.check(walker.sunder_until > 10.0, "sunder mutates server-owned deadline")
	var boss := Zombie.new(87002, "brute", Vector3.ZERO)
	boss.raid_boss = true
	t.check(not boss.apply_stagger(1.0), "boss stun denied in actual server method")
	t.check(not boss.apply_snare(1.0), "boss root denied in actual server method")
	t.check(boss.apply_sunder(10.0, 2.0), "boss sunder remains possible")
	boss.state = Zombie.State.DEAD
	t.check(not boss.apply_sunder(15.0, 2.0), "dead boss cannot gain Sunder")
	t.check(not boss.apply_stagger(1.0), "dead boss cannot be stunned")
