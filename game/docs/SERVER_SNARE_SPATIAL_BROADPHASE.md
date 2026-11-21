# Native cross-set spatial broadphase for multiplayer PvE snares

Cgame's `AIProximityGrid2D.query_cross_radius_batch(sources, targets,
radius, cell_size)` extends its existing native 2D spatial hash to **two
independent cohorts**. It returns an `Array` containing one
`PackedInt32Array` per source, with indices of targets lying within the
inclusive radius, sorted by the targets' original input order.

The method builds a grid only for target positions and checks at most
nine cells for each source (the cell size must be at least the radius).
It does **not** fire collision callbacks, mutate actor positions, authorize
damage, age timers or call scene/physics/nav APIs. Invalid or oversized
requests return an empty array and the game keeps its exhaustive fallback.

- Up to 4096 source positions and 8192 targets per call.
- Query radius in 0..256m; cell size in 1..256m and >= radius.
- All positions must be finite, within +/-1,000,000 world units.
- Up to 32,768 candidate pairs total, otherwise the request fails
  atomically so callers can preserve complete gameplay behavior.
- Coordinates on negative grid boundaries and exact radius edges are
  supported; ties preserve original target index order, including duplicates.

## Real Albion After server integration

In `GameServer._tick_zombies()`, the existing exhaustive
`for zombie in zombies: for trap in infected_snares:` behavior is
replaced *conditionally* when 32..4096 NPCs and 8..64 snares coexist.
The server makes one indexed cross-set query from the authoritative NPC
and deployed trap positions. Each NPC checks only the returned trap IDs.
If the API is absent, the spatial batch is rejected, or the population
is below the threshold, the previous full scan still runs.

All broadphase results go through the exact same
`_try_trigger_infected_snare()` and `InfectedSnare.catches()` code.
That final predicate still checks that the trap exists, has not expired,
is within the **original 1.35m radius**, and that the NPC is alive and
not a raid boss; `Zombie.apply_snare()` still determines root success.
The broadphase radius is widened by 1mm to avoid losing borderline
candidate pairs to float precision, but **does not** widen gameplay's
actual trap trigger distance.

A consumed trap is erased immediately. Later NPC candidates for the same
snapshot index are revalidated against the live server dictionary. This
preserves which zombie wins a shared one-use snare without relying on
hash bucket iteration order. No client-trusted IDs or server state are
sent over the network.

`GameServer.get_snare_query_stats()` is a server-only read-only
snapshot of the current batch state, the population, trap count and
candidate-pair count, not a performance benchmark.

Native doctests cover cross-cohort selection, original target order,
duplicate and negative positions, inclusive radius, input bounds,
rejection on over-large candidate output, and repeatability. The
existing `game/tests/test_infected_snare.gd` also compares actual
server trap consumption and effects between the optimized path and
the forced old-engine exhaustive fallback.

This is inspired by broad phase and narrow phase separation in Unreal
Chaos, **not** a port of Unreal code:
https://dev.epicgames.com/community/learning/tutorials/KWeX/unreal-engine-a-tech-artist-s-playbook-for-chaos-performance

No FPS or CPU improvement is claimed without measuring a compiled Cgame
build under realistic game loads.
