extends RefCounted
## Paid, temporary sentry alarm on a real server-owned campfire.
## Scans are bounded by a two-second cadence and reveal no enemy positions.
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")

const ITEM_ID := "camp_alarm_kit"
const ARM_RANGE := 3.2
const ARM_HEIGHT := 2.5
const MIN_FUEL_SECONDS := 45.0
const DURATION := 180.0
const SCAN_INTERVAL := 2.0
const ALERT_COOLDOWN := 24.0
const DETECTION_RADIUS := 21.0
const DETECTION_HEIGHT := 8.0
const MAX_DETECTED := 5


static func seconds_left(fire: Dictionary, now: float) -> float:
	if not is_finite(now):
		return 0.0
	var deadline: float = float(fire.get("alarm_until", -INF))
	var burning: float = float(fire.get("expires", -INF))
	if not is_finite(deadline) or not is_finite(burning):
		return 0.0
	return maxf(0.0, minf(deadline, burning) - now)


static func arm_reason(fire: Dictionary, position: Vector3, now: float) -> String:
	if not position.is_finite() or not is_finite(now) or now < 0.0:
		return "invalid_position"
	if fire.is_empty():
		return "no_fire"
	var expiry: float = float(fire.get("expires", NAN))
	var x: float = float(fire.get("x", NAN))
	var y: float = float(fire.get("y", NAN))
	var z: float = float(fire.get("z", NAN))
	if not is_finite(expiry) or not is_finite(x) or not is_finite(y) or not is_finite(z):
		return "invalid_fire"
	if expiry <= now:
		return "no_fire"
	var offset := Vector2(position.x - x, position.z - z)
	if offset.length_squared() > ARM_RANGE * ARM_RANGE or absf(position.y - y) > ARM_HEIGHT:
		return "too_far"
	if seconds_left(fire, now) > 0.0:
		return "already_armed"
	if expiry - now < MIN_FUEL_SECONDS:
		return "low_fuel"
	return ""


static func install(fire: Dictionary, owner_id: int, group_id: int, now: float) -> void:
	fire["alarm_owner"] = owner_id
	fire["alarm_group"] = maxi(0, group_id)
	fire["alarm_until"] = minf(float(fire["expires"]), now + DURATION)
	fire["alarm_next_scan"] = now + SCAN_INTERVAL
	fire["alarm_next_alert"] = now


## A positive result authorizes ONE private event, not an automatic attack.
## No enemies are spawned, damaged, or exposed with exact coordinates.
static func scan(fire: Dictionary, zombies: Dictionary, now: float,
		precomputed_count: int = -1) -> int:
	if not is_finite(now) or now < 0.0 or seconds_left(fire, now) <= 0.0:
		return 0
	var next_scan: float = float(fire.get("alarm_next_scan", INF))
	var next_alert: float = float(fire.get("alarm_next_alert", INF))
	if not is_finite(next_scan) or not is_finite(next_alert) or now < next_scan:
		return 0
	fire["alarm_next_scan"] = now + SCAN_INTERVAL
	var fx: float = float(fire.get("x", NAN))
	var fy: float = float(fire.get("y", NAN))
	var fz: float = float(fire.get("z", NAN))
	if not is_finite(fx) or not is_finite(fy) or not is_finite(fz):
		return 0
	var detected := 0
	if precomputed_count >= 0 and precomputed_count <= MAX_DETECTED:
		# The server-only native spatial query is a candidate count, never
		# an authorization to bypass timing, fuel, owner or alert cooldown.
		detected = precomputed_count
	else:
		for infected in zombies.values():
			if infected == null or not infected.is_alive() or not infected.position.is_finite():
				continue
			var point: Vector3 = infected.position
			if absf(point.y - fy) > DETECTION_HEIGHT:
				continue
			if Vector2(point.x - fx, point.z - fz).length_squared() > DETECTION_RADIUS * DETECTION_RADIUS:
				continue
			detected += 1
			if detected >= MAX_DETECTED:
				break
	if detected == 0 or now < next_alert:
		return 0
	fire["alarm_next_alert"] = now + ALERT_COOLDOWN
	return detected
