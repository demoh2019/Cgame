extends Control
## The heads-up display's look: a vitals card with animated bars and status chips, a zone and clock strip, a quest card under
## the minimap, an action bar with cooldown sweeps, an XP strip, a banner for big moments and screen-edge feedback (low health
## pulse, damage flash). It only draws what `client.you` already says; nothing here can change the game.
## The old text labels of hud.gd stay alive (hidden) and F3 shows them as a details panel.

const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Contracts = preload("res://scripts/shared/contracts.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const Evasion = preload("res://scripts/shared/evasion.gd")
const Skills = preload("res://scripts/shared/skills.gd")

const INK := Color(0.96, 0.97, 1.0)
const DIM := Color(0.72, 0.76, 0.84)
const CARD := Color(0.05, 0.06, 0.09, 0.82)
const EDGE := Color(1.0, 0.86, 0.5, 0.35)
const GOLD := Color(0.95, 0.78, 0.35)
const ZONE_COLORS := [Color(0.35, 0.85, 0.45), Color(0.95, 0.82, 0.3), Color(0.95, 0.45, 0.3), Color(0.78, 0.3, 0.95)]
const ZONE_TITLES := ["GREEN ZONE", "YELLOW ZONE", "RED ZONE", "BLACK ZONE"]

var client
var details_visible := false
var _styles: Dictionary = {}
var _shown: Dictionary = {} # smoothed bar values 0..1
var _trail_health := 1.0
var _last_health := -1.0
var _flash := 0.0
var _banner_text := ""
var _banner_color := GOLD
var _banner_time := 0.0
var _last_skill := ""
var _last_skill_time := -100.0
var _time := 0.0
var _font: Font


func setup(p_client) -> void:
	client = p_client
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	client.event_received.connect(_on_event)


func _on_event(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"xp":
			var best := ""
			var best_amount := 0
			for skill_id in event.get("gains", {}):
				if int(event["gains"][skill_id]) >= best_amount:
					best_amount = int(event["gains"][skill_id])
					best = str(skill_id)
			if best != "":
				_last_skill = best
				_last_skill_time = _time
		"skill_up":
			var skill_name: String = str(Skills.SKILLS.get(event.get("skill", ""), {}).get("name", event.get("skill", "")))
			banner("LEVEL UP   %s %d" % [skill_name.to_upper(), int(event.get("level", 0))], GOLD)
			_last_skill = str(event.get("skill", ""))
			_last_skill_time = _time
		"perk":
			banner("PERK LEARNED   %s" % str(Skills.PERKS.get(event.get("perk", ""), {}).get("name", "")).to_upper(), Color(0.55, 0.85, 1.0))
		"death":
			pass


func banner(text: String, color: Color = GOLD) -> void:
	_banner_text = text
	_banner_color = color
	_banner_time = 3.2


func _process(delta: float) -> void:
	_time += delta
	_banner_time = maxf(0.0, _banner_time - delta)
	_flash = maxf(0.0, _flash - delta * 2.2)
	if client != null and client.you.has("health"):
		var health: float = float(client.you["health"])
		if _last_health >= 0.0 and health < _last_health - 0.5:
			_flash = minf(1.0, _flash + (_last_health - health) / 30.0 + 0.35)
		_last_health = health
	queue_redraw()


# --- Drawing helpers --------------------------------------------------------------------------------------------------

func _box(key: String, color: Color, radius: int, border: float = 0.0, border_color: Color = Color.TRANSPARENT, shadow: int = 0) -> StyleBoxFlat:
	if not _styles.has(key):
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(radius)
		style.set_border_width_all(int(border))
		style.border_color = border_color
		if shadow > 0:
			style.shadow_color = Color(0, 0, 0, 0.4)
			style.shadow_size = shadow
		style.anti_aliasing = true
		_styles[key] = style
	return _styles[key]


func _card(rect: Rect2, radius: int = 12) -> void:
	_box("card%d" % radius, CARD, radius, 1.0, EDGE, 8).draw(get_canvas_item(), rect)


func _text(position: Vector2, text: String, size: int, color: Color = INK, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	# Outline first, then the text, for legibility on any background.
	draw_string_outline(_font, position, text, align, width, size, 4, Color(0, 0, 0, 0.8))
	draw_string(_font, position, text, align, width, size, color)


func _bar(rect: Rect2, value: float, color: Color, trail: float = -1.0, caption: String = "", radius: int = 8) -> void:
	value = clampf(value, 0.0, 1.0)
	_box("barbg%d" % radius, Color(0.0, 0.0, 0.0, 0.55), radius, 1.0, Color(1, 1, 1, 0.14)).draw(get_canvas_item(), rect)
	var inner := rect.grow(-1.5)
	if trail > value:
		var trail_rect := Rect2(inner.position, Vector2(maxf(inner.size.x * trail, 0.0), inner.size.y))
		_box("trail%d" % radius, Color(1.0, 0.95, 0.9, 0.55), radius - 1).draw(get_canvas_item(), trail_rect)
	if value > 0.004:
		var width := maxf(inner.size.x * value, inner.size.y)
		var fill_rect := Rect2(inner.position, Vector2(minf(width, inner.size.x), inner.size.y))
		var key := "fill%s%d" % [color.to_html(), radius]
		_box(key, color, radius - 1).draw(get_canvas_item(), fill_rect)
		var gloss := Rect2(fill_rect.position + Vector2(1.5, 1.0), Vector2(maxf(fill_rect.size.x - 3.0, 0.0), fill_rect.size.y * 0.42))
		_box("gloss%d" % radius, Color(1, 1, 1, 0.24), radius - 2).draw(get_canvas_item(), gloss)
	if caption != "":
		_text(Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + 5.0), caption, 13, INK, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


func _ease(key: String, target: float, speed: float = 7.0) -> float:
	var current: float = float(_shown.get(key, target))
	current = lerpf(current, target, clampf(get_process_delta_time() * speed, 0.0, 1.0))
	_shown[key] = current
	return current


# Icons, each drawn inside a square of side `s` centered on `c`.

func _icon_heart(c: Vector2, s: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 28:
		var t: float = TAU * float(i) / 28.0
		points.append(c + Vector2(16.0 * pow(sin(t), 3.0), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)) + 1.0) * (s / 36.0))
	draw_colored_polygon(points, color)


func _icon_drop(c: Vector2, s: float, color: Color) -> void:
	var radius := s * 0.34
	var center := c + Vector2(0, s * 0.12)
	var points := PackedVector2Array([c + Vector2(0, -s * 0.46)])
	for i in 21:
		var angle: float = deg_to_rad(-38.0 + 256.0 * float(i) / 20.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)
	draw_circle(center + Vector2(-radius * 0.35, -radius * 0.2), radius * 0.2, Color(1, 1, 1, 0.5))


func _icon_apple(c: Vector2, s: float, color: Color) -> void:
	draw_circle(c + Vector2(-s * 0.13, s * 0.07), s * 0.27, color)
	draw_circle(c + Vector2(s * 0.13, s * 0.07), s * 0.27, color)
	draw_line(c + Vector2(0, -s * 0.12), c + Vector2(s * 0.02, -s * 0.38), Color(0.4, 0.28, 0.15), 2.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.04, -s * 0.3), c + Vector2(s * 0.28, -s * 0.42), c + Vector2(s * 0.2, -s * 0.18)]), Color(0.4, 0.78, 0.3))


