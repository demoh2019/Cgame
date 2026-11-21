@tool
extends Control
## Draws per-agent AI decision timelines (HTN / GOAP plans, StateTree active paths, Utility AI
## scores over time) from an AIDebugRecorder. The data model is built by build_view(), so the
## whole panel can be driven and tested headlessly; _draw() only renders that view.

const Recorder = preload("res://scripts/shared/ai_debug_recorder.gd")

signal cursor_changed(time: float)

const LABEL_W: float = 74.0
const LANE_H: float = 52.0
const LANES: Array[String] = ["htn", "goap", "state_tree", "utility"]

var recorder: Recorder = null
var selected_agent: String = ""
var view_t0: float = 0.0
var view_t1: float = 10.0
var cursor_time: float = -1.0


func _init() -> void:
	custom_minimum_size = Vector2(320, LANE_H * 4.0 + 24.0)
	clip_contents = true


func set_recorder(r: Recorder) -> void:
	recorder = r
	if selected_agent == "" and r != null:
		var list: Array[String] = r.agents()
		if not list.is_empty():
			selected_agent = list[0]
	fit_range()


func select_agent(agent: Variant) -> void:
	selected_agent = Recorder.agent_key(agent)
	fit_range()


func set_range(t0: float, t1: float) -> void:
	view_t0 = t0
	view_t1 = maxf(t1, t0 + 0.001)
	queue_redraw()


## Fit the visible range to the selected agent's recorded times.
func fit_range() -> void:
	if recorder != null and selected_agent != "":
		var recs: Array[Dictionary] = recorder.timeline(selected_agent, -INF, INF)
		if not recs.is_empty():
			var lo: float = INF
			var hi: float = -INF
			for r in recs:
				lo = minf(lo, float(r["time"]))
				hi = maxf(hi, float(r["time"]))
			set_range(lo, hi + 0.05)
			return
	queue_redraw()


func set_cursor(t: float) -> void:
	cursor_time = t
	cursor_changed.emit(t)
	queue_redraw()


func explain_at(time: float = -1.0) -> String:
	if recorder == null or selected_agent == "":
		return "No agent selected."
	return recorder.explain(selected_agent, cursor_time if time < 0.0 and cursor_time >= 0.0 else (time if time >= 0.0 else view_t1))


## {agent, t0, t1, lanes: {htn: [{t,label,steps}], goap: [{t,label,cost}],
## state_tree: [{t,t_end,label}], utility: {series: {option: [[t,score]]}, chosen: [{t,name}]}}}
func build_view() -> Dictionary:
	var view: Dictionary = {"agent": selected_agent, "t0": view_t0, "t1": view_t1, "lanes": {}}
	var lanes: Dictionary = view["lanes"]
	lanes["htn"] = []
	lanes["goap"] = []
	lanes["state_tree"] = []
	lanes["utility"] = {"series": {}, "chosen": []}
	if recorder == null or selected_agent == "":
		return view
	for r in recorder.timeline(selected_agent, view_t0, view_t1):
		var d: Dictionary = r["data"]
		var t: float = float(r["time"])
		match String(r["kind"]):
			"htn":
				var plan: Array = d["plan"]
				(lanes["htn"] as Array).append({"t": t, "label": " > ".join(PackedStringArray(plan)), "steps": plan.size()})
			"goap":
				var plan2: Array = d["plan"]
				(lanes["goap"] as Array).append({"t": t, "label": " > ".join(PackedStringArray(plan2)), "cost": float(d["cost"])})
			"state_tree":
				var path: Array = d["path"]
				var label: String = "/".join(PackedStringArray(path)) if not path.is_empty() else "(inactive)"
				var spans: Array = lanes["state_tree"]
				if not spans.is_empty() and String((spans.back() as Dictionary)["label"]) == label:
					(spans.back() as Dictionary)["t_end"] = t
				else:
					if not spans.is_empty():
						(spans.back() as Dictionary)["t_end"] = t
					spans.append({"t": t, "t_end": t, "label": label})
			"utility":
				var util: Dictionary = lanes["utility"]
				var series: Dictionary = util["series"]
				var scores: Dictionary = d["scores"]
				for opt in scores:
					if not series.has(opt):
						series[opt] = []
					(series[opt] as Array).append([t, float(scores[opt])])
				(util["chosen"] as Array).append({"t": t, "name": String(d["chosen"])})
	return view


