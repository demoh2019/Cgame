# Native FrameUpdateBudget (Godot C++ module)

An optional engine-level scheduler for low-priority world presentation tasks.
Similar to a small piece of Unreal's significance / animation budgeting:
the caller retains the actual update logic, and this module answers **when**
to update and with how much accumulated time. All calls are main-thread only.

- Register up to 64 named lanes using `register_lane`.
- Call `begin_frame(delta, quality)` once per frame (quality 0..3).
- Call `consume(lane, delta, force=false)` for each lane.
  Return 0 means skip; positive return means run the update with that delta.
- Each lane's accumulated time is capped at 0.16 seconds.
- Defaults: quality frequencies 12/18/30/60 Hz and slots 1/2/3/4.
- `configure(PackedFloat64Array, PackedInt32Array)` atomically changes profiles.
- Forced updates and tier changes bypass the budget (e.g. indoor transitions).
- A slow-frame EWMA-like pressure counter cuts update slots adaptively.
- Register custom Godot performance monitors from the game, not inside this class.

## Integration

`game/scripts/client/online_main.gd` selects this class when its ClassDB
registration is present, and otherwise keeps the old GDScript scheduler.
No gameplay, authoritative physics, combat, saves or network protocol changes.
The new class **does not** execute callbacks, access scene nodes or create
background threads.

## Validation

C++ unit tests: `modules/frame_update_budget/tests/test_frame_update_budget.h`.
Game tests: `game/tests/test_ambient_tick_budget.gd`.
Static contracts: `python3 -m unittest tests/scene/test_frame_update_budget_contract.py -v`.

A passing source contract does not mean the native module has compiled.
Build the custom Godot editor and run native tests before calling it
production-verified.

## Fairness and starvation protection

The scheduler reserves due slots at `begin_frame()`, using the largest
accumulated time first and rotating tie priority each frame. This prevents
the fixed order of `consume()` calls in Albion After from permanently
giving the low-tier one-slot budget to dust devils while starving bats,
dragonflies and tumbleweeds. The caller still controls when work runs;
`FrameUpdateBudget` never executes callbacks or changes simulation logic.

- Only lanes whose projected time exceeds the profile interval are eligible.
- One regular reservation per lane per frame; `force` and quality transitions
  still bypass the cap for immediate world/visibility changes.
- Deterministic bounded scan over at most 64 lanes and 64 slots.
- The stock-Godot fallback `ambient_tick_budget.gd` implements the same
  selection order, and regression tests compare every returned update delta.

## Measured CPU time budget (soft cap)

The native class and Albion After's stock-Godot fallback now support
`set_frame_time_budget_us(limit)` and `record_cost(lane, elapsed_us)`.
Call `record_cost` **after** a granted update using `Time.get_ticks_usec()`.
A regular `consume` call is deferred after the frame's reported cost reaches
the limit; forced visibility/quality updates still run. Zero disables the cap.

Albion After uses quality-tier CPU limits of 900 / 1500 / 2500 / 4000 µs
(Performance / Balanced / High / Ultra) for only four optional atmospheric
systems: dust devils, dragonflies, tumbleweeds and dusk bats. This is
*reported main-thread execution time*, not GPU timing or a hard real-time
guarantee. No authoritative simulation, networking or combat is throttled.

`current_frame_cost_us()` reports cost accumulated in this frame;
`last_frame_cost_us()` reports the previous complete sample. The editor's
custom monitors `Albion/AmbientCPUus` and `Albion/AmbientCPUBudgetus`
make them visible in Godot's profiler.

Older custom engine builds without this API automatically use the updated
GDScript fallback; native CI tests cover rejection of malformed cost reports,
overload deferral and force-update bypass.
