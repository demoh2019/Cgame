extends RefCounted
## Net serialization schema: field types, quantization, replication conditions, bit packing,
## changed-field mask and a schema hash for version checks.
##
## Concepts (not code) from: Quake 3 / Valve Source delta compression and quantization
## (GPL/Valve engines: ideas only, no code copied), Glenn Fiedler "Gaffer on Games" snapshot
## compression articles (technique reference), and Unreal Iris-style NetSerializer descriptors
## (concept only; no Unreal source used). Original implementation for Cgame; reuses the
## project's NetQuantization fixed-point math.

const NetQuantization = preload("res://scripts/shared/net_quantization.gd")

enum Cond { ALWAYS, OWNER_ONLY, INITIAL_ONLY, ON_CHANGE }

const TYPES: PackedStringArray = ["int", "float", "vec3", "quat", "bool", "string", "enum"]
const CONDITIONS: PackedStringArray = ["always", "owner_only", "initial_only", "on_change"]


class BitWriter extends RefCounted:
	var bytes: PackedByteArray = PackedByteArray()
	var bitpos: int = 0

	func write(value: int, n: int) -> void:
		for i in n:
			if (bitpos & 7) == 0:
				bytes.append(0)
			if ((value >> i) & 1) == 1:
				bytes[bytes.size() - 1] = bytes[bytes.size() - 1] | (1 << (bitpos & 7))
			bitpos += 1


class BitReader extends RefCounted:
	var bytes: PackedByteArray = PackedByteArray()
	var bitpos: int = 0
	var valid: bool = true

	func read(n: int) -> int:
		# A truncated packet is invalid, not a smaller (and potentially valid)
		# number. Check the complete field before consuming any of its bits.
		if not valid or n < 0 or n > bytes.size() * 8 - bitpos:
			valid = false
			return 0
		var v: int = 0
		for i in n:
			var byte_i: int = bitpos >> 3
			if ((bytes[byte_i] >> (bitpos & 7)) & 1) == 1:
				v |= 1 << i
			bitpos += 1
		return v


static func make_field(name: String, type: String, bits: int = 0, min_v: float = 0.0, max_v: float = 0.0, condition: String = "on_change") -> Dictionary:
	return {"name": name, "type": type, "bits": bits, "min": min_v, "max": max_v, "condition": condition}


static func bits_for_range(min_v: float, max_v: float) -> int:
	var count: int = int(max_v - min_v) + 1
	var b: int = 1
	while (1 << b) < count and b < 32:
		b += 1
	return b


## Derive a schema from a sample state. hints: {field: {type, bits, min, max, condition}}.
static func generate_from_sample(sample: Dictionary, hints: Dictionary = {}) -> Dictionary:
	var names: Array = sample.keys()
	names.sort()
	var fields: Array = []
	for key in names:
		var fname: String = str(key)
		var v: Variant = sample[key]
		var f: Dictionary = _infer_field(fname, v)
		if hints.has(fname):
			var h: Dictionary = hints[fname]
			for hk in h:
				f[hk] = h[hk]
			if h.has("min") or h.has("max"):
				if not h.has("bits") and (f["type"] == "int" or f["type"] == "enum"):
					f["bits"] = bits_for_range(float(f["min"]), float(f["max"]))
		fields.append(f)
	return {"fields": fields}


static func _infer_field(fname: String, v: Variant) -> Dictionary:
	match typeof(v):
		TYPE_BOOL:
			return make_field(fname, "bool", 1)
		TYPE_INT:
			return make_field(fname, "int", 32, -2147483648.0, 2147483647.0)
		TYPE_FLOAT:
			return make_field(fname, "float", 16, -1024.0, 1024.0)
		TYPE_VECTOR3:
			return make_field(fname, "vec3", 16, -1024.0, 1024.0)
		TYPE_QUATERNION:
			return make_field(fname, "quat", 12, -1.0, 1.0)
		TYPE_STRING, TYPE_STRING_NAME:
			return make_field(fname, "string", 8)
	return make_field(fname, "int", 32, -2147483648.0, 2147483647.0)


