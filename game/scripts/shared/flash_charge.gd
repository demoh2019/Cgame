extends RefCounted
## Short PvE-only group stun paid for by an actual workbench-crafted charge.
## The server derives impact and targets; existing blockers stop the throw
## and the flash cannot bypass obstacles or stun raid bosses.

const NoiseDecoy = preload("res://scripts/shared/noise_decoy.gd")
const RangedCover = preload("res://scripts/shared/ranged_cover.gd")
const ITEM_ID := "flash_charge"
const RADIUS := 5.5
const STAGGER_SECONDS := 1.25
const MAX_TARGETS := 4
const COOLDOWN_SECONDS := 12.0
const PLAYER_NOISE_RADIUS := 28.0
const NOISE_SECONDS := 1.8


static func landing(world, origin: Vector3, direction: Vector2) -> Dictionary:
	return NoiseDecoy.landing(world, origin, direction)


static func targets(world, site: Dictionary, enemies: Dictionary) -> Array:
	var chosen: Array = []
	var x: float = float(site.get("x", NAN))
	var z: float = float(site.get("z", NAN))
	if not is_finite(x) or not is_finite(z):
		return chosen
	var center := Vector2(x, z)
	for enemy in enemies.values():
		if enemy == null or not enemy.is_alive() or enemy.raid_boss or not enemy.position.is_finite():
			continue
		var point := Vector2(enemy.position.x, enemy.position.z)
		var offset: Vector2 = point - center
		var distance: float = offset.length()
		if not is_finite(distance) or distance > RADIUS:
			continue
		if distance > 0.1 and RangedCover.first_blocker_distance(
				world, center, offset, distance) < distance:
			continue
		chosen.append(enemy)
	# Stable nearest first even if the server's Dictionary iteration changes.
	chosen.sort_custom(func(a, b):
		var left: float = center.distance_squared_to(Vector2(a.position.x, a.position.z))
		var right: float = center.distance_squared_to(Vector2(b.position.x, b.position.z))
		if is_equal_approx(left, right):
			return a.id < b.id
		return left < right)
	if chosen.size() > MAX_TARGETS:
		chosen.resize(MAX_TARGETS)
	return chosen
