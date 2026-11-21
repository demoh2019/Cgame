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
