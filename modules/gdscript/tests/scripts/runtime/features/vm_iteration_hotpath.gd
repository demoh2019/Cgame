# Regression coverage for hot GDScript iterator opcodes.
# Integer Vector2i counters, empty and populated dictionaries, and
# packed array reallocation while iterating.

func test():
	var bound: Vector2i = Vector2i(-3, 3)
	var visited: Array[int] = []
	for value in bound:
		visited.append(value)
	print(visited == [-3, -2, -1, 0, 1, 2])

	var count: int = 0
	for value in Vector2i(4, 2):
		count += 1
	print(count == 0)

	var empty: Dictionary = {}
	for key in empty:
		count += 1
	print(count == 0)

	var data: Dictionary = {"alpha": 11, "beta": 22, "gamma": 33}
	var key_count: int = 0
	var total: int = 0
	for key in data:
		key_count += 1
		total += data[key]
	print(key_count == 3 and total == 66)

	var bytes: PackedByteArray = PackedByteArray([1, 2, 3])
	var byte_sum: int = 0
	for byte in bytes:
		byte_sum += byte
		if byte == 2:
			bytes.append(4)
	print(byte_sum == 10 and bytes.size() == 4)

	var names: PackedStringArray = PackedStringArray(["α", "雪", "🚀"])
	var joined: String = ""
	for name in names:
		joined += name
	print(joined == "α雪🚀")

	var zeros: PackedFloat64Array = PackedFloat64Array()
	for number in zeros:
		count += 1
	print(count == 0)

	var large: PackedInt32Array = PackedInt32Array()
	large.resize(10000)
	large.fill(1)
	var sum: int = 0
	for entry in large:
		sum += entry
	print(sum == 10000)
