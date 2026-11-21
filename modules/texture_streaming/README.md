# Cgame native texture streaming

Cgame's texture streaming module uses GPU material feedback, a feedback
processing thread and a separate I/O thread to select and reload texture mips.
Streaming is opt-in at project level; the Compatibility renderer does not
support it. The existing memory budget fitter remains authoritative.

## Runtime streaming diagnostics: Unreal STAT STREAMING-style

[Unreal Engine's texture streaming metrics](https://dev.epicgames.com/documentation/en-us/unreal-engine/texture-streaming-metrics-in-unreal-engine)
make wanted memory, pool pressure and pending work visible in the profiler.
Cgame exposes a small, low-overhead subset as *atomic, last-feedback-pass*
getters on the existing `Engine.get_singleton("TextureStreaming")` object:

| Native getter | Definition |
| --- | --- |
| `get_streaming_texture_count()` | Textures considered during last completed mip fitting pass |
| `get_streaming_pending_count()` | Textures whose resident mip still differs from the fitted target (not the actual number of I/O jobs) |
| `get_streaming_budget_reduction_steps()` | Individual mip-level degradation steps performed by the memory-budget fitter on the last pass (not the count of affected textures) |
| `get_streaming_requested_bytes()` | Initial target mip bytes **before** budget reductions, including temporary retained high-detail mips from previous feedback |
| `get_streaming_fitted_bytes()` | Target mip bytes **after** the memory fitter |
| `get_streaming_budget_bytes()` | Budget allowed in bytes during the last pass; **0 means budget fitting is disabled**, not zero VRAM |
| `get_memory_budget_bytes_used()` | Estimated current resident streamed mip bytes; existing Cgame API |

The metrics **do not claim to measure actual GPU driver allocations, true I/O
inflight requests or disk bandwidth**. As with normal asynchronous telemetry,
different independent atomic loads may reflect adjacent worker passes. Getters
are O(1), don't iterate RIDs, don't lock either worker and don't perform GPU
readbacks. Counters reset when streaming is stopped.

Example:

```gdscript
if Engine.has_singleton("TextureStreaming"):
    var stream: Object = Engine.get_singleton("TextureStreaming")
    if stream.has_method("get_streaming_pending_count"):
        print(stream.call("get_streaming_pending_count"),
            " textures awaiting their approved mip")
```

Albion After's actual `online_main.gd` registers seven custom monitors
(`Albion/TextureStreamingActive`, `...Pending`,
`...BudgetMipCuts`, `...RequestedBytes`, `...FittedBytes`,
`...BudgetBytes`, `...ResidentBytes`) in Godot's **Performance**
profiler when supported by the installed Cgame binary. They are removed on
game-client exit, and registration is idempotent. On stock Godot or older
custom engines, unsupported counters are omitted without breaking gameplay.

## Verification

- Native doctests: `modules/texture_streaming/tests/test_streaming_stats_policy.h`
  validates backlog classification, unchanged targets, sentinel values and
  correct accounting of detail recovery versus budget cuts.
- Game: `game/tests/test_graphics_texture_streaming.gd` validates native
  visibility through the real Performance monitor API, non-negative values,
  no duplicate registration and explicit teardown.
- Source contracts:
  `python3 -m unittest tests/scene/test_texture_streaming_metrics_contract.py -v`
- CI: `.github/workflows/native-adaptive-texture-prefetch.yml` compiles
  the engine, executes all `[TextureStreaming]` doctests, imports Albion After
  and runs its focused headless texture-streaming test suite.

This instruments existing texture work rather than changing mip fit decisions.
To assess actual performance, capture a trace or compare streaming profiles
in a representative scene.
