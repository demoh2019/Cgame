extends RefCounted
## A real red/black-zone ruin cache can wake a finite infected pack.
## Only the authoritative server knows the crate, world seed and loot result.
## No bonus treasure is minted and spawned enemies occupy no respawn slot.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const SupplyDrops = preload("res://scripts/shared/supply_drops.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")

const MAX_ACTIVE_INFECTED := 88
const MAX_ACTIVE_WAVES := 3
const COOLDOWN_SECONDS := 90.0
const LIFETIME_SECONDS := 150.0
const RED_WAKE_CHANCE := 35
const BLACK_WAKE_CHANCE := 60


## Sealed compartments are always noisy; ordinary crates have a stable
## per-site chance. The roll cannot be rerolled by logout or waiting.
static func awakens(zone: int, crate_id: int, world_seed: int, lockpicked: bool) -> bool:
	if not ZoneRisk.full_loot(zone) or crate_id <= 0:
		return false
	if lockpicked:
		return true
	var threshold: int = BLACK_WAKE_CHANCE if zone == 3 else RED_WAKE_CHANCE
	return WorldGen.mix(crate_id, world_seed, 0, 8961) % 100 < threshold


static func available(active: Array, infected: Dictionary) -> int:
	if active.size() >= MAX_ACTIVE_WAVES:
		return 0
	return maxi(0, MAX_ACTIVE_INFECTED - infected.size())


## Reuses the same safe, collision-checked ring as guarded supply drops.
## The given crate zone MUST match real terrain; no target coordinates or
## enemy type are supplied by a player or network request.
static func sites(world, crate: Dictionary, survivors: Array[Vector3],
		infected: Dictionary, capacity: int, angle_offset: int = 0) -> Array[Dictionary]:
	if world == null or capacity <= 0:
		return []
	var x: float = float(crate.get("x", NAN))
	var z: float = float(crate.get("z", NAN))
	var zone: int = int(crate.get("zone", -1))
	if not is_finite(x) or not is_finite(z) or not ZoneRisk.full_loot(zone):
		return []
	if world.zone_at(x, z) != zone or world.is_safe(x, z):
		return []
	var site: Dictionary = {"x": x, "z": z, "zone": zone}
	return SupplyDrops.guard_sites(world, site, survivors, infected,
		mini(capacity, 3), angle_offset)
