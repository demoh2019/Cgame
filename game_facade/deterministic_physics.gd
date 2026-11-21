extends RefCounted
## Facade for the deterministic rigid-body solver. Prefers the native engine class
## CgameDeterministicPhysics and falls back to scripts/shared/deterministic_physics.gd.
## Use create() instead of new() and the SHAPE_* constants instead of Shape.*.
##
## Differences: native bodies are addressed by id only (use get_body_info(id) instead of get_body(id) or
## the bodies array); timelines attach through the physics_timeline facade.

const _FALLBACK_SCRIPT = preload("res://scripts/shared/deterministic_physics.gd")
const NATIVE_CLASS: String = "CgameDeterministicPhysics"
const SHAPE_SPHERE: int = 0
const SHAPE_BOX: int = 1

static var _native: int = -1 # -1 unknown, 0 no, 1 yes


static func is_native() -> bool:
	if _native < 0:
		_native = 1 if ClassDB.class_exists(NATIVE_CLASS) else 0
	return _native == 1


static func create() -> RefCounted:
	if is_native():
		return ClassDB.instantiate(NATIVE_CLASS)
	return _FALLBACK_SCRIPT.new()
