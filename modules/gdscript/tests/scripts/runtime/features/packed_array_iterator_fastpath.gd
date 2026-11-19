# Packed-array loop bytecode regression: optimized direct reads must preserve
# first, middle, last, empty, and single-element iteration semantics.

func _sum_byte(a: PackedByteArray) -> int:
	var total: int = 0
	for item in a:
		total += item
	return total

func _sum_int32(a: PackedInt32Array) -> int:
	var total: int = 0
	for item in a:
		total += item
	return total

func _sum_int64(a: PackedInt64Array) -> int:
	var total: int = 0
	for item in a:
		total += item
	return total

func _sum_float32(a: PackedFloat32Array) -> float:
	var total: float = 0.0
	for item in a:
		total += item
	return total

func _sum_float64(a: PackedFloat64Array) -> float:
	var total: float = 0.0
	for item in a:
		total += item
	return total

func _concat_string(a: PackedStringArray) -> String:
	var result: String = ""
	for item in a:
		result += item
	return result

func _sum_vector2(a: PackedVector2Array) -> Vector2:
	var result: Vector2 = Vector2.ZERO
	for item in a:
		result += item
	return result

func _sum_vector3(a: PackedVector3Array) -> Vector3:
	var result: Vector3 = Vector3.ZERO
	for item in a:
		result += item
	return result

func _sum_color(a: PackedColorArray) -> Color:
	var result: Color = Color(0.0, 0.0, 0.0, 0.0)
	for item in a:
		result += item
	return result

func _sum_vector4(a: PackedVector4Array) -> Vector4:
	var result: Vector4 = Vector4.ZERO
	for item in a:
		result += item
	return result

func test():
	print(_sum_byte(PackedByteArray()) == 0)
	print(_sum_byte(PackedByteArray([255])) == 255)
	print(_sum_byte(PackedByteArray([1, 2, 3])) == 6)

	print(_sum_int32(PackedInt32Array()) == 0)
	print(_sum_int32(PackedInt32Array([-1])) == -1)
	print(_sum_int32(PackedInt32Array([-100, 200, 300])) == 400)

	print(_sum_int64(PackedInt64Array()) == 0)
	print(_sum_int64(PackedInt64Array([4294967296])) == 4294967296)
	print(_sum_int64(PackedInt64Array([4294967296, 5, -4])) == 4294967297)

	print(_sum_float32(PackedFloat32Array()) == 0.0)
	print(_sum_float32(PackedFloat32Array([0.5])) == 0.5)
	print(_sum_float32(PackedFloat32Array([0.25, 0.5, 0.75])) == 1.5)

	print(_sum_float64(PackedFloat64Array()) == 0.0)
	print(_sum_float64(PackedFloat64Array([0.5])) == 0.5)
	print(_sum_float64(PackedFloat64Array([0.25, 0.5, 0.75])) == 1.5)

	print(_concat_string(PackedStringArray()) == "")
	print(_concat_string(PackedStringArray(["тест"])) == "тест")
	print(_concat_string(PackedStringArray(["а", "bc", "🚀"])) == "аbc🚀")

	print(_sum_vector2(PackedVector2Array()) == Vector2.ZERO)
	print(_sum_vector2(PackedVector2Array([Vector2(1, 2)])) == Vector2(1, 2))
	print(_sum_vector2(PackedVector2Array([Vector2(1, 2), Vector2(3, 4)])) == Vector2(4, 6))

	print(_sum_vector3(PackedVector3Array()) == Vector3.ZERO)
	print(_sum_vector3(PackedVector3Array([Vector3(1, 2, 3)])) == Vector3(1, 2, 3))
	print(_sum_vector3(PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)])) == Vector3(5, 7, 9))

	print(_sum_color(PackedColorArray()) == Color(0, 0, 0, 0))
	print(_sum_color(PackedColorArray([Color(1, 0, 0, 1)])) == Color(1, 0, 0, 1))
	print(_sum_color(PackedColorArray([Color(1, 0, 0, 1), Color(0, 1, 0, 1)])) == Color(1, 1, 0, 2))

	print(_sum_vector4(PackedVector4Array()) == Vector4.ZERO)
	print(_sum_vector4(PackedVector4Array([Vector4(1, 2, 3, 4)])) == Vector4(1, 2, 3, 4))
	print(_sum_vector4(PackedVector4Array([Vector4(1, 2, 3, 4), Vector4(4, 5, 6, 7)])) == Vector4(5, 7, 9, 11))

	var large_bytes := PackedByteArray()
	large_bytes.resize(4096)
	large_bytes.fill(1)
	print(_sum_byte(large_bytes) == 4096)

	var large_int32 := PackedInt32Array()
	large_int32.resize(4096)
	large_int32.fill(2)
	print(_sum_int32(large_int32) == 8192)
