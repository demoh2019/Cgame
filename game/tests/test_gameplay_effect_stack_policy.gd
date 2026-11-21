extends RefCounted
## Unreal GAS-style GameplayEffectStackPolicy and server-infected Resolve parity.
const Resolve = preload("res://scripts/shared/infected_resolve.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "native/stock stack policy preserves exact Resolve strength"
	for stacks in [0, 1, 2, 3, 99]:
		var factor: float = Resolve.FACTORS[clampi(stacks, 0, Resolve.MAX_STACKS - 1)]
		t.near(Resolve.duration(1.5, stacks, false), 1.5 * factor, 0.0001,
			"resolve factor matches historical diminishing-returns table")
		t.near(Resolve.duration(1.5, stacks, true), 0.75 * factor, 0.0001,
			"elite resistance remains independent from stack overflow")
	t.eq(Resolve.duration(NAN, 0, false), 0.0, "invalid stun cannot be applied")
	t.eq(Resolve.duration(1.51, 0, false), 0.0, "oversized stun is rejected")
	var first: Dictionary = Resolve.plan_application(1.5, 0, 0.0, false)
	t.check(bool(first["accepted"]), "first valid stun is accepted")
	t.eq(int(first["stacks"]), 1, "first stun consumes a single Resolve stack")
	t.near(float(first["remaining"]), 1.5, 0.0001, "first stun retains full duration")
	var weaker: Dictionary = Resolve.plan_application(1.5, 1, 1.5, false)
	t.check(not bool(weaker["accepted"]), "weaker immediate reapplication is rejected")
	t.eq(int(weaker["stacks"]), 1, "rejected repeat does not consume another stack")
	var second: Dictionary = Resolve.plan_application(1.5, 1, 0.3, false)
	t.check(bool(second["accepted"]), "short remaining duration can be refreshed")
	t.near(float(second["remaining"]), 0.975, 0.0001,
		"accepted second stun is reduced to 65 percent")
	var overflow: Dictionary = Resolve.plan_application(1.5, 3, 0.1, false)
	t.check(bool(overflow["accepted"]), "capped Resolve still allows weaker stuns")
	t.eq(int(overflow["stacks"]), 3, "overflow cannot create a fourth stack")
	t.near(float(overflow["remaining"]), 0.6, 0.0001,
		"overflow uses the last 40 percent factor")

	t.current = "native configurable stack policy strategies"
	if ClassDB.class_exists("GameplayEffectStackPolicy"):
		var policy: Object = ClassDB.instantiate("GameplayEffectStackPolicy")
		t.check(bool(policy.call("configure", 2, PackedFloat32Array([1.0, 0.5]), 1, 1)),
			"native engine configures a two-stack overflow-reject policy")
		var reject: Dictionary = policy.call("preview_application", 2.0, 2, 0.0)
		t.check(not bool(reject["accepted"]), "overflow policy rejects third application")
		t.check(bool(policy.call("configure", 2, PackedFloat32Array([1.0, 0.5]), 2, 2)),
			"native engine configures overflow-reset and duration extension")
		var reset: Dictionary = policy.call("preview_application", 2.0, 2, 1.0)
		t.check(bool(reset["accepted"]), "reset policy accepts the overflow")
		t.eq(int(reset["stacks"]), 1, "reset policy restarts the stack cycle")
		t.near(float(reset["remaining"]), 3.0, 0.0001,
			"extension adds the reset application duration")
	else:
		t.eq(Resolve.plan_application(1.5, 0, 0.0, false)["stacks"], 1,
			"stock engine still applies the identical server-side Resolve policy")

	t.current = "real infected methods enforce the policy before mutating combat"
	var infected := Zombie.new(91842, "spitter", Vector3.ZERO)
	infected.spit_pending = true
	infected.spit_seconds = 0.7
	t.check(infected.apply_stagger(1.5), "confirmed stun applies to living infected")
	t.eq(infected.stagger_resolve_stacks, 1, "successful application records one stack")
	t.check(not infected.spit_pending, "successful stun interrupts a cast")
	infected.spit_pending = true
	infected.spit_seconds = 0.7
	t.check(not infected.apply_stagger(1.5), "weaker duplicate does not apply")
	t.eq(infected.stagger_resolve_stacks, 1, "rejected stun does not consume a stack")
	t.check(infected.spit_pending, "rejected stun does not interrupt attack windup")
	infected.stagger_seconds = 0.1
	t.check(infected.apply_stagger(1.5), "stronger second stun applies")
	t.eq(infected.stagger_resolve_stacks, 2, "second stack recorded")
	t.near(infected.stagger_seconds, 0.975, 0.0001, "second stun scaled correctly")
	infected.stagger_resolve_seconds = 0.0
	infected.stagger_seconds = 0.0
	t.check(infected.apply_stagger(1.5), "expired Resolve window resets stack count")
	t.eq(infected.stagger_resolve_stacks, 1, "new cycle starts at one stack")
