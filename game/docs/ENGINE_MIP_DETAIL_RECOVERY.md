# Streaming high-resolution PBR textures faster

The custom Godot engine's texture-streaming I/O worker now accelerates
**quality improvements** for High/Ultra without changing the GPU feedback
or residency budget. When a sharp texture mip becomes needed, the worker
can skip one intermediate blurry upload rather than doing every level
one by one. The latest selected target is still controlled by the VRAM
budget fitter. No extra shader sampling or framebuffer pass is added.

| Profile | Desired detail prefetch | Maximum quality-recovery step |
| --- | ---: | ---: |
| Performance | 0 mips | 1 mip per upload |
| Balanced | 0 mips | 1 mip per upload |
| High | 1 sharper mip | 2 mips per upload |
| Ultra | 2 sharper mips | 2 mips per upload |

In low/medium quality nothing changes. On low GPU memory the existing
budget fitter may deny extra detail. During VRAM pressure the worker
still reduces fidelity only one mip per reload; an explicit flush still
jumps directly to the desired target. Stock Godot and Compatibility
clients keep the default behavior.

Code: `modules/texture_streaming/feedback_buffer_policy.h`,
`modules/texture_streaming/texture_streaming.cpp`,
`game/scripts/client/graphics_texture_streaming.gd`.
Tests: standalone C++ `test_feedback_prefetch.cpp` and live
GDScript `test_graphics_texture_streaming.gd`, now listed in the
graphics-only test runner.

This is inspired by Unreal's mip texture streaming model, **not** a
port of Unreal virtual texturing. Unreal documentation:
https://dev.epicgames.com/documentation/en-us/unreal-engine/texture-streaming-overview-for-unreal-engine

### Verify
```sh
c++ -std=c++17 -Wall -Wextra -pedantic modules/texture_streaming/tests/test_feedback_prefetch.cpp -o /tmp/aa_prefetch
/tmp/aa_prefetch
godot --headless --editor --path game --quit
godot --headless --path game --script res://tests/run_graphics.gd
```

A real GPU quality pass should compare texture mip sharpness during
rapid camera travel and p50/p95 streaming latency and peak VRAM on
Forward+, checking for memory-thrashing on constrained devices.
FPS gains are not asserted without measurement.
