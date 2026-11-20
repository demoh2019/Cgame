extends RefCounted
## The bite: the server rolls when a fish takes the bait; a strike inside that window hooks it for a bigger catch, a strike
## outside it lets the fish slip, and there is one strike per cast. The client only sees and shows the moment.

const Fishing = preload("res://scripts/shared/fishing.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _shore(world) -> Vector3:
	for x in range(-260, 261, 4):
		for z in range(-260, 261, 4):
			if world.is_water(float(x), float(z)):
				continue
			var where := Vector3(float(x), world.height_at(float(x), float(z)), float(z))
			if Fishing.water_near(world, where) != Vector2.INF:
				return where
	return Vector3.INF


func _cast(sim, player) -> Dictionary:
	sim.time += 30.0 # Past any cooldown.
	return sim.cmd_fish(player.id)


func run(t) -> void:
	t.current = "the bite moment always fits inside the cast"
	for roll in [0.0, 0.25, 0.5, 1.0]:
		var left: float = Fishing.bite_at(Fishing.CAST_SECONDS, roll)
		t.check(left >= Fishing.BITE_LATEST_LEFT - 0.0001 and left <= Fishing.CAST_SECONDS - Fishing.BITE_EARLIEST + 0.0001,
			"bite at %.2f s left is inside the cast" % left)
	t.check(Fishing.biting(2.0, 2.0) and Fishing.biting(2.0 - Fishing.BITE_WINDOW + 0.01, 2.0), "the window opens at the bite")
	t.check(not Fishing.biting(2.1, 2.0) and not Fishing.biting(2.0 - Fishing.BITE_WINDOW, 2.0), "and closes after it")

	var world := WorldGen.new(42)
	var sim := GameServer.new(world, 77)
	var player = sim.add_player(9, "Angler")
	var shore: Vector3 = _shore(world)
	t.check(shore.is_finite(), "a shore to fish from")
	if not shore.is_finite():
		return
	player.position = shore
	player.inventory.add("fishing_rod", 1)

	t.current = "a strike in the window hooks the fish"
	t.check(bool(_cast(sim, player).get("ok", false)), "cast")
	var bite_left: float = float(player.action["bite_at"])
	player.action["remaining"] = bite_left - 0.2
	var strike: Dictionary = sim.cmd_fish(player.id)
	t.check(bool(strike.get("hooked", false)), "hooked")
	t.eq(sim.cmd_fish(player.id).get("reason", ""), "already_struck", "one strike per cast")
	var before: int = player.inventory.count("raw_fish")
	sim._finish_fishing(player)
	var hooked_catch: int = player.inventory.count("raw_fish") - before
	t.check(hooked_catch >= 1 + Fishing.HOOK_BONUS, "a hooked fish is a bigger catch (%d)" % hooked_catch)

	t.current = "a strike outside the window lets the fish slip"
	t.check(bool(_cast(sim, player).get("ok", false)), "second cast")
	t.eq(sim.cmd_fish(player.id).get("reason", ""), "no_bite", "too early")
	t.check(not bool(player.action.get("hooked", false)), "not hooked")
	t.eq(sim.cmd_fish(player.id).get("reason", ""), "already_struck", "no second try after a miss")
	before = player.inventory.count("raw_fish")
	sim._finish_fishing(player)
	var plain: int = player.inventory.count("raw_fish") - before
	t.check(plain >= 1 and plain <= 2, "the cast still pays as an ordinary one (%d)" % plain)

	t.current = "without a strike the cast pays as before"
	t.check(bool(_cast(sim, player).get("ok", false)), "third cast")
	before = player.inventory.count("raw_fish")
	sim._finish_fishing(player)
	var untouched: int = player.inventory.count("raw_fish") - before
	t.check(untouched >= 1 and untouched <= 2, "an ordinary catch (%d)" % untouched)
