# Native FSR2 camera-cut rejection and correct frame-time units

When Albion After moves between ruins, bounces between combat and
respawn, or enters a different camera, the existing FSR2 temporal
upscaler must **not re-use the old image history**. Unreal TSR and
Unity HDRP likewise reject temporal history after significant camera
discontinuities or invalid motion vectors.

## Cgame renderer

`render_forward_clustered.cpp` detects significant camera state
discontinuities using the current and previous camera transforms:
movement greater than **8m**, forward or up orientation change
greater than **60 degrees**, or FOV change greater than **20 degrees**.
It sets the existing `FSR2Effect::Parameters.reset_accumulation`
without allocating additional buffers or tracing any rays.

`fsr2.cpp` now converts renderer **seconds** to the **milliseconds**
required by AMD's `FfxFsr2DispatchDescription.frameTimeDelta`.
Ordinary time steps are kept in the range 1–100 ms. Invalid time
steps use a safe 16.67ms fallback and reset history; long loading
stalls also reset temporal accumulation instead of leaving ghost
frames. No additional sharpening or full-screen passes.

## Game integration

`graphics_resolution.gd` keeps existing FSR2 in Performance/
Balanced and adaptive High/Ultra, while reducing redundant repeated
viewport property updates when settings and render scale are
unchanged. The Cgame history logic therefore applies transparently
to solo and online cameras, including server-controlled teleports.
Compatibility/Mobile do not attempt the Forward+ upscaler.

## Verification

- `tests/servers/rendering/test_fsr2_camera_history.py`: numerically
  validates camera thresholds, 60/30/120 Hz milliseconds, invalid
  frames and native SDK/source contracts.
- `game/tests/test_graphics_resolution.gd`: FSR2 profile and
  repeated viewport-apply regression, plus modern High SSIL policy.
- `.github/workflows/albion-after-graphics.yml`: both suites in
  the existing headless graphics workflow.

A headless test or source-contract check is **not** GPU validation.
Compile the native fork and profile M1 Metal/Vulkan with before/after
captures through teleport, rapid turns and long loading stalls.
