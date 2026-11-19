# Cgame performance backports: rendering, editor, and binary size

This targeted performance pass adopts **compatible pieces** of three still-open Godot upstream PRs, reviewed on 2026-11-19:

| Source | Improvement | Cgame files |
| --- | --- | --- |
| [godotengine/godot#124897](https://github.com/godotengine/godot/pull/124897) | Filter non-shadow-casting, invisible, inactive, wrong-layer, and out-of-frustum objects **before** expensive directional-light culling. Move object checks outside per-light/per-cascade loops. | `servers/rendering/renderer_scene_cull.cpp` |
| [godotengine/godot#124138](https://github.com/godotengine/godot/pull/124138) (focused subset) | Request FileSystem tree thumbnails lazily for open folders; deduplicate requests and apply thumbnail updates once per frame. Remove redundant Unix `change_dir()` during directory construction. | `editor/docks/filesystem_dock.{cpp,h}`, `drivers/unix/dir_access_unix.cpp` |
| [godotengine/godot#124495](https://github.com/godotengine/godot/pull/124495) (Cgame-adapted) | Mark cold one-time class binding and engine init/teardown code as unlikely to execute. On GCC the optimizer can prioritize code size over speed for this work. **Retains Cgame's atomic `SafeFlag` and mutex**, unlike the proposed upstream plain-boolean replacement. | `core/object/object.h`, `core/typedefs.h`, `main/main.h` |

These improvements target **frame-time, editor responsiveness, CPU work, binary size, peak queued thumbnail requests, and unnecessary allocations**. Their benefit depends on scene geometry, number of shadow cascades, asset counts, and folder expansion.

Only the reviewed rendering/filesystem hunks were applied over the current Cgame sources; the object-initialization hot/cold split was adapted to retain the fork's concurrency semantics. Other upstream #124138 changes (e.g., `.tscn` filesystem path lookup overhaul and macOS hidden-file API) were **not** brought in. Existing fork code outside the selected hunks is preserved.

## Deterministic synthetic microbenchmark

Run locally:

```sh
c++ -O3 -std=c++17 -Wall -Wextra -Werror -pedantic \
  misc/scripts/tests/bench_directional_shadow_cull.cpp -o /tmp/bench_directional_shadow_cull
/tmp/bench_directional_shadow_cull
```

The C++ harness exhaustively checks **147,456** combinations of object flags, light counts, frustum flags and seeds for exactly the same selected shadow cascades. It then runs both orderings over 40,000 synthetic objects, asserting identical outputs and a reduction in the expensive culling predicate calls. The harness was run on a Linux GCC 14.2 build with `-O3`:

| Synthetic metric | Original order | Filter-first order |
| --- | ---: | ---: |
| Expensive predicate calls | 320,000 | 8,971 |
| Selected cascade instances | 6,702 | 6,702 |
| Single illustrative wall-time run | 10,262 µs | 540 µs |

**Important:** The benchmark uses a deterministic simulated expensive predicate, *not* the actual renderer's AABB/light algorithm, a GPU, or a representative real scene. It verifies order/predicate equivalence and demonstrates work eliminated, **not a measured Cgame FPS speedup**. Upstream PR #124897 reports approximately 2 ms per frame savings on its Dogwalk test scene; Cgame must separately profile its own hardware and scenes to corroborate that observation.

## Cold class initialization and binary size

Godot upstream #124495 reported GCC binary-size reductions of approximately **2.40 MiB (-3.2%)** for a Linux export template and **3.60 MiB (-2.8%)** for a Linux editor. These are upstream measurements, **not verified Cgame measurements**. The Cgame implementation leaves `static SafeFlag initialized` and the per-class `BinaryMutex` intact, but moves the once-only class binding and registration into `_NO_INLINE_ _COLD_ _initialize_class_cold()`. The regular entrypoint keeps an atomic fast path. Startup and teardown methods are similarly marked `_COLD_`.

A second standalone C++ harness exercises 24 threads × 10,000 calls and confirms that the simulated cold initialization and its bookkeeping run exactly once. Run it with `-pthread`:

```sh
c++ -O2 -std=c++17 -pthread -Wall -Wextra -Werror -pedantic \
  misc/scripts/tests/bench_class_cold_init.cpp -o /tmp/bench_class_cold_init
/tmp/bench_class_cold_init
```

This tests a concurrency model and compiler compatibility, not Godot's complete `GDCLASS` macro or runtime registration. CI compiles the engine to catch actual macro/API issues.

## Editor asset preview requests

The FileSystem Dock change avoids queuing file previews for collapsed folders. For example, a **synthetic** 1,000-folder tree with 50 files per folder and 2 expanded folders needs only 100 tree preview requests instead of 50,000; actual memory savings depend on caching, icons, open folders and preview texture sizes. Preview requests for newly expanded folders are queued on expansion and duplicate requests are blocked per tree generation.

## Regression checks

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_hotpath_perf.py -v
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_cold_class_init.py -v
```

49 Python source-contract tests check rendering and editor hot paths; 25 additional source tests verify the cold-class-entrypoint hot/cold split and preserved `SafeFlag`/mutex ordering (74 total). The GitHub Actions workflow runs these on Python 3.10 and 3.13, compiles/runs two standalone C++ harnesses under GCC and Clang, and builds the Cgame editor for a headless import smoke test.

Source tests are not a replacement for a native build, headless project import, functional UI testing or GPU profiling.

### Interactive acceptance tests

1. **Rendering:** Compare a dense 3D scene with many non-shadow-casting meshes and 1-2 shadowed directional lights across old/new builds. Measure CPU `RendererSceneCull::_scene_cull`, p50/p95 frame time and actual FPS with identical lighting/cascade settings. Visually compare shadow silhouettes, including particles and visibility masks.
2. **FileSystem Dock:** Import a project with tens of thousands of images, leave most folders collapsed, and compare thumbnail jobs, peak RAM, UI responsiveness and frame-rate. Expand and collapse folders repeatedly, verify thumbnail icons load and do not disappear after rebuilds, and verify favorites previews and stale callbacks.
3. **Cold class initialization:** Compare editor/template executable bytes, `.text` section sizes, startup latency, peak RSS and class registration behavior under GCC/Clang and concurrent editor import.
4. **Unix directory startup:** Exercise project import, directory listing, symlinks, relative paths and changing the current directory on Linux. Validate no behavior change from the removed redundant constructor call.

The engine build and end-to-end graphics/editor checks are **pending CI/manual verification** at the time this change is authored.