func _icon_bolt(c: Vector2, s: float, color: Color) -> void:
	var k := s / 36.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(4, -17) * k, c + Vector2(-9, 3) * k, c + Vector2(-1, 3) * k, c + Vector2(-5, 17) * k, c + Vector2(10, -4) * k, c + Vector2(2, -4) * k]), color)


func _icon_virus(c: Vector2, s: float, color: Color) -> void:
	draw_circle(c, s * 0.24, color)
	for i in 8:
		var direction := Vector2.from_angle(TAU * float(i) / 8.0)
		draw_line(c + direction * s * 0.24, c + direction * s * 0.42, color, 2.0)
		draw_circle(c + direction * s * 0.44, s * 0.06, color)


func _icon_flake(c: Vector2, s: float, color: Color) -> void:
	for i in 3:
		var direction := Vector2.from_angle(PI * float(i) / 3.0) * s * 0.42
		draw_line(c - direction, c + direction, color, 2.0)


func _icon_sun(c: Vector2, s: float, color: Color) -> void:
	draw_circle(c, s * 0.2, color)
	for i in 8:
		var direction := Vector2.from_angle(TAU * float(i) / 8.0)
		draw_line(c + direction * s * 0.3, c + direction * s * 0.44, color, 2.0)


func _icon_moon(c: Vector2, s: float, color: Color, cut: Color) -> void:
	draw_circle(c, s * 0.34, color)
	draw_circle(c + Vector2(s * 0.16, -s * 0.08), s * 0.3, cut)


