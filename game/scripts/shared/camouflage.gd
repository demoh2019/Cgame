extends RefCounted
## Classless equipment stealth. Called with server-verified equipment ownership.
## Noise still makes survivors audible, and blood scent is a separate channel.

const Defs = preload("res://scripts/shared/defs.gd")


static func visual_signature(armor_id: String, owned: bool, noise_timer: float,
		alive: bool = true) -> float:
	if not alive or not owned or armor_id.is_empty() or not is_finite(noise_timer):
		return 1.0
	# Real sprinting and gunshots interrupt camouflage until the sound fades.
	if noise_timer > 0.0:
		return 1.0
	var armor: Dictionary = Defs.item(armor_id)
	if str(armor.get("kind", "")) != "armor":
		return 1.0
	var raw: float = float(armor.get("visual_signature", 1.0))
	if not is_finite(raw):
		return 1.0
	return clampf(raw, 0.35, 1.0)
