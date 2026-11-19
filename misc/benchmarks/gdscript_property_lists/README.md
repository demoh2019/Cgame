# GDScript property-list allocations

This benchmark exercises two public API paths:
`GDScript::get_script_property_list()` and
`GDScript::_get_property_list()` (via `get_property_list()` on the script resource).

A derived script declares exported fields and static variables over two
inheritance levels. The regression verifies that instance members retain
derived-first order and static properties retain base-first order.

Build the same Cgame configuration for baseline and patched versions, then:

```sh
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path misc/benchmarks/gdscript_property_lists \
  --script res://regression.gd
```

Each run executes 5,000 paired property-list queries after 100 warmup
iterations; compare medians of multiple runs on the same machine.

Do not treat the script's timing as a measured engine-wide FPS improvement.
It isolates repeated property-list creation, an editor/inspector workload.
