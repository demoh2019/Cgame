extends RefCounted
## Adapter between DeterministicPhysics and RollbackNetcode (scripts/shared/rollback_netcode.gd),
## plus server-side lag compensation for moving physics objects.
##
## State handed to the netcode is {"phys": PackedByteArray (solver snapshot), "tick": int}.
## Player inputs are Dictionaries {"force": Vector3}; each player owns one body (bind_player) and
## the input is applied as a clamped force for that step. step_state() is the pure, deterministic
## Callable(state, inputs, dt) -> state the netcode expects.
##
## Lag compensation: every simulated state is also kept in a bounded ring (tick -> snapshot) so
## rewind_query(time, origin, dir) can pose all bodies as they were at `time` (interpolating
## between the two bracketing snapshots, lerp position / slerp rotation) and ray cast against
## that past world. The ring is keyed by tick, so resimulation after a rollback overwrites
## mispredicted entries with corrected ones.
##
## Ideas: Glenn Fiedler "Networked Physics" (snapshot + resimulate), Valve "Source Multiplayer
## Networking" lag compensation (public documentation). Original implementation.

const DeterministicPhysics = preload("res://scripts/shared/deterministic_physics.gd")

var world: DeterministicPhysics = DeterministicPhysics.new()
var player_bodies: Dictionary = {} # player id -> body id
var max_force: float = 60.0
var history_capacity: int = 120
var dt: float = 1.0 / 60.0

var _history: Dictionary = {} # tick -> PackedByteArray
var _scratch_a: DeterministicPhysics = DeterministicPhysics.new()
var _scratch_b: DeterministicPhysics = DeterministicPhysics.new()
var _newest_tick: int = -1


func bind_player(pid: Variant, body_id: int) -> void:
	player_bodies[pid] = body_id


## Initial netcode state from the current world; also seeds the lag-compensation ring.
func initial_state() -> Dictionary:
	_history.clear()
	_newest_tick = -1
	var bytes: PackedByteArray = world.snapshot()
	_record(0, bytes)
	return {"phys": bytes, "tick": 0}


## Configures a RollbackNetcode instance to run this physics world.
func setup_net(net: RefCounted, players: Array, local_players: Array, p_dt: float = 1.0 / 60.0,
		input_delay: int = 0, max_prediction: int = 8) -> void:
	dt = p_dt
	net.call("setup", Callable(self, "step_state"), initial_state(), players, local_players,
		p_dt, input_delay, max_prediction)


## The netcode step: restore, apply player forces in sorted player order, step, snapshot.
func step_state(state: Dictionary, inputs: Dictionary, p_dt: float) -> Dictionary:
	world.restore(state["phys"] as PackedByteArray)
	var pids: Array = inputs.keys()
	pids.sort()
	for pid in pids:
		var bid: int = int(player_bodies.get(pid, -1))
		if bid < 0:
			continue
		var inp: Dictionary = inputs[pid]
		var f: Vector3 = inp.get("force", Vector3.ZERO)
		if f != Vector3.ZERO:
			if f.length() > max_force:
				f = f.normalized() * max_force
			world.apply_force(bid, f)
	world.step(p_dt)
	var tick: int = int(state["tick"]) + 1
	var bytes: PackedByteArray = world.snapshot()
	state["phys"] = bytes
	state["tick"] = tick
	_record(tick, bytes)
	return state


func state_checksum(state: Dictionary) -> int:
	return hash(state["phys"] as PackedByteArray)


func _record(tick: int, bytes: PackedByteArray) -> void:
	_history[tick] = bytes
	_newest_tick = maxi(_newest_tick, tick)
	# A rollback rewrote older ticks: anything newer is stale until resimulated, but is replaced
	# as the resimulation proceeds. Only trim by age.
	var cutoff: int = _newest_tick - history_capacity
	if _history.size() > history_capacity + 1:
		for k in _history.keys():
			if int(k) < cutoff:
				_history.erase(k)


func history_size() -> int:
	return _history.size()


func oldest_time() -> float:
	var oldest: int = _newest_tick
	for k in _history:
		oldest = mini(oldest, int(k))
	return float(oldest) * dt


func newest_time() -> float:
	return float(_newest_tick) * dt


## Casts a ray against the world as it was at `time` (seconds of simulation time). `time` is
## clamped to the stored history. Result: {"hit", "id", "t", "point", "alpha", "tick"}.
func rewind_query(time: float, ray_origin: Vector3, ray_dir: Vector3, max_dist: float = 1000.0) -> Dictionary:
	var out: Dictionary = {"hit": false, "id": -1, "t": max_dist, "point": Vector3.ZERO, "alpha": 0.0, "tick": -1}
	if _history.is_empty():
		return out
	var oldest: int = _newest_tick
	for k in _history:
		oldest = mini(oldest, int(k))
	var ft: float = clampf(time / dt, float(oldest), float(_newest_tick))
	var lo_tick: int = int(floor(ft))
	var alpha: float = ft - float(lo_tick)
	var hi_tick: int = lo_tick + 1
	if not _history.has(lo_tick):
		return out
	_scratch_a.restore(_history[lo_tick] as PackedByteArray)
	if alpha > 1e-9 and _history.has(hi_tick):
		_scratch_b.restore(_history[hi_tick] as PackedByteArray)
		for b in _scratch_a.bodies:
			var other: DeterministicPhysics.Body = _scratch_b.get_body(b.id)
			if other != null and not b.is_static():
				_scratch_a.set_pose(b.id, b.pos.lerp(other.pos, alpha), b.rot.slerp(other.rot, alpha))
	else:
		alpha = 0.0
	var res: Dictionary = _scratch_a.raycast(ray_origin, ray_dir, max_dist)
	res["alpha"] = alpha
	res["tick"] = lo_tick
	return res
