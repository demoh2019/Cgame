# Hardware-verified MetalFX with graphics-budget fallback

Cgame exposes MetalFX Temporal and Spatial scalers, and Albion After
uses GPU-time-driven dynamic resolution. Metal driver detection alone,
however, does not establish the native GPU's scaler capabilities.
Moreover, a GPU's minimum native temporal scale may be above a graphics
tier's maximum scale. The earlier policy forced that larger size even
if Performance demanded only 0.59x.

## Correct engine and game behavior

The native Viewport validates that RenderingDevice advertises
SUPPORTS_METALFX_TEMPORAL or SUPPORTS_METALFX_SPATIAL before using a
requested MetalFX mode. It automatically falls back to FSR2 or spatial
FSR, respectively, when an RD exists, or bilinear without RD. This
covers other apps/scenes using Cgame, not just Albion After.

The game checks the Temporal GPU feature and verifies both the
minimum and maximum scaler input fractions reported by the native
RenderingDevice. It then rejects MetalFX when its minimum exceeds the
current graphics profile's intended maximum internal 3D scale:

- Performance 0.59, Balanced 0.77, High 1.0, Ultra 1.0.
- For example, a Metal GPU with a 0.70 minimum on Performance must
  use FSR2 at 0.59, rather than MetalFX at 0.70: **~41% more pixels**
  would otherwise be shaded (0.70² / 0.59²).
- The adaptive GPU controller uses the *same* hardware/preset budget
  decision. When MetalFX is ineligible it retains the original FSR2
  lower floor instead of becoming stuck at a clamped maximum.
- Supported MetalFX temporal still handles history/AA itself; no
  extra MSAA, FXAA, render pass, texture or geometry is added.

This follows Unreal Engine's screen-percentage GPU budgets, Unity's
adaptive resolution selection, and Godot's RenderingDevice feature/
limit APIs. It is not a measured FPS claim.

C++ tests: tests/scene/test_viewport.cpp
GDScript tests: game/tests/test_graphics_resolution.gd and
game/tests/test_graphics_dynamic_resolution.gd

To fully validate, compile the Cgame fork, run headless game tests and
profile native Apple GPUs with different temporal-scaler support
levels. Compatibility/Mobile and Windows/Vulkan remain on their
existing fallbacks.
