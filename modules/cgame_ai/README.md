# cgame_ai — native game AI library

Native C++ port of the Cgame GDScript AI libraries (`game/scripts/shared/`), same APIs and the same deterministic behaviour, no scene/physics/navigation dependencies.

| Class | Ports | Notes |
| --- | --- | --- |
| `CgameHTNPlanner` | `htn_planner.gd` | Static `plan(domain, root, state, max_steps)`; depth-first decomposition with backtracking. |
| `CgameGOAPPlanner` | `goap_planner.gd` | Static `plan(actions, state, goal, max_nodes)`; A* over world states, insertion-order ties. |
| `CgameStateTree` | `state_tree.gd` | Tasks / conditions / evaluators are `Callable`s registered by name (whitelist); subtrees, events, priorities. |
| `CgameUtilityAI` | `utility_ai.gd`, `infected_target_utility.gd` | Response curves, IAUS `combine`, `best`, `infected_target_score`. |
| `CgameSpatialQuery` | `spatial_query_graph.gd` | Generators + filter/score tests, time slicing, debug stats. |
| `CgameSmartObjects` | `smart_objects.gd` | Slots, exclusive claims with timeouts, interaction steps, placement. |
| `CgameFormations` | `formations.gd` | Line / wedge / circle / column, Hungarian assignment (<= 64), greedy fallback, slot shifting. |

Planners, utility AI and formations are static (call them on the class or an instance). Assets and results are plain `Dictionary` / `Array` data, so they stay serialisable and identical to the GDScript versions.

## Integration with sibling modules

- `environment_query` (`EnvironmentQuery3D`): `CgameSpatialQuery` results use the same `position` / `index` / `score` keys, the same descending-score / ascending-index ordering and the same grid (<= 65536) and ring (<= 4096) limits. `get_candidates()` exports the generated positions so an `EnvironmentQuery3D` can score the identical candidate set. There is no compile-time dependency, so either module can be disabled.
- `behavior_tree` (`BehaviorTree`): `CgameStateTree.Status` (`RUNNING`, `SUCCEEDED`, `FAILED`) mirrors the tri-state task results; use a state tree for stateful hierarchies and the behavior tree for reactive trees.
- `weighted_selection` (`WeightedChoiceTable`): pair with `CgameUtilityAI.best` when a seeded random pick among scored options is needed.

## Example

```gdscript
var plan = CgameGOAPPlanner.plan(actions, {"hungry": true}, {"hungry": false})

var st = CgameStateTree.new()
st.register_task("work", Callable(), func(ctx, dt, p): return CgameStateTree.SUCCEEDED)
if st.set_asset(asset):
    st.start(ctx)
    st.tick(delta, ctx)
```

## GDScript differences

- Native planners return `PackedStringArray` instead of `Array[String]`; `CgameStateTree.errors`, `validate()` and `trace` are `PackedStringArray` too.
- `CgameStateTree` exposes `errors`, `tree_status`, `running`, `active_path` and `trace` as read-only properties and `clear_trace()`.
- `CgameFormations.get_kinds()` replaces the `KINDS` constant.
- `CgameSpatialQuery.results()` / `debug()` keep their GDScript names; `get_candidates()` is new.

## GDScript facades

`game_facade/` contains one facade per library that uses the native class when `ClassDB.class_exists()` reports it and falls back to `res://scripts/shared/*.gd` otherwise (`create()` for the stateful classes), so game code can use one API with or without this module.

## Tests

Doctests in `tests/` mirror `test_ai_planners`, `test_state_tree`, `test_utility_ai`, `test_ai_tools` (query part) and the formation cases of `test_population_lod`. Build with `tests=yes` and run `./bin/godot... --test --test-case="*Cgame*"`.
