# Array.filter lazy allocation benchmark

Run the same benchmark on **baseline** `develop` before PR and **patched**
Cgame builds using identical optimization settings. The measured time includes
GDScript callback overhead, so compare only paired runs, not absolute numbers.

```sh
./bin/godot.linuxbsd.editor.x86_64 --headless --script misc/benchmarks/array_filter/filter_bench.gd
```

The script filters 50,000 integers using three callbacks (reject-all,
even-only, accept-last, accept-all), with five warm-up runs and 80 timed runs each.
Alternate base/patched binaries and report median timings across several
process launches. This optimization is expected to improve the reject-all
case's allocations and allocation pressure, not necessarily every filter case.
There is no built-in per-operation allocation counter in this script.

The behavior tests are `tests/core/variant/test_array_filter_lazy.cpp`.
A callback that mutates the source is explicitly tested to guard against
reentrant behavior changes.
