# Bounded sky aurora + native ShaderMaterial scalar-uniform fast path

Albion After already had a procedural aurora, but it was overdrawn
**after all cloud compositing** and traced six noisy atmospheric layers
per sky pixel. This upgrade makes it more cinematic and cheaper:

- Only **Forward+** High (0.30 energy) and Ultra (0.65) on clear
  **mountain** nights enable it; Mobile, Compatibility, Performance,
  Balanced, daytime and overcast are exactly zero.
- Two analytic folded green/violet ribbons replace the six-layer
  sample loop. No texture allocations, new draw calls, or GPU passes.
- Aurora is rendered before cirrus/cumulus, so clouds naturally
  obscure it, and excluded from `AT_CUBEMAP_PASS` to keep the existing
  sky ambient radiance and sky reflection probe captures physically
  consistent.
- Uses the existing weather/biome and sky_time inputs, updated at
  existing sky reflection refresh cadence. No game-server packets or
  persistence changes.

**Godot C++ fork improvement**:
`ShaderMaterial::set_shader_parameter` compares the cached value for
immutable NIL, bool, integer, float, Vector2, Vector3, Vector4 and Color.
When an identical value is re-applied, it returns without sending
`RenderingServer::material_set_param`. This reduces CPU work and
unnecessary material dirtying, especially with periodic day/night,
weather, and graphics preset updates. Exact equality prevents losing
small artistic adjustments; NaN is not equal to itself.

Objects/textures are **deliberately not short-circuited**: a Texture2D
can change its underlying RID even when its Object pointer remains
equal. Mutable Array and Dictionary variants retain prior behavior.
This engine improvement applies globally to all games using the fork.

Validation:
- res://tests/test_sky_aurora.gd
- res://tests/test_shader_uniform_idempotence.gd
- godot --headless --path game --script res://tests/run_graphics.gd

A compiled Godot fork and GPU screenshot/frame-time comparison are still
necessary before asserting actual FPS or full visual compatibility.
