# High-fidelity PBR terrain: closer cliff detail, more natural materials

The existing 13 CC0 PBR terrain materials now get physically varied roughness
without adding a texture atlas, extra memory or geometry. Grass/dirt/forest
floor stay comparatively matte, angular stone/cliff rock and cracked asphalt
have richer grazing highlights, while sand and snow remain diffuse. This is
computed from already available per-pixel biome weights. A small bounded
macro-noise modulation prevents uniform plastic-looking surfaces.

**Triplanar cliff normals** are enabled only on High (70% strength) and Ultra
(100%). Rock cliff pixels within the preset's existing camera detail radius
sample three filtered normal projections, reconstruct world-space vectors
and blend by cliff coverage. Performance and Balanced never pay the three
extra normal-map fetches. The near/far transition fades smoothly with
existing terrain LOD; chunk geometry and world collision are unchanged.

Existing weather wetness, shallow puddles, normal-map albedo, roads, snow
and cloud shadows remain intact. Dielectric specular reflectivity stays at
Godot's standard F0 instead of being artificially boosted during rain.

Engineering references:
- Unreal Engine PBR: https://dev.epicgames.com/documentation/unreal-engine/physically-based-materials-in-unreal-engine
- Godot 4 spatial shader: https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html
- Unity HDRP material workflow: https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@10.4/manual/master-stack-lit.html

Run with `godot --headless --path game --script res://tests/run_all.gd`.
New test: `tests/test_terrain_material_fidelity.gd`.
GPU benchmarks and screenshots on a real device remain necessary to
quantify final visual gains and rendering cost.
