# Pooled impact decals: stable rendering cost (Albion After / Cgame)

## The observed hot path

`game/scripts/client/impact_decals.gd` owns a reusable ring of 0/24/48/96
projected splats, depending on graphics quality. Each splat lives for 40
seconds and is fully opaque for the first 34 seconds. Previously the game
called `decal.albedo_mix = 1.0` on **every render frame** throughout that
long opaque period, including in heavy combat scenes. Stock engine
`Decal::set_albedo_mix` forwarded every assignment to RenderingServer.

## Changes

- Cgame `Decal::set_albedo_mix` and `Decal::set_size` now skip redundant
  renderer/Gizmo updates. The *first explicit assignment* still goes to
  RenderingServer even when equal to the local resource default.
- Albion After only adjusts impact-decal alpha during the final six seconds.
  During the fade, 8-bit alpha steps eliminate unnecessary setter churn at
  high FPS while remaining sub-percent per step.
- The decal ring restores full `albedo_mix = 1.0` **before** displaying a
  recycled slot. This also fixes one-frame partially transparent new hits.
- Projectors have a bounded native distance fade: 45/65/85 metres on medium/
  high/ultra, 12-metre fade interval, and no extra material or render pass.
- The Compatibility renderer does not support projected decals. Its
  `gl_compatibility` backend allocates zero impact projector instances;
  dynamic changes of backend or quality update the pool accordingly.
- The pool remains bounded, the same texture variants are reused, and
  rendering changes do not affect physics, hit registration or servers.

This follows the *principle* of limiting screen footprint and unnecessary
per-component work from Unity URP Decal Projectors and Unreal's deferred
decals. It does not copy their implementations.

## Tests and performance validation

```sh
godot --headless --path game --script res://tests/run_graphics.gd
godot --headless --path game --script res://tests/run_all.gd
# On a Cgame native editor built with tests=yes:
godot --headless --test --test-case="*Repeated pooled fade values*"
```

`game/tests/test_impact_decal_budget.gd` verifies renderer-aware pool
capacity, fade monotonicity, quality-tier distance limits, and immediate
opacity reset on reuse. C++ regression cases cover idempotent size and
alpha setters after their first submission.

To measure impact, compare CPU frame timings and RenderingServer message
counts on the *same* hardware and combat scene before/after. This is a
targeted main-thread/render-thread command reduction; no FPS speedup can
be promised until native and GPU profiling is completed.

## Original references

- Unreal Engine decal performance: projected box on-screen size and shader
  complexity drive costs.
  https://dev.epicgames.com/documentation/en-us/unreal-engine/decal-actors-in-unreal-engine
- Unity URP Decal Projector rendering and performance tradeoffs:
  https://docs.unity.com/en-us/engine/6000.7/manual/visual-effects/decals/renderer-feature-decal/decal
