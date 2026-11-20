# Persistent wet ground and physically motivated evaporation

Inspired by Unity HDRP Shader Graph production-ready weather materials and
Unreal Engine material parameter collections, all streamed terrain, grass,
foliage and water now share **two distinct renderer-only global uniforms**:

- `aa_weather_wetness`: accumulated surface moisture from rain, reduced
  gradually by sunlight, wind, time and biome (swamps/forests dry slower)
- `aa_weather_rain`: active rainfall for falling-drop puddle ripples,
  storm wind gusts and open-water whitecaps

Previously both were the instantaneous storm value. Ground was never able to
stay wet after rain, while ripples and whitecaps could not be separated from
the resulting puddle reflections.

The new deterministic, stable and bounded CPU accumulator runs once per
game frame; uploads are capped at **5 updates per second**. Every loaded
chunk and every future chunk uses the same native RenderingServer global
shader uniforms, so there are no per-chunk buffers, new textures, render
passes, shader permutation explosions, or multiplayer packet changes.

The simulator's weather, damage, visibility, navigation, and crafting are
untouched. The wetness is a **client-side visual memory**, not saved state,
and only affects appearance. Performance, Balanced, High and Ultra all
share the inexpensive scalar. More elaborate ripples are still skipped by
the existing low-quality preset gate.

Fork optimization: `RendererRD::Fog::fog_volume_set_material` now
short-circuits identical resource RIDs, avoiding needless renderer updates.
It does not change the public engine API or invalidate previously assigned
materials. 

Run regression suite:
`godot --headless --path game --script res://tests/run_all.gd`

References:
- https://docs.unity.cn/Packages/com.unity.shadergraph%4017.2/manual/Shader-Graph-Sample-Production-Ready.html
- https://dev.epicgames.com/documentation/en-us/unreal-engine/using-material-parameter-collections-in-unreal-engine
- https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html
