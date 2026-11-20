# Multi-threat environment queries in Cgame and Albion After

## Why

Unreal Engine's Environment Query System supports **multi-location
contexts** for scoring generated positions. The original Cgame
`EnvironmentQuery3D` resource already had origin-distance,
single-threat distance, minimum clearance, stable ranking, and
allocation-bounded top-K queries. It could not consider multiple
survivors as one set of hostile contexts without repeating the query
and manually reconciling scores in GDScript.

## Engine API

Cgame now accepts up to 32 world-space threat positions:

```gdscript
var q := EnvironmentQuery3D.new()
q.origin = boss_position
q.candidates = EnvironmentQuery3D.sample_ring(boss_position, 12.0, 16)
q.use_threat = true
q.horizontal_only = true
q.max_distance = 64.0
q.distance_weight = 0.0
q.safety_weight = 1.0
q.min_threat_distance = 7.0
q.threat_positions = PackedVector3Array([
    tank_position, archer_position, healer_position])
var sites: PackedVector3Array = q.query_top_positions(3)
```

- `threat_positions`: optional PackedVector3Array of **up to 32**
  finite world-space positions; invalid updates are rejected without
  modifying previously configured contexts.
- When `use_threat` is enabled and the array is nonempty, the query
  uses the **closest threat** to each candidate for
  `min_threat_distance` filtering, result metadata
  (`threat_distance`) and the safety score.
- When the array is empty, the old `threat_position` code path remains
  unchanged. When `use_threat` is disabled, both contexts are ignored.
- Supports `horizontal_only` for ground AI. A player standing on
  a tower does not lose the horizontal area around their feet.
- `query()`, `query_positions()` and `query_top_positions(count)`
  use the **same** distance function, deterministic candidate-index
  tie ordering and filters. No separate broadphase or physics server
  is introduced.
- Complexity is at most O(N*32) scoring work over N candidates;
  candidate data is still bounded by the existing query system.
  This is a scoring/filtering stage only, not navigation, visibility,
  line-of-sight or collision detection.

## Used immediately in Albion After

The authoritative `RaidReinforcements.sites()` previously scanned
three 16-point rings and returned the first two available sites. It
already checked combat-zone boundaries, water, walkability, a minimum
distance from **every** living player, existing infected, and mutual
spacing between the new minions.

Now it performs these exact same checks **before ranking** candidate
sites. The surviving sites are scored against up to 32 nearby living
survivors, selected deterministically as the closest to the raid boss
(with stable positional ties). The closest survivor controls safety:
a position near a healer cannot incorrectly appear safe simply because
it is far away from the tank. More safely separated, higher-scoring
positions receive priority, while the original `MAX_WAVE=2`,
`MIN_PLAYER_DISTANCE=7.0`, `MIN_INFECTED_DISTANCE=3.5`,
`MIN_BETWEEN_ADDS=5.0` and phase/life guards remain intact.

**Server authority:** only already-validated server-side world terrain,
players, zombies and encounter coordinates enter this selection.
No client supplied query, network protocol change, replicated internal
threat table, player telemetry or cosmetic physics dependency is added.

### Portable fallback

`RaidReinforcements.rank_sites(candidates, threats, center)` calls
the new C++ `EnvironmentQuery3D` only when supported. On ordinary
Godot and older Cgame builds, a pure GDScript fallback uses the same
nearest-distance score `min(nearest_distance / 64.0, 1.0)` and stable
source-index tiebreaker. Candidate radius is bounded to 64 metres.

This ensures servers and clients (or CI runners) running different
engine versions can still verify raid placement. No randomness or
dictionary iteration order participates in the scoring; inactive or
remote players are excluded from the native context, although the
existing independent safety guards still examine every living player.

## Validation

- `tests/scene/test_environment_query_3d.cpp`: native multi-context
  nearest-threat ranking, safety clearance inclusive boundaries,
  single-threat fallback, invalid input rejection, 32-context cap,
  top-K equivalence, context order independence and .tres roundtrip.
- `game/tests/test_raid_multi_threat_query.gd`: native-vs-script
  parity, stable threat and player ordering, finite coordinate guards,
  and actual raid-wave spawn safety with multiple living survivors.
- `game/tests/test_raid_reinforcements.gd`: existing server-only boss
  phases, membership, population, safety and victory behavior.
- `game/tests/run_raid_eqs.gd`: focused headless test. Registered in
  `run_all.gd` too.
- Dedicated native GitHub Actions workflow compiles the engine and
  runs the focused native + game tests.

```sh
godot --headless --test --test-case="*Multi-threat*"
godot --headless --path game --script res://tests/run_raid_eqs.gd
```

Unreal reference:
https://dev.epicgames.com/documentation/en-us/unreal-engine/eqs-node-reference-contexts-in-unreal-engine
