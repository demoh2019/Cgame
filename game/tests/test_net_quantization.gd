extends RefCounted
## Property-based boundary cases for bit-packed replicated coordinates.
const Quant = preload("res://scripts/shared/net_quantization.gd")


func run(t) -> void:
	t.current = "network scalar quantization remains bounded"
	t.eq(Quant.quantize_float(-100.0, 0.0, 1.0, 8), 0,
		"values below range saturate instead of wrapping")
	t.eq(Quant.quantize_float(100.0, 0.0, 1.0, 8), 255,
		"values above range saturate")
	t.eq(Quant.quantize_float(NAN, -1.0, 1.0, 8), 0,
		"invalid float never becomes a malformed bit pattern")
	t.eq(Quant.quantize_float(0.5, NAN, 1.0, 8), 0,
		"bad bounds do not enter fixed-point quantization")
	t.eq(Quant.dequantize_float(0, NAN, 1.0, 8), 0.0,
		"bad packet bounds never produce non-finite decoded values")
	t.near(Quant.dequantize_float(
		Quant.quantize_float(0.5, 0.0, 1.0, 8), 0.0, 1.0, 8),
		0.5, 0.5 / 255.0 + 0.00001, "8-bit normalized scalar error is bounded")
	t.eq(Quant.quantize_angle(INF, 12), 0,
		"corrupted angle normalizes to a safe neutral heading")
	t.eq(Quant.quantize_angle(TAU, 12), Quant.quantize_angle(0.0, 12),
		"full rotations wrap to the same network value")

	t.current = "three-axis packed coordinates round-trip without overflow"
	var lower := Vector3(-100.0, -10.0, -100.0)
	var upper := Vector3(100.0, 30.0, 100.0)
	var source := Vector3(-31.25, 2.75, 44.5)
	for bits in [1, 8, 12, 21]:
		var bytes: PackedByteArray = Quant.pack_vector3(source, lower, upper, bits)
		t.eq(bytes.size(), int(ceil(float(bits * 3) / 8.0)),
			"bit count %d has minimal payload length" % bits)
		var recovered: Vector3 = Quant.unpack_vector3(bytes, lower, upper, bits)
		# Error is bounded by half a quantization interval on each axis.
		# Use the 3D length of those half-steps, not one axis alone.
		var tolerance: float = (upper - lower).length() / 			(2.0 * float((1 << bits) - 1)) + 0.0001
		t.check(recovered.is_finite() and source.distance_to(recovered) <= tolerance,
			"coordinate error stays within each axis' quantization step at %d bits" % bits)
	var corner: PackedByteArray = Quant.pack_vector3(upper, lower, upper, 21)
	t.eq(Quant.unpack_vector3(corner, lower, upper, 21), upper,
		"63-bit all-ones packing handles signed int64 boundary correctly")

	t.current = "invalid position packets never become world transforms"
	var encoded: PackedByteArray = Quant.pack_vector3(source, lower, upper, 12)
	t.eq(Quant.unpack_vector3(PackedByteArray(), lower, upper, 12),
		Vector3.ZERO, "empty buffer is not treated as the world origin packet")
	var truncated: PackedByteArray = encoded.duplicate()
	truncated.resize(truncated.size() - 1)
	t.eq(Quant.unpack_vector3(truncated, lower, upper, 12),
		Vector3.ZERO, "truncated vector payload is rejected")
	var extended: PackedByteArray = encoded.duplicate()
	extended.append(255)
	t.eq(Quant.unpack_vector3(extended, lower, upper, 12),
		Vector3.ZERO, "oversized vector payload cannot shift beyond 64-bit data")
	var unused: PackedByteArray = Quant.pack_vector3(source, lower, upper, 9)
	unused[unused.size() - 1] |= 0xF8 # 27 valid bits: 5 unused high bits.
	t.eq(Quant.unpack_vector3(unused, lower, upper, 9),
		Vector3.ZERO, "non-zero padding bits reject corrupted payload")
	t.check(Quant.pack_vector3(Vector3.INF, lower, upper, 12).is_empty(),
		"invalid source coordinate never produces a sendable payload")
	t.check(Quant.pack_vector3(source, upper, lower, 12).is_empty(),
		"reversed ranges do not create invalid packed positions")
	t.eq(Quant.unpack_vector3(encoded, Vector3.INF, upper, 12),
		Vector3.ZERO, "invalid bounds never propagate into client transforms")
