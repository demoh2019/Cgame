extends RefCounted
## One look for the whole interface: readable outlined text, rounded dark panels with a gold edge, soft buttons and
## rounded bars. Applied to the HUD's top-level controls, so the HUD code does not need to know about it.

const GOLD := Color(0.92, 0.76, 0.34)
const PANEL := Color(0.06, 0.07, 0.1, 0.9)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.set_default_font_size(15)
	_theme.set_color("font_color", "Label", Color(0.96, 0.97, 1.0))
	_theme.set_color("font_outline_color", "Label", Color(0.0, 0.0, 0.0, 0.85))
	_theme.set_constant("outline_size", "Label", 4)
	_theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	_theme.set_constant("shadow_offset_x", "Label", 1)
	_theme.set_constant("shadow_offset_y", "Label", 2)
	_theme.set_stylebox("panel", "PanelContainer", _box(PANEL, 12, 1.5, Color(GOLD.r, GOLD.g, GOLD.b, 0.55), 10))
	_theme.set_stylebox("panel", "Panel", _box(PANEL, 12, 1.5, Color(GOLD.r, GOLD.g, GOLD.b, 0.55), 10))
	_theme.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.5), 7, 1.0, Color(1, 1, 1, 0.12), 0))
	_theme.set_stylebox("fill", "ProgressBar", _box(Color(0.9, 0.75, 0.3), 7, 0.0, Color.TRANSPARENT, 0))
	_theme.set_stylebox("normal", "Button", _box(Color(0.14, 0.16, 0.21, 0.95), 7, 1.0, Color(1, 1, 1, 0.16), 6))
	_theme.set_stylebox("hover", "Button", _box(Color(0.2, 0.23, 0.3, 0.98), 7, 1.5, Color(GOLD.r, GOLD.g, GOLD.b, 0.8), 6))
	_theme.set_stylebox("pressed", "Button", _box(Color(0.3, 0.26, 0.14, 1.0), 7, 1.5, GOLD, 6))
	_theme.set_stylebox("disabled", "Button", _box(Color(0.1, 0.11, 0.14, 0.7), 7, 1.0, Color(1, 1, 1, 0.07), 6))
	_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	_theme.set_color("font_disabled_color", "Button", Color(0.55, 0.57, 0.62))
	_theme.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.6))
	_theme.set_constant("outline_size", "Button", 2)
	_theme.set_stylebox("normal", "LineEdit", _box(Color(0.03, 0.04, 0.06, 0.92), 7, 1.0, Color(1, 1, 1, 0.2), 6))
	_theme.set_stylebox("focus", "LineEdit", _box(Color(0.03, 0.04, 0.06, 0.97), 7, 1.5, GOLD, 6))
	_theme.set_stylebox("panel", "TabContainer", _box(Color(0.04, 0.05, 0.07, 0.6), 8, 1.0, Color(1, 1, 1, 0.1), 6))
	return _theme


static func _box(color: Color, radius: int, border: float, border_color: Color, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(int(ceil(border)) if border > 0.0 else 0)
	style.border_color = border_color
	style.set_content_margin_all(margin)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6 if margin >= 8 else 0
	return style


## Puts the theme on every top-level control of a HUD layer, and rounds the colored bars it created itself.
static func apply(layer: CanvasLayer) -> void:
	for child in layer.get_children():
		if child is Control:
			(child as Control).theme = get_theme()
	for bar in layer.find_children("*", "ProgressBar", true, false):
		var fill: StyleBox = bar.get_theme_stylebox("fill")
		if fill is StyleBoxFlat and bar.has_theme_stylebox_override("fill"):
			(fill as StyleBoxFlat).set_corner_radius_all(7)
