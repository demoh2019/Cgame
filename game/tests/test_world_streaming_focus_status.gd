extends RefCounted
## World Partition-style bounded readiness telemetry; cosmetic only.
const Policy = preload("res://scripts/client/world_streaming_policy.gd")


func run(t) -> void:
	t.current = "client streaming readiness HUD"
	t.eq(Policy.format_focus_streaming_status({}), "", "unknown streamer has no false percentage")
	t.eq(Policy.format_focus_streaming_status({
		"total": 8, "completed": 8, "pending": 0, "failed": 0,
		"progress": 1.0, "ready": true
	}), "", "completed cells do not clutter the HUD")
	t.eq(Policy.format_focus_streaming_status({
		"total": 10, "completed": 6, "pending": 4, "failed": 0,
		"progress": 0.6, "ready": false
	}), "WORLD STREAMING: 60% | pending 4", "partial world has a readable progress notice")
	t.eq(Policy.format_focus_streaming_status({
		"total": 10, "completed": 3, "pending": 5, "failed": 2,
		"progress": 0.3
	}), "WORLD STREAMING: 2 failed, 5 pending", "failed cells are not mistaken for complete")
	t.eq(Policy.format_focus_streaming_status({
		"total": 16384, "pending": 0, "truncated": true
	}), "WORLD STREAMING: grid limit reached", "truncated data never claims readiness")
	t.check(Policy.format_focus_streaming_status({
		"total": 10, "pending": 1, "progress": INF
	}).contains("0%"), "invalid fractional progress is sanitized")

	t.current = "native focus readiness query when available"
	var streamer := WorldStreamer.new()
	streamer.cell_size = 64.0
	streamer.load_radius = 0.0
	streamer.focus_position = Vector3(8.0, 0.0, 8.0)
	if streamer.has_method("get_focus_streaming_status"):
		var status: Dictionary = streamer.call("get_focus_streaming_status", true)
		t.eq(int(status.get("total", -1)), 1, "focus query visits one actual cell")
		t.eq(int(status.get("pending", -1)), 1, "unloaded primary cell is pending")
		t.check(not bool(status.get("ready", true)), "unloaded cell is never ready")
		t.eq(Policy.focus_loading_notice(streamer),
			"WORLD STREAMING: 0% (1 chunks remaining)", "client uses the real native snapshot")
		streamer.enabled = false
		t.eq(Policy.focus_loading_notice(streamer), "", "disabled streamer hides readiness")
	else:
		t.eq(Policy.focus_loading_notice(streamer), "",
			"older custom engine builds retain the original HUD")
	streamer.free()
