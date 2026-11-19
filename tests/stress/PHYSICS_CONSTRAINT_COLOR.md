# Constant-time graph coloring for GodotPhysics large islands

Cgame already uses a greedy constraint graph colorer in the opt-in
`GodotPhysics2D` and `GodotPhysics3D` large-island parallel solvers.
As in Box2D's constraint graph and Jolt's LargeIslandSplitter, a color
contains constraints that can run together without writing the same
dynamic body twice. The solver uses 16 parallel color groups and a
17th sequential overflow group for high-degree constraint hubs.

Previously both solvers selected the first available color by scanning
bits `0..15` in a loop for **every constraint on every coloring-cache
miss**. We now share an exact equivalent first-clear-bit helper in
`servers/physics_constraint_color.h`:

- Mask to the lowest 16 bits; high bits must not affect the choice.
- Return the first zero bit in a bounded mask, using a native bit scan
  (`__builtin_ctz` on GCC/Clang, `_BitScanForward` on MSVC).
- Return `16` if all colors are used, preserving the serial overflow.
- Include a portable C++ fallback for toolchains without these intrinsics.
- Leave the rest of the original coloring algorithm unchanged: static
  body-sharing rules, constraint order, cache validation, worker barriers,
  runtime feature flag and overflow behavior.

This does **not** change the solver when parallel large-island coloring
is disabled. For unchanged constraint topology the existing color cache
is reused, and this optimization does not run.

## Verification

The native C++ test is exhaustive over every 16-bit color mask and the
same masks with high bits set (131,072 cases), plus masks with color
counts 1, 8 and 31. It compares the selected color with the original
greedy loop, not with a hardcoded set of expected results.

```bash
# Source/API wiring contracts, run from repository root:
python3 -m unittest discover -s tests/stress -p test_physics_constraint_color.py -v

# Godot native unit test; compile with tests=yes:
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Bit-scan constraint color matches the existing greedy solver"

# Isolated color selection microbenchmark (not the full physics step):
c++ -O3 -std=c++17 -I. tests/stress/benchmark_physics_constraint_color.cpp \
  -o /tmp/cgame-color-bench
/tmp/cgame-color-bench
```

The standalone benchmark verifies masks before reporting timing in ns/op,
using deterministic pseudo-random values for common, random and saturated
hub cases. Results are sensitive to compiler flags and CPU architecture.
Any claimed speedup applies only to color selection, not constraint graph
building, solver iteration, total frame rate or resident RAM. This standalone
benchmark is not an end-to-end physics-frame benchmark.

## Performance validation before release acceptance

Benchmark equivalent scenes on the same hardware with and without this
change: one dominant contact island, one high-degree hub, many small
islands (which bypass color selection), and an unchanged frame that reuses
the color cache. Report per-frame physics-step time (median and p95),
CPU usage and peak RSS. Native engine tests and CI must pass before a release is considered verified.

References:
- Box2D: https://box2d.org/posts/2024/08/simd-matters/
- Jolt Physics: https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md
