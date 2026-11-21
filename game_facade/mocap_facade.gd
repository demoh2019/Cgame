class_name CgameMocapFacade
extends RefCounted
## Mocap cleanup: native `CgameMocapCleanup` when available, `mocap_cleanup.gd` otherwise. Every
## function of the native class exists under the same name in the script, so `call_cleanup()` can
## forward any of them (including the rotation variants not wrapped below).


static func call_cleanup(function_name: StringName, args: Array = []) -> Variant:
	return CgameAnimNative.call_static(&"CgameMocapCleanup", "mocap_cleanup.gd", function_name, args)


static func one_euro_positions(track: PackedVector3Array, fps: float, min_cutoff: float = 1.0, beta: float = 0.0, d_cutoff: float = 1.0) -> PackedVector3Array:
	return call_cleanup(&"one_euro_positions", [track, fps, min_cutoff, beta, d_cutoff])


static func butterworth(track: PackedVector3Array, fps: float, cutoff_hz: float) -> PackedVector3Array:
	return call_cleanup(&"butterworth", [track, fps, cutoff_hz])


static func remove_spikes(track: PackedVector3Array, threshold_sigma: float = 4.0) -> PackedVector3Array:
	return call_cleanup(&"remove_spikes", [track, threshold_sigma])


static func detect_contacts(foot_track: PackedVector3Array, fps: float, height_threshold: float, speed_threshold: float) -> PackedByteArray:
	return call_cleanup(&"detect_contacts", [foot_track, fps, height_threshold, speed_threshold])


static func fix_foot_skate(foot_track: PackedVector3Array, contacts: PackedByteArray, blend_frames: int = 4) -> PackedVector3Array:
	return call_cleanup(&"fix_foot_skate", [foot_track, contacts, blend_frames])


static func extract_root_motion(hips_track: PackedVector3Array) -> Dictionary:
	return call_cleanup(&"extract_root_motion", [hips_track])


static func reduce_keys(track: PackedVector3Array, tolerance: float) -> PackedInt32Array:
	return call_cleanup(&"reduce_keys", [track, tolerance])


static func retime(track: PackedVector3Array, src_fps: float, dst_fps: float) -> PackedVector3Array:
	return call_cleanup(&"retime", [track, src_fps, dst_fps])