## Derive a schema from a script's exported/script variables (annotated by hints).
static func generate_from_script(script: Script, hints: Dictionary = {}) -> Dictionary:
	var sample: Dictionary = {}
	for p in script.get_script_property_list():
		var usage: int = int(p["usage"])
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var ptype: int = int(p["type"])
		var dv: Variant = null
		match ptype:
			TYPE_BOOL: dv = false
			TYPE_INT: dv = 0
			TYPE_FLOAT: dv = 0.0
			TYPE_VECTOR3: dv = Vector3.ZERO
			TYPE_QUATERNION: dv = Quaternion.IDENTITY
			TYPE_STRING: dv = ""
		if dv != null:
			sample[str(p["name"])] = dv
	return generate_from_sample(sample, hints)


static func schema_hash(schema: Dictionary) -> int:
	var parts: PackedStringArray = PackedStringArray()
	var fields: Array = schema["fields"]
	for f in fields:
		var fd: Dictionary = f
		parts.append("%s:%s:%d:%.6f:%.6f:%s" % [fd["name"], fd["type"], int(fd["bits"]), float(fd["min"]), float(fd["max"]), fd["condition"]])
	return ("|".join(parts)).hash() & 0xFFFFFFFF


static func _bits_of(f: Dictionary) -> int:
	var b: int = int(f["bits"])
	if f["type"] == "bool":
		return 1
	return clampi(b, 1, 32)


## Quantized representation of a field value: Array of ints (or [string]).
static func _quant(f: Dictionary, v: Variant) -> Array:
	var bits: int = _bits_of(f)
	var mn: float = float(f["min"])
	var mx: float = float(f["max"])
	match str(f["type"]):
		"bool":
			return [1 if bool(v) else 0]
		"int", "enum":
			var span: int = (1 << bits) - 1
			return [clampi(int(v) - int(mn), 0, span)]
		"float":
			return [NetQuantization.quantize_float(float(v), mn, mx, bits)]
		"vec3":
			var vv: Vector3 = v
			return [NetQuantization.quantize_float(vv.x, mn, mx, bits), NetQuantization.quantize_float(vv.y, mn, mx, bits), NetQuantization.quantize_float(vv.z, mn, mx, bits)]
		"quat":
			var q: Quaternion = v
			return [NetQuantization.quantize_float(q.x, -1.0, 1.0, bits), NetQuantization.quantize_float(q.y, -1.0, 1.0, bits), NetQuantization.quantize_float(q.z, -1.0, 1.0, bits), NetQuantization.quantize_float(q.w, -1.0, 1.0, bits)]
		"string":
			return [str(v).substr(0, 255)]
	return [0]


static func _dequant(f: Dictionary, q: Array) -> Variant:
	var bits: int = _bits_of(f)
	var mn: float = float(f["min"])
	var mx: float = float(f["max"])
	match str(f["type"]):
		"bool":
			return int(q[0]) == 1
		"int", "enum":
			return int(q[0]) + int(mn)
		"float":
			return NetQuantization.dequantize_float(int(q[0]), mn, mx, bits)
		"vec3":
			return Vector3(NetQuantization.dequantize_float(int(q[0]), mn, mx, bits), NetQuantization.dequantize_float(int(q[1]), mn, mx, bits), NetQuantization.dequantize_float(int(q[2]), mn, mx, bits))
		"quat":
			var r := Quaternion(NetQuantization.dequantize_float(int(q[0]), -1.0, 1.0, bits), NetQuantization.dequantize_float(int(q[1]), -1.0, 1.0, bits), NetQuantization.dequantize_float(int(q[2]), -1.0, 1.0, bits), NetQuantization.dequantize_float(int(q[3]), -1.0, 1.0, bits))
			return r.normalized() if r.length() > 0.0001 else Quaternion.IDENTITY
		"string":
			return str(q[0])
	return null


static func _write_field(w: BitWriter, f: Dictionary, q: Array) -> void:
	var bits: int = _bits_of(f)
	match str(f["type"]):
		"bool":
			w.write(int(q[0]), 1)
		"string":
			var raw: PackedByteArray = str(q[0]).to_utf8_buffer()
			var n: int = mini(raw.size(), 255)
			# Byte-limited network strings must end on a UTF-8 codepoint boundary.
			# Otherwise a long non-ASCII name is damaged when deserialized.
			while n < raw.size() and n > 0 and (raw[n] & 0xC0) == 0x80:
				n -= 1
			w.write(n, 8)
			for i in n:
				w.write(raw[i], 8)
		_:
			for x in q:
				w.write(int(x), bits)


