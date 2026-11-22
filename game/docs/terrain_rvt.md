# Terrain runtime virtual texture (RVT)

**Integrated into:** `game/scripts/client/terrain_rvt.gd` (created by `online_main.gd`),
`game/assets/shaders/ground.gdshader`, engine `ChunkedTerrain3D.render_layers`.

## Why

The ground shader blends up to 13 PBR layers per pixel: three octaves of value noise, 13-entry
weight arrays (dynamically indexed, so they spill out of registers on Apple GPUs), layer ranking,
two or three texture scales per selected layer and parallax near the camera. Replacing it with two
taps measured **−5.2 ms** of GPU time on an M1 at 1080p Balanced (orbit view), which is the ceiling
for any caching scheme.

## How

Same idea as Unreal's Runtime Virtual Texturing, built from engine primitives:

- **Pages**: level 0 = 8 m, level 1 = 16 m, 256×256 texels (3.1 / 6.25 cm per texel), with one
  border texel so bilinear taps stay inside a page. 64 m chunks hold whole pages of both levels.
- **Bake**: three orthographic cameras per rig look straight down at the real terrain geometry
  (`ChunkedTerrain3D.render_layers` puts chunks on visual layer 20). Their viewports use the
  Unshaded debug draw and a linear tonemap. The ground shader recognises a bake from
  `CAMERA_VISIBLE_LAYERS` (a marker layer 17–19 and none of layers 1–15). It then outputs one of:
  - albedo (sRGB, 256²);
  - normal xz + dry roughness (256², pre-decoded so the bytes are the values);
  - wet factor, puddle shape, hard surface (64²).

  Pages are baked at full detail and without parallax. Two rigs bake at most two pages a frame,
  only for chunks that have existed for 0.75 s.
- **Cache**: three `Texture2DArrayRD` arrays with 176 layers (~93 MB), filled with
  `RenderingDevice.texture_copy` from the viewport textures. A 64×32 RGBA8 toroidal page table
  stores `layer + 1` plus the page's low coordinate bytes as a residency check.
- **Use**: the shader reads a page once the eye is 10–14 m away (3D distance, so pixel footprint
  decides). Level 0 is used within 26 m horizontally, level 1 out to the quality preset's detail
  radius + 24 m. The live path still runs near the camera and wherever a page is missing.
  Weather wetness and puddles, cloud shadows, contact/curvature/horizon AO, ripples, caustics and
  clearcoat are always computed live on top of the cached record.
- **Invalidation**: a page is dropped when it leaves the radius, when its chunk unloads, and when
  winter snow cover changes (everything is re-baked).

## Measured (M1, 1920×1080, Balanced, orbit view, screenshot benchmark)

| | GPU p50 | Opaque pass |
| --- | ---: | ---: |
| RVT off (`CGAME_RVT=0`) | 24.7 / 24.2 ms | 11.8 ms |
| RVT on | 20.7 / 20.7 ms | — |

The manager costs ~0.04 ms of script time per frame once the cache is warm. Baking renders up to
six small viewports a frame while pages stream in, which adds CPU time during that phase.
`CGAME_RVT_DEBUG=1` tints cached pixels (red = level 0, blue = level 1) and logs residency.

## Limits

- Forward+ only: it needs `RenderingDevice`. Compatibility shades live.
- Level 1 has no mipmaps, so 6 cm texels can shimmer slightly far away at grazing angles.
- High/Ultra-only terms that need per-layer data are flat inside cached pages: normal-map variance
  and micro-occlusion.
- Terrain geometry LOD is whatever the main camera chose when the page was baked.

References:

- [Unreal Engine: Runtime Virtual Texturing](https://dev.epicgames.com/documentation/unreal-engine/runtime-virtual-texturing-in-unreal-engine)
- [Ka Chen, "Adaptive Virtual Texture Rendering in Far Cry 4" (GDC 2015)](https://www.gdcvault.com/play/1021761/Adaptive-Virtual-Texture-Rendering-in)
- [Apple: Tailor your apps for Apple GPUs and tile-based deferred rendering](https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering)
