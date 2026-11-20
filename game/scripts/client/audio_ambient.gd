extends RefCounted
## Procedural weather loops and per-biome ambience beds (Unity looping Audio Sources + Mixer snapshots /
## Unreal Ambient Sound actors + MetaSounds noise). No audio files: noise is generated once.

const RATE := 22050
const BEDS := {
	"plains": {"pitch": 1.0, "db": -22.0},
	"forest": {"pitch": 0.92, "db": -19.0},
	"swamp": {"pitch": 0.8, "db": -18.0},
	"spore_swamp": {"pitch": 0.75, "db": -17.0},
	"beach": {"pitch": 1.1, "db": -21.0},
	"mountain": {"pitch": 1.05, "db": -24.0},
}


static func bed(biome: String, daylight: float, underground: bool) -> Dictionary:
	if underground:
		return {"pitch": 0.7, "db": -26.0}
	var b: Dictionary = BEDS.get(biome, BEDS["plains"])
	var night := 1.0 - clampf(daylight, 0.0, 1.0)
	return {"pitch": float(b["pitch"]) * (0.92 if daylight < 0.3 else 1.0), "db": float(b["db"]) - night * 3.0}


## Looping 16-bit mono noise. `smooth` 0 = hiss (rain), toward 1 = low rumble (wind). Deterministic by seed.
static func noise_stream(seconds: float, smooth: float, noise_seed: int = 1) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var count := int(seconds * RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var a := clampf(1.0 - smooth, 0.02, 1.0) # One-pole low-pass coefficient.
	var gain := minf(1.0, 0.5 / sqrt(a)) # Smoothing lowers the level; compensate.
	var y := 0.0
	for i in count:
		y += (rng.randf_range(-1.0, 1.0) - y) * a
		bytes.encode_s16(i * 2, int(clampf(y * gain, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = count
	return s


## Loop volumes (dB) from weather: rain follows storm intensity, wind its speed. Cover mutes them.
static func rain_db(storm: float, covered: bool) -> float:
	if storm <= 0.02:
		return -80.0
	return lerpf(-38.0, -17.0, clampf(storm, 0.0, 1.0)) - (12.0 if covered else 0.0)


static func wind_db(wind_speed: float, storm: float, covered: bool) -> float:
	var s := clampf(wind_speed / 8.0 + storm * 0.5, 0.0, 1.0)
	if s <= 0.02:
		return -80.0
	return lerpf(-40.0, -20.0, s) - (10.0 if covered else 0.0)
