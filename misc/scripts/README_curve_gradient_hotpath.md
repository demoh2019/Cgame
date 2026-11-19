# Curve search and Gradient sampling hot-path optimizations

This Cgame `develop` change makes two CPU sampling paths cheaper without creating caches or growing long-lived memory.

- `scene/resources/curve.cpp`: preserve the original segment-index binary search and all of its comparison semantics (including exact offsets, equal points, infinities, NaN), while reading the next point's offset only when the midpoint is strictly left of the requested offset. The old code fetched both point positions on every iteration. Expected benefit: fewer loads/less cache traffic in repeated curve sampling.
- `scene/resources/gradient.h`: compute normalized interpolation weight only within **linear** and **cubic** interpolation. Constant/stair-step mode returns the source color directly without an unused division. Gradients with two or more points continue to clamp, sort, and interpolate exactly as before. Optimizing compilers may already eliminate this division; no engine-FPS claim is made for it.

## Verification

- 20 Python source-contract tests (`test_curve_gradient_hotpath.py`) for result-sensitive guards and fast paths, run on Python 3.10 and 3.13.
- 4 additional native Godot C++ test cases in `tests/scene/test_curve.cpp` and `tests/scene/test_gradient.cpp`. These exercise exact point samples, empty/singleton curves, constant gradient step boundaries, and interpolation modes.
- Standalone `bench_curve_index_equivalence.cpp`: tests deterministic random sorted arrays with duplicate positions, exact offsets and NaN, then executes five million uniform queries, checking sum and counting touched coordinate values on both algorithms. Runs with GCC and Clang in CI.
- Separate CI job compiles this fork's editor and runs native tests (when runners are available). It is not evidence of an already passing engine build until the workflow completes.

### Synthetic benchmark (not engine FPS)

Development container Linux x86_64, GCC `-O3`, 64 sorted control points, 5 million queries, one run:

| Variant | Time | Coordinate reads | Output checksum |
| --- | ---: | ---: | ---: |
| Old | 251,571 μs | 52,313,750 | 157,397,170 |
| New | 231,944 μs | 41,896,690 | 157,397,170 |

A Clang `-O3` check on the same fixture reproduced the same output and coordinate-read counts; measured times vary. These numbers measure only the standalone analogous algorithm and are not valid estimates of game FPS or end-to-end Gradient performance.

The revised search is intentionally not converted to a different lower_bound implementation, as doing so changes the old choice of segment at some exact knot offsets. A conventional binary-search replacement requires additional behavior verification on all interpolation modes. Memory footprint of Curve and Gradient instances is unchanged.
