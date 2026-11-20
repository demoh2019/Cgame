# GPU-bound adaptive graphics — engine + game integration

## Why
Previously the 3D render-scale controller used the viewport GPU timestamp,
but the outer graphics-preset controller still compared CPU frame delta
against 45/55 FPS thresholds. An overloaded game simulation could turn
off shadows, grass and high-resolution effects even when the GPU was
idle; conversely a fast CPU tick could raise detail while the GPU was
the real frame bottleneck.

## Changes
- **Cgame engine**, `servers/rendering/renderer_viewport.cpp`:
  timestamp sampling now returns 0 for disabled, missing or inverted CPU/
  GPU samples. Toggle transitions clear old samples; unsigned underflow
  can no longer produce a fake seconds-long GPU stall. The GPU time is
  converted from nanoseconds to milliseconds using one float division.
- **Game**, `graphics_auto_quality.gd`: one shared GPU duration policy
  with `graphics_dynamic_resolution.gd` gates world-detail downgrades
  only at the pixel-scale floor and upgrades only at its ceiling.
  Stable GPU headroom preserves better lighting, grass and reflections
  during CPU-heavy raid combat.
- **Online**, `online_main.gd`: passes the same measured GPU ms to
  both pixel-scale and scenery quality logic. No new GPU timestamp
  queries, framebuffers or render passes.
- **Compatibility, headless, unavailable GPU timers**: frame delta
  fallback preserves existing behavior. 200 ms loading spikes and
  invalid CPU/GPU values cannot cause a quality oscillation.

Inspired by the performance-budget separation behind Unreal TSR/
scalability and Unity dynamic resolution, implemented using existing
Godot viewport GPU timestamps. The change **does not** implement TSR
or HDRP's proprietary algorithms.

## Verification
`res://tests/test_graphics_auto_quality.gd` now includes CPU-bound
and GPU-bound scenarios, missing timestamp handling and scene
integration assertions; also registered in focused graphics CI.
Run `godot --headless --path game --script res://tests/run_graphics.gd`.
A complete engine rebuild plus P50/P95/P99 GPU and CPU capture on
Apple M1 Metal and Vulkan are necessary to verify measured gains.
