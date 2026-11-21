# Cgame Runtime Object Population Profiler

## Inspiration: Unreal Memory Insights and MemReport

Unreal Engine has editor and runtime diagnostics that help inspect how object
populations change over time. Cgame previously shipped a complete ObjectDB
snapshot for its remote **editor** debugger, which serializes object properties
and can be expensive for a running world.

The new **`ObjectDBRuntimeProfiler`** is a focused, on-demand, **debug-only**
`RefCounted` API:

```gdscript
if ClassDB.class_exists("ObjectDBRuntimeProfiler"):
    var inspector: Object = ClassDB.instantiate("ObjectDBRuntimeProfiler")
    var snapshot: Dictionary = inspector.call("sample_classes",
        PackedStringArray(["Node3D", "MultiMeshInstance3D", "AnimationPlayer"]))
    print(snapshot["total"])   # Total live native engine ObjectDB objects.
    print(snapshot["classes"]) # Exact named class counts (zero if absent).
```

- A single `ObjectDB::debug_objects()` pass counts **all live registered
  objects** and at most 32 named classes. The callback performs only hash
  lookups and count increments; it never serializes properties, acquires
  object references, scans the scene tree, or makes a second ObjectDB query.
- Validation happens **before** entering the ObjectDB traversal; reject empty,
  duplicate, whitespace-padded or overlong class names and groups longer
  than 32. Invalid requests return an empty dictionary.
- The result contains a synchronized `total` object count and dictionary
  `classes` of exact C++ class names. Subclasses are **not** counted as their
  base class. A growing count is a clue for investigation, **not proof** of a
  memory leak or a measurement of bytes/VRAM.
- The module is enabled only with Godot `debug_features`. There is **no**
  per-frame update, renderer query, new runtime singleton or costly automatic
  sampling. Stock Godot and release builds do not require the API.

## Actual Albion After integration

In an Albion After **debug** game client, press **Ctrl+Shift+F10** to collect
the first baseline. Repeat after walking across a streamed world, a teleport,
or a battle. The HUD and log report the total ObjectDB population and changes
in `MultiMeshInstance3D` and `MeshInstance3D`; the retained data also
tracks `AnimationPlayer`, `GPUParticles3D`, `AudioStreamPlayer3D`,
`ShaderMaterial` and other visual classes.

The scene is measured only when the hotkey is pressed. This shortcut is
handled before the normal F10 fish-trap action, without modifying network
authority, streaming decisions, physics or any game object.

### Verification

- Native doctests: `modules/objectdb_profiler/tests/test_runtime_object_profiler.h`
  checks count changes for a real `Node3D`, release, empty/duplicate/oversized
  filters, zero counts and the strict 32-class cap.
- Game: `game/tests/test_object_population_profiler.gd` checks the actual
  debug shortcut, first baseline, class count deltas when creating and freeing
  two live visuals, and stock-Godot fallback.
- Source contract:
  `python3 -m unittest tests/scene/test_runtime_object_profiler_contract.py -v`.
- CI: `.github/workflows/native-objectdb-runtime-profiler.yml`, which builds
  the Cgame debug editor, runs native tests and the Albion headless suite.

Reference:
https://dev.epicgames.com/documentation/unreal-engine/memory-insights-in-unreal-engine

This adds **diagnostic functionality**, not a guaranteed reduction in CPU or
memory consumption. A useful follow-up is capturing two snapshots around a
specific world streaming scenario and inspecting classes that fail to return
to their baseline.
