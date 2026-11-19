# RefCounted initial ownership performance benchmark

For a reproducible comparison, build the baseline and patched Cgame with
the same compiler and optimization settings. Run **each executable** against
the identical script, alternate binary execution order, and report the
median of at least seven runs:

```sh
./bin/godot.linuxbsd.editor.x86_64 --headless --script misc/benchmarks/refcounted_creation/refcounted_creation_bench.gd
```

The GDScript benchmark constructs and releases 120,000 `RefCounted`
objects after a warm-up. It includes GDScript and ClassDB overhead, and
should not be misrepresented as an isolated C++ `memnew()` measurement.
The optimizer targets the initial `Ref<T>` ownership handshake: reducing
unnecessary atomic reference-count updates without retaining extra objects.

Native behavior tests include legacy ClassDB raw instance construction and
multiple-thread copies. They are **not a substitute for ASan/TSan** and do not
prove that every extension/resource lifecycle is compatible. Check memory
leaks and crashes in representative editor projects before release.
