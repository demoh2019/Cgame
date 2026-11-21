extends RefCounted
## Deterministic session recorder / replayer for the authoritative server.
##
## Records the inputs of a session (seed, world seed, initial players and, per tick, the
## delta plus every command) and re-runs them on a fresh server, returning a state hash per
## tick. Two runs of the same recording must produce identical hash lists; the first
## differing tick (see compare) pinpoints a determinism bug or a tampered recording.
##
## Technique credit: input-log deterministic replay and per-frame state checksums as used by
## lockstep/rollback engines (e.g. GGPO, MIT, https://github.com/pond3r/ggpo; Factorio-style
## desync detection). The state hash is 64-bit FNV-1a (public domain, Fowler/Noll/Vo).
## This file is original GDScript; no third-party code was copied.
##
## Only methods named "cmd_*" (client commands) and "submit_input" (the movement input path,
## which is not a cmd_ method in this server) may be replayed. Everything else (add_player,
## tick, restore, ...) is refused so a replay file cannot drive privileged server entry points.

const WorldPersistence = preload("res://scripts/server/world_persistence.gd")

const FORMAT_VERSION := 1
const FNV_OFFSET := -3750763034362895579 # 0xcbf29ce484222325 as signed int64
const FNV_PRIME := 0x100000001b3

var seed_value: int = 0
var world_seed: int = 0
var players: Array = [] # [{id:int, name:String}]
var frames: Array = [] # [{tick:int, delta:float, commands:[{peer,method,args}]}]

var _pending: Array = []
var _tick: int = 0


func _init(p_seed: int = 0, p_world_seed: int = 0) -> void:
	seed_value = p_seed
	world_seed = p_world_seed


func add_initial_player(peer: int, p_name: String) -> void:
	players.append({"id": peer, "name": p_name})


## Queues a command for the tick being recorded. Refused methods return false.
func record_command(peer: int, method: String, args: Array = []) -> bool:
	if not is_allowed_method(method):
		return false
	_pending.append({"peer": peer, "method": method, "args": args.duplicate(true)})
	return true


## Closes the current tick with the delta passed to server.tick().
func end_tick(delta: float) -> void:
	frames.append({"tick": _tick, "delta": delta, "commands": _pending})
	_pending = []
	_tick += 1


static func is_allowed_method(method: String) -> bool:
	return method.begins_with("cmd_") or method == "submit_input"


func to_dict() -> Dictionary:
	return {"format": FORMAT_VERSION, "seed": seed_value, "world_seed": world_seed,
		"players": players.duplicate(true), "frames": frames.duplicate(true)}


func save(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_var(to_dict(), false) # No objects: a replay file can never instantiate scripts.
	file.close()
	return true


## Returns the replay Dictionary, or {} when missing / malformed.
static func load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = file.get_var(false)
	file.close()
	if not (value is Dictionary):
		return {}
	var data: Dictionary = value
	if int(data.get("format", 0)) != FORMAT_VERSION or not (data.get("frames") is Array) \
			or not (data.get("players") is Array):
		return {}
	return data


## Re-runs a replay on make_server.call(seed, world_seed) -> GameServer.
## Returns {"hashes": Array (one int per tick), "rejected": Array[String], "ok": bool}.
static func play(replay: Dictionary, make_server: Callable) -> Dictionary:
	var hashes: Array = []
	var rejected: Array[String] = []
	if replay.is_empty() or not make_server.is_valid():
		return {"hashes": hashes, "rejected": rejected, "ok": false}
	var server: Object = make_server.call(int(replay.get("seed", 0)), int(replay.get("world_seed", 0)))
	if server == null:
		return {"hashes": hashes, "rejected": rejected, "ok": false}
	for p in replay.get("players", []):
		var info: Dictionary = p
		server.add_player(int(info.get("id", 0)), str(info.get("name", "")))
	for f in replay.get("frames", []):
		var frame: Dictionary = f
		for c in frame.get("commands", []):
			var cmd: Dictionary = c
			var method := str(cmd.get("method", ""))
			if not is_allowed_method(method) or not server.has_method(method):
				rejected.append("tick %d: %s" % [int(frame.get("tick", -1)), method])
				continue
			var call_args: Array = [int(cmd.get("peer", 0))]
			call_args.append_array(cmd.get("args", []))
			server.callv(method, call_args)
		server.tick(float(frame.get("delta", 0.0)))
		hashes.append(state_hash(server))
	return {"hashes": hashes, "rejected": rejected, "ok": rejected.is_empty()}


## 64-bit FNV-1a over a canonical (sorted-key) projection of the gameplay-relevant state.
static func state_hash(server) -> int:
	var peers: Array = server.players.keys()
	peers.sort()
	var projection: Array = []
	for peer in peers:
		var player = server.players[peer]
		projection.append({
			"id": int(peer),
			"pos": [snappedf(player.position.x, 0.0001), snappedf(player.position.y, 0.0001),
				snappedf(player.position.z, 0.0001)],
			"health": snappedf(float(player.survival.health), 0.0001),
			"inventory": player.inventory.to_dict(),
		})
	var world_state: Dictionary = WorldPersistence.capture(server)
	var blob := {"players": projection, "zombies": server.zombies.size(), "world": world_state}
	return _fnv1a(JSON.stringify(blob, "", true))


static func _fnv1a(text: String) -> int:
	var h: int = FNV_OFFSET
	for b in text.to_utf8_buffer():
		h = (h ^ int(b)) * FNV_PRIME # int64 wraparound is the intended modular multiply
	return h


## First tick index at which two hash lists differ (a length mismatch counts), else -1.
static func compare(a_hashes: Array, b_hashes: Array) -> int:
	var shared := mini(a_hashes.size(), b_hashes.size())
	for i in range(shared):
		if int(a_hashes[i]) != int(b_hashes[i]):
			return i
	if a_hashes.size() != b_hashes.size():
		return shared
	return -1
