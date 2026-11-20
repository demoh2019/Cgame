extends RefCounted
## Shallow-water drag on foot and bicycles, driven by real terrain depth.
## Both the authoritative server and predictive client use this rule.

const WadingWetness = preload("res://scripts/shared/wading_wetness.gd")
const SPRINT_MAX_DEPTH := 0.25 # More than ankle-deep: no sprinting.
const FOOT_DRAG_AT_ONE_METER := 0.35
const BIKE_DRAG_AT_ONE_METER := 0.45


## The server checks before charging sprint stamina; shared Movement.step
## also checks so a forged sprint flag cannot grant speed in the water.
static func can_sprint(world, position: Vector3) -> bool:
	return WadingWetness.depth_at(world, position) <= SPRINT_MAX_DEPTH


## Existing foot and bike speed factors continue to stack multiplicatively.
## Depth is capped by the same 1 m limit enforced by world collision.
static func factor(world, position: Vector3, mounted: bool) -> float:
	var depth: float = WadingWetness.depth_at(world, position)
	if depth <= 0.0:
		return 1.0
	var loss: float = BIKE_DRAG_AT_ONE_METER if mounted else FOOT_DRAG_AT_ONE_METER
	return clampf(1.0 - depth * loss, 1.0 - loss, 1.0)
