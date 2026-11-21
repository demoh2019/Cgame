extends RefCounted
## World sharding planner: grid regions -> zone servers, load rebalancing with hysteresis,
## ghost (interest) replication near borders and an idempotent two-step player handoff.
##
## Original GDScript implementation. Design references (concepts only, no code copied):
##   - SpatialOS workers/entity authority & ghost "checkout" model (Improbable docs).
##   - EVE Online node-per-solar-system model and Albion Online zone servers.
##   - Greedy longest-processing-time (LPT) scheduling for balanced assignment.
## No third-party code included.

var cell_size: float = 100.0
var cols: int = 4
var rows: int = 4
var server_count: int = 2
var border_margin: float = 15.0        ## ghost replication distance to neighbour regions
var handoff_hysteresis: float = 3.0    ## player must be this far inside the new region
var imbalance_ratio: float = 1.25      ## rebalance only if hottest > coldest * ratio
var max_moves: int = 8

var region_owner: PackedInt32Array = PackedInt32Array()
var entity_owner: Dictionary = {}      ## entity id -> server
var players: Dictionary = {}           ## player id -> {pos, state, transfer, ghosts}
var transfers: Dictionary = {}         ## transfer id -> {player, from, to, state, payload}


func setup(p_cols: int, p_rows: int, p_cell: float, p_servers: int) -> void:
	cols = p_cols
	rows = p_rows
	cell_size = p_cell
	server_count = maxi(1, p_servers)
	region_owner = PackedInt32Array()
	region_owner.resize(cols * rows)


func region_count() -> int:
	return cols * rows


func region_of(pos: Vector2) -> int:
	var cx := clampi(int(floor(pos.x / cell_size)), 0, cols - 1)
	var cy := clampi(int(floor(pos.y / cell_size)), 0, rows - 1)
	return cy * cols + cx


func owner_at(pos: Vector2) -> int:
	return region_owner[region_of(pos)]


func server_loads(loads: Array) -> Array:
	var out: Array = []
	out.resize(server_count)
	out.fill(0.0)
	for r in region_count():
		var s: int = region_owner[r]
		out[s] = float(out[s]) + _load(loads, r)
	return out


func _load(loads: Array, r: int) -> float:
	return float(loads[r]) if r < loads.size() else 0.0


## Greedy LPT: heaviest regions first onto the least-loaded server (ties: fewest regions).
func assign_initial(loads: Array) -> void:
	var order: Array = range(region_count())
	order.sort_custom(func(a: int, b: int) -> bool:
		if _load(loads, a) != _load(loads, b):
			return _load(loads, a) > _load(loads, b)
		return a < b)
	var sload: Array = []
	var scount: Array = []
	for i in server_count:
		sload.append(0.0)
		scount.append(0)
	for r in order:
		var best := 0
		for s in range(1, server_count):
			if float(sload[s]) < float(sload[best]) \
					or (float(sload[s]) == float(sload[best]) and int(scount[s]) < int(scount[best])):
				best = s
		region_owner[r] = best
		sload[best] = float(sload[best]) + _load(loads, r)
		scount[best] = int(scount[best]) + 1


## Returns [{region, from, to}] and applies them. Does nothing while loads are within the
## hysteresis band, and only moves a region when that strictly lowers the peak load.
func rebalance(loads: Array) -> Array:
	var moves: Array = []
	for _i in max_moves:
		var sl := server_loads(loads)
		var hot := 0
		var cold := 0
		for s in server_count:
			if float(sl[s]) > float(sl[hot]):
				hot = s
			if float(sl[s]) < float(sl[cold]):
				cold = s
		var hl: float = float(sl[hot])
		var cl: float = float(sl[cold])
		if hot == cold or hl <= cl * imbalance_ratio or hl <= 0.0:
			break
		var gap := hl - cl
		var pick := -1
		var pick_err := INF
		for r in region_count():
			if region_owner[r] != hot:
				continue
			var rl := _load(loads, r)
			if rl <= 0.0 or rl >= gap:
				continue
			var err := absf(rl - gap * 0.5)
			if err < pick_err:
				pick_err = err
				pick = r
		if pick < 0:
			break
		region_owner[pick] = cold
		moves.append({"region": pick, "from": hot, "to": cold})
	return moves


# ------------------------------------------------------------------ ownership/ghosts

func claim_entity(entity_id: String, server: int) -> void:
	entity_owner[entity_id] = server


func owner_of(entity_id: String) -> int:
	return int(entity_owner.get(entity_id, -1))


func entities_on(server: int) -> Array:
	var out: Array = []
	for id in entity_owner.keys():
		if int(entity_owner[id]) == server:
			out.append(id)
	return out


