extends RefCounted
## Spatial sound lookup, predictable target choice and invalid throw rejection.

const NoiseDecoy = preload("res://scripts/shared/noise_decoy.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _lure(id: int, x: float, z: float, expiry: float) -> Dictionary:
	return {"id": id, "x": x, "z": z, "expires": expiry}


func run(t) -> void:
	t.current = "spatial index chooses closest audible active decoy"
	var now := 10.0
	var decoys: Dictionary = {
		101: _lure(101, 1.0, 0.0, 20.0),
		102: _lure(102, 5.0, 0.0, 20.0),
		103: _lure(103, 500.0, 0.0, 20.0),
		104: _lure(104, 0.0, 0.0, 10.0),
		105: _lure(105, -450.0, 0.0, INF),
	}
	var cells: Dictionary = NoiseDecoy.sound_buckets(decoys, now)
	t.eq(cells.size(), 2, "expired, invalid and far cells are handled")
	var closest: Dictionary = NoiseDecoy.closest_audible(cells, Vector3.ZERO, now)
	t.eq(int(closest.get("id", 0)), 101, "nearest audible lure takes priority")
	t.eq(NoiseDecoy.closest_audible(cells, Vector3(200, 0, 200), now).size(), 0,
		"unrelated far-away cells cannot attract infected")
	t.eq(NoiseDecoy.closest_audible(cells, Vector3(NAN, 0, 0), now).size(), 0,
		"invalid target position never becomes audible")
	t.eq(NoiseDecoy.closest_audible(cells, Vector3.ZERO, 21.0).size(), 0,
		"index is not a license to hear expired lures")

	t.current = "negative grid boundaries and deterministic tie breaking"
	var equal: Dictionary = {
		40: _lure(40, -23.1, 0.0, 30.0),
		12: _lure(12, -21.9, 0.0, 30.0),
		6: _lure(6, -22.0, 0.0, 30.0),
	}
	var index: Dictionary = NoiseDecoy.sound_buckets(equal, now)
	t.eq(int(NoiseDecoy.closest_audible(index, Vector3(-23.0, 0, 0), now).get("id", 0)),
		40, "adjacent negative cells are searched")
	var ties: Dictionary = {
		3: _lure(3, -5.0, 0.0, 30.0),
		2: _lure(2, 5.0, 0.0, 30.0),
	}
	t.eq(int(NoiseDecoy.closest_audible(NoiseDecoy.sound_buckets(ties, now),
		Vector3.ZERO, now).get("id", 0)), 2, "equal range prefers lower stable ID")

	t.current = "live server hearing and bounded investigation"
	var world := WorldGen.new(721)
	var server := GameServer.new(world, 721)
	var player = server.add_player(951, "Scout")
	player.position = Vector3(300, world.height_at(300, 300), 300)
	var walker := Zombie.new(server.new_id(), "walker",
		Vector3(320, world.height_at(320, 300), 300))
	server.zombies[walker.id] = walker
	server.decoys[800] = {"id": 800, "x": 317.0,
		"y": world.height_at(317, 300), "z": 300.0, "owner": 951, "expires": 20.0}
	server.decoys[801] = {"id": 801, "x": 319.0,
		"y": world.height_at(319, 300), "z": 300.0, "owner": 951, "expires": 20.0}
	server.time = 10.0
	server._alert_noise_decoys()
	t.eq(walker.state, Zombie.State.INVESTIGATE, "idle infected investigates server decoy")
	t.near(walker.last_known_target.x, 319.0, 0.001, "closest lure selected")
	server.decoys[802] = {"id": 802, "x": 320.0,
		"y": world.height_at(320, 300), "z": 300.0, "owner": 951, "expires": 20.0}
	server._alert_noise_decoys()
	t.near(walker.last_known_target.x, 319.0, 0.001,
		"an active investigation cannot be redirected each scheduler pass")
	var chasing := Zombie.new(server.new_id(), "walker", walker.position)
	chasing.state = Zombie.State.CHASE
	chasing.target_id = 951
	server.zombies[chasing.id] = chasing
	server._alert_noise_decoys()
	t.eq(chasing.target_id, 951, "existing combat target remains authoritative")

	t.current = "world validates safe source and rejects invalid throws"
	var base = Vector3.ZERO
	t.check(NoiseDecoy.landing(world, base, Vector2.RIGHT).is_empty(),
		"protected settlement cannot throw lures outward")
	t.check(NoiseDecoy.landing(world, player.position,
		Vector2(INF, 0.0)).is_empty(), "nonfinite direction rejected")
