# Native occupancy exclusions for EnvironmentQuery3D

## Engine feature

Cgame now supports two optional properties on `EnvironmentQuery3D`:

- `exclusion_positions: PackedVector3Array` — 0–128 finite world-space
  centers supplied by game logic, never collected from a physics query.
- `min_exclusion_distance: float` — nonnegative finite clearance radius;
  zero disables the filter.

Every candidate closer than the clearance radius to **any** exclusion center
is removed *before* weighted scoring. The strict comparison allows candidates
at exactly the radius. `horizontal_only` also applies to exclusions.
The same filter is shared by the full query, top-K query and spread query.
Invalid updates preserve the previous values and the 128-center cap prevents
unbounded O(N * occupied) work in the engine.

This follows the filter-before-score design described in Unreal's EQS:
https://dev.epicgames.com/documentation/en-us/unreal-engine/environment-query-system-overview-in-unreal-engine

No physics, navigation, line-of-sight or automatic occupancy discovery is
added. Candidate walkability and zone authorization remain the game's job.

## Albion After integration

The authoritative `RaidReinforcements.sites()` now gathers living infected
world positions and sends them to `spread_sites()`. Cgame processes up to
128 exclusions in native code alongside the existing multi-threat score and
minimum 5m separation. If the engine lacks the new property, has no native EQS,
or there are more than 128 occupants, the GDScript fallback checks **every**
occupant without truncating the list.

Server-owned walkability, water, zone and player-distance validation remains
unchanged, as does the two-add wave limit. No client-provided positions enter
the context.

## Validation

- `tests/scene/test_environment_query_3d.cpp`: full, top-K and spread
  consistent exclusion; exact boundary; XZ vs 3D; invalid arrays/radii;
  disabled radius.
- `game/tests/test_raid_reinforcements.gd`: parity with stock Godot,
  unsafe best-site filtering, oversized context fallback, existing raids.

Run a full native build and the focused test suites before merging:

```bash
scons platform=linuxbsd target=editor dev_build=yes tests=yes module_environment_query_enabled=yes
bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case="*[EnvironmentQuery3D]*"
bin/godot.linuxbsd.editor.dev.x86_64 --headless --path game --script res://tests/run_raid_eqs.gd
```