## Servers (other than `owner`) whose regions fall within border_margin of pos.
func ghost_servers(pos: Vector2, owner: int) -> Array:
	var out: Array = []
	var x0 := clampi(int(floor((pos.x - border_margin) / cell_size)), 0, cols - 1)
	var x1 := clampi(int(floor((pos.x + border_margin) / cell_size)), 0, cols - 1)
	var y0 := clampi(int(floor((pos.y - border_margin) / cell_size)), 0, rows - 1)
	var y1 := clampi(int(floor((pos.y + border_margin) / cell_size)), 0, rows - 1)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var s: int = region_owner[cy * cols + cx]
			if s != owner and not out.has(s):
				out.append(s)
	out.sort()
	return out


## Target server if the player should be handed off, else -1.
func handoff_needed(player_pos: Vector2, current_server: int) -> int:
	var target := owner_at(player_pos)
	if target == current_server:
		return -1
	for off in [Vector2(handoff_hysteresis, 0), Vector2(-handoff_hysteresis, 0),
			Vector2(0, handoff_hysteresis), Vector2(0, -handoff_hysteresis)]:
		if owner_at(player_pos + off) == current_server:
			return -1  # still hugging the old border: avoid ping-pong
	return target


func track_player(player_id: String, pos: Vector2, server: int) -> void:
	players[player_id] = {"pos": pos, "state": "stable", "transfer": "",
		"ghosts": ghost_servers(pos, server)}
	entity_owner[player_id] = server


## Moves the player; returns {"ghosts": Array, "handoff_to": int}.
func update_player(player_id: String, pos: Vector2) -> Dictionary:
	if not players.has(player_id):
		return {"ghosts": [], "handoff_to": -1}
	var p: Dictionary = players[player_id]
	p["pos"] = pos
	var srv := owner_of(player_id)
	p["ghosts"] = ghost_servers(pos, srv)
	var target := -1
	if String(p["state"]) == "stable":
		target = handoff_needed(pos, srv)
	return {"ghosts": p["ghosts"], "handoff_to": target}


# ------------------------------------------------------------ two-step handoff
# stable -> frozen (begin) -> transferring (send_state) -> acked (ack) -> stable on new owner (release)

## Freezes the player. Idempotent per transfer id; returns the id or "" if rejected.
func begin_transfer(player_id: String, to_server: int, transfer_id: String) -> String:
	if transfers.has(transfer_id):
		return transfer_id  # duplicate request: ignored, no state change
	if not players.has(player_id):
		return ""
	var p: Dictionary = players[player_id]
	if String(p["state"]) != "stable":
		return ""
	var from := owner_of(player_id)
	if from == to_server:
		return ""
	transfers[transfer_id] = {"player": player_id, "from": from, "to": to_server,
		"state": "frozen", "payload": {}}
	p["state"] = "frozen"
	p["transfer"] = transfer_id
	return transfer_id


func send_state(transfer_id: String, payload: Dictionary) -> bool:
	if not transfers.has(transfer_id):
		return false
	var tr: Dictionary = transfers[transfer_id]
	if String(tr["state"]) != "frozen":
		return String(tr["state"]) != "aborted"  # already past this step: idempotent
	tr["payload"] = payload.duplicate(true)
	tr["state"] = "transferring"
	return true


## Destination confirms it has the state.
func ack_transfer(transfer_id: String) -> bool:
	if not transfers.has(transfer_id):
		return false
	var tr: Dictionary = transfers[transfer_id]
	var st := String(tr["state"])
	if st == "transferring":
		tr["state"] = "acked"
		return true
	return st == "acked" or st == "done"


## Source releases authority; ownership flips to the destination. Idempotent.
func release_transfer(transfer_id: String) -> bool:
	if not transfers.has(transfer_id):
		return false
	var tr: Dictionary = transfers[transfer_id]
	var st := String(tr["state"])
	if st == "done":
		return true
	if st != "acked":
		return false
	var pid := String(tr["player"])
	entity_owner[pid] = int(tr["to"])
	var p: Dictionary = players[pid]
	p["state"] = "stable"
	p["transfer"] = ""
	p["ghosts"] = ghost_servers(p["pos"], int(tr["to"]))
	tr["state"] = "done"
	return true


## Cancels an unfinished transfer (e.g. destination timeout); player unfreezes on the source.
func abort_transfer(transfer_id: String) -> bool:
	if not transfers.has(transfer_id):
		return false
	var tr: Dictionary = transfers[transfer_id]
	var st := String(tr["state"])
	if st == "done" or st == "aborted":
		return false
	tr["state"] = "aborted"
	var p: Dictionary = players[String(tr["player"])]
	p["state"] = "stable"
	p["transfer"] = ""
	return true
