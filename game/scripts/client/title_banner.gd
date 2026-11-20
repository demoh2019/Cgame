extends MarginContainer
## The sign-in card of the title screen as a hanging cloth banner: deep red with a gold edge, a rod across the top and
## a pointed tail, the way fantasy online games present their login. Children are laid out inside the cloth.

const CLOTH := Color(0.42, 0.07, 0.07)
const CLOTH_DARK := Color(0.24, 0.03, 0.04)
const TRIM := Color(0.86, 0.66, 0.3)
const ROD := Color(0.3, 0.2, 0.12)
const TAIL := 70.0 # Height of the pointed end.


func _init() -> void:
	add_theme_constant_override("margin_left", 44)
	add_theme_constant_override("margin_right", 44)
	add_theme_constant_override("margin_top", 46)
	add_theme_constant_override("margin_bottom", int(TAIL) + 30)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _outline(inset: float) -> PackedVector2Array:
	var w: float = size.x
	var h: float = size.y
	return PackedVector2Array([Vector2(inset, 10.0 + inset), Vector2(w - inset, 10.0 + inset),
		Vector2(w - inset, h - TAIL - inset * 0.4), Vector2(w * 0.5, h - inset * 1.6), Vector2(inset, h - TAIL - inset * 0.4)])


func _draw() -> void:
	# Shadow, gold edge, then the cloth darkening toward its tail.
	var shadow := _outline(0.0)
	for i in shadow.size():
		shadow[i] += Vector2(6, 10)
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.4))
	draw_colored_polygon(_outline(0.0), TRIM)
	var cloth := _outline(7.0)
	var colors := PackedColorArray()
	for point in cloth:
		colors.append(CLOTH.lerp(CLOTH_DARK, clampf(point.y / size.y, 0.0, 1.0)))
	draw_polygon(cloth, colors)
	var inner := _outline(15.0)
	inner.append(inner[0])
	draw_polyline(inner, Color(TRIM.r, TRIM.g, TRIM.b, 0.35), 1.5, true)
	# The rod it hangs from, with round caps.
	draw_rect(Rect2(-14.0, 0.0, size.x + 28.0, 14.0), ROD)
	draw_rect(Rect2(-14.0, 2.0, size.x + 28.0, 4.0), Color(1, 1, 1, 0.12))
	for x in [-14.0, size.x + 14.0]:
		draw_circle(Vector2(x, 7.0), 11.0, TRIM.darkened(0.2))
		draw_circle(Vector2(x, 7.0), 7.0, TRIM)
