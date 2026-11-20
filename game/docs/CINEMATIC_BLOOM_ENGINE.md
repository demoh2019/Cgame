# HDR lens bloom with quality- and weather-aware optics

Albion After now controls the **existing** Godot native HDR glow
rather than creating a second post-process. Clear midday retains a
high brightness threshold so PBR textures, leaf edges and specular
highlights stay crisp. At sunset, softly illuminated cloud rims and
bright sunlit surfaces acquire a more natural halo. At night, small
emissive torches and lanterns stand out while the black background
remains dark. Overcast daylight suppresses aggressive halos.

Godot's `Environment.glow_intensity`, `glow_bloom`, and
`glow_hdr_threshold` update at a maximum of **5 Hz**, quantized
to increments of 0.01. This eliminates the old every-frame glow
property upload from the cinematic grade. GraphicsQuality still
owns enabling/disabling the existing native bloom chain. High and
Ultra Forward+ receive stronger optical response; Performance,
Balanced, Mobile, and Compatibility retain the original settings.
Neither geometry, textures, bloom passes nor HDR target allocations
are added.

The engine fork also skips redundant changes in four native
`Environment` glow setters (`enabled`, `intensity`, `bloom`,
`hdr_threshold`), refuses NaN/Inf and clamps numeric input to
the same ranges defined for Godot's Environment inspector. Avoiding
`_update_glow()` means avoiding normalization and repeated
render-thread upload of unchanged glow uniforms. No engine class
or scripting API surface changes.

Design influence: Unreal's standard bloom and UE local light/post
process controls, Unity HDRP energy-conscious bloom intensity and
threshold, native Godot glow and AgX. This is not a claim to
implement Unreal's separate convolution bloom mode.

Regression suite: `res://tests/test_cinematic_bloom.gd` (full and
focused Godot graphics CI). Verify visually at noon, clear golden
hour, moonlit dungeon and overcast storm with identical exposure
and GPU captures; no FPS claim until measured.
