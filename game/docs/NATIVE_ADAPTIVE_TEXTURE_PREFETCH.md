# Adaptive predictive mip prefetch for Cgame / Albion After

## Upstream inspiration

- Unreal [Texture Streaming Overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/texture-streaming-overview-for-unreal-engine)
- Unreal [Texture Streaming Configuration](https://dev.epicgames.com/documentation/en-us/unreal-engine/texture-streaming-configuration-in-unreal-engine)

Unreal's texture streaming system adjusts requested mip quality against a
streaming memory pool. Cgame already has GPU feedback, async reloads and a
separate memory fitter. This change adds an **optional hysteretic admission
gate for speculative high-fidelity prefetch**, not a replacement for the
budget fitter and not a general-purpose texture streaming rewrite.

## Native engine API

`TextureStreaming.set_adaptive_detail_prefetch_enabled(enabled: bool)`
`TextureStreaming.is_adaptive_detail_prefetch_enabled() -> bool`
`TextureStreaming.get_effective_detail_prefetch_mips() -> int`

The existing `set_detail_prefetch_mips(0..2)` continues to specify the
user's desired **maximum** number of speculative sharper mips. Adaptive mode
defaults to **off** for backwards compatibility, and all toggles/counters
are atomic across the UI, feedback and I/O threads.

When adaptation is enabled and the existing texture **memory budget is
enabled** (>0), the engine compares the currently resident streamed-texture
bytes against that budget:

| Resident memory / configured budget | Action |
|---|---|
| >=95% | Drop extra prefetch to 0 |
| >=85% | Restrict to at most 1 extra mip |
| 78–85% | Preserve current admission tier |
| <=78% | Recover one mip, if previously fully suppressed |
| <=70% | Recover the user-configured maximum |

Thresholds intentionally form a deadband to discourage oscillation. The
effective value is read by the GPU feedback prefetch calculation and the
texture upload-step optimization; final reload targets **still come from**
the independent existing memory fitter. No extra scheduled I/O is created
and ordinary nonstreamed textures are unchanged.

The native helper is pure, integer-based and handles uint64 large budgets
without threshold multiplication overflow. A zero/disabled memory budget
passes through the user-configured prefetch level rather than guessing
GPU memory limits. Actual device VRAM usage is not inferred here.

## Albion After

`GraphicsTextureStreaming.apply(level, renderer)` opts into adaptive
prefetch only for Forward+ **High/Ultra**. Performance, Balanced and the
Compatibility renderer keep their existing behavior. Game scripts detect
the new API at runtime, so stock Godot and older Cgame binaries continue
to work. The graphics quality menu already calls `apply`.

**Important deployment requirement:** Albion After does not forcibly
enable native streamed textures or turn on a global memory budget. The new
adaptive gate becomes active for textures registered in Cgame's streaming
system **only when** that existing streaming/budget feature is configured
for the project. This is deliberate to avoid changing resource import
semantics or imposing an untested VRAM pool size on existing players.

## Validation

- Native doctests: `modules/texture_streaming/tests/test_adaptive_prefetch_policy.h`
- Existing game suite: `game/tests/test_graphics_texture_streaming.gd`
- Focused runner: `game/tests/run_adaptive_texture_prefetch.gd`
- CI: `.github/workflows/native-adaptive-texture-prefetch.yml`

The optimization aims to reduce unnecessary high-resolution prefetch and
upload churn near the configured streaming pool limit; no measured FPS,
memory usage or upload count reduction is claimed.
