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

## Scene significance and learned-cost reservations

This module now provides data-driven scheduling importance alongside elapsed-time
fairness. Each registered lane defaults to importance 1.0, configurable through
`set_lane_importance(lane, weight)` where `0.25 <= weight <= 4.0`.
The native engine and GDScript fallback use the same algorithm.

`record_cost(lane, microseconds)` learns an integer exponential moving average
`estimate = (3 * estimate + sample + 2) / 4` (first sample initializes it).
The scheduler reserves **due** lanes each frame using importance, accumulated
time and starvation age. When estimates exist, it first prefers work predicted
to fit the remaining microsecond budget. If nothing fits, at least one due
channel can still be reserved. A channel deferred for 48+ due frames may bypass
the forecast, and an additional age term prevents low-importance starvation.

- `get_lane_importance(lane)`: current weight or -1 if unknown.
- `get_lane_estimated_cost_us(lane)`: learned microseconds (0 unsampled).
- `get_reserved_estimated_cost_us()`: estimated time of reserved work.
- `reset()`: clears frame timers and starvation age; retains weights and cost
  estimates, so a level transition doesn't discard useful measurements.

Albion After sets weights before `begin_frame` using day/night, storm and
dungeon context. Nighttime favors bats; daylight favors dragonflies; storms
raise dust-devil significance, while all four lanes are optional underground.
The custom `Albion/AmbientPlannedCPUus` performance monitor exposes predicted
time alongside actual CPU measurements.

**Limitations:** These are soft budgets. Work already started cannot be
preempted; predicted time is not a guarantee of rendered frame time, and the
engine does not measure GPU cost. No authoritative server AI, combat, physics,
save state or network synchronization is subject to this scheduler.

## Per-lane relevance-driven update rates

The native engine also supports `set_lane_rate_scale(lane, scale)` and
`get_lane_rate_scale(lane)` for finite **0.75–2.0** frequency multipliers.
Defaults are **1.0**. Unknown lanes and invalid values are rejected without
mutating the lane, and a normal `reset()` preserves the configured rate.

**Frequency vs. importance:** an update is eligible only after its own
`1 / (quality_hz * rate_scale)` interval. Eligible lanes still use the
existing significance priority, bounded starvation aging and measured
CPU-cost forecast to compete for slots. This preserves the other engine
work in `develop`, rather than replacing the learned-cost allocator.

Albion After now maps the game's **existing** per-scene importance scores
to rate multipliers through `AmbientTickBudget.rate_scale_for_importance()`:
importance 0.25 maps to 0.75×, 1.0 to 1.0×, and 4.0 to 1.5×.
The online world only calls the new native method when available; older
custom engine binaries continue using the established importance-aware
scheduler. Stock Godot uses identical GDScript logic. Cached profile values
avoid redundant setter calls on unchanged weather/day-night conditions.

C++ unit tests cover invalid input, reset, independent importance and
frequency, non-starvation, and frame-slot limits. The headless game suite
compares the native and scripted schedulers for 241 frames, with the
same significance and rate configuration.
