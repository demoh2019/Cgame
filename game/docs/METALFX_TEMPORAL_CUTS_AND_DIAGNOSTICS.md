# MetalFX Temporal camera-cut rejection and live upscale diagnostics

## Engine

Albion After's Cgame fork already offers Apple MetalFX Temporal as a
native high-quality alternative to FSR2 on Metal devices. Its history
previously reset **only when a new scaler was constructed**. That
allowed a stale world frame to bleed into teleports, large spectator
camera rotations, respawns and scene transitions.

The Forward+ renderer now computes one camera-discontinuity decision
before selecting either temporal upscaler: camera translation >8 m,
forward/up orientation change >60°, lens FOV jump >20°. Both FSR2
and MetalFX receive this decision through their existing reset flags.
MetalFX also rejects invalid time steps and loading stalls >200 ms;
its existing initial-context reset is preserved.

This follows Apple's MetalFX Temporal integration guidance to reset
history after cuts and the history rejection principles in Unreal TSR.
No new GPU textures, full-screen passes, motion vectors or temporal
history buffers are created. Ordinary walking/camera movement retains
accumulation and fine PBR texture stability.

## Game

The optional FPS overlay, sampled at 4 Hz only while visible, now
displays **the actual native viewport mode and current render scale**:
`MetalFX Temporal 70%`, `FSR2 77%`, or `Native 100%`.
This helps compare temporal sharpness, moving foliage and GPU budgets
in solo/online sessions without incorrectly labelling a requested
graphics setting as a real backend capability.

The game still enables MetalFX only on compatible Forward+ Metal
devices and otherwise uses FSR2; non-Forward+ uses native or bilinear
scaling. No effect or additional work is added when FPS overlay is off.

## Validation

- Native mathematical/source regression: `python3 -m unittest
  tests/servers/rendering/test_fsr2_camera_history.py -v`.
- Game-level tests: `res://tests/test_graphics_resolution.gd`
  in full and focused graphics test suites.
- Existing `.github/workflows/albion-after-graphics.yml` already
  runs both suites when these source files change.

These checks confirm logic and integration, **not** successful
Apple Metal rendering or an FPS improvement. Verify on M1/M2 Metal
with side-by-side moving-camera captures around a teleport, respawn,
and 250ms loading stall before claiming measured frame quality.
