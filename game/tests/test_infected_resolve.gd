extends RefCounted
## Stagger diminishing returns must be deterministic, server-owned and PvE only.

const Resolve = preload("res://scripts/shared/infected_resolve.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "bounded resolve durations and invalid input"
	t.near(Resolve.duration(1.5, 0, false), 1.5, 0.001, "first stun unchanged")
	t.near(Resolve.duration(1.5, 1, false), 0.975, 0.001, "second stun is 65 percent")
	t.near(Resolve.duration(1.5, 2, false), 0.6, 0.001, "third stun is 40 percent")
	t.near(Resolve.duration(1.5, 99, false), 0.6, 0.001, "stacks cannot overflow")
	t.near(Resolve.duration(1.5, 0, true), 0.75, 0.001, "elites retain shorter stun")
	t.eq(Resolve.duration(NAN, 0, false), 0.0, "NaN cannot stun")
	t.eq(Resolve.duration(1.51, 0, false), 0.0, "oversized stun cannot bypass bounds")
	t.eq(Resolve.remaining(5.0, 6.0), 0.0, "timer never becomes negative")

	t.current = "real infected resists repeated hits but recovers after six seconds"
	var ground: float = WorldGen.HUB_HEIGHT
	var world := WorldGen.new(2026)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var zombie := Zombie.new(1001, "spitter", Vector3(0.0, ground, 0.0))
	zombie.spit_pending = true
	zombie.spit_seconds = 0.7
	t.check(zombie.apply_stagger(1.5), "first successful hit stuns infected")
	t.near(zombie.stagger_seconds, 1.5, 0.001, "full initial stagger")
	t.eq(zombie.stagger_resolve_stacks, 1, "one effective application recorded")
	t.check(not zombie.spit_pending and zombie.spit_seconds == 0.0,
		"successful stun interrupts spit windup")
	zombie.spit_pending = true
	zombie.spit_seconds = 0.5
	t.check(not zombie.apply_stagger(1.5), "immediate shorter refresh is ignored")
	t.eq(zombie.stagger_resolve_stacks, 1, "rejected reapplication does not consume a stack")
	t.near(zombie.stagger_resolve_seconds, Resolve.RESET_SECONDS, 0.001,
		"rejected reapplication does not refresh the immunity timer")
	t.check(zombie.spit_pending and zombie.spit_seconds == 0.5,
		"rejected reapplication cannot cancel a second cast")
	zombie.spit_pending = false
	zombie.think(world, {}, 1.0, rng)
	t.near(zombie.stagger_seconds, 0.5, 0.001,
		"stun still expires on simulated ticks")
	t.check(zombie.apply_stagger(1.5), "later hit refreshes with reduced duration")
	t.near(zombie.stagger_seconds, 0.975, 0.001, "second hit has diminishing returns")
	t.eq(zombie.stagger_resolve_stacks, 2, "second effective hit increases resistance")
	zombie.think(world, {}, 0.7, rng)
	t.check(zombie.apply_stagger(1.5), "third hit after recovery applies shortest stun")
	t.near(zombie.stagger_seconds, 0.6, 0.001, "third hit is bounded")
	t.eq(zombie.stagger_resolve_stacks, 3, "hard cap on accumulated resolve")
	zombie.think(world, {}, 0.3, rng)
	t.check(zombie.apply_stagger(1.5), "further hits use capped resistance")
	t.near(zombie.stagger_seconds, 0.6, 0.001, "further hits cannot stack durations")
	t.eq(zombie.stagger_resolve_stacks, 3, "stacks stay capped")
	zombie.think(world, {}, Resolve.RESET_SECONDS + 0.1, rng)
	t.eq(zombie.stagger_resolve_stacks, 0, "resolve expires without player commands")
	t.near(zombie.stagger_resolve_seconds, 0.0, 0.001,
		"reset window is gone after enough server time")
	t.check(zombie.apply_stagger(1.5), "fresh hit after reset has full effect")
	t.near(zombie.stagger_seconds, 1.5, 0.001, "full initial duration restored")
	zombie.take_damage(zombie.health + 1.0)
	t.eq(zombie.stagger_resolve_stacks, 0, "death clears temporary resistance")
	t.eq(zombie.stagger_resolve_seconds, 0.0, "death clears temporary resolve clock")
	t.check(not zombie.apply_stagger(1.0), "dead infected cannot be stunned")

	t.current = "elite, raid boss and network visibility"
	var elite = Zombie.new(1002, "walker", Vector3.ZERO)
	elite.become_elite()
	t.check(elite.apply_stagger(1.5), "elite can be stunned once")
	t.near(elite.stagger_seconds, 0.75, 0.001, "elite initial duration halves")
	elite.raid_boss = true
	t.check(not elite.apply_stagger(1.5), "raid boss remains immune")
	t.eq(elite.stagger_resolve_stacks, 1, "boss rejection does not alter resolve")

	var sim := GameServer.new(world, 224)
	var viewer = sim.add_player(74, "Guardian")
	viewer.position = Vector3(0.0, ground, 0.0)
	sim.zombies.clear()
	zombie = Zombie.new(1003, "walker", Vector3(5.0, ground, 0.0))
	sim.zombies[zombie.id] = zombie
	t.check(zombie.apply_stagger(1.5), "server world has confirmed stun")
	zombie.think(world, {}, 1.0, rng)
	t.check(zombie.apply_stagger(1.5), "second server stun accumulates resolve")
	var visible: Array = sim.snapshot_for(viewer.id)["zombies"]
	t.eq(visible.size(), 1, "nearby infected is replicated")
	t.eq(int(visible[0].get("resolve_stacks", 0)), 2, "client sees observable resistance")
	t.check(float(visible[0].get("resolve_seconds", 0.0)) > 0.0,
		"snapshot includes resistance remaining")
	t.check(not visible[0].has("target_id") and not visible[0].has("threat"),
		"client still cannot inspect private AI targets")
	zombie.think(world, {}, Resolve.RESET_SECONDS + 1.0, rng)
	visible = sim.snapshot_for(viewer.id)["zombies"]
	t.eq(int(visible[0].get("resolve_stacks", -1)), 0, "client marker expires")
