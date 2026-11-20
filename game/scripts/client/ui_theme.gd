extends RefCounted
## One look for the whole interface, in the manner of the classic online RPGs: windows are warm parchment cards with a
## dark wood frame, dark ink text, brown buttons and a red one for the main action; text that floats over the world
## (log, prompts, title screen) stays light with an outline. `apply` gives every window of a HUD layer the parchment
## theme and everything else the light one, so the HUD code does not need to know about it.

const GOLD := Color(0.92, 0.76, 0.34)
const PANEL := Color(0.06, 0.07, 0.1, 0.9)
# Parchment palette.
const PAPER := Color(0.93, 0.86, 0.72)
const PAPER_DARK := Color(0.84, 0.75, 0.6)
const WOOD := Color(0.33, 0.22, 0.13)
const INK := Color(0.24, 0.15, 0.08)
const INK_SOFT := Color(0.42, 0.32, 0.22)
const HEADING := Color(0.45, 0.22, 0.1)
const BUTTON := Color(0.47, 0.32, 0.19)
const ACCENT := Color(0.66, 0.2, 0.14) # The red of a confirm button.
const CREAM := Color(0.99, 0.95, 0.86)

static var _theme: Theme
static var _paper: Theme


## The light theme for text over the game world and the title screen.
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
	_buttons(_theme)
	_theme.set_stylebox("normal", "LineEdit", _box(Color(0.03, 0.04, 0.06, 0.92), 7, 1.0, Color(1, 1, 1, 0.2), 6))
	_theme.set_stylebox("focus", "LineEdit", _box(Color(0.03, 0.04, 0.06, 0.97), 7, 1.5, GOLD, 6))
	_theme.set_stylebox("panel", "TabContainer", _box(Color(0.04, 0.05, 0.07, 0.6), 8, 1.0, Color(1, 1, 1, 0.1), 6))
	_tooltips(_theme)
	return _theme


## Parchment for windows: inventory, crafting, skills, help.
static func paper_theme() -> Theme:
	if _paper != null:
		return _paper
	var t := Theme.new()
	_paper = t
	t.set_default_font_size(14)
	t.set_color("font_color", "Label", INK)
	t.set_constant("outline_size", "Label", 0)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	var frame := _box(PAPER, 12, 3.0, WOOD, 14)
	frame.shadow_color = Color(0, 0, 0, 0.45)
	frame.shadow_size = 10
	frame.shadow_offset = Vector2(0, 4)
	t.set_stylebox("panel", "PanelContainer", frame)
	t.set_stylebox("panel", "Panel", frame)
	_buttons(t)
	t.set_stylebox("normal", "LineEdit", _box(CREAM, 7, 1.5, INK_SOFT, 6))
	t.set_stylebox("focus", "LineEdit", _box(CREAM, 7, 2.0, HEADING, 6))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK_SOFT.r, INK_SOFT.g, INK_SOFT.b, 0.7))
	t.set_color("caret_color", "LineEdit", INK)
	for kind in ["CheckBox", "CheckButton"]:
		t.set_color("font_color", kind, INK)
		t.set_color("font_hover_color", kind, HEADING)
		t.set_color("font_pressed_color", kind, INK)
		t.set_color("font_hover_pressed_color", kind, HEADING)
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			t.set_stylebox(state, kind, StyleBoxEmpty.new())
	# Tabs: the open tab is the page itself, the others are darker paper behind it.
	t.set_stylebox("panel", "TabContainer", _box(PAPER_DARK, 8, 1.5, Color(WOOD.r, WOOD.g, WOOD.b, 0.5), 8))
	var open := _box(PAPER_DARK, 8, 1.5, Color(WOOD.r, WOOD.g, WOOD.b, 0.5), 7)
	open.corner_radius_bottom_left = 0
	open.corner_radius_bottom_right = 0
	open.border_width_bottom = 0
	t.set_stylebox("tab_selected", "TabContainer", open)
	var closed := _box(Color(0.72, 0.62, 0.47), 8, 1.0, Color(WOOD.r, WOOD.g, WOOD.b, 0.35), 7)
	closed.corner_radius_bottom_left = 0
	closed.corner_radius_bottom_right = 0
	t.set_stylebox("tab_unselected", "TabContainer", closed)
	var hovered := closed.duplicate() as StyleBoxFlat
	hovered.bg_color = Color(0.78, 0.68, 0.52)
	t.set_stylebox("tab_hovered", "TabContainer", hovered)
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabContainer", HEADING)
	t.set_color("font_unselected_color", "TabContainer", INK_SOFT)
	t.set_color("font_hovered_color", "TabContainer", INK)
	t.set_font_size("font_size", "TabContainer", 15)
	# Scroll bars: a thin wooden rail.
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, _box(Color(WOOD.r, WOOD.g, WOOD.b, 0.15), 4, 0.0, Color.TRANSPARENT, 3))
		t.set_stylebox("grabber", bar, _box(Color(WOOD.r, WOOD.g, WOOD.b, 0.6), 4, 0.0, Color.TRANSPARENT, 3))
		t.set_stylebox("grabber_highlight", bar, _box(WOOD, 4, 0.0, Color.TRANSPARENT, 3))
		t.set_stylebox("grabber_pressed", bar, _box(HEADING, 4, 0.0, Color.TRANSPARENT, 3))
	t.set_stylebox("background", "ProgressBar", _box(Color(WOOD.r, WOOD.g, WOOD.b, 0.25), 6, 1.0, Color(WOOD.r, WOOD.g, WOOD.b, 0.4), 0))
	t.set_stylebox("fill", "ProgressBar", _box(Color(0.5, 0.62, 0.25), 6, 0.0, Color.TRANSPARENT, 0))
	t.set_color("font_color", "ProgressBar", INK)
	t.set_color("font_color", "RichTextLabel", INK)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_constant("separation", "HSeparator", 8)
	_tooltips(t)
	return t


