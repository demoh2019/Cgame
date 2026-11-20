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
	t.eq(Streaming.prefetch_mips(3, "forward_plus"), 1, "Ultra prefetches a sharper mip")
	t.eq(Streaming.prefetch_mips(-99, "forward_plus"), 0, "negative quality clamps")
	t.eq(Streaming.prefetch_mips(99, "forward_plus"), 1, "high quality clamps")
	Streaming.apply(1, "gl_compatibility")
	Streaming.apply(3, "forward_plus")
	if Engine.has_singleton("TextureStreaming"):
		var server: Object = Engine.get_singleton("TextureStreaming")
		if server != null and server.has_method("get_detail_prefetch_mips"):
			t.eq(int(server.call("get_detail_prefetch_mips")), 1,
				"runtime quality actually reaches native streaming worker")
			Streaming.apply(0, "forward_plus")
			t.eq(int(server.call("get_detail_prefetch_mips")), 0,
				"downgrade immediately cancels predictive prefetch")
	var quality_source: String = (Quality as Script).source_code
	t.check(quality_source.contains("GraphicsTextureStreaming.apply(_level"),
		"shared graphics quality profile configures engine prefetch")
