extends RefCounted
## Cross-layer graphics contract: game quality -> engine mip prefetch.

const Streaming = preload("res://scripts/client/graphics_texture_streaming.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "engine streamed texture prefetch budgets"
	for method in ["gl_compatibility", "mobile", "unknown"]:
		for tier in 4:
			t.eq(Streaming.prefetch_mips(tier, method), 0,
				"non-Forward+ renderer never requests extra mip residency")
	t.eq(Streaming.prefetch_mips(0, "forward_plus"), 0, "Performance keeps minimum memory")
	t.eq(Streaming.prefetch_mips(1, "forward_plus"), 0, "Balanced avoids extra residency")
	t.eq(Streaming.prefetch_mips(2, "forward_plus"), 1, "High prefetches a sharper mip")
	t.eq(Streaming.prefetch_mips(3, "forward_plus"), 2, "Ultra prefetches two sharper mips where memory permits")
	t.eq(Streaming.prefetch_mips(-99, "forward_plus"), 0, "negative quality clamps")
	t.eq(Streaming.prefetch_mips(99, "forward_plus"), 2, "high quality clamps")
	t.current = "adaptive prefetch only on Forward+ detail tiers"
	for tier in 4:
		t.eq(Streaming.adaptive_prefetch_enabled(tier, "forward_plus"), tier >= 2,
			"High/Ultra opt in and Performance/Balanced stay legacy")
		t.eq(Streaming.adaptive_prefetch_enabled(tier, "gl_compatibility"), false,
			"Compatibility never schedules VRAM prefetch")
		t.eq(Streaming.adaptive_prefetch_enabled(tier, "mobile"), false,
			"non-Forward+ never schedules predictive mip residency")
	Streaming.apply(1, "gl_compatibility")
	Streaming.apply(3, "forward_plus")
	if Engine.has_singleton("TextureStreaming"):
		var server: Object = Engine.get_singleton("TextureStreaming")
		if server != null and server.has_method("get_detail_prefetch_mips"):
			t.eq(int(server.call("get_detail_prefetch_mips")), 2,
				"runtime Ultra quality reaches native streaming worker")
			if server.has_method("is_adaptive_detail_prefetch_enabled"):
				t.eq(bool(server.call("is_adaptive_detail_prefetch_enabled")), true,
					"Ultra enables native memory-pressure admission")
				if server.has_method("get_effective_detail_prefetch_mips"):
					var effective: int = int(server.call("get_effective_detail_prefetch_mips"))
					t.check(effective >= 0 and effective <= 2,
						"effective speculative mip count never exceeds the user cap")
			Streaming.apply(0, "forward_plus")
			t.eq(int(server.call("get_detail_prefetch_mips")), 0,
				"downgrade immediately cancels predictive prefetch")
			if server.has_method("is_adaptive_detail_prefetch_enabled"):
				t.eq(bool(server.call("is_adaptive_detail_prefetch_enabled")), false,
					"downgrade disables native adaptive prefetch")
				if server.has_method("get_effective_detail_prefetch_mips"):
					t.eq(int(server.call("get_effective_detail_prefetch_mips")), 0,
						"no speculative mips left when Performance is selected")
	var quality_source: String = (Quality as Script).source_code
	t.check(quality_source.contains("GraphicsTextureStreaming.apply(_level"),
		"shared graphics quality profile configures engine prefetch")
