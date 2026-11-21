# Cgame profiling and runtime architecture (native)

Native ports of the GDScript profiling / scheduling libraries (`trace_capture`, `task_graph`,
`cpu_budget`, `lock_profiler`, `hitch_correlator`, `frame_hitch_analyzer`, `perf_capture_format`,
`perf_regression`, `shader_stall_analyzer`). Always enabled; no external dependencies.

| Class | Kind | Replaces |
| --- | --- | --- |
| `CgameTrace` | engine singleton | `trace_capture.gd` |
| `CgameTaskGraph` | `RefCounted` | `task_graph.gd` |
| `CgameCPUBudget` | `RefCounted` | `cpu_budget.gd` |
| `CgameProfiledMutex` | `RefCounted` | `lock_profiler.gd` |
| `CgameHitchCorrelator` | `RefCounted` | `hitch_correlator.gd`, `frame_hitch_analyzer.gd` |
| `CgamePerfCapture` | `RefCounted` (static API) | `perf_capture_format.gd`, `perf_regression.gd` |
| `CgameShaderStallAnalyzer` | `RefCounted` | `shader_stall_analyzer.gd` |

## CgameTrace

- Per-thread, single-producer ring buffers: no locks and no allocations on the recording path.
  Readers (export, frame markers) snapshot optimistically and drop slots the writer may have
  overwritten meanwhile.
- Disabled cost: one relaxed atomic load per call (`CgameTrace::is_active()`).
- Scopes are stored as complete (`X`) events when they end, so overwriting old events never
  leaves orphaned begin/end pairs. Counters, instants, flows (`s`/`f`) and frame markers are
  supported; `export_chrome_json()` output opens in `chrome://tracing` and `ui.perfetto.dev`.
- Frame aggregates (per-scope microseconds, last counter values) are computed at each frame
  marker by reading the events recorded since the previous marker, so writers never touch shared
  aggregation state.
- Frame markers are inserted automatically at the end of every `Main::iteration()` through
  `Engine::set_frame_hook()` (`core/config/engine.h`) while `auto_frame_markers` is on.
- `max_events` is the per-thread capacity and applies to threads that record their first event
  after the change.

C++ usage:

```cpp
#include "modules/cgame_profiling/cgame_trace.h"

void simulate() {
	CGAME_TRACE_SCOPE("simulate");          // name must be a string literal
	CGAME_TRACE_COUNTER("bodies", count);
	// ...
}
```

## Integration points

- `core/config/engine.h` / `main/main.cpp`: a single `FrameHook` function pointer called once per
  main loop iteration after rendering. The module chains any previously installed hook.
  `CgameShaderStallAnalyzer::start_auto_sampling()` also runs from this hook.
- `CgameTaskGraph` schedules on `WorkerThreadPool` and records task scopes plus dependency flows
  in `CgameTrace`; `CgameProfiledMutex` shows contended waits as `wait:<name>` scopes.
- `CgameHitchCorrelator::read_counters()` and `CgameShaderStallAnalyzer` read the
  `RenderingServer` pipeline compilation counters natively.
- `GodotProfileZone` (Tracy and friends) is intentionally not rerouted into `CgameTrace`; add
  `CGAME_TRACE_SCOPE` next to the zones that matter.

## GDScript facades

`game_facade/*.gd` (repository root) wrap the native classes and fall back to the original
GDScript implementations when the module is not compiled in, so game code can switch
`preload` paths without behavior changes.

## Tests

`tests/test_cgame_profiling.h` (doctest, run with `--test --test-case="*Cgame*"`) mirrors the
GDScript cases: nesting, disabled = no events, JSON validity, ring-buffer overwrite, frame
aggregation, compare, task ordering / parallel aggregate / cycles / failure cancellation,
critical path and DOT, budget allocation and adaptation, mutex contention, hitch attribution,
capture round trips, regression comparison and shader stall attribution.
