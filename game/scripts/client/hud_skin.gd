extends Control
## The heads-up display's look: a vitals card with animated bars and status chips, a zone and clock strip, a quest card under
## the minimap, an action bar with cooldown sweeps, an XP strip, a banner for big moments and screen-edge feedback (low health
## pulse, damage flash). It only draws what `client.you` already says; nothing here can change the game.
## The old text labels of hud.gd stay alive (hidden) and F3 shows them as a details panel.

const UiSettings = preload("res://scripts/client/ui_settings.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Contracts = preload("res://scripts/shared/contracts.gd")
const FirstSteps = preload("res://scripts/client/first_steps.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const Evasion = preload("res://scripts/shared/evasion.gd")
const Skills = preload("res://scripts/shared/skills.gd")
const ItemIcons = preload("res://scripts/client/item_icons.gd")

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
var _draw_delta := 0.0 # Time since the last redraw; easing in _draw advances by it (redraws are throttled).
var _since_draw := 0.0
const REDRAW_INTERVAL := 1.0 / 30.0 # ~45 draw calls rebuilt every frame cost ~1.6 ms of CPU; 30 Hz reads the same.
var _font: Font
var _textures: Dictionary = {}
var _vitals_bottom := 150.0 # Where the vitals block ends, so the quest card can sit under it.

const WOOD := Color(0.24, 0.16, 0.1)
const BRONZE := Color(0.72, 0.55, 0.3)
const PARCHMENT := Color(0.93, 0.86, 0.72)
const INK_DARK := Color(0.24, 0.15, 0.08)


func setup(p_client) -> void:
	client = p_client
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	client.event_received.connect(_on_event)


## An interface silhouette (assets/icons/ui) or item icon, loaded once.
func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


## A white silhouette drawn centred in a square of side `size`, with a soft dark copy under it.
func _glyph(path: String, center: Vector2, size: float, color: Color) -> void:
	var texture: Texture2D = _texture(path)
	if texture == null:
		return
	var rect := Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size))
	draw_texture_rect(texture, Rect2(rect.position + Vector2(1.5, 2.0), rect.size), false, Color(0, 0, 0, 0.55))
	draw_texture_rect(texture, rect, false, color)


