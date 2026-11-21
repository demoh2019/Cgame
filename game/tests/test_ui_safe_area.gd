extends RefCounted
## Safe-area insets for HUD margins.

const UiSafeArea = preload("res://scripts/client/ui_safe_area.gd")


func run(t) -> void:
	t.current = "ui safe area"
	var full: Dictionary = UiSafeArea.insets(Vector2i(1280, 800), Rect2i(0, 0, 1280, 800))
	t.eq(full["left"] + full["top"] + full["right"] + full["bottom"], 0, "fully safe window has no insets")
	var notch: Dictionary = UiSafeArea.insets(Vector2i(2400, 1080), Rect2i(90, 0, 2220, 1060))
	t.eq(notch["left"], 90, "left notch inset")
	t.eq(notch["right"], 90, "symmetric right inset")
	t.eq(notch["bottom"], 20, "home indicator inset")
	var outside: Dictionary = UiSafeArea.insets(Vector2i(800, 600), Rect2i(-50, -50, 2000, 2000))
	t.eq(outside["left"], 0, "a safe area larger than the window gives no inset")
	t.eq(UiSafeArea.insets(Vector2i.ZERO, Rect2i())["top"], 0, "degenerate input is safe")
	var margin := MarginContainer.new()
	UiSafeArea.apply(margin, notch)
	t.eq(margin.get_theme_constant("margin_left"), 104, "base margin plus inset")
	margin.free()
