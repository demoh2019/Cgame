extends SceneTree
## Headless native/stock Godot parity of ranked stimulus memory and
## bounded, authoritative multiple-noise investigation.
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_native_infected_senses.gd")


func _initialize() -> void:
    var t := TestCase.new()
    Suite.new().run(t)
    for failure in t.failures:
        printerr("FAIL " + failure)
    print("RANKED PERCEPTION TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
    quit(1 if not t.failures.is_empty() else 0)
