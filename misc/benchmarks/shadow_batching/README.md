# Forward+ Shadow Instancing Benchmark

This benchmark creates **10,000 MeshInstance3D nodes** sharing a single
BoxMesh and material, one four-cascade-style shadow-casting directional light,
and a fixed camera. It reports average *shadow draw calls per frame* and
approximate frame interval over 240 samples after 120 warm-up frames.

Run with **Forward+ Vulkan or D3D12** and V-Sync **off** (same driver/settings
in both builds). Do not use Compatibility rendering or headless mode: both
bypass the Forward+ shadow batching code. A project-level renderer override
must use Forward+ for this comparison.

Build baseline and optimized Cgame binaries with matching settings. Run:

Use the project's default Forward+ rendering method on a compatible GPU:

```sh
/path/to/godot --path misc/benchmarks/shadow_batching
```

Compare the `SHADOW_BENCH` output between both builds.
Check output correctness by capturing identical frames with the same
viewpoint, lights, driver and sample configuration; pixel differences should
be investigated. The script's average frame interval is **not** GPU timestamp
profiling. For accurate GPU time use a hardware profiler or engine frame
profiling alongside the logged shadow draw calls.

Upstream reference: https://github.com/godotengine/godot/pull/125528.
Its GPU measurements were obtained on a different reproduction scene and
should not be presented as measurements on this project.
