# Foveated rendering (Metal rasterization rate maps)

**Integrated into:** the engine's Forward+ renderer
(`servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp`) and the Metal driver,
driven by `rendering/vrs/cgame_foveation_edge_rate`. The game sets it per preset in
`scripts/client/graphics_quality.gd`: Performance 0.5, Balanced 0.6, High/Ultra off.

## Why

Once triangle counts were down, the M1 frame was fill-bound: alpha-tested foliage in the depth
pre-pass, and the opaque pass. Apple GPUs support variable rasterization rates. A rate map lowers the
shading rate where detail matters least (the screen edges in the orbit view) and keeps full rate in
the middle. Upstream Godot only used rate maps for visionOS through the XR runtime, in the Mobile
renderer.

## How

- **Engine API**: `RenderingDevice.rasterization_rate_map_create(screen_size, horizontal_rates,
  vertical_rates)`, `rasterization_rate_map_get_physical_size()` and
  `rasterization_rate_map_get_axis_mapping()`. They are implemented in the Metal driver
  (`MTLRasterizationRateMap`). RD already sizes a framebuffer by its rate map, so attachments are
  physical-size while viewports stay logical.
- **Measured on an M1 with a probe**: physical size is smaller than the screen; varyings are
  interpolated in screen space; `gl_FragCoord` is in physical coordinates.
- **Scene shader**: light-cluster lookup and `SCREEN_UV` take the screen position. The renderer
  rebuilds it from 16 knots per axis in its implementation UBO. The knots are the inverse of the map's
  monotonic per-axis mapping.
- **Frame**: the depth pre-pass, opaque pass and sky render into physical colour and depth with the map
  attached. A raster resolve (`effects/cgame_foveation_resolve.glsl`) then reads every full-resolution
  pixel through the exact per-column and per-row mapping. Colour is filtered bilinearly; depth is
  written through `gl_FragDepth`. Transparent, post and upscaling passes run at full resolution as before.
- **When it applies**: only when nothing reads the targets by screen position before the resolve. That
  excludes MSAA, SSAO, SSIL, SSR, SDFGI, VoxelGI, contact shadows, motion vectors (temporal upscalers),
  SSS or separate specular, multiview, debug draws, and compositor effects before transparency.
  Otherwise the frame renders normally.

## Measured (M1, 1920×1080, Balanced, orbit view)

Same-scene A/B with `CGAME_AB="rendering/vrs/cgame_foveation_edge_rate:1.0:0.6"`
(`scripts/client/ab_benchmark.gd` flips the setting every 2 s and averages the GPU time of each value):

| Edge rate | GPU | Frame |
| --- | ---: | ---: |
| 1.0 (off) | 21.05 ms | 24.9 ms |
| 0.6 | 18.37 ms | 22.6 ms |

In the light spawn scene (GPU ~9 ms) there was no gain: the resolve (~0.25 ms) eats the saving.
The screenshot benchmark now takes `CGAME_BENCH_FRAMES=start:end` to sample after streaming. The default
window (frames 540–700) mostly measured loading.

## Limits

- Metal only: other drivers report no `SUPPORTS_RASTERIZATION_RATE_MAP` and render normally.
- The edges are softer by design; HUD and transparent effects are unaffected.
- The knots are linear between 16 samples per axis. That is exact enough for 32 px light clusters and
  `SCREEN_UV`, not for per-pixel screen reads, which is why such effects disable foveation.

References:

- [Apple: Rendering with a rasterization rate map](https://developer.apple.com/documentation/metal/rendering-with-a-rasterization-rate-map)
- [Apple: Creating a rasterization rate map](https://developer.apple.com/documentation/metal/creating-a-rasterization-rate-map)
- [Apple: MTLRasterizationRateMap](https://developer.apple.com/documentation/metal/mtlrasterizationratemap)
