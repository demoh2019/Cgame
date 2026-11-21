extends Control
## First-person brawling HUD: a wind-up arc around the crosshair while a power blow charges
## (white, turning orange when it will stagger), and the Rage bar under it (pulses when ready).

const STAGGER_CHARGE := 0.75
var charge := 0.0
var charging := false
var rage := 0.0
var rage_seconds := 0.0
var _pulse := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func update_state(new_charge: float, is_charging: bool, new_rage: float, new_rage_seconds: float, delta: float) -> void:
	_pulse += delta
	if absf(new_charge - charge) > 0.001 or is_charging != charging or absf(new_rage - rage) > 0.1 \
			or new_rage_seconds > 0.0 or rage >= 100.0 or rage_seconds != new_rage_seconds:
		charge = new_charge
		charging = is_charging
		rage = new_rage
		rage_seconds = new_rage_seconds
		queue_redraw()


func _draw() -> void:
	var centre: Vector2 = size * 0.5
	if charging and charge > 0.0:
		var colour := Color(1, 1, 1, 0.85) if charge < STAGGER_CHARGE else Color(1.0, 0.55, 0.15, 0.95)
		draw_arc(centre, 22.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 48, colour, 3.0, true)
		if charge >= 1.0:
			draw_arc(centre, 27.0, 0.0, TAU, 48, Color(1.0, 0.3, 0.1, 0.6 + 0.3 * sin(_pulse * 18.0)), 2.0, true)
	# Rage bar.
	var width := 160.0
	var bar := Rect2(centre + Vector2(-width * 0.5, 46.0), Vector2(width, 5.0))
	if rage <= 0.5 and rage_seconds <= 0.0:
		return
	draw_rect(bar, Color(0, 0, 0, 0.45))
	var fill: float = rage_seconds / 12.0 if rage_seconds > 0.0 else rage / 100.0
	var hot := Color(0.95, 0.15, 0.1, 0.95)
	if rage >= 100.0 and rage_seconds <= 0.0:
		hot = hot.lerp(Color(1, 0.85, 0.3), 0.5 + 0.5 * sin(_pulse * 6.0))
		draw_string(ThemeDB.fallback_font, bar.position + Vector2(0, 20), "R — RAGE", HORIZONTAL_ALIGNMENT_CENTER, width, 13, hot)
	draw_rect(Rect2(bar.position, Vector2(width * clampf(fill, 0.0, 1.0), bar.size.y)), hot)
