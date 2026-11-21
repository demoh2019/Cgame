extends RefCounted
## Network property quantization (Quake 3 / Valve Source / Unreal replication style):
## floats become fixed-point integers over a known range, so max error is half a quantum.


static func _levels(bits: int) -> int:
	return (1 << clampi(bits, 1, 32)) - 1


static func quantize_float(v: float, min_v: float, max_v: float, bits: int) -> int:
	var span: float = max_v - min_v
	if span <= 0.0:
		return 0
	var t: float = clampf((v - min_v) / span, 0.0, 1.0)
	return int(round(t * float(_levels(bits))))


static func dequantize_float(q: int, min_v: float, max_v: float, bits: int) -> float:
	var levels: int = _levels(bits)
	var t: float = float(clampi(q, 0, levels)) / float(levels)
	return min_v + t * (max_v - min_v)


## Angles wrap into [0, TAU) and use `bits` bits with no duplicate endpoint.
static func quantize_angle(radians: float, bits: int) -> int:
	var count: int = 1 << clampi(bits, 1, 32)
	var t: float = fposmod(radians, TAU) / TAU
	return int(round(t * float(count))) % count


static func dequantize_angle(q: int, bits: int) -> float:
	var count: int = 1 << clampi(bits, 1, 32)
	return float(posmod(q, count)) / float(count) * TAU


static func pack_vector3(v: Vector3, bounds_min: Vector3, bounds_max: Vector3, bits_per_axis: int) -> PackedByteArray:
	var bits: int = clampi(bits_per_axis, 1, 21)
	var qs: Array[int] = [
		quantize_float(v.x, bounds_min.x, bounds_max.x, bits),
		quantize_float(v.y, bounds_min.y, bounds_max.y, bits),
		quantize_float(v.z, bounds_min.z, bounds_max.z, bits),
	]
	var packed: int = (qs[0] << (bits * 2)) | (qs[1] << bits) | qs[2]
	var total_bits: int = bits * 3
	var out := PackedByteArray()
	out.resize((total_bits + 7) / 8)
	for i in out.size():
		out[i] = (packed >> (8 * i)) & 0xFF
	return out


static func unpack_vector3(data: PackedByteArray, bounds_min: Vector3, bounds_max: Vector3, bits_per_axis: int) -> Vector3:
	var bits: int = clampi(bits_per_axis, 1, 21)
	var packed: int = 0
	for i in data.size():
		packed |= int(data[i]) << (8 * i)
	var mask: int = (1 << bits) - 1
	return Vector3(
		dequantize_float((packed >> (bits * 2)) & mask, bounds_min.x, bounds_max.x, bits),
		dequantize_float((packed >> bits) & mask, bounds_min.y, bounds_max.y, bits),
		dequantize_float(packed & mask, bounds_min.z, bounds_max.z, bits))
