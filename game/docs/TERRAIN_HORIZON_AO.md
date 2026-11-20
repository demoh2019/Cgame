# Native terrain horizon ambient occlusion

## Why

Rocky valleys and terrain cuts often look too evenly lit when global illumination is disabled or the camera is far from screen-space ambient occlusion. Unreal Engine's landscape workflows and Unity HDRP both address different scales of terrain lighting with baked/indirect occlusion, while Godot's standard SSAO is a short-range screen-space effect.

Our open world now has a complementary **static horizon-based ambient sky visibility** approximation that follows the actual heightfield and survives camera movement, LOD changes and low-resolution upscaling. This is not ray-traced global illumination or a directional shadow replacement.

## Reusable native Godot feature

The forked Godot engine exposes:

```gdscript
var visibility: PackedFloat32Array = ChunkedTerrain3D.bake_horizon_visibility(
    padded_heights, Vector2i(padded_side, padded_side),
    meters_per_sample, 6)
```

The C++ `HeightmapTerrainGeometry::bake_horizon_visibility` helper evaluates eight fixed azimuth directions for every point, looking up to six grid intervals toward potential horizon blockers. It measures the excess angle above the local tangent-plane slope (so an infinite tilted plane is not treated as a narrow valley), and computes the cosine-squared horizon factor expected for Lambertian sky irradiance. Results lie between 0 (fully occluded) and 1 (open sky). No randomness, GPU rays, offscreen buffers or new textures are required. Native C++ unit tests cover flat planes, bowls, range bounds and bad inputs.

## Game integration and streaming

`terrain_horizon_ao.gd` builds a six-grid-sample **height halo around each 33×33 world chunk**. The interior is taken from the cached heightfield; only outside-border samples query the authoritative deterministic world height function. The returned C++ sky field is cropped back to the original 33×33 vertices. Adjacent independently streamed chunks therefore bake matching visibility for shared world coordinates.

The source heightfield is clipped to the same `HEIGHT_MIN` and `HEIGHT_RANGE` used for terrain geometry. Its existing `COLOR.r` cavity and `COLOR.g` ridge values are preserved; `COLOR.b` now carries sky visibility. Flat land defaults to blue = 1, so the existing terrain vertex data remains compatible even when this feature is disabled. There are **no new mesh vertex channels or textures**.

Both `assets/shaders/ground.gdshader` (13-material PBR) and the procedural fallback inside `chunk_view.gd` multiply ambient occlusion by a subtle global-strength-weighted sky visibility term. A minor albedo correction makes the depth visible on the GL Compatibility renderer, which has no SSAO. The sun and its existing high-quality shadows remain unchanged.

## Performance budgets

| Graphics tier | `aa_terrain_horizon_ao_strength` | Native CPU bake |
| --- | ---: | --- |
| Performance | 0.0 | Disabled |
| Balanced | 0.0 | Disabled |
| High | 0.50 | Per loaded chunk, once |
| Ultra | 0.80 | Per loaded chunk, once |

High/Ultra pay the height halo world sampling cost and a fast C++ 8-direction integration at chunk creation. The visibility values are cached on the chunk and reused when changing quality. Switching down to a cheap tier restores the existing curvature-only colors; switching up reuses the cached sky field and rebuilds only the already-existing vertex colors. This is a source-grid update, not a collision or network change.

The material shader uses the baked third vertex-color component, adding no new GPU texture fetches, draw calls or raymarch passes. At low tiers, a uniform strength zero skips the optional shading work. The extra native height sampling and terrain color mesh updates may cause **CPU spikes during heavy streaming or when changing presets**; measure and budget these before shipping.

## Verification

Rebuild the customized Godot engine and run its native `test_heightmap_terrain_geometry.cpp` test suite. Then run the game tests:

`godot --headless --path game --script res://tests/run_all.gd`

The GDScript `test_terrain_curvature.gd` now also covers native sky baking, a flat plane, canyon darkening, consistency across adjacent world chunks, palette safety, shader use in both terrain variants, and live quality changes.

Visual acceptance: capture fixed-camera comparisons of forest hollows, mountain saddles, roads cut through hills and cliff bases in noon/overcast weather; verify that an open grassy slope does not get artificially dark. Compare PBR Forward+ against Compatibility and check transitions at terrain LOD seams. Measure native **chunk bake CPU milliseconds**, new height queries at chunk borders, vertex-color memory and p50/p95 GPU frame times. Do not infer FPS gains from shader ALU counts alone.

This improvement requires the custom Godot build; standard Godot does not expose `ChunkedTerrain3D.bake_horizon_visibility`.
