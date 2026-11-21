extends RefCounted
## Predictive mip prefetch for the native TextureStreaming engine module.
## GPU material feedback still selects the visible textures; the streaming
## memory-budget fitter may drop the prefetch during VRAM pressure.
## Only streamed textures are affected; ordinary textures cost nothing extra.

# Ultra opts into one more sharp resident mip when the VRAM fitter permits.
# All premium I/O uploads remain limited to a two-mip improvement step.
const PREFETCH_MIPS := [0, 0, 1, 2]


static func prefetch_mips(level: int, method: String) -> int:
	if method != "forward_plus":
		return 0
	return PREFETCH_MIPS[clampi(level, 0, PREFETCH_MIPS.size() - 1)]


## Adaptive prefetch is useful only when Forward+ has speculative detail
## residency. Low tiers and Compatibility keep their previous predictable use.
## The native worker changes only speculative mip prefetch, not visible mip
## feedback or the budget fitter's approved target.
static func adaptive_prefetch_enabled(level: int, method: String) -> bool:
	return method == "forward_plus" and prefetch_mips(level, method) > 0


static func apply(level: int, method: String) -> void:
	# Stock Godot and Compatibility builds must still run this game.
	if not Engine.has_singleton("TextureStreaming"):
		return
	var server: Object = Engine.get_singleton("TextureStreaming")
	if server != null and server.has_method("set_detail_prefetch_mips"):
		server.call("set_detail_prefetch_mips", prefetch_mips(level, method))
	# Feature-detect to support older Cgame binaries and stock Godot.
	if server != null and server.has_method("set_adaptive_detail_prefetch_enabled"):
		server.call("set_adaptive_detail_prefetch_enabled",
			adaptive_prefetch_enabled(level, method))
