extends RefCounted
## Environmental reverb — the equivalent of Unity Reverb Zones / Unreal Audio Volumes.
## World sounds route through an "SFX" bus with one AudioEffectReverb whose room
## parameters glide toward a preset chosen from where the listener stands.

const BUS := "SFX"
const PRESETS := {
	"underground": {"room_size": 0.85, "damping": 0.35, "wet": 0.42, "spread": 1.0},
	"forest": {"room_size": 0.35, "damping": 0.75, "wet": 0.12, "spread": 0.8},
	"open": {"room_size": 0.2, "damping": 0.9, "wet": 0.04, "spread": 0.5},
}


static func zone_for(underground: bool, biome: String) -> String:
	if underground:
		return "underground"
	if biome in ["forest", "swamp", "spore_swamp"]:
		return "forest"
	return "open"


## Creates the SFX bus with a reverb effect once; returns the bus index.
static func ensure_bus() -> int:
	var index := AudioServer.get_bus_index(BUS)
	if index == -1:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, "Master")
		var reverb := AudioEffectReverb.new()
		reverb.dry = 1.0
		reverb.wet = 0.0
		AudioServer.add_bus_effect(index, reverb)
	return index


static func reverb(index: int) -> AudioEffectReverb:
	if index < 0 or AudioServer.get_bus_effect_count(index) == 0:
		return null
	return AudioServer.get_bus_effect(index, 0) as AudioEffectReverb


## Moves the reverb `weight` (0..1) of the way toward the zone's preset.
static func blend(effect: AudioEffectReverb, zone: String, weight: float) -> void:
	if effect == null:
		return
	var p: Dictionary = PRESETS.get(zone, PRESETS["open"])
	var w := clampf(weight, 0.0, 1.0)
	effect.room_size = lerpf(effect.room_size, p["room_size"], w)
	effect.damping = lerpf(effect.damping, p["damping"], w)
	effect.wet = lerpf(effect.wet, p["wet"], w)
	effect.spread = lerpf(effect.spread, p["spread"], w)
