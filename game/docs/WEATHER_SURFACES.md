# Weather-linked water and vegetation in Albion After

The existing environment controller already sends a smooth GPU-global wetness value (`aa_weather_wetness`), which the terrain shaders use for dark soil and puddles. The other major visible surfaces now use the **same** value without new textures, postprocessing passes, or CPU updates for individual plants.

- **Water:** storm wind strengthens the already inexpensive analytic wave slopes. Subtle offshore crest foam uses the existing wave crest and depth, and the roughness increases slightly in rain. Shoreline foam, water clarity and Fresnel remain. Fine water noise still runs only on High/Ultra and only near the camera.
- **Trees and bushes:** leaves and bark gently darken and reduce roughness when wet, retaining their diffuse textures, instance tint, cut-out transparency, cloud shadows and wind distance-LOD.
- **Procedural grass:** wet grass gets a richer, darker color and stronger gust bending. Distant blade wind still skips the expensive trigonometric branch.

The **Performance** profile still has `water_ripples = 0`; its water performs no wave trigonometry or high-frequency foam noise. Changes are visual only; world generation, collision, physics, multiplayer and save data are unchanged.

## Benchmark and validation

Run `godot --headless --path game --script res://tests/run_all.gd` to include the new source-level regression `test_weather_surface_response.gd`. Compare scenes at identical camera position and time-of-day in calm and storm conditions, with a shoreline and forest visible. Check for excessive foam, too-glossy leaves, and unwanted material clipping. On target GPUs, compare median and p95 GPU frame times for Performance, Balanced, High and Ultra. No FPS improvement is claimed without measurement.