## A round medallion: a dark wooden rim, a bronze ring and a coloured face lit from above.
func _medallion(center: Vector2, radius: float, face: Color, ring: Color) -> void:
	draw_circle(center + Vector2(0, 3), radius + 2.0, Color(0, 0, 0, 0.35))
	draw_circle(center, radius + 1.0, WOOD)
	draw_arc(center, radius - 1.5, 0, TAU, 48, ring, 3.0, true)
	draw_circle(center, radius - 4.0, face.darkened(0.35))
	draw_circle(center + Vector2(0, -(radius - 4.0) * 0.18), (radius - 4.0) * 0.82, face)
	draw_arc(center, radius - 4.5, PI * 1.15, PI * 1.85, 24, Color(1, 1, 1, 0.22), 2.0, true)


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
	_since_draw += delta
	# Hit flashes, banners and the low-health pulse stay at full rate; steady bars refresh at 30 Hz.
	if _since_draw >= REDRAW_INTERVAL or _flash > 0.0 or _banner_time > 0.0:
		_draw_delta = _since_draw
		_since_draw = 0.0
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
	current = lerpf(current, target, clampf(_draw_delta * speed, 0.0, 1.0))
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
	var steady: bool = UiSettings.flash_scale() == 0.0 # "Reduce flashes": no hit flash, no low-health pulsing.
	var intensity: float = 0.0 if steady else _flash * 0.55
	if fraction < 0.3 and bool(you.get("alive", true)):
		intensity = maxf(intensity, (0.3 - fraction) / 0.3 * (0.28 if steady else 0.28 + 0.14 * sin(_time * 5.0)))
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
	# One compact unit in the manner of online RPG unit frames: the round portrait, a parchment name plate with notched
	# ends, and right under it a dark frame with thin health and energy bars carrying their numbers.
	var portrait := Vector2(54, 54)
	var fraction: float = clampf(health / maximum, 0.0, 1.0)
	var left := 92.0
	var right := 316.0
	# The bar frame first, so the portrait ring overlaps its left end.
	var frame := Rect2(Vector2(left - 14.0, 36), Vector2(right - left + 18.0, 36))
	_box("barframe", Color(0.13, 0.09, 0.06, 0.94), 7, 2.0, Color(0.55, 0.42, 0.24)).draw(get_canvas_item(), frame)
	# Name plate: parchment with notched ends.
	var plate_top := 10.0
	var plate_h := 24.0
	var plate := PackedVector2Array([Vector2(left - 6.0, plate_top), Vector2(right, plate_top), Vector2(right - 8.0, plate_top + plate_h * 0.5),
		Vector2(right, plate_top + plate_h), Vector2(left - 6.0, plate_top + plate_h)])
	draw_colored_polygon(plate, PARCHMENT)
	var outline := plate.duplicate()
	outline.append(plate[0])
	draw_polyline(outline, WOOD, 2.0, true)
	var title: String = "Survivor"
	if "player_name" in client:
		title = str(client.player_name)
	draw_string(_font, Vector2(left + 4.0, plate_top + 17.0), title, HORIZONTAL_ALIGNMENT_CENTER, right - left - 20.0, 14, INK_DARK)
	# Health (with a light trail of recent damage) and energy.
	var shown: float = _ease("health", fraction, 9.0)
	_trail_health = move_toward(_trail_health, fraction, _draw_delta * 0.18) if fraction < _trail_health else fraction
	_framed_bar(Rect2(Vector2(left, 40), Vector2(right - left, 14)), shown, Color(0.78, 0.16, 0.13), _trail_health,
		"%d / %d" % [mini(roundi(health), roundi(maximum)), roundi(maximum)], 11)
	var energy: float = clampf(float(you.get("combat_energy", Defs.COMBAT_ENERGY_MAX)) / Defs.COMBAT_ENERGY_MAX, 0.0, 1.0)
	_framed_bar(Rect2(Vector2(left, 56), Vector2(right - left, 12)), _ease("energy", energy, 12.0), Color(0.22, 0.46, 0.88), -1.0,
		"%d / %d" % [roundi(energy * Defs.COMBAT_ENERGY_MAX), roundi(Defs.COMBAT_ENERGY_MAX)], 10)
	# Stamina only shows while it is being spent: a thin green line along the bottom of the frame.
	var stamina: float = clampf(float(you.get("stamina", Defs.MAX_STAMINA)) / Defs.MAX_STAMINA, 0.0, 1.0)
	var stamina_shown: float = _ease("stamina", stamina, 12.0)
	if stamina_shown < 0.995:
		draw_rect(Rect2(Vector2(left, 69.5), Vector2((right - left) * stamina_shown, 2.0)), Color(0.55, 0.88, 0.35))
	# The portrait on top: low health makes it pulse red; the gold arc is the progress to the next level.
	var pulse: float = 0.5 + 0.5 * sin(_time * 7.0) if fraction < 0.3 else 0.0
	_medallion(portrait, 44.0, Color(0.36, 0.3, 0.26).lerp(Color(0.55, 0.16, 0.14), pulse * 0.6), BRONZE)
	draw_arc(portrait, 42.5, -PI * 0.5, -PI * 0.5 + TAU * clampf(_skill_progress_total(), 0.0, 1.0), 64, Color(1.0, 0.82, 0.4), 3.0, true)
	_glyph("res://assets/icons/ui/portrait.svg", portrait + Vector2(0, 2), 54.0, Color(0.95, 0.88, 0.74))
	var badge := portrait + Vector2(30, 30)
	draw_circle(badge, 13.0, WOOD)
	draw_circle(badge, 11.0, Color(0.16, 0.11, 0.07))
	draw_arc(badge, 11.5, 0, TAU, 32, BRONZE, 1.5, true)
	_text(badge + Vector2(-13, 5), str(_total_level()), 13, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 26)
	# Conditions show as round icons under the portrait (hud.gd, the effects row), which also sets _vitals_bottom.
	statuses.clear()


