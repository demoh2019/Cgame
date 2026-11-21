extends RefCounted
## Server replay inspector over ReplayRecorder data: tick listing, summary, state at a tick
## (re-simulated on a fresh server) and hash-list divergence finding.
## Original GDScript, no third-party code.

const ReplayRecorder = preload("res://scripts/server/replay_recorder.gd")

var replay: Dictionary = {}


func load_file(path: String) -> bool:
	replay = ReplayRecorder.load(path)
	return not replay.is_empty()


func load_dict(data: Dictionary) -> void:
	replay = data


## [{tick, delta, command_count, commands}] for every recorded tick.
func list_ticks(only_with_commands: bool = false) -> Array:
	var out: Array = []
	for f in replay.get("frames", []):
		var fr: Dictionary = f
		var cmds: Array = fr.get("commands", [])
		if only_with_commands and cmds.is_empty():
			continue
		out.append({"tick": int(fr.get("tick", 0)), "delta": float(fr.get("delta", 0.0)),
			"command_count": cmds.size(), "commands": cmds})
	return out


func summary() -> Dictionary:
	var by_type: Dictionary = {}
	var by_peer: Dictionary = {}
	var total: int = 0
	var ids: Array = []
	for p in replay.get("players", []):
		var info: Dictionary = p
		ids.append(int(info.get("id", 0)))
	var frames: Array = replay.get("frames", [])
	for f in frames:
		var fr: Dictionary = f
		for c in fr.get("commands", []):
			var cmd: Dictionary = c
			var m: String = str(cmd.get("method", ""))
			by_type[m] = int(by_type.get(m, 0)) + 1
			var peer: int = int(cmd.get("peer", 0))
			by_peer[peer] = int(by_peer.get(peer, 0)) + 1
			total += 1
	return {"players": ids, "ticks": frames.size(), "commands": total,
		"commands_by_type": by_type, "commands_by_peer": by_peer,
		"seed": int(replay.get("seed", 0)), "world_seed": int(replay.get("world_seed", 0))}


## Re-simulates ticks 0..tick (inclusive) on make_server.call(seed, world_seed).
## Returns {tick, hash, players: {peer: {pos, health}}, zombies, server} or {} on failure.
func state_at(tick: int, make_server: Callable) -> Dictionary:
	if replay.is_empty() or not make_server.is_valid():
		return {}
	var server: Object = make_server.call(int(replay.get("seed", 0)), int(replay.get("world_seed", 0)))
	if server == null:
		return {}
	for p in replay.get("players", []):
		var info: Dictionary = p
		server.add_player(int(info.get("id", 0)), str(info.get("name", "")))
	var last: int = -1
	for f in replay.get("frames", []):
		var fr: Dictionary = f
		if int(fr.get("tick", 0)) > tick:
			break
		for c in fr.get("commands", []):
			var cmd: Dictionary = c
			var method: String = str(cmd.get("method", ""))
			if not ReplayRecorder.is_allowed_method(method) or not server.has_method(method):
				continue
			var args: Array = [int(cmd.get("peer", 0))]
			args.append_array(cmd.get("args", []))
			server.callv(method, args)
		server.tick(float(fr.get("delta", 0.0)))
		last = int(fr.get("tick", 0))
	var players: Dictionary = {}
	for peer in server.players:
		var pl: Variant = server.players[peer]
		players[int(peer)] = {"pos": pl.position, "health": float(pl.survival.health)}
	return {"tick": last, "hash": ReplayRecorder.state_hash(server), "players": players,
		"zombies": server.zombies.size(), "server": server}


## {first, differing: [ticks], length_a, length_b}; first = -1 when identical.
static func diff_hashes(a_hashes: Array, b_hashes: Array) -> Dictionary:
	var differing: Array = []
	var shared: int = mini(a_hashes.size(), b_hashes.size())
	for i in range(shared):
		if int(a_hashes[i]) != int(b_hashes[i]):
			differing.append(i)
	for i in range(shared, maxi(a_hashes.size(), b_hashes.size())):
		differing.append(i)
	return {"first": ReplayRecorder.compare(a_hashes, b_hashes), "differing": differing,
		"length_a": a_hashes.size(), "length_b": b_hashes.size()}


## Replays and compares with reference hashes. {tick, expected, actual, commands} (tick -1 = none).
func find_first_divergence(rep: Dictionary, make_server: Callable, reference_hashes: Array) -> Dictionary:
	var res: Dictionary = ReplayRecorder.play(rep, make_server)
	var hashes: Array = res["hashes"]
	var tick: int = ReplayRecorder.compare(hashes, reference_hashes)
	var out: Dictionary = {"tick": tick, "expected": null, "actual": null, "commands": []}
	if tick >= 0:
		if tick < reference_hashes.size():
			out["expected"] = int(reference_hashes[tick])
		if tick < hashes.size():
			out["actual"] = int(hashes[tick])
		var frames: Array = rep.get("frames", [])
		if tick < frames.size():
			out["commands"] = (frames[tick] as Dictionary).get("commands", [])
	return out
