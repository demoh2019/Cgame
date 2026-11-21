# Gameplay Tag branch synchronization (Cgame)

The native `GameplayTagContainer` now supports:

- `get_matching_tags(query, exact = false)`: returns stored explicit tags matching a hierarchical parent query, in insertion order.
- `replace_tag_branch(query, replacements)`: validates *every* replacement, atomically replaces the entire queried branch, and emits `changed` only when content/order changes. Invalid input returns `false` and leaves the original tags untouched. Empty replacements clear the branch.

For example, `replace_tag_branch("Runtime", PackedStringArray(["Runtime.Life.Alive", "Runtime.Status.Staggered"]))` preserves the independent `Enemy.Infected.Walker` or `Player` identity tag. The matcher respects dot boundaries: `Runtime` must **not** match `RuntimeExtra`.

## In-game integration

`game/scripts/client/entity_view.gd` synchronizes `Runtime.*` actor state **once per server timestamp** (not each render frame) using `EngineFeatures.sync_runtime_tags()`. The snapshots are server-authoritative, and these client tags are **visual/debug state only**: tags never authorize damage, movement, or inventory writes. Live stagger tint is sourced from `Runtime.Status.Staggered` when the new native API exists, and falls back to the unchanged snapshot boolean in regular Godot.

Player states include `Runtime.Life.*`, `Runtime.Movement.*`, `Runtime.Status.Outlaw`, and `Runtime.Item.FlareLit`. Infected states include `Runtime.Life.*`, `Runtime.Combat.Alert`, `Runtime.Rank.*`, and `Runtime.Status.*`.

The native module is **optional**: `EngineFeatures` probes for the available classes/methods. Rebuilding the fork exposes the new APIs. Running the game on stock Godot keeps its existing visuals.

## Tests

- C++: `modules/gameplay_tags/tests/test_gameplay_tags.h` tests hierarchy, atomic rejection, independent branches, idempotency and branch clearing.
- GDScript: `game/tests/test_engine_runtime_tags.gd` checks snapshot mapping and native/stock fallback (added to `game/tests/run_all.gd`).

Full engine compilation / headless game tests are required to validate runtime and performance; static validation alone does not prove those passed.
