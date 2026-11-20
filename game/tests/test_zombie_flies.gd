extends RefCounted
## Zombie flies budget.
const ZombieFlies = preload("res://scripts/client/zombie_flies.gd")


func run(t) -> void:
	t.current = "flies on nearby zombies, daytime and dry weather"
	t.eq(ZombieFlies.swarm_count(3, 1.0, 0.0), ZombieFlies.POOL, "Ultra day: full pool")
	t.eq(ZombieFlies.swarm_count(2, 1.0, 0.0), 2, "High: two swarms")
	t.eq(ZombieFlies.swarm_count(1, 1.0, 0.0), 0, "Balanced pays nothing")
	t.eq(ZombieFlies.swarm_count(3, 0.1, 0.0), 0, "flies rest at night")
	t.eq(ZombieFlies.swarm_count(3, 1.0, 0.6), 0, "rain grounds them")
