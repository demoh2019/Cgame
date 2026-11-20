extends RefCounted
## Cosmetic-only server-event reactions, like Unreal's Gameplay Cues.
## Nearby impacts feel powerful; distant ones smoothly fade, not hard cut at
## arbitrary metre thresholds. No gameplay damage, network state, or scene
## nodes are modified. Uses the Cgame native camera trauma path when available.

const PROFILES := {
	"hit_zombie": {"amount": 0.12, "inner": 0.6, "outer": 4.0},
	"zombie_died": {"amount": 0.18, "inner": 1.0, "outer": 6.0},
	"knockback": {"amount": 0.15, "inner": 1.0, "outer": 8.0},
	"flash_thrown": {"amount": 0.25, "inner": 1.5, "outer": 12.0},
	"barricade_broken": {"amount": 0.30, "inner": 1.5, "outer": 10.0},
}


## Same smoothstep attenuation as CameraShake::spatial_falloff; used only by
## stock Godot fallback (the native fork computes it without script work).
static func falloff(distance: float, inner_radius: float, outer_radius: float) -> float:
	if not is_finite(distance) or not is_finite(inner_radius) or not is_finite(outer_radius) \
			or distance < 0.0 or inner_radius < 0.0 or outer_radius <= inner_radius:
		return 0.0
	if distance <= inner_radius:
		return 1.0
	if distance >= outer_radius:
		return 0.0
	var t: float = clampf((distance - inner_radius) / (outer_radius - inner_radius), 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)


## Mutates only the camera's *visual* trauma, never the player's transform.
## The UI accessibility preference scales the impulse before it reaches C++.
static func apply(camera: Camera3D, kind: String, source: Vector3,
		listener: Vector3, shake_scale: float) -> void:
	if camera == null or not PROFILES.has(kind) or not source.is_finite() \
			or not listener.is_finite() or not is_finite(shake_scale) or shake_scale <= 0.0:
		return
	var profile: Dictionary = PROFILES[kind]
	var amount: float = float(profile["amount"]) * clampf(shake_scale, 0.0, 1.0)
	var inner: float = float(profile["inner"])
	var outer: float = float(profile["outer"])
	if camera.has_method("add_spatial_trauma"):
		camera.call("add_spatial_trauma", source, listener, amount, inner, outer)
	elif camera.has_method("add_trauma"):
		# Older engine builds keep the same game feedback and accessibility.
		var faded: float = falloff(source.distance_to(listener), inner, outer)
		if faded > 0.0:
			camera.call("add_trauma", amount * faded)
