extends Node
## Same-scene A/B measurement of one project setting (engine work): CGAME_AB="setting/path:value_a:value_b".
## Every PERIOD seconds the setting flips; the GPU time of the main viewport (and the frame time) is averaged
## per value, skipping the first frames after each flip, and printed as "AB <setting> a=... b=...".
## Separate runs of the screenshot benchmark land in different scenes, so they cannot compare reliably.

const PERIOD := 2.0
const SETTLE := 0.5

var setting := ""
var values: Array = []
var _index := 0
var _timer := 0.0
var _sums := [0.0, 0.0]
var _frames := [0, 0]
var _cpu_sums := [0.0, 0.0]
var _report_timer := 0.0


static func from_environment() -> Node:
	var spec := OS.get_environment("CGAME_AB")
	var parts := spec.split(":")
	if parts.size() != 3 or not ProjectSettings.has_setting(parts[0]):
		return null
	var node = load("res://scripts/client/ab_benchmark.gd").new()
	node.setting = parts[0]
	node.values = [str_to_var(parts[1]), str_to_var(parts[2])]
	return node


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	ProjectSettings.set_setting(setting, values[0])


func _process(delta: float) -> void:
	_timer += delta
	_report_timer += delta
	if _timer >= SETTLE:
		var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		if gpu > 0.0:
			_sums[_index] += gpu
			_cpu_sums[_index] += delta * 1000.0
			_frames[_index] += 1
	if _timer >= PERIOD:
		_timer = 0.0
		_index = 1 - _index
		ProjectSettings.set_setting(setting, values[_index])
	if _report_timer >= PERIOD * 4.0:
		_report_timer = 0.0
		var line := "AB %s" % setting
		for i in 2:
			var n: int = maxi(int(_frames[i]), 1)
			line += "  %s: gpu %.2f ms, frame %.2f ms (%d frames)" % [str(values[i]), _sums[i] / n, _cpu_sums[i] / n, _frames[i]]
		print(line)