## A bar in a dark wooden frame with a light trail of recent damage and its numbers on it.
func _framed_bar(rect: Rect2, value: float, color: Color, trail: float = -1.0, caption: String = "", caption_size: int = 12) -> void:
	value = clampf(value, 0.0, 1.0)
	var radius: int = int(minf(rect.size.y * 0.5, 6.0))
	_box("fbar%d" % radius, Color(0.08, 0.05, 0.03, 0.85), radius, 2.0, WOOD).draw(get_canvas_item(), rect)
	var inner := rect.grow(-2.0)
	if trail > value:
		_box("ftrail%d" % radius, Color(1.0, 0.9, 0.75, 0.6), maxi(radius - 1, 0)).draw(get_canvas_item(),
			Rect2(inner.position, Vector2(inner.size.x * trail, inner.size.y)))
	if value > 0.004:
		var fill := Rect2(inner.position, Vector2(maxf(inner.size.x * value, 2.0), inner.size.y))
		_box("ffill" + color.to_html() + str(radius), color, maxi(radius - 1, 0)).draw(get_canvas_item(), fill)
		_box("fgloss%d" % radius, Color(1, 1, 1, 0.2), maxi(radius - 2, 0)).draw(get_canvas_item(),
			Rect2(fill.position + Vector2(1, 1), Vector2(maxf(fill.size.x - 2.0, 0.0), fill.size.y * 0.4)))
	if caption != "" and caption_size > 0:
		_text(Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + caption_size * 0.36), caption, caption_size, INK,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


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
	# Keep the danger readable even when the detailed F3 HUD is hidden.
	var spore_state: Dictionary = you.get("spore", {})
	if bool(spore_state.get("active", false)):
		var warning: String = "INFECTED SPORES  +%.2f/s   FILTER %d%%" % [
			float(spore_state.get("rate", 0.0)),
			int(round(100.0 * float(spore_state.get("protection", 0.0))))]
		_text(Vector2(view.x * 0.5 - 180.0, 107.0), warning, 13,
			Color(1.0, 0.55, 0.32), HORIZONTAL_ALIGNMENT_CENTER, 360.0)
	if details_visible: # The frame counter is a debugging aid; it shows with the F9 readout only.
		var fps_text := "%d fps" % Engine.get_frames_per_second()
		_text(Vector2(view.x * 0.5 - 40.0, 86.0), fps_text, 10, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_CENTER, 80.0)


func _draw_quest_card(you: Dictionary, view: Vector2) -> void:
	var lines: Array = []
	var story: Dictionary = you.get("story", {})
	var story2: Dictionary = you.get("story2", {})
	if not story2.is_empty() and int(story2.get("stage", 0)) > 0:
		lines.append(["CHAPTER II — THE DEEP SIGNAL", str(story2.get("objective", ""))])
	elif not story.is_empty():
		lines.append(["CHAPTER I — BEACON SEVEN", str(story.get("objective", ""))])
	var guide: String = FirstSteps.current_text()
	if guide != "":
		lines.append(["FIRST STEPS  (Ctrl+F2 hides)", guide])
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
	var width := 300.0
	var x := 16.0
	var y := _vitals_bottom + 8.0
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
	var radius := 31.0
	var step := 76.0
	var count := 5
	var x0 := view.x * 0.5 - step * float(count - 1) * 0.5
	var y := view.y - radius - 26.0
	var weapon_info: Dictionary = Defs.item(weapon)
	var ammo_id: String = str(weapon_info.get("ammo", ""))
	# 0 weapon: the icon of the item in hand, the ammo left as a badge.
	var center := Vector2(x0, y)
	_medallion(center, radius, Color(0.55, 0.2, 0.15), BRONZE if weapon != "" else Color(0.45, 0.4, 0.35))
	if weapon == "":
		_glyph("res://assets/icons/ui/act_fist.svg", center, 34.0, Color(0.98, 0.93, 0.85))
	else:
		_glyph(ItemIcons.icon(weapon).resource_path if ItemIcons.icon(weapon) != null else "", center, 36.0, Color(0.98, 0.93, 0.85))
	if ammo_id != "":
		_count_badge(center + Vector2(radius * 0.72, -radius * 0.72), str(client.inventory.count(ammo_id)), Color(1.0, 0.85, 0.4))
	_key_badge(center, radius, "LMB")
	# 1 active skill (G) with its energy cost and a cooldown sweep.
	center = Vector2(x0 + step, y)
	var skill_cooldown: float = float(you.get("skill_cooldown", 0.0))
	var skill_total: float = float(active.get("cooldown", 1.0)) if not active.is_empty() else 1.0
	var cost: float = float(active.get("energy_cost", 0.0))
	var affordable: bool = float(you.get("combat_energy", 0.0)) >= cost
	var skill_ready: bool = not active.is_empty() and affordable
	_medallion(center, radius, Color(0.42, 0.22, 0.58) if not active.is_empty() else Color(0.3, 0.27, 0.32), Color(1.0, 0.75, 0.3) if skill_ready else Color(0.45, 0.4, 0.35))
	_glyph("res://assets/icons/ui/act_skill.svg", center, 34.0, Color(0.98, 0.93, 0.85, 1.0 if not active.is_empty() else 0.35))
	if not active.is_empty():
		_count_badge(center + Vector2(radius * 0.72, -radius * 0.72), "%d" % int(cost), Color(0.55, 0.75, 1.0) if affordable else Color(1.0, 0.4, 0.35))
	_sweep(center, radius - 4.0, skill_cooldown / maxf(skill_total, 0.1))
	_key_badge(center, radius, "G")
	# 2 dodge (Space)
	center = Vector2(x0 + step * 2.0, y)
	var dodge_cooldown: float = float(you.get("dodge_cooldown", 0.0))
	_medallion(center, radius, Color(0.16, 0.42, 0.5), Color(0.5, 0.85, 1.0) if dodge_cooldown <= 0.0 else Color(0.45, 0.4, 0.35))
	_glyph("res://assets/icons/ui/act_dodge.svg", center, 34.0, Color(0.98, 0.93, 0.85))
	_sweep(center, radius - 4.0, dodge_cooldown / Evasion.COOLDOWN)
	_key_badge(center, radius, "SPACE")
	# 3 drink (F), bright only next to water.
	center = Vector2(x0 + step * 3.0, y)
	var water: bool = _near_water()
	_medallion(center, radius, Color(0.16, 0.3, 0.58) if water else Color(0.25, 0.28, 0.34), Color(0.45, 0.75, 1.0) if water else Color(0.45, 0.4, 0.35))
	_glyph("res://assets/icons/ui/act_drink.svg", center, 30.0, Color(0.98, 0.93, 0.85, 1.0 if water else 0.45))
	_key_badge(center, radius, "F")
	# 4 interact (E)
	center = Vector2(x0 + step * 4.0, y)
	_medallion(center, radius, Color(0.24, 0.42, 0.2), BRONZE)
	_glyph("res://assets/icons/ui/act_use.svg", center, 32.0, Color(0.98, 0.93, 0.85))
	_key_badge(center, radius, "E")


