# Performance pass — 19 November 2026

Target: `demoh2019/Cgame`, **develop**. Scope: CPU hot paths, avoidable allocations, editor import responsiveness and baseline memory measurement.

## Changes landed directly on develop

- **Directional shadow culling** — backport/adaptation of [godotengine/godot#124897](https://github.com/godotengine/godot/pull/124897), commit `a1b48bacf41f88c8e48277c0d3cef3c9eaea7e8d`. Perform instance visibility/geometry/particle eligibility once, test shadow layer before cascade loops, test frustum before expensive directional light culler. This reduces unnecessary calls when many geometry instances or cascades are rejected.
- **AnimationNodeBlendTree lookups** — [#124845](https://github.com/godotengine/godot/pull/124845), commit `043463aef6262869bad56b04cb4bac6815156b0e`. Replace has()+operator[] pairs with one HashMap getptr().
- **AnimationMixer/AnimationPlayer** — [#124845](https://github.com/godotengine/godot/pull/124845) adapted, commits `f4994445867fe4e8bc49880c02ec4e1c67203b38`, `1dafc2e1c0f9a634356a47557e2a0e67cc802d76`, `2ad4402abd663c5e793a62fe5407cd37cb6f8915`. Avoid redundant RESET lookups, store playback name as StringName, convert to String only when formatting diagnostics.
- **GDScript notification allocations** — adapted from [#125060](https://github.com/godotengine/godot/pull/125060), commit `02133d60e301b4a66e1ad84d559c84b5258211ce`. Unlike the upstream branch order, Cgame retains its previous observable notification order: direct derived-first traversal for reversed notification; for non-reversed, a stack-local 8-entry ancestry cache and a dynamic fallback for deeper chains. Both paths use getptr() for one hash lookup per method.
- **Editor threaded asset import** — [#124138](https://github.com/godotengine/godot/pull/124138), commit `730191706307b8331b33a797b8772293a09cac83`. Main-thread polling yields briefly to background import workers, and the progress filename uses the actual current batch offset.
- **FileSystem search & Unix directory construction** — [#124138](https://github.com/godotengine/godot/pull/124138), atomic commit `859d2fb63bef1abeb4b4a4468328f0c39e807123`. Use span comparisons, avoid allocating a DirAccess for each file lookup, skip needless path localization for simple res:// paths, remove redundant current directory change.
- **FileSystem Dock thumbnail batching and fast ASCII case lowering** — independently landed by other concurrent develop changes during this session. Confirmed presence on develop; not duplicated.

## Validation

- `misc/scripts/tests/test_engine_hotpath_perf.py` contains **24 new test methods** covering source-contracts, randomized directional shadow output equivalence and a standalone C++ harness compiled from the **actual** GDScriptInstance::notification() function on supported CI compilers.
- `misc/scripts/tests/test_editor_file_path_perf.py` adds **7** more source/compiled-helper tests for the actual Cgame resource-path and string-span fast-path functions; the new suite is included in the GCC/Clang matrix (31 regression test methods across the two new suites).
- An additional local C++ test using equivalent code and mocks passed 7 inheritance depths x 2 traversal directions on both GCC and Clang. A second local C++ test verified 10 resource-path cases and 3 span-comparison cases on both compilers (after correctly treating `.hidden` as a valid file name). These are isolated tests, not a full engine build.
- `.github/workflows/engine-hotpath-performance.yml`: Python source/model/compiled C++ regressions on GCC and Clang; Cgame native Linux editor build with tests=yes, headless GDScript and animation tests; three real subprocess samples each of editor import and scene execution, recording wall time, user/system CPU and **peak RSS (KiB)** with GNU time, as a CSV artifact.
- The [latest workflow run](https://github.com/demoh2019/Cgame/actions/runs/44439968341) was **queued** when checked. The native editor build and measurements are *not yet confirmed*.

## Performance interpretation and next steps

Upstream PR benchmarks are directional evidence only, not Cgame measurements. Source tests validate semantic invariants; they cannot establish FPS, CPU or RAM improvement. For credible comparisons, record metrics for previous and new commits using the same runner, engine configuration and project; report distributions, not a single sample. Renderer performance additionally requires a real GPU benchmark. Track worst-case latency and memory on large imported projects, large navigation meshes, many animation tracks and deep scene trees.

Future high-impact candidates include navigation BVHs, scene visibility caching, hash-map ownership reduction and lowering editor SignalData allocations; verify they have not already landed on develop before porting. Avoid claiming full production validation until native CI and platform-specific tests pass.
