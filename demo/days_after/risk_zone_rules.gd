extends RefCounted
## Risk/reward rules for the one Days After sandbox world.
## These are game rules, not engine primitives. Coordinates are in metres.

const CAMP_CENTER := Vector2(0.0, 7.0)
const CAMP_RADIUS: float = 5.0
const EXCLUSION_RADIUS: float = 18.0
const HAZARD_DAMAGE_PER_SECOND: float = 2.5
const SCAVENGE_BONUS: int = 1
const INTERACTION_BONUS_RANGE: float = 3.5

const CAMP := "camp"
const WILDERNESS := "wilderness"
const EXCLUSION := "exclusion"


static func zone_at(world_position: Vector3) -> String:
    if not world_position.is_finite():
        return WILDERNESS
    var horizontal := Vector2(world_position.x, world_position.z)
    var distance := horizontal.distance_to(CAMP_CENTER)
    if distance <= CAMP_RADIUS:
        return CAMP
    if distance < EXCLUSION_RADIUS:
        return WILDERNESS
    return EXCLUSION


static func danger_damage(delta: float, world_position: Vector3) -> float:
    if delta <= 0.0 or zone_at(world_position) != EXCLUSION:
        return 0.0
    return HAZARD_DAMAGE_PER_SECOND * delta


static func gathering_yield(
        player_position: Vector3, deposit_position: Vector3, base_quantity: int) -> int:
    if base_quantity <= 0:
        return 0
    # A reward requires the survivor to physically enter the risky territory.
    # The bonus is never paid to a player far from the deposit.
    if player_position.distance_to(deposit_position) <= INTERACTION_BONUS_RANGE and \
            zone_at(player_position) == EXCLUSION and zone_at(deposit_position) == EXCLUSION:
        return base_quantity + SCAVENGE_BONUS
    return base_quantity


static func is_sheltered(world_position: Vector3) -> bool:
    return zone_at(world_position) == CAMP


static func zone_description(world_position: Vector3) -> String:
    match zone_at(world_position):
        CAMP:
            return "CAMP: sheltered from infected / no radiation"
        WILDERNESS:
            return "WILDERNESS: infected and normal resource yields"
        EXCLUSION:
            return "EXCLUSION: radiation exposure / +1 material per harvest"
        _:
            return "WILDERNESS"
