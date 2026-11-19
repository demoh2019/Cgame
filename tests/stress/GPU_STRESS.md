# GPU and real-display stress (Cgame)

This suite supplements `tests/stress/stress.gd` with workloads that exercise
texture creation/upload, transparent canvas overdraw, MultiMesh3D batching,
shadow-casting lights, CPU particle updates and shader variant compilation.

The Python runner reuses the standard suite's **per-process timeout, RSS
watchdog, engine log error detection and isolated repetitions**. Each case
runs in a fresh Cgame process, emits an integrity-checked `STRESS_RESULT`,
and writes machine-readable JSON plus Markdown with p95 frame/tick latency.

Build Cgame, then run with a real display:

```bash
python3 -m unittest discover -s tests/stress -p 'test_*.py' -v

python3 tests/stress/run_gpu.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --preset standard --repeats 5 --frame-p95-budget-ms 25 \
  --output out/gpu-stress.json

python3 tests/stress/run_gpu.py --godot /path/to/cgame \
  --case shader_variants --case shadow_lights --preset brutal \
  --rss-limit-mib 8192 --timeout 1800 --output out/gpu-brutal.json
```

**This is not a headless benchmark.** Do not pass `--headless`, and do not
mistake Xvfb+software Mesa rendering for discrete-GPU measurements. Test on
the target GPU and record model, driver, resolution, VSync, rendering backend,
compiler/build flags and thermal profile. Frame latency includes scheduling,
presentation, and synchronization: it is not GPU execution time. The 12
warm-up frames are excluded from latency sampling; workload setup time is
reported separately where relevant. Render workload volumes differ: compare
the same case, preset and hardware when looking for a regression.

The `brutal` preset is deliberately manual only. It can consume large
amounts of RAM, VRAM and CPU time; run on a disposable/isolated GPU host.
