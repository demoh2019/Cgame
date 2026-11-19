# Regression for the typed container is/assign/return VM opcodes.
# The runtime test runner calls test() and compares output with the .out file.

func _return_array(items: Array[int]) -> Array[int]:
	return items

func _return_dictionary(items: Dictionary[int, String]) -> Dictionary[int, String]:
	return items

func test():
	var numbers: Array[int] = [1, 2, 3]
	var labels: Dictionary[int, String] = {1: "one", 2: "two"}
	var dynamic_numbers: Variant = numbers
	var dynamic_labels: Variant = labels

	print(dynamic_numbers is Array[int])
	print(dynamic_numbers is Array[String])
	print(dynamic_labels is Dictionary[int, String])
	print(dynamic_labels is Dictionary[int, int])
	print(_return_array(numbers) == numbers)
	print(_return_dictionary(labels) == labels)
