# Camera-stable directional soft shadows in Cgame + Albion After

Unreal Engine Virtual Shadow Maps and Unity HDRP emphasize temporally
stable soft shadows and reusable shadow-map data. Cgame already offers
Forward+ PCF and premium PCSS contact-hardening, cascades and weather.
However, the Poisson kernel rotation was seeded with gl_FragCoord, a
camera-space pixel coordinate. A moving camera reassigns unrelated
screen hashes to the same world surface, making the penumbra appear
to crawl even with a static shadow caster.

The Cgame renderer now seeds directional PCF and PCSS kernel rotation
from quantized 2x2 shadow-map texel coordinates. The existing temporal
sample phase remains available for TAA, but static camera/caster
conditions produce stable sampling. Blocker search and penumbra pass
share the same orientation. Spot and omni light filtering are not
altered; only the sun/moon directional filters change.

No new render target, extra shadow sampling or draw pass is added.
The original PCSS contact-hardening calculation remains unchanged.
The game calls the existing renderer automatically for High/Ultra,
while Performance/Balanced/Compatibility/Mobile still use the normal
low-cost profile. SunShadowQuality avoids redundant native angular
distance writes on repeated tier selection.

Tests: standalone C++ numerical reference (texture-space anchoring and
bounded finite angles), targeted CI contract verifying the exact
shader call sites, and GDScript test_sun_shadow_quality.gd for
forward and compatibility quality settings.

Run the game's full headless suite and compile Cgame on target Vulkan /
Metal hardware; verify camera pans, forest canopies and sunrise shadows.
Actual visual quality and FPS are not yet benchmarked.