## The key of a round button, on a small cream disc at its lower right.
func _key_badge(center: Vector2, radius: float, label: String) -> void:
	var size: int = 10 if label.length() <= 1 else 8
	var width: float = maxf(_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 8.0, 17.0)
	var at := center + Vector2(radius * 0.62, radius * 0.66)
	var rect := Rect2(at - Vector2(width * 0.5, 8.5), Vector2(width, 17.0))
	_box("keybadge", PARCHMENT, 8, 1.5, WOOD).draw(get_canvas_item(), rect)
	draw_string(_font, rect.position + Vector2(0, 12.5), label, HORIZONTAL_ALIGNMENT_CENTER, width, size, INK_DARK)


func _count_badge(center: Vector2, text: String, color: Color) -> void:
	var width: float = maxf(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10.0, 20.0)
	var rect := Rect2(center - Vector2(width * 0.5, 10.0), Vector2(width, 20.0))
	_box("countbadge", Color(0.1, 0.07, 0.04, 0.92), 10, 1.5, BRONZE).draw(get_canvas_item(), rect)
	draw_string(_font, rect.position + Vector2(0, 14.5), text, HORIZONTAL_ALIGNMENT_CENTER, width, 11, color)


func _near_water() -> bool:
	if client == null or client.world == null or not client.you.has("x"):
		return false
	var here := Vector2(float(client.you["x"]), float(client.you["z"]))
	for i in 8:
		var spot := here + Vector2.from_angle(float(i) * TAU / 8.0) * 3.0
		if client.world.is_water(spot.x, spot.y):
			return true
	return false


## A clockwise pie of darkness over a round button that shrinks as the cooldown ends.
func _sweep(center: Vector2, radius: float, remaining: float) -> void:
	remaining = clampf(remaining, 0.0, 1.0)
	if remaining <= 0.002:
		return
	var points := PackedVector2Array([center])
	var steps := 32
	for i in steps + 1:
		var angle: float = -PI * 0.5 + TAU * remaining * float(i) / float(steps)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, Color(0, 0, 0, 0.6))


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
