extends RefCounted
## Replication of streaming state: each client reports which cells it has fully ready (see
## stream_readiness.gd) as a compact bitset over a window centred on its cell, delta-encoded
## (XOR) against the last report the server acknowledged. The server keeps per-client ready sets
## with versions, uses them for interest management (`server_relevant`) and rejects claims for
## cells the client cannot plausibly have loaded (anti-cheat).
##
## Packet loss: a report is always relative to the last ACKED version, never to the last sent one,
## so a lost report or lost ack only costs a slightly larger delta. If the server no longer has the
## base version it answers need_full and the client resends a full (base 0) report.
##
## Concept (not code) from UE replication graph / relevancy and delta-ack snapshot protocols (Quake
## 3 / Glenn Fiedler style). Original GDScript; no third-party code copied, so no license
## obligations.

const HEADER_BYTES: int = 17


static func window_side(radius: int) -> int:
	return radius * 2 + 1


static func bit_index(center: Vector2i, radius: int, cell: Vector2i) -> int:
	var dx := cell.x - center.x
	var dy := cell.y - center.y
	if absi(dx) > radius or absi(dy) > radius:
		return -1
	return (dy + radius) * window_side(radius) + (dx + radius)


static func in_window(center: Vector2i, radius: int, cell: Vector2i) -> bool:
	return bit_index(center, radius, cell) >= 0


static func bytes_for(radius: int) -> int:
	var n := window_side(radius)
	return (n * n + 7) / 8


## Sets of cells (Dictionary keyed by Vector2i) <-> bitset over the window.
static func encode_cells(center: Vector2i, radius: int, cells: Dictionary) -> PackedByteArray:
	var bits := PackedByteArray()
	bits.resize(bytes_for(radius))
	for cell: Vector2i in cells.keys():
		var i := bit_index(center, radius, cell)
		if i >= 0:
			bits[i >> 3] = bits[i >> 3] | (1 << (i & 7))
	return bits


static func decode_cells(center: Vector2i, radius: int, bits: PackedByteArray) -> Dictionary:
	var out: Dictionary = {}
	var n := window_side(radius)
	for i in n * n:
		if (bits[i >> 3] & (1 << (i & 7))) != 0:
			out[Vector2i(center.x - radius + i % n, center.y - radius + i / n)] = true
	return out


## Wire format: u32 version, u32 base, s32 cx, s32 cy, u8 radius, then the bitset.
static func serialize(packet: Dictionary) -> PackedByteArray:
	var bits: PackedByteArray = packet["bits"]
	var center: Vector2i = packet["center"]
	var buf := PackedByteArray()
	buf.resize(HEADER_BYTES)
	buf.encode_u32(0, int(packet["v"]))
	buf.encode_u32(4, int(packet["base"]))
	buf.encode_s32(8, center.x)
	buf.encode_s32(12, center.y)
	buf.encode_u8(16, int(packet["radius"]))
	buf.append_array(bits)
	return buf


static func deserialize(buf: PackedByteArray) -> Dictionary:
	if buf.size() < HEADER_BYTES:
		return {}
	var radius := buf.decode_u8(16)
	if buf.size() != HEADER_BYTES + bytes_for(radius):
		return {}
	return {
		"v": buf.decode_u32(0), "base": buf.decode_u32(4),
		"center": Vector2i(buf.decode_s32(8), buf.decode_s32(12)),
		"radius": radius, "bits": buf.slice(HEADER_BYTES),
	}


## Client side: tracks ready cells and builds delta reports.
class Client extends RefCounted:
	## Limit retained snapshots when ACKs are lost for a long time.
	const MAX_PENDING_REPORTS: int = 32
	var radius: int = 6
	var version: int = 0
	var acked_version: int = 0

	var _ready: Dictionary = {}
	var _acked: Dictionary = {}
	var _pending: Dictionary = {}
	var _force_full: bool = false

	static func _outer() -> GDScript:
		return load("res://scripts/shared/stream_state_replication.gd")

	func _init(report_radius: int = 6) -> void:
		radius = report_radius

	func set_ready(cell: Vector2i, is_ready: bool) -> void:
		if is_ready:
			_ready[cell] = true
		else:
			_ready.erase(cell)

	## The server lost our base: next report is a full one.
	func request_full() -> void:
		_force_full = true

	func build_report(center: Vector2i) -> Dictionary:
		var full := _force_full or acked_version == 0
		var base_set: Dictionary = {} if full else _acked
		var snap: Dictionary = {}
		for cell: Vector2i in _ready.keys():
			if _outer().in_window(center, radius, cell):
				snap[cell] = true
		var toggled: Dictionary = {}
		for cell: Vector2i in snap.keys():
			if not base_set.has(cell):
				toggled[cell] = true
		for cell: Vector2i in base_set.keys():
			if _outer().in_window(center, radius, cell) and not snap.has(cell):
				toggled[cell] = true
		version += 1
		_pending[version] = snap
		while _pending.size() > MAX_PENDING_REPORTS:
			_pending.erase(_pending.keys().min())
		_force_full = false
		return {
			"v": version, "base": 0 if full else acked_version, "center": center, "radius": radius,
			"bits": _outer().encode_cells(center, radius, toggled),
		}

	func on_ack(acked: int) -> void:
		if acked <= acked_version or not _pending.has(acked):
			return
		_acked = _pending[acked]
		acked_version = acked
		for v in _pending.keys():
			if int(v) <= acked:
				_pending.erase(v)


