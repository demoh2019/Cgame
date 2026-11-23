extends RefCounted
## Network property quantization (Quake 3 / Valve Source / Unreal replication style):
## floats become fixed-point integers over a known range, so max error is half a quantum.


static func _levels(bits: int) -> int:
	return (1 << clampi(bits, 1, 32)) - 1


static func quantize_float(v: float, min_v: float, max_v: float, bits: int) -> int:
	if not is_finite(v) or not is_finite(min_v) or not is_finite(max_v):
		return 0
	var span: float = max_v - min_v
	if not is_finite(span) or span <= 0.0:
		return 0
	var t: float = clampf((v - min_v) / span, 0.0, 1.0)
	return int(round(t * float(_levels(bits))))


static func dequantize_float(q: int, min_v: float, max_v: float, bits: int) -> float:
	if not is_finite(min_v) or not is_finite(max_v):
		return 0.0
	var span: float = max_v - min_v
	if not is_finite(span) or span <= 0.0:
		return min_v
	var levels: int = _levels(bits)
	var t: float = float(clampi(q, 0, levels)) / float(levels)
	return min_v + t * span


## Angles wrap into [0, TAU) and use `bits` bits with no duplicate endpoint.
static func quantize_angle(radians: float, bits: int) -> int:
	if not is_finite(radians):
		return 0
	var count: int = 1 << clampi(bits, 1, 32)
	var t: float = fposmod(radians, TAU) / TAU
	return int(round(t * float(count))) % count


static func dequantize_angle(q: int, bits: int) -> float:
	var count: int = 1 << clampi(bits, 1, 32)
	return float(posmod(q, count)) / float(count) * TAU


static func pack_vector3(v: Vector3, bounds_min: Vector3, bounds_max: Vector3, bits_per_axis: int) -> PackedByteArray:
	if not v.is_finite() or not bounds_min.is_finite() or not bounds_max.is_finite() 			or not (bounds_max - bounds_min).is_finite() 			or bounds_min.x >= bounds_max.x or bounds_min.y >= bounds_max.y 			or bounds_min.z >= bounds_max.z:
		return PackedByteArray()
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
	var total_bits: int = bits * 3
	var expected_bytes: int = int((total_bits + 7) / 8)
	# Do not interpret malformed lengths or high padding bits as a different
	# position. In particular, never shift packet data beyond the int64 range.
	if data.size() != expected_bytes or not bounds_min.is_finite() 			or not bounds_max.is_finite() or not (bounds_max - bounds_min).is_finite() 			or bounds_min.x >= bounds_max.x or bounds_min.y >= bounds_max.y 			or bounds_min.z >= bounds_max.z:
		return Vector3.ZERO
	if total_bits % 8 != 0 			and (int(data[data.size() - 1]) >> (total_bits % 8)) != 0:
		return Vector3.ZERO
	var packed: int = 0
	for i in data.size():
		packed |= int(data[i]) << (8 * i)
	var mask: int = (1 << bits) - 1
	return Vector3(
		dequantize_float((packed >> (bits * 2)) & mask, bounds_min.x, bounds_max.x, bits),
		dequantize_float((packed >> bits) & mask, bounds_min.y, bounds_max.y, bits),
		dequantize_float(packed & mask, bounds_min.z, bounds_max.z, bits))
