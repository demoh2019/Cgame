# gathering_noise.gd

> Noisy resource gathering: a real server-completed harvest can betray the survivor to infected.

`res://scripts/shared/gathering_noise.gd`

## Overview

Noisy resource gathering: a real server-completed harvest can betray the
survivor to infected. No client-provided noise radius or target positions.

Hard work (chopping and mining) cannot be silenced by crouching; careful
low-profile foraging trades reach for quietness.

## Constants

- `const SOUND_SECONDS := 1.1`
- `const TREE_RADIUS := 25.0`
- `const ROCK_RADIUS := 24.0`
- `const ORE_RADIUS := 28.0`
- `const BUSH_RADIUS := 8.0`
- `const BERRY_RADIUS := 6.0`
- `const CROUCHED_FORAGING_FACTOR := 0.55`

## Functions

### `radius`

```gdscript
static func radius(kind: String, crouching: bool, collected: int) -> float
```