func _icon_sword(c: Vector2, s: float, color: Color) -> void:
	var k := s / 36.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -17) * k, c + Vector2(3.5, -9) * k, c + Vector2(3.5, 6) * k, c + Vector2(-3.5, 6) * k, c + Vector2(-3.5, -9) * k]), color)
	draw_rect(Rect2(c + Vector2(-9, 6) * k, Vector2(18, 3.5) * k), color.darkened(0.25))
	draw_rect(Rect2(c + Vector2(-2, 9) * k, Vector2(4, 8) * k), color.darkened(0.45))


func _icon_gun(c: Vector2, s: float, color: Color) -> void:
	var k := s / 36.0
	draw_rect(Rect2(c + Vector2(-14, -7) * k, Vector2(26, 8) * k), color)
	draw_rect(Rect2(c + Vector2(-9, 0) * k, Vector2(8, 15) * k), color.darkened(0.3))
	draw_rect(Rect2(c + Vector2(4, 1) * k, Vector2(4, 5) * k), color.darkened(0.2))


func _icon_fist(c: Vector2, s: float, color: Color) -> void:
	draw_circle(c, s * 0.26, color)
	for i in 3:
		draw_circle(c + Vector2(-s * 0.16 + s * 0.16 * float(i), -s * 0.2), s * 0.09, color)


func _icon_star(c: Vector2, s: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 8:
		var radius: float = s * 0.44 if i % 2 == 0 else s * 0.14
		points.append(c + Vector2.from_angle(TAU * float(i) / 8.0 - PI * 0.5) * radius)
	draw_colored_polygon(points, color)


func _icon_dodge(c: Vector2, s: float, color: Color) -> void:
	for i in 2:
		var x := -s * 0.14 + s * 0.26 * float(i)
		draw_polyline(PackedVector2Array([c + Vector2(x - s * 0.12, -s * 0.28), c + Vector2(x + s * 0.12, 0), c + Vector2(x - s * 0.12, s * 0.28)]), color, 3.0)


func _icon_hand(c: Vector2, s: float, color: Color) -> void:
	draw_arc(c, s * 0.3, 0, TAU, 24, color, 2.5)
	draw_circle(c, s * 0.08, color)


func _chip(position: Vector2, text: String, color: Color, icon: String = "") -> float:
	# A pill with an optional icon; returns its width so chips can be laid out in a row.
	var width: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + (44.0 if icon != "" else 22.0)
	var rect := Rect2(position, Vector2(width, 24))
	_box("chip" + color.to_html(), Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.88), 12, 1.0, Color(color.r, color.g, color.b, 0.8)).draw(get_canvas_item(), rect)
	var text_x := position.x + 11.0
	if icon != "":
		var c := position + Vector2(18, 12)
		match icon:
			"virus": _icon_virus(c, 20, color)
			"drop": _icon_drop(c, 20, color)
			"flake": _icon_flake(c, 20, color)
			"bolt": _icon_bolt(c, 20, color)
		text_x = position.x + 32.0
	_text(Vector2(text_x, position.y + 17.0), text, 13, INK)
	return width + 6.0


# --- The layout ---------------------------------------------------------------------------------------------------------

func _draw() -> void:
	if client == null or not client.you.has("health") or _font == null:
		return
	var you: Dictionary = client.you
	var view := get_viewport_rect().size
	_draw_edge_feedback(you, view)
	_draw_vitals(you)
	_draw_top_strip(you, view)
	_draw_quest_card(you, view)
	_draw_action_bar(you, view)
	_draw_xp_strip(view)
	_draw_banner(view)


