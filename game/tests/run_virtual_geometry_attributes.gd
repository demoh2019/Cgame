extends SceneTree
## Single-purpose native/portable virtual geometry attribute validation.

const Case = preload("res://tests/test_case.gd")
const GeometrySuite = preload("res://tests/test_virtual_geometry.gd")
const MeshRendererSuite = preload("res://tests/test_meshlet_renderer.gd")


func _initialize() -> void:
	var count := 0
	var fails: Array[String] = []
	for suite in [GeometrySuite.new(), MeshRendererSuite.new()]:
		var t := Case.new()
		suite.run(t)
		count += t.checks
		fails.append_array(t.failures)
	for failure in fails:
		printerr("FAIL " + failure)
	print("CLUSTER ATTRIBUTE TOTAL: %d checks, %d failures" % [count, fails.size()])
	quit(1 if not fails.is_empty() else 0)
