extends RefCounted
## GPU settings database matching/learning and the thermal/battery governor.

const GpuDb = preload("res://scripts/client/gpu_settings_db.gd")
const Governor = preload("res://scripts/client/thermal_governor.gd")
const TMP_PATH: String = "user://test_gpu_learned.json"


func run(t) -> void:
	t.current = "adapter matching"
	t.eq(int(GpuDb.match_adapter("Apple M3 Max")["level"]), 3, "M3 Max is top tier")
	t.eq(int(GpuDb.match_adapter("Apple M1")["level"]), 2, "base M1 is mid-high")
	t.eq(str(GpuDb.match_adapter("Apple M2 Pro")["family"]), "apple_m_pro_max", "M2 Pro family")
	t.eq(int(GpuDb.match_adapter("NVIDIA GeForce RTX 4090")["level"]), 3, "RTX 4090")
	t.eq(int(GpuDb.match_adapter("NVIDIA GeForce RTX 3060")["level"]), 2, "RTX 3060")
	t.eq(int(GpuDb.match_adapter("NVIDIA GeForce GTX 1050 Ti")["level"]), 1, "GTX 1050")
	t.eq(int(GpuDb.match_adapter("AMD Radeon RX 7800 XT")["level"]), 3, "RX 7800")
	t.eq(int(GpuDb.match_adapter("AMD Radeon RX 580")["level"]), 1, "RX 580")
	t.eq(int(GpuDb.match_adapter("Intel(R) Arc(TM) A750 Graphics")["level"]), 2, "Arc")
	t.eq(int(GpuDb.match_adapter("Intel(R) Iris(R) Xe Graphics")["level"]), 1, "Iris Xe")
	t.eq(int(GpuDb.match_adapter("Intel(R) UHD Graphics 620")["level"]), 0, "UHD")
	t.eq(int(GpuDb.match_adapter("Adreno (TM) 740")["level"]), 2, "Adreno 740")
	t.eq(int(GpuDb.match_adapter("Mali-G610")["level"]), 0, "Mali low")
	t.check(float(GpuDb.match_adapter("Adreno (TM) 619")["scale"]) < 1.0, "mobile renders below native scale")

	t.current = "unknown fallback"
	var unk: Dictionary = GpuDb.match_adapter("Totally Unknown GPU 9000")
	t.eq(str(unk["source"]), "fallback", "unknown flagged as fallback")
	t.eq(int(unk["level"]), 1, "unknown gets a safe middle-low level")
	t.eq(int(GpuDb.match_adapter("llvmpipe (LLVM 15)")["level"]), 0, "software renderer is lowest")
	t.eq(int(GpuDb.match_adapter("Mystery", "NVIDIA")["level"]), 2, "vendor hint used for unknown adapters")
	var feats: Dictionary = GpuDb.features_for(3)
	t.check(bool(feats["sdfgi"]) and not bool(GpuDb.features_for(1)["ssao"]), "features scale with level")

	t.current = "learning"
	_cleanup()
	var adapter: String = "NVIDIA GeForce RTX 3060"
	t.eq(int(GpuDb.recommend(adapter, "", 16.6, TMP_PATH)["level"]), 2, "static value before learning")
	t.check(GpuDb.learn(adapter, 30.0, 2, TMP_PATH), "learn stores a sample")
	GpuDb.learn(adapter, 28.0, 2, TMP_PATH)
	GpuDb.learn(adapter, 90.0, 2, TMP_PATH)
	var rec: Dictionary = GpuDb.recommend(adapter, "", 16.6, TMP_PATH)
	t.eq(str(rec["source"]), "learned", "learned data used")
	t.eq(int(rec["level"]), 1, "slow measurements at level 2 push the recommendation down (median, not mean)")
	GpuDb.learn(adapter, 8.0, 1, TMP_PATH)
	GpuDb.learn(adapter, 9.0, 1, TMP_PATH)
	GpuDb.learn(adapter, 10.0, 1, TMP_PATH)
	rec = GpuDb.recommend(adapter, "", 16.6, TMP_PATH)
	t.eq(int(rec["level"]), 1, "level 1 passes, level 2 does not, so stay at 1")
	t.eq(int(GpuDb.recommend("Some Other GPU", "", 16.6, TMP_PATH)["level"]), 1, "other adapters unaffected")
	t.check(not GpuDb.learn(adapter, -1.0, 1, TMP_PATH), "invalid sample rejected")
	_cleanup()

	t.current = "thermal governor"
	var g: RefCounted = Governor.new()
	g.configure(60)
	t.eq(g.fps_cap(), 60, "initial cap is target")
	var now: float = 0.0
	for i in 600:
		now += 0.03
		g.sample_frame(30.0, now)
	t.check(g.quality_step() >= 2, "sustained slow frames step quality down")
	var stepped: int = g.quality_step()
	for i in 60:
		now += 0.03
		g.sample_frame(30.0, now)
	t.check(g.quality_step() >= stepped, "no recovery while still slow")
	# Brief fast burst must not recover (hysteresis).
	var burst_start: int = g.quality_step()
	for i in 100:
		now += 0.01
		g.sample_frame(8.0, now)
	t.eq(g.quality_step(), burst_start, "short fast burst does not step back up")
	for i in 5000:
		now += 0.01
		g.sample_frame(8.0, now)
	t.eq(g.quality_step(), 0, "long headroom recovers fully")
	t.eq(g.apply_to(3), 3, "no step-down at recovery")
	var g2: RefCounted = Governor.new()
	for i in 2000:
		now += 0.05
		g2.sample_frame(40.0, now)
	t.eq(g2.fps_cap(), 30, "max throttling caps at 30 fps")
	t.eq(g2.apply_to(3), 0, "quality drops by max steps")
	t.eq(g2.apply_to(0), 0, "quality never below zero")

	t.current = "battery drain"
	var b: RefCounted = Governor.new()
	t.near(b.drain_per_hour(), -1.0, 0.0001, "no data is unknown")
	b.record_battery(0.0, 80.0, false)
	b.record_battery(1800.0, 75.0, false)
	b.record_battery(3600.0, 70.0, false)
	t.near(b.drain_per_hour(), 10.0, 0.01, "10 percent per hour")
	t.near(b.hours_remaining(), 7.0, 0.01, "70 percent at 10 per hour is 7 hours")
	t.eq(b.fps_cap(), 60, "healthy battery does not cap")
	b.record_battery(3700.0, 15.0, false)
	t.eq(b.fps_cap(), 30, "low battery caps fps")
	t.eq(b.apply_to(2), 1, "low battery steps quality down")
	b.record_battery(3800.0, 16.0, true)
	t.near(b.drain_per_hour(), -1.0, 0.0001, "charging resets the estimate")
	t.eq(b.fps_cap(), 60, "charging lifts battery cap")
	t.check(Governor.read_system_battery().has("available"), "probe returns a dictionary")


func _cleanup() -> void:
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))
