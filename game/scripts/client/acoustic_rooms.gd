extends RefCounted
## Geometric room acoustics: RT60 from box geometry and synthetic impulse responses.
##
## Sources (formulas only, no code copied): W. C. Sabine reverberation equation
## T60 = 0.161 V / A; C. F. Eyring (1930) T60 = 0.161 V / (-S ln(1 - a_mean));
## mean free path 4V/S (Kuttruff, Room Acoustics); typical octave-band absorption
## coefficients from public acoustics handbooks (rounded, approximate); the
## Wwise Rooms & Portals and Steam Audio documentation for the overall concept.
## Written from scratch for this project.

const SPEED_OF_SOUND := 343.0
const SABINE_K := 0.161
const DEFAULT_MATERIAL := "concrete"

## Absorption per material as Vector3(low ~125 Hz, mid ~1 kHz, high ~4 kHz).
const MATERIALS := {
	"concrete": Vector3(0.01, 0.02, 0.03),
	"wood": Vector3(0.15, 0.10, 0.07),
	"grass": Vector3(0.11, 0.60, 0.65),
	"metal": Vector3(0.05, 0.04, 0.05),
	"glass": Vector3(0.35, 0.12, 0.04),
	"carpet": Vector3(0.02, 0.20, 0.65),
	"water": Vector3(0.01, 0.01, 0.02),
}


## `absorption` maps a surface ("floor", "ceiling", "walls") to a material name
## or directly to a Vector3 of band coefficients. Missing surfaces use concrete.
static func room_from_box(size: Vector3, absorption: Dictionary) -> Dictionary:
	var sx: float = maxf(size.x, 0.1)
	var sy: float = maxf(size.y, 0.1)
	var sz: float = maxf(size.z, 0.1)
	var volume: float = sx * sy * sz
	var surfaces: Dictionary = {
		"floor": sx * sz,
		"ceiling": sx * sz,
		"walls": 2.0 * sy * (sx + sz),
	}
	var total_area: float = 0.0
	var material_areas: Dictionary = {}
	var absorb_area: Vector3 = Vector3.ZERO
	for surface in surfaces.keys():
		var area: float = surfaces[surface]
		var coeff: Vector3 = _coefficients(absorption.get(surface, DEFAULT_MATERIAL))
		total_area += area
		absorb_area += coeff * area
		var key: String = str(absorption.get(surface, DEFAULT_MATERIAL))
		var prev: float = material_areas.get(key, 0.0)
		material_areas[key] = prev + area
	var mean_alpha: Vector3 = absorb_area / total_area
	var sabine: Vector3 = Vector3(
		_sabine(volume, absorb_area.x), _sabine(volume, absorb_area.y), _sabine(volume, absorb_area.z))
	var eyring: Vector3 = Vector3(
		_eyring(volume, total_area, mean_alpha.x),
		_eyring(volume, total_area, mean_alpha.y),
		_eyring(volume, total_area, mean_alpha.z))
	var mean_free_path: float = 4.0 * volume / total_area
	var early_msec: float = mean_free_path / SPEED_OF_SOUND * 1000.0
	var rt_mid: float = eyring.y
	var damping: float = clampf(1.0 - eyring.z / maxf(rt_mid, 0.001), 0.0, 1.0)
	return {
		"volume": volume,
		"surface_area": total_area,
		"material_areas": material_areas,
		"mean_absorption": mean_alpha,
		"rt60_sabine": sabine,
		"rt60_eyring": eyring,
		"mean_free_path": mean_free_path,
		"early_reflection_delay_msec": early_msec,
		"reverb": {
			"room_size": clampf(rt_mid / 5.0, 0.05, 1.0),
			"damping": damping,
			"wet": clampf(0.08 + 0.06 * rt_mid, 0.05, 0.5),
			"predelay_msec": clampf(early_msec, 0.0, 150.0),
		},
	}


static func _coefficients(spec: Variant) -> Vector3:
	if spec is Vector3:
		var v: Vector3 = spec
		return v.clamp(Vector3.ZERO, Vector3.ONE)
	var name: String = str(spec)
	if MATERIALS.has(name):
		var c: Vector3 = MATERIALS[name]
		return c
	var fallback: Vector3 = MATERIALS[DEFAULT_MATERIAL]
	return fallback


static func _sabine(volume: float, absorb_area: float) -> float:
	return SABINE_K * volume / maxf(absorb_area, 0.01)


static func _eyring(volume: float, area: float, mean_alpha: float) -> float:
	var a: float = clampf(mean_alpha, 0.001, 0.99)
	return SABINE_K * volume / (-area * log(1.0 - a))


## Synthetic impulse response: noise split into three bands, each decaying
## 60 dB over its own RT60 (x = low, y = mid, z = high). Peak-normalised to 1.
static func impulse_response(rt60: Vector3, sample_rate: int, seconds: float, seed: int) -> PackedFloat32Array:
	var count: int = maxi(int(seconds * float(sample_rate)), 1)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed
	var rate: float = float(maxi(sample_rate, 1))
	var coef_lo: float = 1.0 - exp(-TAU * 300.0 / rate)
	var coef_hi: float = 1.0 - exp(-TAU * 3000.0 / rate)
	var lp_lo: float = 0.0
	var lp_hi: float = 0.0
	var t60: Vector3 = Vector3(maxf(rt60.x, 0.02), maxf(rt60.y, 0.02), maxf(rt60.z, 0.02))
	var peak: float = 0.0
	for i in count:
		var n: float = rng.randf_range(-1.0, 1.0)
		lp_lo += coef_lo * (n - lp_lo)
		lp_hi += coef_hi * (n - lp_hi)
		var time: float = float(i) / rate
		var low: float = lp_lo * pow(10.0, -3.0 * time / t60.x)
		var mid: float = (lp_hi - lp_lo) * pow(10.0, -3.0 * time / t60.y)
		var high: float = (n - lp_hi) * pow(10.0, -3.0 * time / t60.z)
		var s: float = low + mid + high
		out[i] = s
		peak = maxf(peak, absf(s))
	if peak > 0.0:
		var inv: float = 1.0 / peak
		for i in count:
			out[i] *= inv
	return out
