# decor_streaming_policy.gd

> Small pure scheduling policy for streamed cosmetic MultiMesh categories.

`res://scripts/client/decor_streaming_policy.gd`

## Overview

Small pure scheduling policy for streamed cosmetic MultiMesh categories.
Gameplay resources, terrain collision and authoritative objects never wait.

## Constants

- `const CAMERA_BONUS := 0.30`

## Functions

### `rank`

```gdscript
static func rank(distance: float, facing: float) -> float
```

### `can_continue`

```gdscript
static func can_continue(elapsed_usec: int, budget_usec: int, completed: int) -> bool
```

One indivisible batch always progresses, even when it exceeds a budget.
A budget is shared by every ChunkView in the process frame.

