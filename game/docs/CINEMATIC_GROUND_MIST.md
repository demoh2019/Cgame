# Cinematic local ground fog (Forward+)

**Implemented in the game and the Godot fork.** Inspired by atmospheric
light transport in Unreal Engine Lumen scenes and Unity HDRP fog volumes,
this is a small, bounded *native Godot* froxel volume, **not Lumen** and not
a new full-screen pass.

- A single camera-near FogVolume draws shader-shaped world-space mist with
  coherent broad and detail noise. Density is strongest near the ground,
  and softens toward the top and all four edges of the finite box.
- Forests develop delicate green morning mist; swamps receive deeper wet
  haze; beaches get cool sea mist. Plains stay subtle, mountains remain
  largely clear. Rain and low sun smoothly boost the effect.
- Existing sun/moon/torch lights illuminate the mist through the engine's
  volumetric integration, retaining native shadows and scattering.
- Works only for Forward+ **High/Ultra**. Performance, Balanced, Mobile,
  Compatibility and underground dungeons incur no fog-volume shader work.
- One volume follows the local player on an 8m grid, with position and
  uniforms updated no faster than 5 Hz, avoiding per-chunk allocations,
  fluid simulation and rapid motion ghosting.
- Both offline and multiplayer clients reuse identical weather-driven logic.
  No authoritative server, PvP visibility, mechanics or saved data changes.

**Engine enhancement:** FogVolume setters skip repeated equal size,
shape and material assignments instead of sending redundant RenderingServer
updates, improving dynamic graphical profile handling with no API change.

Testing:
- `game/tests/test_ground_mist.gd` for scene integration and bounded
  quality/weather profiles.
- `tests/scene/test_fog_volume.cpp` for native setter behavior.

Run `godot --headless --path game --script res://tests/run_all.gd`
and test both renderer backends and the Metal device with screenshots.
GPU performance and native C++ tests still require a built local engine.

References:
- https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/fog_shader.html
- https://docs.godotengine.org/en/4.6/tutorials/3d/volumetric_fog.html
- https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine
