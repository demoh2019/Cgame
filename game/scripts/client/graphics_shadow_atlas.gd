extends RefCounted
## Renderer-aware directional shadow atlas budgets for the game's single sun.
## Unity HDRP and Unreal size the shadow-map pool against quality and target
## hardware. This uses Godot's existing global shadow atlas: no extra lights,
## shader texture fetches, shadow-casting nodes, or network/world state.
##
## Resizing a shadow atlas reallocates GPU storage. Never do it per frame:
## GraphicsQuality.apply() invokes this only when its resolved plan changes.
## 32-bit depth on Ultra Forward+ improves depth precision (less shadow acne)
## at a real memory cost; Compatibility/Mobile keep the 16-bit budget.

static var _applied: Dictionary = {}


static func plan(level: int, rendering_method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var desktop_forward: bool = rendering_method == "forward_plus"
	var size: int = 1024
	if tier == 1:
		size = 2048
	elif tier >= 2:
		size = 4096 if desktop_forward else 2048
	var depth_16: bool = not (desktop_forward and tier >= 3)
	return {"size": size, "depth_16": depth_16}


## Pure plan comparison, useful for headless regression tests. Avoids
## reallocating the global shadow atlas for unchanged/duplicate requests.
static func needs_apply(previous: Dictionary, next: Dictionary) -> bool:
	return previous.is_empty() or int(previous.get("size", -1)) != int(next["size"]) \
		or bool(previous.get("depth_16", true)) != bool(next["depth_16"])


## A global RenderingServer resource, not a per-viewport setting. The game's
## solo and multiplayer clients share one global configuration in each process.
static func apply(level: int, rendering_method: String) -> void:
	var next: Dictionary = plan(level, rendering_method)
	if not needs_apply(_applied, next):
		return
	RenderingServer.directional_shadow_atlas_set_size(int(next["size"]),
		bool(next["depth_16"]))
	_applied = next
