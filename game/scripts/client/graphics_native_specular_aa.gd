extends RefCounted
## Godot's built-in screen-space roughness limiter controls the unmodified
## imported glTF/PBR assets, complementing the game's terrain/foliage shader AA.
## Unlike a full-screen image blur it filters glancing highlights at the
## material stage. No additional samplers, textures, or framebuffer passes.
## RenderingServer setting is process-global: cache actual applied plan.

static var _applied: Dictionary = {}


static func plan(level: int, method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var supported: bool = method == "forward_plus" or method == "mobile"
	# Mobile gets the affordable Balanced parameters even if a saved
	# Ultra desktop graphics level is loaded on that backend.
	if method == "mobile":
		tier = mini(tier, 1)
	return {
		"enabled": supported and tier >= 1,
		"amount": 0.0 if tier == 0 else (0.25 if tier == 1 else
			(0.33 if tier == 2 else 0.43)),
		"limit": 0.18 if tier <= 1 else (0.16 if tier == 2 else 0.14),
	}


static func needs_apply(previous: Dictionary, next: Dictionary) -> bool:
	return previous.is_empty() or bool(previous.get("enabled", not next["enabled"])) != bool(next["enabled"]) \
		or float(previous.get("amount", -1.0)) != float(next["amount"]) \
		or float(previous.get("limit", -1.0)) != float(next["limit"])


static func apply(level: int, method: String) -> void:
	var next: Dictionary = plan(level, method)
	if not needs_apply(_applied, next):
		return
	# The Cgame renderer accepts these runtime updates without changing the
	# shader or reallocating a render target. Unsupported methods disable it.
	RenderingServer.screen_space_roughness_limiter_set_active(
		bool(next["enabled"]), float(next["amount"]), float(next["limit"]))
	_applied = next
