class_name CgameFaceFacade
extends RefCounted
## Lip sync and facial animation: native `CgameLipSync` / `CgameFacialAnimation` when available,
## `lip_sync.gd` / `facial_animation.gd` otherwise.


static func viseme_timeline(text: String, duration_seconds: float, language: String = "en") -> Array:
	return CgameAnimNative.call_static(&"CgameLipSync", "lip_sync.gd", &"timeline", [text, duration_seconds, language])


static func sample_visemes(timeline: Array, time: float) -> Dictionary:
	return CgameAnimNative.call_static(&"CgameLipSync", "lip_sync.gd", &"sample", [timeline, time])


static func refine_timeline(timeline: Array, envelope: PackedFloat32Array, hop: float) -> Array:
	return CgameAnimNative.call_static(&"CgameLipSync", "lip_sync.gd", &"refine_with_audio", [timeline, envelope, hop])


static func amplitude_track(samples: PackedFloat32Array, sample_rate: int, hop_seconds: float = 0.02) -> PackedFloat32Array:
	return CgameAnimNative.call_static(&"CgameLipSync", "lip_sync.gd", &"amplitude_track", [samples, sample_rate, hop_seconds])


## Returns a facial animator with evaluate(time, emotion, weight, visemes) and apply_to(mesh, weights).
static func create_facial_animation(seed_value: int = 1) -> Variant:
	if CgameAnimNative.has_native(&"CgameFacialAnimation"):
		var native: RefCounted = ClassDB.instantiate(&"CgameFacialAnimation")
		native.set("seed", seed_value)
		return native
	return CgameAnimNative.create(&"CgameFacialAnimation", "facial_animation.gd", [seed_value])
