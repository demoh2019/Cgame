# Lightning-aware temporal volumetric fog (game + engine)

This uses the temporal volumetric principle from Unreal Engine and Unity
HDRP: reprojecting previous low-resolution froxel lighting smooths
scattering and sun shafts but strong instantaneous light changes can
leave luminous ghosts. Our storm-lightning feature is authoritative
and already briefly intensifies sun/ambient/fog lighting.

## The visual change
- Forward+ High/Ultra keep the existing 0.66/0.74 history weights in
  normal weather, preserving stable volumetric mist and light shafts.
- At a confirmed local lightning pulse, history weight smoothly falls
  toward **0.12**. Fresh froxel lighting appears immediately instead of
  blending strongly with a pre-strike image. The weight returns after
  the short flash, restoring fog stability.
- Performance/Balanced/GL Compatibility/Mobile continue using only
  cheap height fog; no temporal or froxel pass is allocated for them.
- No new light, texture, volume, shadow map, gameplay state or packets.

## Cgame engine optimization
`scene/resources/environment.cpp` guards unchanged fog settings before
calling the RenderingServer, notably the per-frame weather fog density
and albedo, and the transient temporal history weight. Invalid negative
density and non-finite inputs are dropped, and the history blend is
clamped to 0..1, preventing malformed fog data in the renderer.
Existing valid fog and scattering settings retain the same values.

## Validation
- C++ Environment regression in `tests/scene/test_sky.cpp`
- Gameplay fog regression in `game/tests/test_cinematic_fog.gd`
- The existing headless suite includes this GDScript test.

`godot --headless --path game --script res://tests/run_all.gd`

No GPU benchmark or visual capture is claimed until the updated Cgame
engine is compiled and tested on target hardware. Profile storm flashes
in Forward+ and verify compatibility/mobility paths remain cheap.
