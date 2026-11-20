extends RefCounted
## Predictive mip prefetch for the native TextureStreaming engine module.
## GPU material feedback still selects the visible textures; the streaming
## memory-budget fitter may drop the prefetch during VRAM pressure.
## Only streamed textures are affected; ordinary textures cost nothing extra.

const PREFETCH_MIPS := [0, 0, 1, 1]


static func prefetch_mips(level: int, method: String) -> int:
	if method != "forward_plus":
		return 0
	return PREFETCH_MIPS[clampi(level, 0, PREFETCH_MIPS.size() - 1)]


static func apply(level: int, method: String) -> void:
	# Stock Godot and Compatibility builds must still run this game.
	if not Engine.has_singleton("TextureStreaming"):
		return
	var server: Object = Engine.get_singleton("TextureStreaming")
	if server != null and server.has_method("set_detail_prefetch_mips"):
		server.call("set_detail_prefetch_mips", prefetch_mips(level, method))
