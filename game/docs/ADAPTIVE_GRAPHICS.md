# Forward+ graphics: modern desktop visuals, measured pixel costs

The default **desktop** renderer is now Godot/Cgame **Forward+**, unlocking
the existing cinematic sky and shadow profiles, Ultra SSIL and volumetric fog
and High/Ultra screen-space contact shadows. Forward+ also enables **FSR2**
temporal upscaling (77% of native on Balanced, 59% on Performance) while
keeping the native-resolution 2D GUI sharp. Manual High and Ultra retain
native rendering and MSAA 2x/4x.

On new installs the title screen now defaults to **Auto (adaptive 3D +
details)**. Previous graphics preferences are preserved. At runtime, Auto
adapts FSR2 resolution first, within tier-specific floors/ceilings, to avoid
expensive grass, shadow, terrain and streaming changes on small FPS dips.
A pure frame-time controller requires sustained low FPS (2.2s) or high FPS
(6s) and ignores loading stalls >200 ms. Only when the resolution reaches
its floor or ceiling does the existing whole-preset controller change the
LOD/streaming/postprocessing budget. The server/gameplay simulation is
untouched.

GL Compatibility remains the default for **web/mobile**. The active backend
is checked at runtime. Mobile/Compatibility do not get unsupported FSR2:
they retain native 3D rendering and ordinary AA; Auto still adapts scene
detail. For older desktop GPUs, launch with
`godot --path game --rendering-method gl_compatibility`.
Rendering backend changes require startup, not merely a quality toggle.

References used for engineering decisions:
- Epic temporal upscaling: https://dev.epicgames.com/documentation/en-us/unreal-engine/temporal-upscalers-in-unreal-engine
- Epic virtualized geometry: https://dev.epicgames.com/documentation/en-us/unreal-engine/nanite-virtualized-geometry-in-unreal-engine
- Unity HDRP: https://github.com/Unity-Technologies/Graphics/blob/master/Packages/com.unity.render-pipelines.high-definition/Documentation~/HDRP-Features.md
- Godot: https://docs.godotengine.org/en/4.5/tutorials/3d/resolution_scaling.html

This is not Nanite, Lumen or Unreal TSR; those require a different renderer
architecture. The implementation uses real Godot 4 APIs, existing GPU-batched
foliage/HLOD and deterministic game-level rendering budgets. Claims about
FPS improvement require GPU measurements on target hardware; none have been
made without testing. Tests live in
`game/tests/test_graphics_resolution.gd` and
`game/tests/test_graphics_dynamic_resolution.gd`.