static func _buttons(t: Theme) -> void:
	t.set_stylebox("normal", "Button", _raised(BUTTON))
	t.set_stylebox("hover", "Button", _raised(BUTTON.lightened(0.14)))
	t.set_stylebox("pressed", "Button", _raised(ACCENT, true))
	t.set_stylebox("hover_pressed", "Button", _raised(ACCENT.lightened(0.1), true))
	t.set_stylebox("disabled", "Button", _box(Color(0.82, 0.74, 0.6, 0.9), 7, 1.0, Color(WOOD.r, WOOD.g, WOOD.b, 0.3), 6))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color(1, 0.98, 0.9))
	t.set_color("font_pressed_color", "Button", Color(1, 0.96, 0.88))
	t.set_color("font_focus_color", "Button", CREAM)
	t.set_color("font_disabled_color", "Button", Color(INK_SOFT.r, INK_SOFT.g, INK_SOFT.b, 0.85))
	t.set_color("font_outline_color", "Button", Color(0.12, 0.07, 0.03, 0.7))
	t.set_constant("outline_size", "Button", 2)
	# Drop-down lists of option buttons.
	t.set_stylebox("panel", "PopupMenu", _box(PAPER, 8, 2.0, WOOD, 6))
	t.set_stylebox("hover", "PopupMenu", _box(Color(BUTTON.r, BUTTON.g, BUTTON.b, 0.9), 5, 0.0, Color.TRANSPARENT, 4))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", CREAM)
	t.set_color("font_disabled_color", "PopupMenu", Color(INK_SOFT.r, INK_SOFT.g, INK_SOFT.b, 0.6))


## A button that stands out of the paper: a darker bottom edge like a wooden plaque.
static func _raised(color: Color, sunk: bool = false) -> StyleBoxFlat:
	var style := _box(color, 7, 1.5, color.darkened(0.45), 6)
	style.border_width_bottom = 1 if sunk else 3
	style.border_width_top = 2 if sunk else 1
	style.shadow_color = Color(0, 0, 0, 0.0)
	style.shadow_size = 0
	return style


static func _tooltips(t: Theme) -> void:
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.96, 0.9, 0.77, 0.98), 8, 2.0, WOOD, 8))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", 13)


static func _box(color: Color, radius: int, border: float, border_color: Color, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(int(ceil(border)) if border > 0.0 else 0)
	style.border_color = border_color
	style.set_content_margin_all(margin)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6 if margin >= 8 else 0
	style.anti_aliasing = true
	return style


## Windows (panels) of a HUD layer get parchment, everything else the light theme; colored bars it created are rounded.
static func apply(layer: CanvasLayer) -> void:
	for child in layer.get_children():
		if child is PanelContainer or child is Panel:
			(child as Control).theme = paper_theme()
		elif child is Control:
			(child as Control).theme = get_theme()
	for bar in layer.find_children("*", "ProgressBar", true, false):
		var fill: StyleBox = bar.get_theme_stylebox("fill")
		if fill is StyleBoxFlat and bar.has_theme_stylebox_override("fill"):
			(fill as StyleBoxFlat).set_corner_radius_all(7)