static func color_for(key: String) -> Color:
	return Color.from_hsv(float(absi(key.hash()) % 360) / 360.0, 0.6, 0.95)


func _tx(t: float) -> float:
	var span: float = maxf(view_t1 - view_t0, 0.0001)
	return LABEL_W + (t - view_t0) / span * maxf(size.x - LABEL_W - 4.0, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var span: float = maxf(view_t1 - view_t0, 0.0001)
			var w: float = maxf(size.x - LABEL_W - 4.0, 1.0)
			set_cursor(view_t0 + (mb.position.x - LABEL_W) / w * span)


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var fs: int = 11
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.11, 0.13))
	var view: Dictionary = build_view()
	var lanes: Dictionary = view["lanes"]
	if selected_agent == "":
		draw_string(font, Vector2(8, 18), "No agent selected", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		return
	for li in LANES.size():
		var y0: float = 4.0 + float(li) * LANE_H
		draw_rect(Rect2(LABEL_W, y0, size.x - LABEL_W - 2.0, LANE_H - 4.0), Color(0.16, 0.17, 0.2))
		draw_string(font, Vector2(4, y0 + 14.0), LANES[li], HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 6.0, fs)
		match LANES[li]:
			"htn", "goap":
				var marks: Array = lanes[LANES[li]]
				for m_v in marks:
					var m: Dictionary = m_v
					var x: float = _tx(float(m["t"]))
					draw_line(Vector2(x, y0), Vector2(x, y0 + LANE_H - 4.0), color_for(String(m["label"])), 2.0)
					draw_string(font, Vector2(x + 3.0, y0 + 14.0), String(m["label"]), HORIZONTAL_ALIGNMENT_LEFT, 140.0, fs - 1)
			"state_tree":
				for s_v in (lanes["state_tree"] as Array):
					var s: Dictionary = s_v
					var xa: float = _tx(float(s["t"]))
					var xb: float = maxf(_tx(float(s["t_end"])), xa + 3.0)
					draw_rect(Rect2(xa, y0 + 6.0, xb - xa, LANE_H - 16.0), color_for(String(s["label"])).darkened(0.3))
					draw_string(font, Vector2(xa + 2.0, y0 + 26.0), String(s["label"]), HORIZONTAL_ALIGNMENT_LEFT, maxf(xb - xa, 20.0), fs - 1)
			"utility":
				var util: Dictionary = lanes["utility"]
				var series: Dictionary = util["series"]
				for opt in series:
					var pts: PackedVector2Array = PackedVector2Array()
					for p_v in (series[opt] as Array):
						var p: Array = p_v
						pts.append(Vector2(_tx(float(p[0])), y0 + (LANE_H - 8.0) * (1.0 - float(p[1])) + 2.0))
					var col: Color = color_for(String(opt))
					if pts.size() >= 2:
						draw_polyline(pts, col, 1.5)
					elif pts.size() == 1:
						draw_circle(pts[0], 2.5, col)
				for c_v in (util["chosen"] as Array):
					var c: Dictionary = c_v
					draw_line(Vector2(_tx(float(c["t"])), y0 + LANE_H - 8.0), Vector2(_tx(float(c["t"])), y0 + LANE_H - 4.0), color_for(String(c["name"])), 2.0)
	if cursor_time >= 0.0:
		var cx: float = _tx(cursor_time)
		draw_line(Vector2(cx, 0), Vector2(cx, size.y), Color(1, 1, 1, 0.7), 1.0)