class ClientState extends RefCounted:
	var position: Vector2i = Vector2i.ZERO
	var has_position: bool = false
	var version: int = 0
	var effective: Dictionary = {}
	var history: Dictionary = {}
	var violations: int = 0
	var flagged: bool = false


## Max Chebyshev distance (cells) from the server-known client cell for a ready claim to count.
var allowed_radius: int = 6
var max_report_radius: int = 8
## How far the reported window centre may be from the server-known cell.
var max_center_error: int = 2
var history_size: int = 8
var violation_limit: int = 8

var _clients: Dictionary = {}


func set_client_position(client: Variant, cell: Vector2i) -> void:
	var s := _state(client)
	s.position = cell
	s.has_position = true


func remove_client(client: Variant) -> void:
	_clients.erase(client)


## Applies a report. Returns {ok, ack, reason, need_full, stripped}. `ack` is what the server wants
## sent back to the client (the newest applied version).
func apply_report(client: Variant, packet: Dictionary) -> Dictionary:
	var s := _state(client)
	var res := {"ok": false, "ack": s.version, "reason": "", "need_full": false, "stripped": 0}
	# Validate untrusted network data before typed reads and array indexing.
	if typeof(packet.get("bits")) != TYPE_PACKED_BYTE_ARRAY \
			or typeof(packet.get("center")) != TYPE_VECTOR2I \
			or typeof(packet.get("radius")) != TYPE_INT \
			or typeof(packet.get("v")) != TYPE_INT \
			or typeof(packet.get("base")) != TYPE_INT:
		res["reason"] = "malformed"
		return _violate(s, res)
	var radius: int = int(packet["radius"])
	var center: Vector2i = packet["center"]
	var bits: PackedByteArray = packet["bits"]
	var version: int = int(packet["v"])
	var base: int = int(packet["base"])
	if radius < 0 or radius > max_report_radius or bits.size() != bytes_for(radius) \
			or version <= 0 or base < 0 or base >= version:
		res["reason"] = "malformed"
		return _violate(s, res)
	if version <= s.version:
		res["reason"] = "old"
		return res
	if not s.has_position:
		res["reason"] = "no_position"
		return res
	if maxi(absi(center.x - s.position.x), absi(center.y - s.position.y)) > max_center_error:
		res["reason"] = "center"
		return _violate(s, res)
	var base_set: Dictionary = {}
	if base != 0:
		if not s.history.has(base):
			res["reason"] = "need_full"
			res["need_full"] = true
			return res
		base_set = s.history[base]
	# raw = (base restricted to the window) XOR delta
	var raw: Dictionary = {}
	for cell: Vector2i in base_set.keys():
		if in_window(center, radius, cell):
			raw[cell] = true
	for cell: Vector2i in decode_cells(center, radius, bits).keys():
		if raw.has(cell):
			raw.erase(cell)
		else:
			raw[cell] = true
	var effective: Dictionary = {}
	var stripped := 0
	for cell: Vector2i in raw.keys():
		if maxi(absi(cell.x - s.position.x), absi(cell.y - s.position.y)) > allowed_radius:
			stripped += 1
		else:
			effective[cell] = true
	s.version = version
	s.effective = effective
	s.history[version] = raw
	while s.history.size() > history_size:
		var oldest: int = s.history.keys().min()
		s.history.erase(oldest)
	res["ok"] = true
	res["ack"] = version
	res["stripped"] = stripped
	if stripped > 0:
		res["reason"] = "stripped"
		_violate(s, res)
		res["ok"] = true
	return res


func _violate(s: ClientState, res: Dictionary) -> Dictionary:
	s.violations += 1
	if s.violations >= violation_limit:
		s.flagged = true
	return res


func ack_version(client: Variant) -> int:
	return _state(client).version


func ready_set(client: Variant) -> Dictionary:
	return _state(client).effective


func is_ready(client: Variant, cell: Vector2i) -> bool:
	return _state(client).effective.has(cell)


func violations(client: Variant) -> int:
	return _state(client).violations


func is_flagged(client: Variant) -> bool:
	return _state(client).flagged


## Interest management: the subset of `cells_of_interest` the client has confirmed ready.
func server_relevant(client: Variant, cells_of_interest: Array) -> Array[Vector2i]:
	var s := _state(client)
	var out: Array[Vector2i] = []
	for cell: Vector2i in cells_of_interest:
		if s.effective.has(cell):
			out.append(cell)
	return out


## The subset of `cells_of_interest` the client has NOT confirmed (hold back state for these).
func server_missing(client: Variant, cells_of_interest: Array) -> Array[Vector2i]:
	var s := _state(client)
	var out: Array[Vector2i] = []
	for cell: Vector2i in cells_of_interest:
		if not s.effective.has(cell):
			out.append(cell)
	return out


func _state(client: Variant) -> ClientState:
	if not _clients.has(client):
		_clients[client] = ClientState.new()
	return _clients[client]
