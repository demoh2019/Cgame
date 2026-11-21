# cgame_raytrace

Native CPU ray tracing for light baking, ported from the GDScript `bvh.gd` / `path_tracer.gd`
libraries of the Cgame game.

- `CgameBVH` (RefCounted): binned-SAH BVH with flat nodes, `build`, `intersect`, `occluded`,
  `get_stats`. Queries are const and thread-safe.
- `CgamePathTracer` (RefCounted): static `bake_vertex_lighting`, `bake_ambient_occlusion`,
  `render_image`, `make_light`, plus an instance API for progressive refinement
  (`begin_progressive`, `accumulate`, `get_pixel`, `to_image`).

Work is split across `WorkerThreadPool`. Each vertex and pixel owns a PCG32 stream seeded from
`(seed, index)`, so output is deterministic per seed regardless of thread count.

Differences from the GDScript version: the progressive state lives on the `CgamePathTracer`
instance instead of a nested `Progressive` class; the BVH has a hard depth cap (96) so the
traversal stack is fixed-size. RNG streams differ from `RandomNumberGenerator`, so baked values
match the GDScript output statistically, not bit for bit.

Tests: `tests/test_cgame_raytrace.h` (doctest, `--test --test-case="*Cgame*"`).
A GDScript facade with automatic fallback lives in `game_facade/cgame_raytrace_facade.gd`.
