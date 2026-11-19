# Cold class registration & engine startup (upstream #124495)

Based on [Godot PR #124495](https://github.com/godotengine/godot/pull/124495).
This backport isolates the expensive one-time `GDCLASS` registration path in
`_initialize_class_cold()` and marks it cold on GCC/Clang. The frequent check
for an already-initialized class stays small and inline; comparisons of
method-binding function pointers become compile-time, allowing the compiler
to remove dead calls. One-time engine `Main` setup and teardown methods are
also marked cold so compilation can favor smaller, colder machine code.

**Important Cgame adaptation:** the existing initializer used an atomic
`SafeFlag`. This variant keeps it, rather than replacing it with an ordinary
`bool`, to preserve safe publication to other threads and the prior mutex-
protected exactly-once class binding behavior. The flag has a `constexpr`
constructor, so the inline static member can be constant-initialized.

No frame-loop method is marked cold. No class registration or binding is
removed. The non-GNU compiler fallback leaves `_COLD_` empty.

## Validation

- 18 static source contracts for cold/hot separation, atomic publication,
  locking, compile-time binds, and native test presence.
- C++ native regressions for repeat initialization and inherited bindings.
- CI builds a Linux editor with tests and runs engine tests; startup/crash
  testing on macOS, Windows, and extension-heavy projects remains advisable.

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_class_cold_init_source.py -v
```

**Performance caveat:** `cold` is a compiler layout/size hint. Actual binary
size, wall-clock startup, runtime memory usage and FPS must be measured on
release builds; no universal speedup is claimed from the attribute alone.
