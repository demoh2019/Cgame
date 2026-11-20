extends RefCounted
## Native Cgame and stock Godot seed mixer and world-seeded ambient life.
const Streams = preload("res://scripts/client/seeded_substreams.gd")
const Birds = preload("res://scripts/client/ambient_birds.gd")


func run(t) -> void:
	t.current = "named RNG streams do not consume their parent"
	var parent := RandomNumberGenerator.new()
	parent.seed = 1337
	var initial_state: int = parent.state
	var positions := Streams.fork(parent, Birds.STREAM_POSITION)
	var velocities := Streams.fork(parent, Birds.STREAM_VELOCITY)
	var wings := Streams.fork(parent, Birds.STREAM_WING_PHASE)
	t.check(positions != null and velocities != null and wings != null,
		"position, flight motion and animation each have an isolated generator")
	t.eq(parent.state, initial_state, "spawning multiple substreams never advances the parent")
	t.eq(parent.seed, 1337, "forking does not change the original seed")
	t.eq(positions.seed, Streams.seed_for(1337, Birds.STREAM_POSITION),
		"position stream uses the stable native-compatible derived seed")
	t.eq(velocities.seed, Streams.seed_for(1337, Birds.STREAM_VELOCITY),
		"velocity stream uses the stable native-compatible derived seed")
	t.eq(wings.seed, Streams.seed_for(1337, Birds.STREAM_WING_PHASE),
		"animation stream uses the stable native-compatible derived seed")
	t.check(positions.seed != velocities.seed and positions.seed != wings.seed and velocities.seed != wings.seed,
		"separate cosmetic concerns cannot accidentally share the same random sequence")

	t.current = "versioned mixer golden vectors"
	t.eq(Streams.seed_for(0, 0), -8991371085989781972,
		"version one seed vector: zero world and zero tag")
	t.eq(Streams.seed_for(1337, 1), -8119305880941845874,
		"version one seed vector: named position stream")
	t.eq(Streams.seed_for(1337, 2), 3750391151841051190,
		"version one seed vector: independent flight stream")
	t.eq(Streams.seed_for(-1, -1), -5240767868243073691,
		"version one seed vector: negative world and negative tag")

	t.current = "stream identity is invariant to draw order and parent state"
	var again := Streams.fork(parent, Birds.STREAM_POSITION)
	for i in 16:
		t.eq(positions.randi(), again.randi(), "substreams with matching seed and id produce identical PCG draws")
	for i in 25:
		parent.randi()
	var after_parent_draw := Streams.fork(parent, Birds.STREAM_POSITION)
	t.eq(after_parent_draw.seed, again.seed,
		"the original generator's draws never change the named substream seed")
	t.eq(after_parent_draw.randi(), Streams.fork(parent, Birds.STREAM_POSITION).randi(),
		"substream creation remains reproducible after arbitrary parent draws")
	var reversed_wings := Streams.fork(parent, Birds.STREAM_WING_PHASE)
	t.eq(reversed_wings.seed, wings.seed,
		"asking for wing animation before or after positions is equivalent")
	t.check(Streams.seed_for(1337, 1) != Streams.seed_for(1337, -1),
		"negative stream identifiers remain distinct")
	t.check(Streams.seed_for(1337, 1) != Streams.seed_for(1337, 4294967297),
		"upper 32-bit stream id changes affect the result")
	t.check(Streams.seed_for(0, 7) != Streams.seed_for(4294967296, 7),
		"upper 32-bit world seed changes affect the result")
	var child := Streams.fork(parent, 41)
	var nested := Streams.fork(child, 17)
	t.eq(nested.seed, Streams.seed_for(child.seed, 17),
		"nested streams are reproducible for sub-jobs")

	t.current = "native engine seed derivation agrees with the portable exact algorithm"
	if parent.has_method("fork"):
		for root_seed in [0, 1, -1, 1337, -99999, 4294967297]:
			parent.seed = root_seed
			for tag in [0, 1, -1, 9999, 4294967297]:
				t.eq(int(parent.call("get_substream_seed", tag)), Streams.seed_for(root_seed, tag),
					"native C++ seed mixing agrees bit-for-bit with GDScript fallback")
				t.eq((parent.call("fork", tag) as RandomNumberGenerator).seed,
					Streams.seed_for(root_seed, tag),
					"native C++ child is initialized with the requested substream seed")
	else:
		t.check(Streams.fork(parent, -11).seed == Streams.seed_for(parent.seed, -11),
			"official Godot receives a deterministic child with no Cgame-only API")

	t.current = "ambient life is now driven by world seed rather than global randf"
	var a := Birds.new(4141)
	var b := Birds.new(4141)
	var different := Birds.new(4142)
	t.eq(a._pos, b._pos, "same connected world recreates identical flock positions")
	t.eq(a._vel, b._vel, "same connected world recreates identical flock flight vectors")
	t.check(a._pos != different._pos, "different world seed changes decorative bird layout")
	t.check(a._vel != different._vel, "different world seed changes decorative flight velocities")
	t.check(a._pos.size() == Birds.MAX_BIRDS, "flock geometry budget remains unchanged")
	a.free()
	b.free()
	different.free()

	t.current = "real game seeds client-only wildlife from connected world"
	var live_source := FileAccess.get_file_as_string("res://scripts/client/online_main.gd")
	t.check(live_source.contains("_ambient_birds = AmbientBirds.new(client.world.world_seed)"),
		"live multiplayer game passes the shared world seed to client-side birds")
	t.check(not live_source.contains("client.world.world_seed ="),
		"visual initialization never modifies the authoritative world seed")
