# Cgame RuntimeNodePool / Albion After burst effects

A reusable GDScript runtime-engine addon lives at game/addons/runtime_pool/node_pool.gd.
It prewarms PackedScene instances, separates active and idle objects, limits memory
and concurrent scene nodes, detects foreign/double returns, prunes destroyed objects
using WeakRefs, supports lifecycle callbacks and reports runtime statistics.

The canonical Albion After client at game/scripts/client/effects.gd now uses this
addon for hits, infected deaths, muzzle flashes, loot, gathering, footsteps, and
level-up bursts. The pooled_burst.tscn and pooled_burst.gd retain the same effect
parameters while caching one CPUParticles3D, SphereMesh, StandardMaterial3D and
Gradient per emitter. Emission is stopped on release; no timer is created for
every burst.

Default gameplay policy: prewarm 12 emitters, max_active 48, max_idle 24.
Only excess cosmetic bursts are dropped on overload. Server-side combat and
survival calculations are not affected. This addon is script-level engine
functionality, NOT a new native C++ Godot class.

API: pool.acquire(parent), pool.release(node), pool.release_deferred(node),
pool.prewarm(n), pool.clear_idle(), pool.get_stats(). Optional hooks:
on_pool_created(), on_pool_acquired(pool), on_pool_released().
Released instances are detached from SceneTree and do not process or render.
Always reset scene-specific timers, velocity and collision state in the hooks.
Do not queue_free ordinary pooled objects. Changing template while active/idle
instances exist is not supported.

Regression test: game/tests/test_runtime_node_pool.gd is listed in
game/tests/run_all.gd. Run in a Godot/Cgame environment:

    godot --headless --path game --editor --import --quit
    godot --headless --path game --script res://tests/run_all.gd

The change does not claim measured FPS improvements without profiling.

References:
Godot CPU optimization: https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html
Unity reusable objects: https://docs.unity.com/en-us/engine/6000.7/manual/analysis/performance-memory/managed-memory/optimizing-code-managed-memory/reusable-code
Unreal CPU and memory: https://dev.epicgames.com/documentation/en-us/unreal-engine/common-memory-and-cpu-performance-considerations-in-unreal-engine

## Cgame native engine implementation

`scene/main/scene_node_pool.{h,cpp}` implements `SceneNodePool` in C++, registered
in the scene type registry. It has the **same script-facing pool API** as the
GDScript addon, plus editor-exposed properties, template-change checks and
immediate cache shrinking when max_idle is reduced. It is available to any
Cgame game or plugin and contains no Albion-specific code.

The live Albion After `effects.gd` now uses native `SceneNodePool` when
`ClassDB.class_exists("SceneNodePool")` is true; it falls back to the
script implementation in official Godot so headless game tests remain runnable
without compiling custom Cgame. Its VFX budget and results do not change.

Run Cgame native regression tests with a test-enabled Cgame binary:
`cgame --test --test-case="[SceneNodePool]*"`.
The script-level `game/tests/run_all.gd` also tests native behavior on
a custom Cgame binary. **No native build/FPS results are claimed until CI.**

Native design references:
- Unity ObjectPool: https://docs.unity.com/en-us/engine/6000.7/manual/analysis/performance-memory/managed-memory/optimizing-code-managed-memory/reusable-code
- Unreal Niagara component reuse: https://dev.epicgames.com/documentation/en-us/unreal-engine/scalability-and-best-practices-for-niagara