func _draw_edge_feedback(you: Dictionary, view: Vector2) -> void:
	var maximum: float = maxf(float(you.get("max_health", Defs.MAX_HEALTH)), 1.0)
	var fraction: float = float(you["health"]) / maximum
	var intensity: float = _flash * 0.55
	if fraction < 0.3 and bool(you.get("alive", true)):
		intensity = maxf(intensity, (0.3 - fraction) / 0.3 * (0.28 + 0.14 * sin(_time * 5.0)))
	if intensity <= 0.01:
		return
	var steps := 7
	for i in steps:
		var inset: float = float(i) / float(steps) * 70.0
		var alpha: float = intensity * pow(1.0 - float(i) / float(steps), 2.0) * 0.5
		var color := Color(0.85, 0.05, 0.05, alpha)
		draw_rect(Rect2(inset, inset, view.x - inset * 2.0, 14.0), color)
		draw_rect(Rect2(inset, view.y - inset - 14.0, view.x - inset * 2.0, 14.0), color)
		draw_rect(Rect2(inset, inset, 14.0, view.y - inset * 2.0), color)
		draw_rect(Rect2(view.x - inset - 14.0, inset, 14.0, view.y - inset * 2.0), color)


func _draw_vitals(you: Dictionary) -> void:
	var origin := Vector2(16, 16)
	var maximum: float = maxf(float(you.get("max_health", Defs.MAX_HEALTH)), 1.0)
	var health: float = float(you["health"])
	var statuses: Array = []
	var infection: float = float(you.get("infection", 0.0))
	var bleeding: float = float(you.get("bleeding", 0.0))
	var exposure: float = float(you.get("exposure", 0.0))
	if infection > 0.5:
		statuses.append(["INFECTION %d%%" % int(infection), Color(0.75, 0.4, 0.95), "virus"])
	if bleeding > 0.5:
		statuses.append(["BLEEDING %d%%" % int(bleeding), Color(0.95, 0.3, 0.35), "drop"])
	var fracture: float = float(you.get("fracture", 0.0))
	if fracture > 0.5:
		statuses.append(["FRACTURE %d%%" % int(fracture), Color(0.95, 0.65, 0.3), "bolt"])
	if exposure > 0.5:
		statuses.append(["COLD %d%%" % int(exposure), Color(0.5, 0.82, 0.98), "flake"])
	var rows := 1 if statuses.is_empty() else 2
	var card := Rect2(origin, Vector2(318, 134 + rows * 30 - 30))
	_card(card)
	# Level badge: the sum of all skill levels.
	var badge := origin + Vector2(34, 34)
	draw_circle(badge, 22, Color(0, 0, 0, 0.5))
	draw_arc(badge, 21, -PI * 0.5, -PI * 0.5 + TAU * clampf(_skill_progress_total(), 0.0, 1.0), 40, GOLD, 3.0, true)
	draw_arc(badge, 21, 0, TAU, 40, Color(1, 1, 1, 0.12), 1.0)
	_text(badge + Vector2(-20, 6), str(_total_level()), 18, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 40)
	var title: String = "Survivor"
	if "player_name" in client:
		title = str(client.player_name)
	_text(origin + Vector2(66, 28), title, 17, INK)
	var weapon_name: String = "Fists"
	if str(you.get("weapon", "")) != "":
		weapon_name = str(Defs.item(str(you["weapon"])).get("name", you["weapon"]))
	_text(origin + Vector2(66, 47), "%s   |   %d kills" % [weapon_name, int(you.get("kills", 0))], 12, DIM)
	# Health with a trailing "recent damage" bar.
	var fraction: float = clampf(health / maximum, 0.0, 1.0)
	var shown: float = _ease("health", fraction, 9.0)
	_trail_health = move_toward(_trail_health, fraction, get_process_delta_time() * 0.18) if fraction < _trail_health else fraction
	var heart_center := origin + Vector2(26, 76)
	var pulse: float = 1.0 + (0.1 * sin(_time * 7.0) if fraction < 0.3 else 0.0)
	_icon_heart(heart_center, 26.0 * pulse, Color(0.95, 0.25, 0.3))
	var health_color := Color(0.85, 0.2, 0.25).lerp(Color(0.35, 0.8, 0.3), clampf((fraction - 0.25) / 0.5, 0.0, 1.0))
	_bar(Rect2(origin + Vector2(48, 62), Vector2(258, 26)), shown, health_color, _trail_health, "%d / %d" % [mini(roundi(health), roundi(maximum)), roundi(maximum)], 9)
	# Stamina and combat energy, thin.
	var stamina: float = clampf(float(you.get("stamina", Defs.MAX_STAMINA)) / Defs.MAX_STAMINA, 0.0, 1.0)
	var energy: float = clampf(float(you.get("combat_energy", Defs.COMBAT_ENERGY_MAX)) / Defs.COMBAT_ENERGY_MAX, 0.0, 1.0)
	_icon_bolt(origin + Vector2(26, 100), 18.0, Color(0.5, 0.9, 0.4))
	_bar(Rect2(origin + Vector2(48, 95), Vector2(124, 11)), _ease("stamina", stamina, 12.0), Color(0.45, 0.85, 0.35), -1.0, "", 5)
	_icon_star(origin + Vector2(184, 100), 14.0, Color(1.0, 0.7, 0.25))
	_bar(Rect2(origin + Vector2(196, 95), Vector2(110, 11)), _ease("energy", energy, 12.0), Color(1.0, 0.65, 0.2), -1.0, "", 5)
	# Hunger and thirst.
	var hunger: float = clampf(float(you["hunger"]) / 100.0, 0.0, 1.0)
	var thirst: float = clampf(float(you["thirst"]) / 100.0, 0.0, 1.0)
	_icon_apple(origin + Vector2(26, 122), 20.0, Color(0.95, 0.65, 0.2) if hunger > 0.2 else Color(1.0, 0.3, 0.2))
	_bar(Rect2(origin + Vector2(48, 116), Vector2(124, 13)), _ease("hunger", hunger), Color(0.93, 0.66, 0.2) if hunger > 0.2 else Color(0.95, 0.3, 0.2), -1.0, "", 6)
	_icon_drop(origin + Vector2(184, 122), 20.0, Color(0.35, 0.65, 1.0) if thirst > 0.2 else Color(1.0, 0.35, 0.3))
	_bar(Rect2(origin + Vector2(196, 116), Vector2(110, 13)), _ease("thirst", thirst), Color(0.3, 0.6, 0.98) if thirst > 0.2 else Color(0.95, 0.3, 0.3), -1.0, "", 6)
	var x := origin.x + 12.0
	for status in statuses:
		x += _chip(Vector2(x, origin.y + 138.0), status[0], status[1], status[2])


