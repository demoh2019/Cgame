# Interpreting whole-engine stress bottlenecks

The suite samples resource usage and frame intervals and ranks cases by
**failure**, **baseline regression**, **frame pacing**, **RSS pressure** and
**CPU intensity**. Each scenario is isolated in a fresh engine process.

Run the Python harness tests and a native engine stress run first:

~~~bash
python3 -m unittest discover -s tests/stress -p 'test_*.py' -v
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 --preset standard --repeats 10 --output out/current.json
python3 tests/stress/analyze.py out/current.json --markdown out/bottlenecks.md --csv out/bottlenecks.csv
~~~

For a **matched** baseline, compare on identical hardware, CPU and GPU drivers,
power settings, build flags, workload preset, scale, seed and render mode:

~~~bash
python3 tests/stress/analyze.py out/current.json --baseline out/baseline.json --max-regression-pct 10 --max-frame-p95-ms 33.3 --max-rss-mib 4096 --markdown out/diff.md --csv out/diff.csv
~~~

The optional --fail-on-findings makes the analyzer exit nonzero for failure,
large regression, excessive p95 frame interval or RSS threshold. CI archives
reports without enforcing hardware-dependent thresholds by default.

Frame intervals measure time between consecutive frame signals (not GPU time).
The report shows the **largest per-run p95**, not a pooled p95 across runs.
CPU core equivalents = process CPU seconds / process wall seconds and may exceed
1.0 under parallel workloads. They are not CPU utilization percent.

The native engine duration measures scenario execution, not process startup.
Different scenarios are not normalized by operation count, so comparing their
absolute wall times does not prove one engine subsystem is less efficient.
For trustworthy p95/p99 of per-run durations use 10+ repetitions. Compare
identical workloads; do not compare dummy headless renderer values with GPU data.

High RSS or retained allocator memory may reflect caching rather than leaks.
Confirm hotspots with CPU/heap/GPU profilers, ASan/UBSan/TSan, real projects,
real-device render profiling and network load simulations. The "brutal" preset
is strictly manual; avoid running it on production/shared systems.
