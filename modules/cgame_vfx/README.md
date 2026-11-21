# cgame_vfx

Native port of the Cgame GDScript VFX graph (`game/scripts/client/vfx_graph.gd`, `vfx_graph_node.gd`,
`vfx_presets.gd`, `vfx_budget.gd`, `vfx_bindings.gd`, `gpu_particle_backend.gd`).

| Class | Role |
| --- | --- |
| `VFXGraphAsset` (Resource) | Emitter dictionary (same format as `vfx_graph.gd`) plus `validate()` |
| `VFXGraphInstance3D` (Node3D) | Native SoA CPU simulation, MultiMesh billboard rendering via RenderingServer, optional GPU compute update, one-shot auto free |
| `VFXBudgetServer` (Object, engine singleton) | Per category/global effect and particle caps by quality tier, priority/distance admission, eviction |
| `VFXPresets` | `lightning_sparks(level)` graph and `spawn()` helper |
| `VFXBindings`, `VFXSequence` | Event type to effect mapping, parameter mapping, timed sequences, `GameplayCueQueue` event intake |

Internals (not exposed to scripting): `vfx_simulation.*` (`VFXSim::System`/`Emitter`, the CPU core, usable
without a scene) and `vfx_gpu_kernel.*` (`VFXGpuKernel`, GLSL generation and compute dispatch).

## Format

```
{"emitters": {name: {"max_particles": int, "duration": float, "attributes": {n: default},
                      "spawn": [...], "update": [...], "events": {"death": spec, "collision": spec},
                      "blend": "alpha"|"add", "texture": Texture2D, "bounds": float}}}
```

Spawn modules: `spawn_rate`, `spawn_burst`, `initial_position_sphere/box/cone`, `initial_velocity`,
`lifetime_random`, `initial_color`, `initial_size`, `initial_attribute`. Update modules: `gravity`, `drag`,
`curl_noise`, `vortex`, `attractor`, `color_over_life`, `size_over_life`, `collide_plane`, `kill_below_plane`
(the two plane modules run after integration). Event spec: `{"emitter", "count", "inherit_velocity"}` or an array.
See `doc_classes/VFXGraphAsset.xml` for every parameter.

## Behavior notes

* Deterministic per `random_seed` (per-emitter PCG streams seeded exactly like the GDScript runtime:
  `seed * 1000003 + index * 7919 + 17`). Random values are not bit identical to GDScript (different RNG).
* `curl_noise` on the CPU uses a built-in value noise instead of `FastNoiseLite` (so the module does not
  depend on `noise`). With `use_gpu` it uses the analytic "lite" curl shared by CPU fallback and GPU kernel.
* Gradients in `color_over_life` are baked to 32 color stops when the graph starts.
* GPU path: update, integration and plane stages run in a generated compute shader (same template and
  placeholders as `shaders/compute/particles_update.glsl.template`, embedded in `vfx_gpu_kernel.cpp`) on one
  shared local `RenderingDevice`. Spawn and death routing stay on the CPU; collision events return through an
  atomic-append buffer. Without a device (headless, dummy, Compatibility) or on compile failure the CPU kernel
  runs. Particle data is uploaded and read back each step, so it pays off for large emitters only.
  The GPU path is **not verified on hardware**.
* `gameplay_fx`: `VFXBindings.handle_cue_events()` consumes `GameplayCueQueue.take_events()` output, so cue tags
  can map to effects without a compile-time dependency between the modules.

## Tests

`tests/test_cgame_vfx.h` (doctest) mirrors `test_vfx_graph.gd`, `test_vfx_presets.gd` and the budget, bindings
and GPU-source cases: burst/rate counts, lifetime, gravity/drag integration, over-life curves, collision and
death event routing, caps and budget, determinism, profiling, validation, eviction, node behavior and GLSL
generation. Run with `./bin/godot... --test --test-case="*VFX*"`.

GDScript facade with native-first/fallback behavior: `game_facade/cgame_vfx_facade.gd`.
