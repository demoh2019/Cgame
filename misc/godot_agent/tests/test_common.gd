extends SceneTree
## Unit tests for the DSL helpers: godot --headless --path misc/godot_agent --script res://tests/test_common.gd

const C = preload("res://addons/godot_agent/common.gd")
const Proc = preload("res://addons/godot_agent/proc.gd")
const Api = preload("res://addons/godot_agent/api_ref.gd")

var failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		print("FAIL ", what)


func _initialize() -> void:
	# Paths: only project-relative, non-hidden, non-escaping paths are accepted.
	check(C.res_path("scenes/a.tscn") == "res://scenes/a.tscn", "relative path")
	check(C.res_path("res://a.gd") == "res://a.gd", "res path")
	check(C.res_path("../x") == "", "parent escape")
	check(C.res_path("a/../../x") == "", "nested escape")
	check(C.res_path("/etc/passwd") == "", "absolute")
	check(C.res_path("res://.godot/x") == "", "hidden dir")
	check(C.res_path("C:\\x") == "", "windows path")
	check(C.res_path("") == "", "empty")

	# Tokenizer keeps groups and quotes together.
	var t := C.tokenize('+ A/B Sprite2D position=Vector2(1, 2) text="a b" arr=[1, 2]')
	check(t.size() == 6, "token count %d" % t.size())
	check(t[3] == "position=Vector2(1, 2)", "group token")
	check(t[4] == 'text="a b"', "quoted token")
	check(C.split_kv("k=v=w") == ["k", "v=w"], "split_kv first =")
	check(C.split_kv("plain").is_empty(), "split_kv none")

	# Coercion shorthands.
	var v2 := C.coerce({"type": TYPE_VECTOR2}, "10,20")
	check(v2[0] and v2[1] == Vector2(10, 20), "vector shorthand")
	check(C.coerce({"type": TYPE_VECTOR2}, "1,2,3")[0] == false, "vector arity")
	check(C.coerce({"type": TYPE_COLOR}, "#ff0000")[1] == Color(1, 0, 0), "hex color")
	check(C.coerce({"type": TYPE_COLOR}, "red")[1] == Color.RED, "named color")
	check(C.coerce({"type": TYPE_COLOR}, "nonsense")[0] == false, "bad color")
	check(C.coerce({"type": TYPE_BOOL}, "yes")[1] == true, "bool yes")
	check(C.coerce({"type": TYPE_INT}, "42")[1] == 42, "int")
	var en := C.coerce({"type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "hint_string": "Grounded,Floating"}, "floating")
	check(en[0] and en[1] == 1, "enum by name")
	check(C.coerce({"type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "hint_string": "A,B"}, "zzz")[0] == false, "bad enum")
	check(C.coerce({"type": TYPE_STRING}, '"hi there"')[1] == "hi there", "quoted string")
	check(C.coerce({"type": TYPE_OBJECT}, "new:RectangleShape2D")[1] is RectangleShape2D, "new resource")
	check(C.coerce({"type": TYPE_OBJECT}, "new:Nope")[0] == false, "bad class")

	# Output condensing: engine error blocks become "file:line message" and dedupe.
	var log := "Godot Engine v4.8\nSCRIPT ERROR: Parse Error: bad\n          at: GDScript::reload (res://a.gd:3)\nSCRIPT ERROR: Parse Error: bad\n          at: GDScript::reload (res://a.gd:3)\n"
	var lines := Proc.condense(log)
	check(lines.size() == 1 and lines[0] == "res://a.gd:3 S: Parse Error: bad", "condense: %s" % str(lines))
	var pr := Proc.game_prints("x\nx\nx\ny\nERROR: no\n")
	check(pr == PackedStringArray(["x (x3)", "y"]), "prints: %s" % str(pr))

	# API reference is compact and always tied to the engine build.
	var api := Api.new().lookup("CharacterBody2D", "velocity")
	check(api.begins_with("CharacterBody2D < PhysicsBody2D"), "api chain")
	check(api.contains("velocity"), "api member")
	check(Api.new().lookup("?rigidbody").contains("RigidBody2D"), "api search")
	check(Api.new().lookup("RigidBod").contains("unknown class"), "api unknown")
	check(Api.new().lookup("Node2D").length() < 2000, "api Node2D stays small")

	print("test_common: ", "OK" if failures == 0 else "%d FAILED" % failures)
	quit(1 if failures > 0 else 0)
