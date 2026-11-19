# GDScript function-call argument fast path regressions.
# Exercise calls through Callable to retain runtime argument checking.

func _plain_int(value: int) -> int:
	return value + 1

func _plain_float(value: float) -> bool:
	return typeof(value) == TYPE_FLOAT and value == 7.0

func _plain_string(value: String) -> int:
	return value.length()

func _plain_vector(value: Vector2) -> bool:
	return value == Vector2(2.0, 3.0)

func _plain_array(value: Array) -> int:
	return value.size()

func _plain_dictionary(value: Dictionary) -> int:
	return value.size()

func _typed_array(value: Array[int]) -> int:
	return value[0] + value[1] + value[2]

func _typed_dictionary(value: Dictionary[int, String]) -> String:
	return value[1] + value[2]

func _native_object(value: Node) -> bool:
	return value == null

func _default_argument(value: int = 17) -> int:
	return value

func _variant_argument(value: Variant) -> bool:
	return value == null

func test():
	var f: Callable = _plain_int
	print(f.call(41) == 42)
	f = _plain_float
	print(f.call(7))
	f = _plain_string
	print(f.call("wide") == 4)
	f = _plain_vector
	print(f.call(Vector2(2, 3)))
	f = _plain_array
	print(f.call([1, 2, 3]) == 3)
	f = _plain_dictionary
	print(f.call({1: "one", 2: "two"}) == 2)

	var typed_numbers: Array[int] = [2, 4, 6]
	f = _typed_array
	print(f.call(typed_numbers) == 12)
	var untyped_numbers: Array = [2, 4, 6]
	print(f.call(untyped_numbers) == 12)

	var typed_labels: Dictionary[int, String] = {1: "one", 2: "two"}
	f = _typed_dictionary
	print(f.call(typed_labels) == "onetwo")
	var untyped_labels: Dictionary = {1: "one", 2: "two"}
	print(f.call(untyped_labels) == "onetwo")

	f = _native_object
	print(f.call(null))
	f = _default_argument
	print(f.call() == 17)
	print(f.call(23) == 23)
	f = _variant_argument
	print(f.call(null))
