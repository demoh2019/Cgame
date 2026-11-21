@tool
extends VBoxContainer
## Authoring panel for SpatialQueryGraph assets: add/remove generators and tests, tweak
## parameters, run a preview and see scored points. All operations are plain methods (the
## buttons just call them), so the panel is fully usable headlessly.

const SQG = preload("res://scripts/shared/spatial_query_graph.gd")

signal changed
signal preview_ready(count: int)

var asset: Dictionary = SQG.new_asset("preview_query")
var context: Dictionary = {}
var preview: Array[Dictionary] = []
var last_debug: Dictionary = {}

var _runner: SQG = SQG.new()
var _gen_kind: OptionButton = null
var _test_kind: OptionButton = null
var _list: ItemList = null
var _canvas: Control = null
var _status: Label = null


func _init() -> void:
	context = default_context()
	_build_ui()
	_refresh()


static func default_context() -> Dictionary:
	return {"querier": Vector3.ZERO, "facing": Vector3(0, 0, -1), "target": Vector3(12, 0, 0),
			"actors": [], "navmesh_points": Callable(), "custom": {}}


func set_context(ctx: Dictionary) -> void:
	context = ctx


func load_asset(data: Dictionary) -> void:
	asset = data.duplicate(true)
	preview = []
	_refresh()
	changed.emit()


func asset_json(indent: String = "\t") -> String:
	var out: Dictionary = asset.duplicate(true)
	for t_v in (out["tests"] as Array):
		var t: Dictionary = t_v
		t.erase("fn")
	return JSON.stringify(out, indent)


func add_generator(type: String, params: Dictionary = {}) -> int:
	var idx: int = SQG.add_generator(asset, SQG.make_generator(type, params))
	_refresh()
	changed.emit()
	return idx


func add_test(type: String, params: Dictionary = {}) -> int:
	var idx: int = SQG.add_test(asset, SQG.make_test(type, params))
	_refresh()
	changed.emit()
	return idx


func remove_generator(index: int) -> bool:
	var arr: Array = asset["generators"]
	if index < 0 or index >= arr.size():
		return false
	arr.remove_at(index)
	_refresh()
	changed.emit()
	return true


func remove_test(index: int) -> bool:
	var arr: Array = asset["tests"]
	if index < 0 or index >= arr.size():
		return false
	arr.remove_at(index)
	_refresh()
	changed.emit()
	return true


func set_test_param(index: int, key: String, value: Variant) -> bool:
	var arr: Array = asset["tests"]
	if index < 0 or index >= arr.size():
		return false
	(arr[index] as Dictionary)[key] = value
	changed.emit()
	return true


func set_generator_param(index: int, key: String, value: Variant) -> bool:
	var arr: Array = asset["generators"]
	if index < 0 or index >= arr.size():
		return false
	(arr[index] as Dictionary)[key] = value
	changed.emit()
	return true


func problems() -> Array[String]:
	return SQG.validate(asset)


## Runs the query (full, not sliced) and stores the scored points for drawing.
func run_preview() -> Array[Dictionary]:
	var ctx: Dictionary = context.duplicate()
	if not (ctx.get("navmesh_points", Callable()) as Callable).is_valid():
		ctx["navmesh_points"] = Callable(self, "_fallback_navmesh")
	preview = _runner.run(asset, ctx)
	last_debug = _runner.debug()
	if _status != null:
		_status.text = "%d generated, %d passed, best %.2f" % [int(last_debug["generated"]), int(last_debug["passed"]),
				float((preview[0] as Dictionary)["score"]) if not preview.is_empty() else 0.0]
	if _canvas != null:
		_canvas.queue_redraw()
	preview_ready.emit(preview.size())
	return preview


# Deterministic stand-in so navmesh generators show something without a real navmesh.
func _fallback_navmesh(center: Vector3, radius: float, cnt: int) -> Array:
	var out: Array = []
	for i in cnt:
		var a: float = float(i) * 2.399963
		var r: float = radius * sqrt((float(i) + 0.5) / float(maxi(cnt, 1)))
		out.append(center + Vector3(cos(a), 0.0, sin(a)) * r)
	return out


func _build_ui() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)
	_gen_kind = OptionButton.new()
	for g in SQG.GENERATOR_TYPES:
		_gen_kind.add_item(g)
	bar.add_child(_gen_kind)
	var add_g := Button.new()
	add_g.text = "+Gen"
	add_g.pressed.connect(func() -> void: add_generator(SQG.GENERATOR_TYPES[_gen_kind.selected]))
	bar.add_child(add_g)
	_test_kind = OptionButton.new()
	for t in SQG.TEST_TYPES:
		_test_kind.add_item(t)
	bar.add_child(_test_kind)
	var add_t := Button.new()
	add_t.text = "+Test"
	add_t.pressed.connect(func() -> void: add_test(SQG.TEST_TYPES[_test_kind.selected]))
	bar.add_child(add_t)
	var bar2 := HBoxContainer.new()
	add_child(bar2)
	var rm := Button.new()
	rm.text = "Remove"
	rm.pressed.connect(_remove_selected)
	bar2.add_child(rm)
	var run_b := Button.new()
	run_b.text = "Run preview"
	run_b.pressed.connect(func() -> void: run_preview())
	bar2.add_child(run_b)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(240, 90)
	add_child(_list)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(240, 160)
	_canvas.draw.connect(_draw_preview)
	add_child(_canvas)
	_status = Label.new()
	add_child(_status)


func _refresh() -> void:
	if _list == null:
		return
	_list.clear()
	for g_v in (asset["generators"] as Array):
		var g: Dictionary = g_v
		_list.add_item("G: " + String(g.get("type", "?")))
	for t_v in (asset["tests"] as Array):
		var t: Dictionary = t_v
		_list.add_item("T: %s (w %.2f)" % [String(t.get("type", "?")), float(t.get("weight", 1.0))])


func _remove_selected() -> void:
	var sel: PackedInt32Array = _list.get_selected_items()
	if sel.is_empty():
		return
	var gcount: int = (asset["generators"] as Array).size()
	var i: int = sel[0]
	if i < gcount:
		remove_generator(i)
	else:
		remove_test(i - gcount)


func _draw_preview() -> void:
	var rect := Rect2(Vector2.ZERO, _canvas.size)
	_canvas.draw_rect(rect, Color(0.1, 0.11, 0.13))
	if preview.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for it in preview:
		var p: Vector3 = it["position"]
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var span := Vector2(maxf(hi.x - lo.x, 0.001), maxf(hi.y - lo.y, 0.001))
	for it in preview:
		var p: Vector3 = it["position"]
		var s: float = it["score"]
		var uv := Vector2((p.x - lo.x) / span.x, (p.z - lo.y) / span.y)
		_canvas.draw_circle(rect.position + Vector2(8, 8) + uv * (rect.size - Vector2(16, 16)), 3.0, Color(1.0 - s, s, 0.2))
