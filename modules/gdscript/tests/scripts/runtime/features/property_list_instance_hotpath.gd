#GDTEST_OK

class PropertyProfile:
	extends RefCounted

	var first: int = 10
	var second: int = 20

	func _get_property_list() -> Array[Dictionary]:
		var custom: Array[Dictionary] = []
		custom.append({"name": "dynamic_test", "type": TYPE_INT})
		return custom

	func _validate_property(property: Dictionary) -> void:
		if property["name"] == "first":
			property["hint_string"] = "checked"

func test() -> void:
	var instance := PropertyProfile.new()
	var wanted: Array[String] = []
	var validated := false
	for property in instance.get_property_list():
		var name := str(property["name"])
		if name == "first" or name == "second" or name == "dynamic_test":
			wanted.append(name)
			if name == "first":
				validated = property["hint_string"] == "checked"

	assert(wanted == ["first", "second", "dynamic_test"])
	assert(validated)
	print("gdscript property list order: ok")
