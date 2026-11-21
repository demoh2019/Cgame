extends RefCounted
## Safe-area insets (notches, rounded corners, TV overscan, Steam Deck/handheld
## bezels): HUD margins grow by the part of the window the display reports as
## unsafe, so nothing important is drawn under a cut-out.

const BASE_MARGIN := 14


## Per-side insets in window pixels for a window of `window_size` whose safe
## rectangle (in the same pixel space) is `safe_rect`.
static func insets(window_size: Vector2i, safe_rect: Rect2i) -> Dictionary:
	if window_size.x <= 0 or window_size.y <= 0 or safe_rect.size.x <= 0 or safe_rect.size.y <= 0:
		return {"left": 0, "top": 0, "right": 0, "bottom": 0}
	var safe := safe_rect.intersection(Rect2i(Vector2i.ZERO, window_size))
	return {
		"left": maxi(0, safe.position.x),
		"top": maxi(0, safe.position.y),
		"right": maxi(0, window_size.x - safe.end.x),
		"bottom": maxi(0, window_size.y - safe.end.y),
	}


## Current insets of the main window, converted to the viewport's 2D space.
static func current(viewport: Viewport) -> Dictionary:
	if viewport == null or DisplayServer.get_name() == "headless":
		return insets(Vector2i.ONE, Rect2i(Vector2i.ZERO, Vector2i.ONE))
	var window_pos: Vector2i = DisplayServer.window_get_position()
	var window_size: Vector2i = DisplayServer.window_get_size()
	var screen_safe: Rect2i = DisplayServer.get_display_safe_area()
	var local_safe := Rect2i(screen_safe.position - window_pos, screen_safe.size)
	var raw: Dictionary = insets(window_size, local_safe)
	# Stretch modes scale the 2D canvas: convert window pixels to canvas units.
	var canvas_size: Vector2 = viewport.get_visible_rect().size
	var scale := Vector2(canvas_size.x / maxf(1.0, float(window_size.x)), canvas_size.y / maxf(1.0, float(window_size.y)))
	return {
		"left": int(round(float(raw["left"]) * scale.x)),
		"top": int(round(float(raw["top"]) * scale.y)),
		"right": int(round(float(raw["right"]) * scale.x)),
		"bottom": int(round(float(raw["bottom"]) * scale.y)),
	}


static func apply(margin: MarginContainer, inset: Dictionary, base: int = BASE_MARGIN) -> void:
	if margin == null:
		return
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, base + int(inset.get(side, 0)))
