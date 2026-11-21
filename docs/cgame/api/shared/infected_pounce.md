# infected_pounce.gd

> Infected gap-closers.

`res://scripts/shared/infected_pounce.gd`

## Overview

Infected gap-closers. A runner (or walker) crouches and LEAPS from a few metres; a brute
lowers its head and CHARGES from further out. Both telegraph first. At impact: a dodge makes
it whiff and stumble, a timed parry floors it, otherwise it bowls the survivor over.

## Constants

- `const KINDS := {`
- `const HIT_RANGE := 1.7`
- `const CHANCE_PER_SECOND := 0.35`
- `const MISS_STAGGER := 0.9`

## Functions

### `kind_for`

```gdscript
static func kind_for(type: String) -> String
```

Which gap-closer this infected type uses, or "" for none.

### `spec`

```gdscript
static func spec(kind: String) -> Dictionary
```

