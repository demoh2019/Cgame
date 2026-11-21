extends RefCounted
## Compact replication of mass destruction state.
##
## One class serves both ends: the server calls apply_damage() and delta_since();
## a client mirror calls apply_delta(). State per object is tiny (quantised health
## bucket, fractured flag, deterministic fracture seed, broken-chunk bitmask) and
## is sent as ABSOLUTE values, so a delta is idempotent and a lost/duplicated
## packet only costs bandwidth, never correctness.
##
## Design follows the usual snapshot-delta pattern (per-entity change version vs
## client-acked baseline, varint + bit-packed encoding as in Quake 3 / Valve
## Source / Glenn Fiedler's "Snapshot Compression" articles) - common
## technique, no third-party code. Varints are LEB128 (public domain format).
##
## Wire format: varint target_version, varint baseline_version, varint count,
## then per object: varint (id - previous_id - 1), byte flags
## (bits 0-3 health bucket, bit 4 fractured), and when fractured a varint
## fracture_seed (24 bit) and varint broken_chunks (32 bit mask).

enum Result { APPLIED, STALE, GAP, MALFORMED }

const BUCKETS := 15
const CHUNKS := 32
const FRACTURE_FRACTION := 0.5
const SEED_MASK := 0xFFFFFF
const FLAG_FRACTURED := 16

var version := 0
var world_seed := 1

# Per-object state (index == object id).
var _bucket := PackedByteArray()
var _fractured := PackedByteArray()
var _seed := PackedInt32Array()
var _mask := PackedInt32Array()
var _obj_version := PackedInt32Array()
# Server only.
var _health := PackedFloat32Array()
var _max_health := PackedFloat32Array()

var _fracture_events: Array[Dictionary] = []
var _destroyed_events: Array[int] = []

var bytes_sent := 0
var deltas_sent := 0
var objects_sent := 0
var bytes_received := 0
var deltas_applied := 0
var deltas_rejected := 0


func setup(count: int, p_world_seed: int = 1) -> void:
	world_seed = p_world_seed
	version = 0
	_bucket.resize(count)
	_bucket.fill(BUCKETS)
	_fractured.resize(count)
	_fractured.fill(0)
	_seed.resize(count)
	_seed.fill(0)
	_mask.resize(count)
	_mask.fill(0)
	_obj_version.resize(count)
	_obj_version.fill(0)
	_health.resize(count)
	_max_health.resize(count)
	_max_health.fill(100.0)
	_health.fill(100.0)


func object_count() -> int:
	return _bucket.size()


func set_max_health(id: int, hp: float) -> void:
	_max_health[id] = maxf(hp, 1.0)
	_health[id] = _max_health[id]


# ------------------------------------------------------------------ queries

func health_bucket(id: int) -> int:
	return _bucket[id]


func health_fraction(id: int) -> float:
	return float(_bucket[id]) / float(BUCKETS)


func is_fractured(id: int) -> bool:
	return _fractured[id] != 0


func is_destroyed(id: int) -> bool:
	return _bucket[id] == 0


func fracture_seed(id: int) -> int:
	return _seed[id]


func broken_chunks(id: int) -> int:
	return _mask[id]


## Fracture events (id, seed, mask) since last call: clients spawn identical debris from them.
func consume_fracture_events() -> Array[Dictionary]:
	var out := _fracture_events.duplicate()
	_fracture_events.clear()
	return out


## Ids that reached health 0 since last call: feed to NavmeshCarving.on_destroyed().
func consume_destroyed() -> Array[int]:
	var out := _destroyed_events.duplicate()
	_destroyed_events.clear()
	return out


# ------------------------------------------------------------------- server

## Deterministic seed: every peer derives the same debris layout from (world, id, quantised impact).
static func make_fracture_seed(p_world_seed: int, id: int, impact_point: Vector2) -> int:
	var qx := int(roundf(impact_point.x * 4.0))
	var qy := int(roundf(impact_point.y * 4.0))
	var h := _mix(p_world_seed ^ 0x9E3779B1)
	h = _mix(h ^ (id * 0x85EBCA6B))
	h = _mix(h ^ (qx * 0xC2B2AE35))
	h = _mix(h ^ (qy * 0x27D4EB2F))
	return h & SEED_MASK


## Initial set of broken chunks for a fresh fracture (about a quarter of them).
static func initial_chunk_mask(p_seed: int) -> int:
	var m := 0
	var h := _mix(p_seed)
	for i in CHUNKS:
		h = _mix(h + i)
		if (h & 3) == 0:
			m |= 1 << i
	return m


static func chunk_for_impact(p_seed: int, impact_point: Vector2) -> int:
	var h := _mix(p_seed ^ (int(roundf(impact_point.x * 4.0)) * 0x9E3779B1))
	h = _mix(h ^ (int(roundf(impact_point.y * 4.0)) * 0x85EBCA6B))
	return h % CHUNKS


