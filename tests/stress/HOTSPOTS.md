# Identify performance bottlenecks from stress reports

`analyze_hotspots.py` consumes JSON from the main
`tests/stress/run.py` and the real-display `tests/stress/run_gpu.py`.
It produces three files: `hotspots.json`, `hotspots.md`, `hotspots.csv`.

### First capture a reference on the target hardware

```bash
python3 tests/stress/run.py --godot /path/to/old-cgame \
  --preset standard --repeats 7 --output out/baseline.json
python3 tests/stress/run.py --godot /path/to/new-cgame \
  --preset standard --repeats 7 --output out/current.json

python3 tests/stress/analyze_hotspots.py out/current.json \
  --baseline out/baseline.json --out out/hotspots.json \
  --fail-over-pct 10 --min-repeats 5
```

For graphics use `run_gpu.py` for **both** builds (same GPU model,
driver, renderer, VSync, window size and OS) instead of `run.py`.
Headless tests are not evidence of GPU speed.

### How results are interpreted

* Matched scenario, scale, frame count, preset and available host metadata are
  required. Dissimilar reports are rejected.
* The ranking measures positive changes in median engine time, process wall
  time, CPU consumption, RSS, and p95 frame latency when available.
* At least three matched repeats are recommended; fewer are flagged
  `low_confidence`. The CLI can gate failures only after `--min-repeats`.
* Absolute time across different stress cases is **not** normalized:
  workloads do not perform identical amounts of work.
* `memory_churn` retained allocator growth is a **heuristic**, never proof
  of a leak. Confirm with a heap profiler or sanitizer builds.
* Not every frame scenario exposes p95; absent measurements are left blank,
  never inferred from draw-call or CPU counters.

### Standalone usage without a baseline

```bash
python3 tests/stress/analyze_hotspots.py out/current.json --out out/hotspots.json
```

This sorts the longest instrumented workloads, lists failed scenarios
and flags suspicious retained memory. It does not claim performance regressions
without an actual reference report.
