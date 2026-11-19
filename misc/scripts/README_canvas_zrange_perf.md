# Canvas Z-range performance optimization

Cgame-specific adaptation of the motivation behind Godot PR [#94390](https://github.com/godotengine/godot/pull/94390). The upstream patch uses a different internal canvas-culling API, so this implementation deliberately preserves Cgame's draw order and existing `_cull_canvas_item` recursive signatures.

## Change

The 2D canvas rasterizer currently allocates two fixed-size Z-bin pointer arrays. Previously it cleared both arrays and scanned every possible Z bin for **every** canvas cull pass, even if only one or two Z values were visible. This change records the smallest and largest bins actually used and clears only the *previous* pass's occupied interval before collecting the next pass. At first construction both arrays are explicitly zero-initialized once. Collecting the result scans the *current* occupied interval in ascending Z order.

- No additional dynamic allocations or containers; only two integer bounds per renderer instance.
- Preserves stable order inside each bin and ascending Z order across bins.
- Empty canvases do not iterate or clear unused bins; every pass still calls the canvas renderer.
- Works across consecutive passes, including empty → nonempty, wide → narrow, and min-Z/max-Z transitions.
- Worst case stays linear in the full Z range, as before, when both extreme bins are occupied.
- Does not change GPU commands, canvas materials, clipping or Y-sort behavior.

## Local differential test

`misc/scripts/tests/bench_canvas_zrange.cpp` compares a full-clear/full-scan reference model to the span model for 12,000 deterministic frames, random z-values, empty canvases, extreme bins, repeated bucket insertions and an explicit empty-frame reset. It tests identical per-frame item order and counts scanned/cleared bins. This is a **standalone CPU model, not a native renderer test or engine FPS benchmark**.

Run:

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_canvas_zrange_perf.py -v
c++ -std=c++17 -O2 misc/scripts/tests/bench_canvas_zrange.cpp -o /tmp/cgame_canvas_zrange && /tmp/cgame_canvas_zrange
```

Full engine build and headless smoke run are configured in `.github/workflows/canvas-zrange-perf.yml`. Visual comparisons should cover nested Y-sort, canvas groups, mirroring/repeat, CanvasLayer, cutout/transparency, offscreen clipping and 2D lights on multiple consecutive frames.

## Measurement guidance

Profile `RendererCanvasCull::_render_canvas_item_tree` CPU time before/after on small-Z-span 2D scenes and a worst-case scene with both Z extremes. Track p50/p95 frame time, CPU cycles, RSS and GPU time. Do not infer FPS improvements from the standalone model. The code uses no new large persistent storage; it trades two integers for fewer memory writes and iterations.
