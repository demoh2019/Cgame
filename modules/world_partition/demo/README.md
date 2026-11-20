# HLOD Proxy Streaming (Cgame / Godot 4)

Runnable self-contained demo project for the Cgame fork's native WorldPartition3D.
This is a **scene-level HLOD prototype**, not a Nanite implementation or an
automatic HLOD asset baker. It demonstrates the runtime handoff between nearby
detailed cells and lightweight distant proxies with no additional engine renderer.

## Architecture

- Two *existing* WorldPartition3D nodes share one camera as an observer.
- Detailed forest scenes stream at load radius 1, unload radius 2.
- Proxy forest scenes stream at load radius 4, unload radius 5.
- Each scene cell generates its ground and deterministic trees using MultiMesh.
- The full detail layer uses 160 trees per cell; the proxy layer uses 20 and a
  simpler canopy mesh. This reduces scene and geometry complexity away from the camera.
- Both layers remain independently budgeted, to limit new instances per frame.
- `WorldPartition3D.get_cell_instance(Vector2i)` is used on cell_loaded/cell_unloaded
  to hide proxies wherever detailed scenes have finished loading.
- Optional additional observer attached 180 m in front of camera prefetches
  detailed cells when PR #919 is included.

## Run

Build the Cgame fork with `world_partition` enabled and open this directory
as a Godot project:

```sh
scons platform=linuxbsd target=editor tests=yes -j"$(nproc)"
./bin/godot.linuxbsd.editor.x86_64 --editor --path modules/world_partition/demo
```

The project uses Compatibility renderer so it can be inspected on low-end GPUs;
near/far proxy handoff is implemented without renderer-specific effects.

WASD to fly, Space/Ctrl for up/down, Shift for speed, P to toggle forward prefetch,
L to toggle distant proxy scenes, R to retry failed resource loads.
HUD displays FPS, detail/proxy cell counts, the active quality preset and auto mode.

The optional adaptive quality controller monitors a 3-second time-weighted FPS
window. Under 48 FPS it reduces streaming distance/instantiation budgets, and
at 58+ FPS it increases them after a 10-second cooldown. The modes are
Performance (proxy radius 2), Balanced (4) and Cinematic (5). Switch with
keys 1/2/3 (manual), or Q (automatic toggle). This is an intentionally simple
demo controller, not a measured production GPU or frametime feedback system.

Quality controller assertions (after importing the project):

```sh
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/world_partition/demo --script res://tests/quality_controller_test.gd
```

## Limitations / validation

- Native `get_cell_instance()` is required for proxy handoff; this branch includes it.
- This is not the user's actual game project. The example lives in the engine
  source repository so it can be copied into a real Godot game once its source is available.
- Repeated procedural forest art is illustrative and does not include physics,
  navigation, terrain painting, atmospheric scattering, automated proxy generation,
  impostor atlas, or object-level persistence.
- There is no crossfade: the swap occurs when the detail cell is loaded/unloaded.
  Add fade or alpha dither on production asset authoring paths as appropriate.
- The test cases cover native lookup semantics, but the demo itself needs a real
  Godot editor/runtime test and GPU profiling before production use.
