# Apple MetalFX temporal upscaling integrated into Cgame + Albion After

The game previously selected FSR2 for every adaptive Forward+ render path,
including machines using the Metal driver. The Cgame engine already exposes
Godot's built-in MetalFX Temporal pipeline, which accepts color, motion
vectors and depth for temporal reconstruction, but was never selected.

## Runtime policy
- On **Metal + Forward+**, query the real RenderingDevice's
  LIMIT_METALFX_TEMPORAL_SCALER_MIN_SCALE (integer scaled by 1,000,000).
  Reject unsupported, missing, out-of-range or nonfinite limits. When
  valid, choose native MetalFX Temporal for adaptive/upscaled 3D scenes.
- Keep FSR2 for Vulkan, D3D12, and Metal GPUs without reported temporal
  support. Keep Compatibility/Mobile native resolution. Manual Ultra at
  native scale still uses the existing MSAA setting.
- Both MetalFX and FSR2 perform their own temporal anti-aliasing, so do
  not stack expensive MSAA/FXAA with them. MetalFX ignores RCAS sharpness.
- Feed the GPU's real minimum input scale into the existing adaptive
  resolution controller. It will stop lowering resolution before asking
  MetalFX to render an unsupported size.
- In the **Cgame engine**, Viewport rejects MetalFX modes requested from
  saved settings or scenes on non-Metal drivers and selects supported
  FSR2 on RenderingDevice or bilinear on GL Compatibility. This protects
  callers outside this particular game.

## No new render passes
This switches between already integrated render paths. Existing depth,
motion-vector inputs, high-quality shading, SDFGI and dynamic terrain
quality remain intact. Do not confuse this with Apple's new Metal 4
neural denoising; this selects the existing temporal scaler, not a new
neural renderer.

References: Godot Viewport/RenderingDevice docs, Apple MetalFX temporal
scaler and Unity HDRP's renderer-aware temporal upscaling choices.

Verification: tests/scene/test_viewport.cpp plus game/tests/
test_graphics_resolution.gd and test_graphics_dynamic_resolution.gd.
Full engine compile, macOS GPU screenshots and FPS comparisons are
required before claiming performance gains.