## Applies damage on the server. Returns true if replicated state changed.
func apply_damage(id: int, amount: float, impact_point: Vector2 = Vector2.ZERO) -> bool:
	if id < 0 or id >= _bucket.size() or amount <= 0.0 or _bucket[id] == 0:
		return false
	_health[id] = maxf(_health[id] - amount, 0.0)
	var frac := _health[id] / _max_health[id]
	var nb := 0 if _health[id] <= 0.0 else clampi(ceili(frac * BUCKETS), 1, BUCKETS)
	var changed := nb != _bucket[id]
	_bucket[id] = nb
	if _fractured[id] == 0 and (frac <= FRACTURE_FRACTION or nb == 0):
		_fractured[id] = 1
		_seed[id] = make_fracture_seed(world_seed, id, impact_point)
		_mask[id] = initial_chunk_mask(_seed[id])
		_fracture_events.append({"id": id, "seed": _seed[id], "mask": _mask[id]})
		changed = true
	elif _fractured[id] != 0:
		var before := _mask[id]
		_mask[id] |= 1 << chunk_for_impact(_seed[id], impact_point)
		if amount >= _max_health[id] * 0.25:
			_mask[id] |= 1 << ((chunk_for_impact(_seed[id], impact_point) + 1) % CHUNKS)
		if nb == 0:
			_mask[id] = -1 & 0xFFFFFFFF
		changed = changed or _mask[id] != before
	if nb == 0:
		_destroyed_events.append(id)
	if changed:
		version += 1
		_obj_version[id] = version
	return changed


## Encodes every object changed after baseline_version (the client's acked version).
func delta_since(baseline_version: int) -> PackedByteArray:
	var out := PackedByteArray()
	_put_varint(out, version)
	_put_varint(out, baseline_version)
	var body := PackedByteArray()
	var count := 0
	var prev := -1
	for id in _obj_version.size():
		if _obj_version[id] <= baseline_version:
			continue
		_put_varint(body, id - prev - 1)
		prev = id
		var flags: int = _bucket[id]
		if _fractured[id] != 0:
			flags |= FLAG_FRACTURED
		body.append(flags)
		if _fractured[id] != 0:
			_put_varint(body, _seed[id])
			_put_varint(body, _mask[id] & 0xFFFFFFFF)
		count += 1
	_put_varint(out, count)
	out.append_array(body)
	bytes_sent += out.size()
	deltas_sent += 1
	objects_sent += count
	return out


## Size of a full-state packet, for bandwidth comparison.
func full_state_size() -> int:
	return delta_size_only(0)


func delta_size_only(baseline_version: int) -> int:
	var sent := bytes_sent
	var ds := deltas_sent
	var osent := objects_sent
	var n := delta_since(baseline_version).size()
	bytes_sent = sent
	deltas_sent = ds
	objects_sent = osent
	return n


func stats() -> Dictionary:
	return {
		"bytes_sent": bytes_sent,
		"deltas_sent": deltas_sent,
		"objects_sent": objects_sent,
		"avg_bytes_per_delta": 0.0 if deltas_sent == 0 else float(bytes_sent) / float(deltas_sent),
		"bytes_received": bytes_received,
		"deltas_applied": deltas_applied,
		"deltas_rejected": deltas_rejected,
	}


# ------------------------------------------------------------------- client

## Applies a delta. Stale/duplicate deltas (target <= our version) are ignored; a delta whose
## baseline is newer than what we hold would skip history and is rejected (GAP: ack the
## old version again so the server resends from there).
func apply_delta(bytes: PackedByteArray) -> Result:
	bytes_received += bytes.size()
	var cur := [0]
	var target := _get_varint(bytes, cur)
	var baseline := _get_varint(bytes, cur)
	var count := _get_varint(bytes, cur)
	if target < 0 or baseline < 0 or count < 0:
		deltas_rejected += 1
		return Result.MALFORMED
	if target <= version:
		deltas_rejected += 1
		return Result.STALE
	if baseline > version:
		deltas_rejected += 1
		return Result.GAP
	var prev := -1
	var staged: Array[Dictionary] = []
	for i in count:
		var gap := _get_varint(bytes, cur)
		if gap < 0 or cur[0] >= bytes.size():
			deltas_rejected += 1
			return Result.MALFORMED
		var id := prev + gap + 1
		prev = id
		var flags: int = bytes[cur[0]]
		cur[0] += 1
		var sd := 0
		var mk := 0
		if flags & FLAG_FRACTURED:
			sd = _get_varint(bytes, cur)
			mk = _get_varint(bytes, cur)
		if sd < 0 or mk < 0 or id >= _bucket.size():
			deltas_rejected += 1
			return Result.MALFORMED
		staged.append({"id": id, "flags": flags, "seed": sd, "mask": mk})
	for s in staged:
		var oid: int = s["id"]
		var fl: int = s["flags"]
		var was_fractured := _fractured[oid] != 0
		var was_alive := _bucket[oid] != 0
		_bucket[oid] = fl & 15
		if fl & FLAG_FRACTURED:
			_fractured[oid] = 1
			_seed[oid] = s["seed"]
			_mask[oid] = s["mask"]
			if not was_fractured:
				_fracture_events.append({"id": oid, "seed": _seed[oid], "mask": _mask[oid]})
		if was_alive and _bucket[oid] == 0:
			_destroyed_events.append(oid)
		_obj_version[oid] = target
	version = target
	deltas_applied += 1
	return Result.APPLIED


# ------------------------------------------------------------------ helpers

static func _mix(x: int) -> int:
	x &= 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	return (x ^ (x >> 16)) & 0xFFFFFFFF


static func _put_varint(out: PackedByteArray, value: int) -> void:
	var v := value
	while v >= 0x80:
		out.append((v & 0x7F) | 0x80)
		v >>= 7
	out.append(v)


## Reads a varint at cur[0]; returns -1 on truncation.
static func _get_varint(bytes: PackedByteArray, cur: Array) -> int:
	var result := 0
	var shift := 0
	var pos: int = cur[0]
	while pos < bytes.size() and shift <= 35:
		var b: int = bytes[pos]
		pos += 1
		result |= (b & 0x7F) << shift
		if b < 0x80:
			cur[0] = pos
			return result
		shift += 7
	return -1
