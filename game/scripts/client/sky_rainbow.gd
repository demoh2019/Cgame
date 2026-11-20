extends RefCounted
## Post-rain rainbow (RDR2 / Ghost of Tsushima style). Physically placed in the sky
## shader: primary bow at ~42 deg around the antisolar point (red outside), a
## fainter reversed secondary at ~51 deg and the darker Alexander band between.
## This helper only decides WHEN it shows; it costs nothing while 0.


## 0..1. Appears only while a storm is clearing (not building), in daylight,
## with the sun below ~42 deg elevation (otherwise the bow is under the horizon).
static func strength(storm: float, storming: bool, daylight: float, sun_height: float) -> float:
	if storming or daylight < 0.4 or sun_height <= 0.02:
		return 0.0
	# Peaks mid-clearing: rain still falling opposite the sun, sky mostly open.
	var clearing: float = clampf(1.0 - absf(storm - 0.3) / 0.25, 0.0, 1.0)
	# sin(42 deg) ~= 0.67: higher sun pushes the whole arc below the horizon.
	var elevation: float = clampf((0.67 - sun_height) / 0.3, 0.0, 1.0)
	return clearing * elevation * clampf((daylight - 0.4) / 0.3, 0.0, 1.0)
