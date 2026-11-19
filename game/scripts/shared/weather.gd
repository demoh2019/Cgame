extends RefCounted
## Deterministic weather shared by local preview, multiplayer and server.
## Weather is computed from world seed, 256m weather cells and server time.
## No client-supplied weather value is ever accepted by the combat/survival rules.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const WEATHER_CELL_METERS := 256.0
const CHANGE_SECONDS := 240.0
const COLD_START_C := 8.0

const BIOME_TEMP_C := {
	"mountain": 3.0,
	"swamp": 15.0,
	"forest": 11.0,
	"plains": 15.0,
	"beach": 18.0,
	"water": 9.0,
}


static func conditions(world, x: float, z: float, server_seconds: float) -> Dictionary:
	if not (is_finite(x) and is_finite(z) and is_finite(server_seconds)):
		return {}
	var phase: int = maxi(0, int(floor(server_seconds / CHANGE_SECONDS)))
	var cell_x: int = int(floor(x / WEATHER_CELL_METERS))
	var cell_z: int = int(floor(z / WEATHER_CELL_METERS))
	var roll: int = WorldGen.mix(cell_x, cell_z, int(world.world_seed), phase + 5101) % 100
	var biome: String = world.biome_at(x, z)
	var storm: bool = roll < 42
	var temperature_c: float = float(BIOME_TEMP_C.get(biome, 14.0)) - (12.0 if storm else 0.0)
	# The starter settlement is a roofed refuge even during stormy periods.
	var sheltered: bool = world.is_safe(x, z)
	var cold: float = clampf((COLD_START_C - temperature_c) / 16.0, 0.0, 1.0)
	var severity: float = 0.0 if sheltered else cold * (1.0 if storm else 0.25)
	return {
		"condition": "storm" if storm else "clear",
		"temperature_c": temperature_c,
		"sheltered": sheltered,
		"severity": severity,
	}


## Armor works as simple wind/rain insulation for the first survival slice.
## The protection is derived from the equipped item on the authoritative server.
static func protection(armor_id: String) -> float:
	return 0.35 if not armor_id.is_empty() else 0.0


static func effective_severity(weather: Dictionary, armor_id: String) -> float:
	if weather.is_empty():
		return 0.0
	return clampf(float(weather.get("severity", 0.0)) * (1.0 - protection(armor_id)), 0.0, 1.0)
