extends RefCounted
## Unreal-like over-budget GPU panic, native/script parity, and live viewport policy.
const Adaptive = preload("res://scripts/client/graphics_dynamic_resolution.gd")
const Panic = preload("res://scripts/client/graphics_resolution_panic.gd")


func run(t) -> void:
	t.current = "pure GPU panic respects consecutive frames and 12% cap"
	t.near(Panic.calculate_scale(0.90, 0.65, 40.0, 20.0, 2),
		0.90, 0.00001, "two slow GPU frames cannot trigger a resize")
	t.near(Panic.calculate_scale(0.90, 0.65, 40.0, 20.0, 3),
		0.78, 0.00001, "three expensive frames reduce at most twelve points")
	t.near(Panic.calculate_scale(0.90, 0.65, 37.0, 20.0, 7),
		0.90, 0.00001, "near-budget GPU samples are ignored")
	t.near(Panic.calculate_scale(0.90, 0.65, 0.0, 20.0, 10),
		0.90, 0.00001, "missing GPU timings cannot trigger")
	t.near(Panic.calculate_scale(0.77, 0.71, 55.0, 20.0, 3),
		0.71, 0.00001, "MetalFX hardware floor is never crossed")
	t.near(Panic.calculate_scale(0.71, 0.71, 55.0, 20.0, 3),
		0.71, 0.00001, "already at hardware floor is a no-op")
	for invalid in [NAN, INF, -5.0, 100.0]:
		t.eq(Panic.calculate_scale(0.77, 0.65, invalid, 20.0, 3), -1.0,
			"non-finite, negative and huge GPU durations are rejected")

	t.current = "native and portable panic agree across a GPU/frame workload grid"
	var native: Object = null
	if ClassDB.class_exists("DynamicResolutionPanicPolicy"):
		native = ClassDB.instantiate("DynamicResolutionPanicPolicy")
		t.check(native != null and native.has_method("calculate_scale"),
			"native engine exports the strict GPU over-budget policy")
	for floor in [0.52, 0.65, 0.71, 0.82, 0.90]:
		for initial in [0.76, 0.90, 1.0]:
			if initial < floor:
				continue
			for gpu in [0.0, 12.0, 37.0, 38.0, 40.0, 55.0, 79.0]:
				for frames in [0, 1, 2, 3, 4, 9]:
					var scripted: float = Panic.calculate_scale(
						initial, floor, gpu, 20.0, frames)
					t.check(scripted <= initial and scripted >= floor,
						"bounded scale in workload matrix")
					if native != null:
						var computed: float = float(native.call("calculate_scale",
							initial, floor, gpu, 20.0, frames, 3))
						t.near(computed, scripted, 0.000001,
							"engine/script scale parity for input matrix")

	t.current = "game ignores isolated GPU spikes, then reacts before slow 2.2s policy"
	var scaler := Adaptive.new()
	scaler.configure(2)
	for i in 65:
		scaler.sample_frame(1.0 / 60.0, 10.0)
	t.check(scaler.at_ceiling(), "quiet GPU warmup retains high resolution")
	for i in 2:
		t.check(not scaler.sample_frame(1.0 / 60.0, 45.0),
			"one or two expensive GPU frames never cause panic")
	t.near(scaler.scale, 1.0, 0.00001, "short spike does not resize framebuffer")
	t.check(scaler.sample_frame(1.0 / 60.0, 45.0),
		"third consecutive over-budget frame triggers immediate panic")
	t.near(scaler.scale, 0.88, 0.00001,
		"one panic is capped at twelve resolution points")
	for i in 10:
		t.check(not scaler.sample_frame(1.0 / 60.0, 45.0),
			"cooldown prevents per-frame viewport buffer reallocations")
	t.near(scaler.scale, 0.88, 0.00001, "cooldown preserves the new scale")
	var stepped_again := false
	for i in 45:
		stepped_again = scaler.sample_frame(1.0 / 60.0, 45.0) or stepped_again
	t.check(stepped_again and scaler.at_floor(),
		"persistent overload eventually reaches high-profile floor")

	t.current = "CPU-bound gameplay never triggers GPU panic; reconfigure resets history"
	scaler.configure(1)
	for i in 160:
		scaler.sample_frame(1.0 / 25.0, 7.0)
	t.check(scaler.at_ceiling(), "slow CPU cannot force a GPU panic")
	scaler.configure(1, 0.71)
	for i in 65:
		scaler.sample_frame(1.0 / 60.0, 8.0)
	for i in 3:
		scaler.sample_frame(1.0 / 60.0, 60.0)
	t.near(scaler.scale, 0.71, 0.00001,
		"real game uses the exact MetalFX-supported minimum")
	scaler.configure(2)
	t.near(scaler.scale, 1.0, 0.00001,
		"quality change resets scale and consecutive over-budget history")
	t.check(not scaler.sample_frame(1.0 / 60.0, 60.0),
		"old GPU history cannot trigger panic right after preset switch")

	t.current = "live Albion After reuses existing resolution apply path"
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/client/online_main.gd")
	t.check(source.contains("_adaptive_resolution.sample_frame(delta, gpu_ms)") \
		and source.contains("GraphicsQuality.apply_resolution(get_viewport(), _adaptive_resolution.scale, true)"),
		"GPU panic is applied through the real graphics viewport scaler")
	var controller: String = (Adaptive as Script).source_code
	t.check(controller.contains('EngineFeatures.make("DynamicResolutionPanicPolicy")') \
		and controller.contains("PanicPolicy.calculate_scale("),
		"custom engine and ordinary Godot both support emergency scaling")
