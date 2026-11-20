# Imported PBR texture fidelity and viewport anisotropic budgets

The game's terrain already uses a cached three-tier sampler strategy:
trilinear on Performance/Balanced, anisotropic color sampling on High, and
anisotropic color plus normal mapping on Ultra.

This extension improves **imported glTF/GLB model materials** in the same
graphics presets. ModelCatalog's existing PBR bake now converts ordinary
trilinear-with-mipmaps StandardMaterial3D texture filters to anisotropic
filters on a **private duplicate**, preserving source art, tangents,
normal/ORM textures, mipmaps, metallic and roughness values. Pixelated
nearest-filter materials and preconfigured anisotropic materials are left
alone.

The active viewport enforces these per-quality sampler ceilings:

| Preset | Max anisotropic filtering |
| --- | --- |
| Performance | 2× |
| Balanced | 4× |
| High | 8× |
| Ultra | 16× |

This makes roads, rocky cliffs, slanted building textures, machinery
surfaces and gear viewed from an isometric camera less smeared without
adding geometry, extra lights, a fullscreen pass or GPU texture allocations.
Viewport caps also apply to already cached terrain sampler variants.

The existing GPU-aware Auto mode and FSR2 resolution controller remain intact.
Auto presets change the anisotropy cap only when the quality tier changes,
not each frame. Offline mode uses the same GraphicsQuality.apply() path.

Regression tests are extensions of test_graphics_quality.gd and
test_mesh_pbr_preservation.gd. Verify actual FPS on target GPUs with the
existing render benchmark and screenshot workflow; no performance gain
is claimed without a device capture.

Godot reference:
https://docs.godotengine.org/en/stable/classes/class_viewport.html
https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html
