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

	# A loop must reuse its own character storage without changing any
	# previously captured value. Include non-BMP UTF-32 codepoints.
	var unicode_text: String = "aβ🌍a\nZ"
	var saved_characters: Array[String] = []
	for letter in unicode_text:
		saved_characters.append(letter)
	print(saved_characters == ["a", "β", "🌍", "a", "\n", "Z"])
	print(unicode_text == "aβ🌍a\nZ")

	# Capture the same character more than once. COW must detach when a
	# previous iteration's value is still retained by another container.
	var repeats: Array[String] = []
	for letter in "aabbccaa":
		repeats.append(letter)
	print(repeats == ["a", "a", "b", "b", "c", "c", "a", "a"])

	var empty_count: int = 0
	for letter in "":
		empty_count += 1
	print(empty_count == 0)

	var single: Array[String] = []
	for letter in "🌍":
		single.append(letter)
	print(single == ["🌍"])

	# Every second character changes. This is the fast path where there
	# are no long-lived aliases to the current iterator value.
	var long_text: String = "ab".repeat(8192)
	var a_count: int = 0
	for letter in long_text:
		if letter == "a":
			a_count += 1
	print(a_count == 8192)

	# The old path constructed a new character for every iteration.
	# Keeping an alias requires a COW detach rather than mutating it.
	var first_alias: String = ""
	var last_seen: String = ""
	for letter in "xyz":
		if first_alias.is_empty():
			first_alias = letter
		last_seen = letter
	print(first_alias == "x" and last_seen == "z")
