# seeded_substreams.gd

> Portable Cgame RNG substreams: one seed and numeric stream id produce an independent PCG stream without drawing from or changing the parent RNG.

`res://scripts/client/seeded_substreams.gd`

## Overview

Portable Cgame RNG substreams: one seed and numeric stream id produce an
independent PCG stream without drawing from or changing the parent RNG.
Cgame implements get_substream_seed()/fork() natively; official Godot
follows exactly the same 32-bit unsigned mixing using 64-bit GDScript ints.

## Constants

- `const WORD_MASK := 0xffffffff`
- `const FNV_PRIME := 16777619`
- `const AVALANCHE := 0x045d9f3b`

## Functions

### `seed_for`

```gdscript
static func seed_for(seed: int, stream_id: int) -> int
```

Returns the exact seed computed by Cgame RNG.get_substream_seed().
Treat this mixer as a versioned serialization algorithm: changing it
would change all resulting birds, decoration and future procedural jobs.

### `fork`

```gdscript
static func fork(parent: RandomNumberGenerator, stream_id: int) -> RandomNumberGenerator
```

_1 private function(s) starting with `_` are not listed._
