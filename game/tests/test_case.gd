extends RefCounted
## Tiny assertion helper shared by the test scripts.

var failures: Array[String] = []
var checks: int = 0
var current: String = ""


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append("%s: %s" % [current, message])


func eq(actual: Variant, expected: Variant, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s: %s (got %s, expected %s)" % [current, message, str(actual), str(expected)])


func near(actual: float, expected: float, tolerance: float, message: String) -> void:
	checks += 1
	if absf(actual - expected) > tolerance:
		failures.append("%s: %s (got %f, expected %f +- %f)" % [current, message, actual, expected, tolerance])