func _draw_top_strip(you: Dictionary, view: Vector2) -> void:
	var zone: int = clampi(int(you.get("zone", 0)), 0, 3)
	var zone_color: Color = ZONE_COLORS[zone]
	var risk: String = "PvE   gear kept" if zone <= 1 else "PvP   full loot"
	var zone_text: String = "%s    %s" % [ZONE_TITLES[zone], risk]
	var width: float = _font.get_string_size(zone_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 44.0
	var rect := Rect2(Vector2(view.x * 0.5 - width * 0.5, 14), Vector2(width, 30))
	_box("zone%d" % zone, Color(zone_color.r * 0.22, zone_color.g * 0.22, zone_color.b * 0.22, 0.88), 15, 2.0, zone_color, 6).draw(get_canvas_item(), rect)
	draw_circle(rect.position + Vector2(17, 15), 5.0, zone_color)
	_text(rect.position + Vector2(30, 21), zone_text, 15, INK)
	# Clock and weather.
	var clock: float = client.server_time
	var phase: float = WorldCycle.phase(clock)
	var hours: float = fposmod(6.0 + phase * 24.0, 24.0)
	var weather: Dictionary = you.get("weather", {})
	var condition: String = str(weather.get("condition", "clear"))
	var sheltered: bool = bool(weather.get("sheltered", false))
	var info: String = "%02d:%02d   %s   %d C%s" % [int(hours), int(fposmod(hours, 1.0) * 60.0), condition.capitalize(), int(round(float(weather.get("temperature_c", 15.0)))), "   Sheltered" if sheltered else ""]
	var info_width: float = _font.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 50.0
	var info_rect := Rect2(Vector2(view.x * 0.5 - info_width * 0.5, 48), Vector2(info_width, 26))
	_box("clock", CARD, 13, 1.0, EDGE).draw(get_canvas_item(), info_rect)
	var icon_center := info_rect.position + Vector2(18, 13)
	if WorldCycle.is_night(clock):
		_icon_moon(icon_center, 20, Color(0.85, 0.9, 1.0), CARD)
	else:
		_icon_sun(icon_center, 20, Color(1.0, 0.82, 0.3))
	_text(info_rect.position + Vector2(34, 18), info, 13, INK)
	var fps_text := "%d fps" % Engine.get_frames_per_second()
	_text(Vector2(view.x * 0.5 - 40.0, 86.0), fps_text, 10, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_CENTER, 80.0)


func _draw_quest_card(you: Dictionary, view: Vector2) -> void:
	var lines: Array = []
	var journal: Variant = you.get("contract", Contracts.empty_state())
	var contract_text: String = Contracts.description(journal if journal is Dictionary else Contracts.empty_state())
	if contract_text != "":
		lines.append(["CONTRACT", contract_text])
	var daily: String = str(you.get("daily_description", ""))
	if daily != "":
		lines.append(["DAILY", daily])
	var alerts: Array = _alerts()
	if lines.is_empty() and alerts.is_empty():
		return
	var width := 240.0
	var x := view.x - width - 16.0
	var y := 234.0
	var wrapped: Array = []
	var height := 14.0
	for entry in lines:
		var text: String = str(entry[1]).replace("{ ", "").replace(" }", "").replace("\"", "")
		var parts := _wrap(text, width - 24.0, 12)
		wrapped.append([entry[0], parts])
		height += 18.0 + 15.0 * parts.size() + 6.0
	var alert_lines: Array = []
	for alert in alerts:
		alert_lines.append_array(_wrap(str(alert), width - 24.0, 12))
	height += 15.0 * alert_lines.size() + 6.0
	_card(Rect2(x, y, width, height))
	var cursor := y + 22.0
	for entry in wrapped:
		_text(Vector2(x + 12.0, cursor), entry[0], 11, GOLD)
		cursor += 18.0
		for part in entry[1]:
			_text(Vector2(x + 12.0, cursor), part, 12, INK)
			cursor += 15.0
		cursor += 6.0
	for line in alert_lines:
		_text(Vector2(x + 12.0, cursor), line, 12, Color(1.0, 0.55, 0.4))
		cursor += 15.0


func _alerts() -> Array:
	# Important lines of the old info text that a player must not miss.
	var result: Array = []
	var source: Label = client_info_label if client_info_label != null else null
	if source == null:
		return result
	for line in source.text.split("\n"):
		for marker in ["PvP COMBAT", "SELF-DEFENSE", "BLOOD SCENT", "WARDEN", "PARTY RALLY", "SCENT MASK", "FIELD STIM", "GHILLIE"]:
			if line.begins_with(marker):
				result.append(line)
				break
	return result


var client_info_label: Label


func _wrap(text: String, width: float, size: int) -> Array:
	var result: Array = []
	var line := ""
	for word in text.split(" "):
		var candidate: String = word if line == "" else line + " " + word
		if _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and line != "":
			result.append(line)
			line = word
		else:
			line = candidate
	if line != "":
		result.append(line)
	return result


func _draw_action_bar(you: Dictionary, view: Vector2) -> void:
	var weapon: String = str(you.get("weapon", ""))
	var active: Dictionary = Combat.active_skill(weapon)
	var slot := 62.0
	var gap := 10.0
	var slots := 5
	var total := slot * slots + gap * (slots - 1)
	var x := view.x * 0.5 - total * 0.5
	var y := view.y - slot - 22.0
	_card(Rect2(x - 12, y - 10, total + 24, slot + 20), 14)
	var weapon_info: Dictionary = Defs.item(weapon)
	var ammo_id: String = str(weapon_info.get("ammo", ""))
	var ammo_text: String = ""
	if ammo_id != "":
		ammo_text = str(client.inventory.count(ammo_id))
	# 0 weapon
	var weapon_rect := Rect2(x, y, slot, slot)
	_slot_box(weapon_rect, GOLD if weapon != "" else Color(1, 1, 1, 0.2))
	var center := weapon_rect.position + weapon_rect.size * 0.5 + Vector2(0, -3)
	if weapon == "":
		_icon_fist(center, 34, DIM)
	elif str(weapon_info.get("weapon", "melee")) == "ranged":
		_icon_gun(center, 38, Color(0.8, 0.85, 0.95))
	else:
		_icon_sword(center, 38, Color(0.85, 0.88, 0.95))
	_text(weapon_rect.position + Vector2(0, slot - 6), ammo_text if ammo_text != "" else "MELEE", 11, Color(1.0, 0.85, 0.4) if ammo_text != "" else DIM, HORIZONTAL_ALIGNMENT_CENTER, slot)
	_keycap(weapon_rect, "LMB")
	# 1 active skill (G) with a cooldown sweep
	var skill_rect := Rect2(x + (slot + gap), y, slot, slot)
	var skill_cooldown: float = float(you.get("skill_cooldown", 0.0))
	var skill_total: float = float(active.get("cooldown", 1.0)) if not active.is_empty() else 1.0
	var cost: float = float(active.get("energy_cost", 0.0))
	var affordable: bool = float(you.get("combat_energy", 0.0)) >= cost
	_slot_box(skill_rect, Color(1.0, 0.7, 0.25) if (not active.is_empty() and affordable) else Color(1, 1, 1, 0.2))
	_icon_star(skill_rect.position + skill_rect.size * 0.5 + Vector2(0, -3), 36, Color(1.0, 0.75, 0.3) if not active.is_empty() else Color(1, 1, 1, 0.25))
	if not active.is_empty():
		_text(skill_rect.position + Vector2(0, slot - 6), "%d" % int(cost), 11, Color(1.0, 0.8, 0.4) if affordable else Color(1.0, 0.4, 0.35), HORIZONTAL_ALIGNMENT_CENTER, slot)
	else:
		_text(skill_rect.position + Vector2(0, slot - 6), "NONE", 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, slot)
	_sweep(skill_rect, skill_cooldown / maxf(skill_total, 0.1))
	_keycap(skill_rect, "G")
	# 2 dodge (Space)
	var dodge_rect := Rect2(x + (slot + gap) * 2.0, y, slot, slot)
	var dodge_cooldown: float = float(you.get("dodge_cooldown", 0.0))
	_slot_box(dodge_rect, Color(0.5, 0.85, 1.0) if dodge_cooldown <= 0.0 else Color(1, 1, 1, 0.2))
	_icon_dodge(dodge_rect.position + dodge_rect.size * 0.5 + Vector2(0, -3), 36, Color(0.6, 0.88, 1.0))
	_text(dodge_rect.position + Vector2(0, slot - 6), "DODGE", 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, slot)
	_sweep(dodge_rect, dodge_cooldown / Evasion.COOLDOWN)
	_keycap(dodge_rect, "SPACE")
	# 3 drink (F)
	var drink_rect := Rect2(x + (slot + gap) * 3.0, y, slot, slot)
	_slot_box(drink_rect, Color(0.4, 0.7, 1.0) if _near_water() else Color(1, 1, 1, 0.2))
	_icon_drop(drink_rect.position + drink_rect.size * 0.5 + Vector2(0, -3), 36, Color(0.4, 0.7, 1.0) if _near_water() else Color(0.5, 0.6, 0.75))
	_text(drink_rect.position + Vector2(0, slot - 6), "DRINK", 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, slot)
	_keycap(drink_rect, "F")
	# 4 interact (E)
	var use_rect := Rect2(x + (slot + gap) * 4.0, y, slot, slot)
	_slot_box(use_rect, Color(1, 1, 1, 0.3))
	_icon_hand(use_rect.position + use_rect.size * 0.5 + Vector2(0, -3), 36, Color(0.9, 0.92, 1.0))
	_text(use_rect.position + Vector2(0, slot - 6), "USE", 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, slot)
	_keycap(use_rect, "E")


func _near_water() -> bool:
	if client == null or client.world == null or not client.you.has("x"):
		return false
	var here := Vector2(float(client.you["x"]), float(client.you["z"]))
	for i in 8:
		var spot := here + Vector2.from_angle(float(i) * TAU / 8.0) * 3.0
		if client.world.is_water(spot.x, spot.y):
			return true
	return false


func _slot_box(rect: Rect2, edge: Color) -> void:
	_box("slot" + edge.to_html(), Color(0.02, 0.03, 0.05, 0.78), 10, 2.0, edge).draw(get_canvas_item(), rect)


func _keycap(rect: Rect2, label: String) -> void:
	var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10.0
	var cap := Rect2(Vector2(rect.position.x + rect.size.x * 0.5 - width * 0.5, rect.position.y - 8.0), Vector2(width, 16.0))
	_box("cap", Color(0.12, 0.13, 0.18, 0.96), 5, 1.0, Color(1, 1, 1, 0.35)).draw(get_canvas_item(), cap)
	draw_string(_font, cap.position + Vector2(0, 12.0), label, HORIZONTAL_ALIGNMENT_CENTER, width, 10, INK)


## A clockwise pie of darkness that shrinks as the cooldown ends, with the seconds left in the middle.
func _sweep(rect: Rect2, remaining: float) -> void:
	remaining = clampf(remaining, 0.0, 1.0)
	if remaining <= 0.002:
		return
	var center := rect.position + rect.size * 0.5
	var points := PackedVector2Array([center])
	var steps := 28
	var start := -PI * 0.5
	for i in steps + 1:
		var angle: float = start + TAU * remaining * float(i) / float(steps)
		var direction := Vector2(cos(angle), sin(angle))
		var scale: float = minf(rect.size.x * 0.5 / maxf(absf(direction.x), 0.001), rect.size.y * 0.5 / maxf(absf(direction.y), 0.001))
		points.append(center + direction * scale * 0.96)
	draw_colored_polygon(points, Color(0, 0, 0, 0.62))


func _draw_xp_strip(view: Vector2) -> void:
	var age: float = _time - _last_skill_time
	if age > 9.0 or _last_skill == "" or not ("skills" in client):
		return
	var alpha: float = clampf((9.0 - age) / 1.5, 0.0, 1.0)
	var skill_name: String = str(Skills.SKILLS.get(_last_skill, {}).get("name", _last_skill))
	var level: int = client.skills.level(_last_skill)
	var progress: float = client.skills.progress(_last_skill)
	var width := 300.0
	var rect := Rect2(Vector2(view.x * 0.5 - width * 0.5, view.y - 118.0), Vector2(width, 20))
	var shown: float = _ease("xp_strip", progress, 8.0)
	_bar(rect, shown, Color(GOLD.r, GOLD.g, GOLD.b, alpha), -1.0, "", 8)
	_text(rect.position + Vector2(0, 15), "%s  Lv %d" % [skill_name, level], 12, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_CENTER, width)


func _draw_banner(view: Vector2) -> void:
	if _banner_time <= 0.0 or _banner_text == "":
		return
	var appear: float = clampf((3.2 - _banner_time) / 0.25, 0.0, 1.0)
	var fade: float = clampf(_banner_time / 0.6, 0.0, 1.0)
	var alpha: float = minf(appear, fade)
	var width: float = _font.get_string_size(_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 80.0
	var y: float = 120.0 - (1.0 - appear) * 18.0
	var rect := Rect2(Vector2(view.x * 0.5 - width * 0.5, y), Vector2(width, 54))
	var color := Color(_banner_color.r, _banner_color.g, _banner_color.b, alpha)
	_box("banner" + _banner_color.to_html(), Color(0.07, 0.06, 0.04, 0.92), 14, 2.0, _banner_color, 14).draw(get_canvas_item(), rect)
	draw_rect(Rect2(rect.position + Vector2(22, 8), Vector2(width - 44, 2)), Color(color.r, color.g, color.b, alpha * 0.8))
	_text(rect.position + Vector2(0, 37), _banner_text, 26, Color(color.r, color.g, color.b, alpha), HORIZONTAL_ALIGNMENT_CENTER, width)


## Character level: starts at 1 and grows with every skill level gained.
func _total_level() -> int:
	if "skills" in client:
		return client.skills.total_level() - Skills.SKILLS.size() + 1
	return 1


func _skill_progress_total() -> float:
	if not ("skills" in client) or _last_skill == "":
		return 0.0
	return client.skills.progress(_last_skill)
