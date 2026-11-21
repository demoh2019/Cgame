# Deterministic named random substreams in Cgame / Albion After

## Goal

Native Godot's `RandomNumberGenerator` supports reproducible `seed` and
`state`, but ordinarily requires gameplay code to devise a different
seed for each independent generator. Unity Mathematics offers
`Random.CreateFromIndex`, while Unreal supports explicitly seeded
`RandomStream` objects. Cgame adds an engine-level equivalent for
**deterministic, independent procedural streams**.

## New Cgame C++ API

```gdscript
var world := RandomNumberGenerator.new()
world.seed = 1337

var terrain := world.fork(1)
var creatures := world.fork(2)
var effects := world.fork(3)
var creature_seed: int = world.get_substream_seed(2)
```

`RandomNumberGenerator.fork(stream_id: int)` constructs a new instance
with a seed derived entirely from the parent's *original* seed and the
64-bit signed stream ID. `get_substream_seed(stream_id)` gives the exact
64-bit bit pattern used for its seed.

- **Idempotent names**: for any root seed and numeric tag, repeated
  forks start at the same PCG state.
- **Parent state untouched**: the method neither consumes `randi()`
  values nor calls `seed` or `randomize` on the parent. Calling it
  after thousands of parent draws produces the same child as before
  those draws.
- **Independent progression**: creating a child or advancing its state
  does not alter any other RNG instance.
- **Full 64-bit inputs**: both the world seed and the stream ID use all
  of their 64 bits, including negative signed identifiers.
- **Composable**: `child.fork(7)` can spawn a deterministic nested
  subsystem stream without remembering the world root.

This extends the existing PCG generator; it does not replace or alter
the output of `seed`, `randi`, `randf`, `state` or `randomize`.
Hashing reduces correlations between close seed values but **does not
mathematically guarantee disjoint PCG periods**. These are not
cryptographic random sources.

## Cross-engine compatibility

The engine uses a **version-one, unsigned 32-bit-word FNV-1a mixer and
two final avalanche rounds**, then joins two salted 32-bit outputs
into one 64-bit seed. It hashes the four 16-bit words of the parent's
seed (least significant first), then the four 16-bit words of the stream
ID in the same order. Each product is reduced modulo `2^32`.

The pure GDScript fallback at
`game/scripts/client/seeded_substreams.gd` implements exactly this
algorithm. It masks each intermediate word so its multiplications
remain below the signed 64-bit integer limit. `SeededSubstreams.fork`
prefers native `parent.fork(id)` when available, and otherwise seeds a
stock Godot `RandomNumberGenerator` from the same derived integer.
This guarantees equal child PCG sequences when running either binary
with the same engine PCG implementation. Golden vectors cover
`(seed=0,tag=0)`, `(1337,1)`, `(1337,2)` and `(-1,-1)`.

Do not change this mixer without explicitly versioning serialized
procedural seeds and updating regression vectors.

## Integrated into Albion After

Ambient bird flocks previously consumed the **global game RNG** inside
their MultiMesh constructor, making placement sensitive to creation
order and other systems drawing global random values.

Now `AmbientBirds.new(client.world.world_seed)` initializes three
separate streams:

| Stream ID | Cosmetic purpose |
| --- | --- |
| 1 | Initial bird positions |
| 2 | Initial bird velocities and headings |
| 3 | Wing animation custom-data phases |
| 4 | Native Flock3D boids simulation seed |

Adding or removing random wing effects does not reshuffle birds or
their initial flight directions. A saved world seed recreates the same
starting flock across sessions on a given engine build.

**Important native simulation detail:** Cgame's `Flock3D` already has
its *own* C++ boids PRNG and regenerates agents on ready/count changes.
This PR also adds the opt-in `Flock3D.simulation_seed` property and
sets it from stream 4. In the seeded mode, every native flock reset
restarts its PCG state from that seed, including scene-tree entry and
graphics-quality changes, while existing unseeded Flock3D scenes retain
their previous evolving RNG behavior. The same world and native build
thus produce matching initial agent positions even after repeated
rebuilds. The native boids algorithm is distinct from the script
fallback's algorithm, so *exact positions across those two different
boids implementations are not promised*.

Gameplay damage, authoritative AI, world generation, loot and network
packets are unchanged.

## Tests and verification

- `tests/core/math/test_random_substreams.cpp`: native seed/state
  invariance, reproducibility after drawing, nested streams, negative
  and high-bit IDs, distinct stream seeds and fixed hash vectors.
- `tests/scene/test_flock_3d.cpp`: native boids use the configured seed,
  reproduce agent positions after count/quality resets and react to a
  different seed.
- `game/tests/test_seeded_substreams.gd`: bit-for-bit native/GDScript
  parity, fixed seed vectors, independent streams, actual ambient
  bird placement and live-game world-seed wiring.
- Both `run_all.gd` and `run_graphics.gd` run the new game test.
- A focused `run_rng_substreams.gd` runner runs this new test alongside
  the original bird behavior regression; a dedicated native CI
  workflow builds Cgame with tests and runs both.

```sh
# Cgame compiled with tests=yes
godot --headless --test --test-case="*Named substreams*"
godot --headless --test --test-case="*Substreams distinguish*"
godot --headless --test --test-case="*Seeded flock resets*"
godot --headless --path game --script res://tests/run_rng_substreams.gd

# Standard upstream Godot also executes the GDScript fallback
godot --headless --path game --script res://tests/run_rng_substreams.gd
```

This iteration adds **engine functionality and deterministic content
control**, not a claimed frame-time speedup.

## References

- [Unity Mathematics Random.CreateFromIndex](https://docs.unity.com/en-us/engine/6000.7/script-reference/unity/mathematics/random/createfromindex)
- [Unreal Engine Random Streams](https://dev.epicgames.com/documentation/unreal-engine/random-streams-in-unreal-engine)
- [Godot RandomNumberGenerator](https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html)
