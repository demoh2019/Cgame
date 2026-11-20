# Geometric specular anti-aliasing

## Background and reference techniques

Unreal Engine supports composite normal-to-roughness data to prevent distant, high-frequency specular sparkle. Unity HDRP provides **Geometric Specular Anti-Aliasing**, based on screen-space normal variance. Godot 4 supports `dFdx()` and `dFdy()` in fragment shaders.

- Unreal Engine: https://dev.epicgames.com/documentation/unreal-engine/composite-texture?application_version=4.27
- Unity HDRP: https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition@10.1/manual/Geometric-Specular-Anti-Aliasing.html
- Godot: https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html

## Albion After integration

A small reusable shader include is shared by the existing textured terrain and foliage materials. The fragment shader estimates the local variation in the shading normal from adjacent pixels **using derivatives, not additional texture samples**. Variance is converted into a bounded increase in squared PBR roughness. The effect broadens tiny unstable highlights when viewed from a moving camera; large stable highlights remain sharp. It does not modify the normal or surface color.

- Performance: 0.00, derivative filter disabled.
- Balanced: 0.00, derivative filter disabled.
- High: 0.18.
- Ultra: 0.30.

The global uniform `aa_specular_aa_strength` is updated in `GraphicsQuality.apply` alongside existing terrain and foliage budgets; no per-chunk material rebuild or extra fullscreen pass is needed.

The ground path uses its existing final triplanar/mixed world normal, which includes nearby cliff relief and rain-puddle smoothing. Foliage uses the existing normal-map sample for variance estimation where one is present, or the geometric normal otherwise. Existing artist PBR maps, alpha-to-coverage, cloud occlusion, wetness, shadows and LOD are retained.

**Trade-off:** More fragment ALU/derivative work on High/Ultra may broaden very sharp highlights. The cost is controlled by the quality global and capped variance. This is an approximation inspired by established methods, not a port of HDRP's full filtering implementation.

## Verification

Run `godot --headless --path game --script res://tests/run_all.gd`. Source tests verify budget wiring, shader includes, cost gates and wet-ground/cutout preservation.

For GPU acceptance compare the same glossy wet-road, cliff and sunlit tree scenes while panning the camera. Look for less shimmering without losing crisp near-field texture detail. Profile median and p95 GPU frame times at 720p and 1080p on Forward+ and Compatibility, ensuring low-tier performance is unchanged. No measured FPS gain is claimed.