static func _read_field(r: BitReader, f: Dictionary) -> Array:
	var bits: int = _bits_of(f)
	match str(f["type"]):
		"bool":
			return [r.read(1)]
		"string":
			var n: int = r.read(8)
			var raw: PackedByteArray = PackedByteArray()
			for i in n:
				raw.append(r.read(8))
			return [raw.get_string_from_utf8()]
		"vec3":
			return [r.read(bits), r.read(bits), r.read(bits)]
		"quat":
			return [r.read(bits), r.read(bits), r.read(bits), r.read(bits)]
	return [r.read(bits)]


## Whether a field is transmitted for this (baseline, ownership) context and has data to send.
static func _should_send(f: Dictionary, state: Dictionary, baseline: Dictionary, is_owner: bool) -> bool:
	var fname: String = str(f["name"])
	if not state.has(fname):
		return false
	var cond: String = str(f["condition"])
	if cond == "owner_only" and not is_owner:
		return false
	if cond == "initial_only":
		return baseline.is_empty() or not baseline.has(fname)
	if cond == "always":
		return true
	# on_change and owner_only (for the owner) are delta-coded against the baseline.
	if not baseline.has(fname):
		return true
	return _quant(f, state[fname]) != _quant(f, baseline[fname])


## Layout: one mask bit per schema field, then the present fields in schema order.
static func serialize(schema: Dictionary, state: Dictionary, baseline: Dictionary, is_owner: bool) -> PackedByteArray:
	var fields: Array = schema["fields"]
	var w := BitWriter.new()
	var send: Array[bool] = []
	for f in fields:
		var fd: Dictionary = f
		var s: bool = _should_send(fd, state, baseline, is_owner)
		send.append(s)
		w.write(1 if s else 0, 1)
	for i in fields.size():
		if send[i]:
			var fd2: Dictionary = fields[i]
			_write_field(w, fd2, _quant(fd2, state[fd2["name"]]))
	return w.bytes


## A valid empty delta and an invalid/truncated packet are not equivalent.
## Keep the public legacy Dictionary decoder while allowing versioned callers
## to fail closed instead of reporting "ok" for a damaged payload.
static func _deserialize_checked(schema: Dictionary, bytes: PackedByteArray, baseline: Dictionary) -> Dictionary:
	var fields: Array = schema["fields"]
	var r := BitReader.new()
	r.bytes = bytes
	var present: Array[bool] = []
	for f in fields:
		present.append(r.read(1) == 1)
	if not r.valid:
		return {"ok": false, "state": {}}
	var out: Dictionary = baseline.duplicate()
	for i in fields.size():
		if present[i]:
			var fd: Dictionary = fields[i]
			out[fd["name"]] = _dequant(fd, _read_field(r, fd))
			if not r.valid:
				return {"ok": false, "state": {}}
	var expected_bytes: int = int((r.bitpos + 7) / 8)
	if bytes.size() != expected_bytes:
		return {"ok": false, "state": {}}
	var used_bits: int = r.bitpos % 8
	if used_bits != 0 and not bytes.is_empty():
		var padding_mask: int = 0xFF << used_bits
		if (int(bytes[bytes.size() - 1]) & padding_mask) != 0:
			return {"ok": false, "state": {}}
	return {"ok": true, "state": out}


static func deserialize(schema: Dictionary, bytes: PackedByteArray, baseline: Dictionary) -> Dictionary:
	var decoded: Dictionary = _deserialize_checked(schema, bytes, baseline)
	if not bool(decoded["ok"]):
		return {}
	var state: Dictionary = decoded["state"]
	return state


## Versioned wrapper: 4-byte schema hash header followed by the payload.
static func serialize_versioned(schema: Dictionary, state: Dictionary, baseline: Dictionary, is_owner: bool) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, schema_hash(schema))
	out.append_array(serialize(schema, state, baseline, is_owner))
	return out


## Returns {ok: bool, state: Dictionary}; invalid headers and incomplete
## payloads are both rejected without mutating an existing baseline.
static func deserialize_versioned(schema: Dictionary, bytes: PackedByteArray, baseline: Dictionary) -> Dictionary:
	if bytes.size() < 4 or int(bytes.decode_u32(0)) != schema_hash(schema):
		return {"ok": false, "state": {}}
	return _deserialize_checked(schema, bytes.slice(4), baseline)
