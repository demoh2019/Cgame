# Ground-contact shading for streamed world geometry

## Purpose and rendering technique

The game now uses a **64 × 64 L8 ground-contact mask per visible terrain chunk** to ground trees, rocks, resource nodes and building bases visually. It is an inexpensive ambient-occlusion approximation inspired by baked-object contact work, not the screen-space depth ray marching implemented in Unreal Engine's Contact Shadows or Unity HDRP.

The server supplies the authoritative tree/resource/structure positions as before. The client-only module `scripts/client/ground_contact_ao.gd` stamps soft circular imprints into 4 KiB of raw pixels per above-ground chunk, using bounded pixel rectangles rather than evaluating all objects over every image pixel.

The mask is assigned to a duplicate of the chunk-specific material. This is important: the procedural fallback material is otherwise shared, and writing a per-chunk texture to that shared resource would make every chunk display the same shadows.

Both `assets/shaders/ground.gdshader` and the procedural fallback shader embedded in `chunk_view.gd` sample the mask only near the player, multiply the result into PBR `AO`, and add a very subtle albedo darkening for the Compatibility renderer. On the Performance profile the shared strength is zero and the contact sampler branch is skipped. The shadow fades continuously with the existing `aa_terrain_detail_radius`, without new meshes, full-screen passes, shadow-map draws or transparent sorting.

## Preset tuning

| Profile | `aa_ground_contact_strength` | Additional work |
| --- | ---: | --- |
| Performance | 0.00 | GPU contact-map lookup skipped |
| Balanced | 0.28 | Up to one filtered L8 fetch per nearby terrain fragment |
| High | 0.48 | Same lookup, stronger visible grounding |
| Ultra | 0.70 | Same lookup, maximum contact grounding |

The mask source is local per chunk and fades before chunk borders. Consequently, no neighboring chunks need to be generated to keep seams unobtrusive. When the server hides a depleted rock, gathered tree or other resource node, the mask is rebuilt only after the visibility state actually changes, so dark patches do not remain behind.

## Visual and performance acceptance

1. Compare rock feet, tree trunks, berry bushes, roadside structures and city ruins in identical lighting on High/Ultra. Look for convincing grounding without black circles.
2. Check chunk corners and borders, especially object footprints that cross them. Confirm no abrupt square seams.
3. Deplete a rock or tree and confirm its ground stain disappears after the network state update.
4. Test both installed PBR terrain textures and missing-texture procedural fallback; verify wet puddles, roads, snow and terrain LOD remain unchanged.
5. Benchmark GPU median and p95 frame times at 720p and 1080p with matching camera angle, weather, and scene contents. Also inspect per-chunk L8 texture memory and CPU masks built during streaming.

All source changes have been integrated into `develop` through PR #856. The structural tests are in `tests/test_terrain_shader_lod.gd`. A Godot runtime/GPU benchmark has **not** been executed in the current environment, so there is no measured FPS claim.
