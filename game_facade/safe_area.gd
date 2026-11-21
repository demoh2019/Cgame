extends RefCounted
## Facade over the safe-area insets. Prefers the native CgameSafeArea (modules/cgame_platform) and falls back to
## scripts/client/ui_safe_area.gd. The helpers keep the original call signatures.

const LEGACY = preload("res://scripts/client/ui_safe_area.gd")
const NATIVE_CLASS := &"CgameSafeArea"
const BASE_MARGIN := 14

static var _native_instance: Object = null


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


static func _n() -> Object:
	if _native_instance == null:
		_native_instance = ClassDB.instantiate(NATIVE_CLASS)
	return _native_instance


## Per-side insets in window pixels: {left, top, right, bottom}.
static func insets(window_size: Vector2i, safe_rect: Rect2i) -> Dictionary:
	return _n().insets(window_size, safe_rect) if is_native() else LEGACY.insets(window_size, safe_rect)


## Current insets of the main window in the viewport's 2D space.
static func current(viewport: Viewport) -> Dictionary:
	return _n().current(viewport) if is_native() else LEGACY.current(viewport)


static func apply(margin: MarginContainer, inset: Dictionary, base: int = BASE_MARGIN) -> void:
	if is_native():
		_n().apply(margin, inset, base)
	else:
		LEGACY.apply(margin, inset, base)
