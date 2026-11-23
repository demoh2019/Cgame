extends SceneTree
## Focused native/portable virtual shadow page regression, no game server.

const Case = preload("res://tests/test_case.gd")
const ShadowPages = preload("res://tests/test_shadow_pages_and_gates.gd")


func _initialize() -> void:
	var t := Case.new()
	ShadowPages.new().run(t)
	for failure in t.failures:
		printerr("FAIL " + failure)
	print("VSM PAGE JOBS TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(1 if not t.failures.is_empty() else 0)
