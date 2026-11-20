# Graphics fidelity pass — PBR materials and cinematic grade

## References and goal

The project already uses imported CC0 glTF/GLB assets, an ACES tone mapper,
weather-sensitive lights, procedural terrain and vegetation LOD. This update
focuses on **appearance**, not adding new geometry to the world.

Relevant industry workflows:
- Unreal physically based materials: https://dev.epicgames.com/documentation/unreal-engine/physically-based-materials-in-unreal-engine
- Unreal filmic color pipeline: https://dev.epicgames.com/documentation/unreal-engine/color-grading-and-the-filmic-tonemapper-in-unreal-engine
- Unity HDRP (physically based lighting and post): https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition@14.0/manual/HDRP-Features.html
- Godot tangent arrays: https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/arraymesh.html
- Godot normal mapping: https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html
- Godot Environment: https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html

## 1. Restored mesh PBR shading

Previously, `ModelCatalog.bake()` zeroed `Mesh.ARRAY_TANGENT`,
disabled `BaseMaterial3D.normal_enabled` and clamped metallic to 0.2 on
imported scene models. This destroyed the appearance of authored stone relief,
brushed metal, scratches, wood grain and normal-mapped props. Artists' GLB
materials were not being represented faithfully even when the textures existed.

`scripts/client/mesh_pbr_preservation.gd` implements a one-time CPU
transformation of imported vertex normal and tangent frames. Normals use
inverse-transpose; tangents use the forward transform and Gram-Schmidt
orthonormalization. Reflection flips tangent handedness; singular transforms
fall back safely without invalid normal maps. A material is duplicated and
retains albedo, normal/ORM/roughness/metallic textures and artist-provided
PBR values. Geometry without valid tangents safely disables normal mapping.

The model baker also preserves per-instance material overrides, as used by
some glTF scenes. Models with an explicit replacement hand-painted texture
still intentionally receive the original replacement material. The existing
dungeon palette remains unchanged. Imported mesh LODs remain intact.

**Performance:** No extra triangles, runtime mesh rebuild or GPU render pass
is added. Preserved normal maps may increase texture sampling on affected
materials versus their previous flat rendering. The benefit is improved
appearance where the asset provides normal/PBR maps; models without such maps
will not gain microdetail.

## 2. Scene-referred cinematic grade

`scripts/client/cinematic_color_grade.gd` applies subtle, continuous native
Godot ACES exposure/contrast/saturation/glow changes for daylight, golden
hour, moonlit night, and overcast storms. The existing `Atmosphere` updates
it alongside sky lighting in both the online and local game. It does not
introduce an additional full-screen pass or force bloom on budget presets.
Storms become softer and less saturated; twilight retains slightly warmer
highlight energy; night stays readable without color clipping.

The look is configurable in a pure `look()` function, so designers can tune
the numbers against actual screenshots. It is a simple artistic calibration,
**not** Unreal's full filmic color-grading pipeline or HDRP's exposure stack.

## Regression checks

- `tests/test_mesh_pbr_preservation.gd`: non-uniform transforms, mirrored
  tangent sign, normal/tangent orthogonality, material texture references,
  artist metallic/roughness values, missing tangents, singular transforms,
  intentional dungeon palette, and integration in the catalog.
- `tests/test_cinematic_color_grade.gd`: day/night/weather grade bounds,
  live Environment properties, and shared Atmosphere integration.
- Both suites are registered in `tests/run_all.gd`.

To validate on a machine with Godot installed:

```bash
godot --headless --editor --path game --quit
godot --headless --path game --script res://tests/run_all.gd
```

For an A/B comparison use the same camera positions in a scanned boulder
field, a ruined city with metal props, a wood-covered dock and a dusk/storm
forest. Inspect normal-map depth, roughness highlights, UV seams, reflected
light, and visible grading changes. Record native resolution, GPU timing
(p50/p95), texture sampling cost and draw calls for Performance/High/Ultra.
Godot runtime tests and FPS profiling have not been executed in this
editing environment because the binary is not installed.
