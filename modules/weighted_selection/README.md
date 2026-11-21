# WeightedChoiceTable — deterministic weighted selection

Reusable Cgame native `Resource` for loot categories, spawn variation, AI choice and procedural content. Similar in purpose to Unreal's weighted selection utilities and Godot's `RandomNumberGenerator.rand_weighted`, but `WeightedChoiceTable` stores a validated, precomputed float64 cumulative distribution and accepts externally supplied uniform samples for reproducible replay.

```gdscript
var choice = WeightedChoiceTable.new()
assert(choice.configure(PackedFloat64Array([24.0, 20.0, 16.0, 16.0, 10.0, 9.0, 5.0])))
var rng = RandomNumberGenerator.new()
rng.seed = 12345
var category = choice.sample_unit(rng.randf()) # exactly one RNG draw
```

- Build once and sample in O(log n). No per-sample allocation; batch query via `sample_many` (max 65536).
- Atomic configuration rejects invalid/negative/non-finite inputs; max 4096 entries and total weight <=1e12.
- Zero weights never select an outcome, even when the random sample is 0.
- Game integration: `game/scripts/shared/combat.gd` uses the same seven crate-loot probabilities and exactly the same `rng.randf()` event call sequence. Stock Godot and older Cgame engines retain the original ordered threshold selection.
- No network protocol, inventory schema, server trust boundary, or loot quantity changes.
- Native doctests under `tests/`, plus regression checks in `game/tests/test_survival_combat.gd`.

**Caution:** This is a probability sampler, not a secure RNG. Gameplay randomness should come from the game server's own `RandomNumberGenerator`, not client-provided draws.
