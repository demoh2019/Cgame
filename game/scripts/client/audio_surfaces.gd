extends RefCounted
## Surface-dependent footsteps (Unity physic-material footsteps / Unreal Physical Surface + Footstep notifies).
## One walking loop is shared; each surface retunes pitch, loudness and brightness of it.

const PROFILES := {
	"grass": {"pitch": 1.0, "db": -14.0, "cutoff": 20500.0},
	"leaves": {"pitch": 0.94, "db": -13.0, "cutoff": 16000.0},
	"sand": {"pitch": 0.85, "db": -18.0, "cutoff": 6500.0},
	"stone": {"pitch": 1.12, "db": -11.0, "cutoff": 20500.0},
	"mud": {"pitch": 0.78, "db": -15.0, "cutoff": 4500.0},
	"water": {"pitch": 0.9, "db": -9.0, "cutoff": 9000.0},
}


static func surface_for(underground: bool, biome: String, ground_height: float, water_level: float) -> String:
	if underground:
		return "stone"
	if ground_height <= water_level + 0.2:
		return "water"
	if ground_height <= water_level + 0.7:
		return "sand"
	match biome:
		"beach":
			return "sand"
		"mountain":
			return "stone"
		"swamp", "spore_swamp":
			return "mud"
		"forest":
			return "leaves"
	return "grass"


static func profile(surface: String) -> Dictionary:
	return PROFILES.get(surface, PROFILES["grass"])


## Running steps faster: pitch of the loop follows speed relative to a walk (clamped).
static func speed_pitch(base: float, speed: float, walk_speed: float = 4.0) -> float:
	return base * clampf(0.8 + 0.2 * speed / maxf(walk_speed, 0.1), 0.8, 1.35)
