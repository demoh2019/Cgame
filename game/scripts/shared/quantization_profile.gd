extends RefCounted
## Editable data model for per-field network quantization: error bounds, bandwidth cost,
## bit suggestions for a target error, JSON import/export.
##
## Original implementation (fixed-point error = half a quantum, as in Quake 3 / Source
## style quantization; concept only). Pairs with net_schema.gd.

const NetSchema = preload("res://scripts/shared/net_schema.gd")

var fields: Dictionary = {}  # name -> {type, bits, min, max}


func set_field(fname: String, type: String, bits: int, min_v: float, max_v: float) -> void:
	fields[fname] = {"type": type, "bits": bits, "min": min_v, "max": max_v}


func set_bits(fname: String, bits: int) -> void:
	if fields.has(fname):
		var f: Dictionary = fields[fname]
		f["bits"] = clampi(bits, 1, 32)


func from_schema(schema: Dictionary) -> void:
	fields.clear()
	var sf: Array = schema["fields"]
	for f in sf:
		var fd: Dictionary = f
		set_field(str(fd["name"]), str(fd["type"]), int(fd["bits"]), float(fd["min"]), float(fd["max"]))


## Writes the edited bits/ranges back into a schema (matching by name).
func apply_to_schema(schema: Dictionary) -> void:
	var sf: Array = schema["fields"]
	for f in sf:
		var fd: Dictionary = f
		var key: String = str(fd["name"])
		if fields.has(key):
			var p: Dictionary = fields[key]
			fd["bits"] = p["bits"]
			fd["min"] = p["min"]
			fd["max"] = p["max"]


func _is_quantized(type: String) -> bool:
	return type == "float" or type == "vec3" or type == "quat"


## Max absolute error per component (half a quantum); integer-like types are exact.
func max_error(fname: String) -> float:
	var f: Dictionary = fields[fname]
	var type: String = str(f["type"])
	if not _is_quantized(type):
		return 0.0
	var mn: float = float(f["min"])
	var mx: float = float(f["max"])
	if type == "quat":
		mn = -1.0
		mx = 1.0
	var levels: float = float((1 << clampi(int(f["bits"]), 1, 32)) - 1)
	return (mx - mn) / levels * 0.5


func bits_per_update(fname: String) -> int:
	var f: Dictionary = fields[fname]
	var b: int = clampi(int(f["bits"]), 1, 32)
	match str(f["type"]):
		"bool":
			return 1
		"vec3":
			return b * 3
		"quat":
			return b * 4
		"string":
			return 8 + 8 * b  # length byte + b reserved characters (estimate)
	return b


func total_bits() -> int:
	var t: int = 0
	for k in fields:
		t += bits_per_update(str(k))
	return t


## Estimated bandwidth in bytes/second for `entities` each sending all fields at `hz`.
func bandwidth_bytes_per_sec(hz: float, entities: int = 1) -> float:
	return float(total_bits()) / 8.0 * hz * float(entities)


## Smallest bit count whose max error is <= target_error.
func suggest_bits(fname: String, target_error: float) -> int:
	var f: Dictionary = fields[fname]
	if not _is_quantized(str(f["type"])) or target_error <= 0.0:
		return clampi(int(f["bits"]), 1, 32)
	var mn: float = float(f["min"])
	var mx: float = float(f["max"])
	if str(f["type"]) == "quat":
		mn = -1.0
		mx = 1.0
	for b in range(1, 33):
		var levels: float = float((1 << b) - 1)
		if (mx - mn) / levels * 0.5 <= target_error:
			return b
	return 32


func to_json() -> String:
	return JSON.stringify(fields, "\t", true)


func from_json(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	fields.clear()
	for k in d:
		var f: Dictionary = d[k]
		set_field(str(k), str(f["type"]), int(f["bits"]), float(f["min"]), float(f["max"]))
	return true


static func max_error_for(span: float, bits: int) -> float:
	return span / float((1 << clampi(bits, 1, 32)) - 1) * 0.5
