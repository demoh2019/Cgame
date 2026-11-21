# far_field.gd

> Distant landscape: what lies beyond the streamed chunks (about 150 m) out to ~850 m.

`res://scripts/client/far_field.gd`

## Overview

```text
Distant landscape: what lies beyond the streamed chunks (about 150 m) out to ~850 m.
 * A coarse far-terrain ring sampled from the same WorldGen.ground_at, coloured by biome, sitting
   just under the real chunk terrain so near ground always wins.
 * Forest HLOD: distant woods as one MultiMesh of IMPOSTORS — camera-facing cards whose
   pictures are baked at start-up from the game's own tree models in an off-screen viewport.
The ring is rebuilt incrementally (a few rows per frame) when the player has moved far enough,
then swapped in at once, so it never hitches.
```

## Constants

- `const Assets = preload("res://scripts/client/assets.gd")`
- `const GRID := 72 # Vertices per side.`
- `const SPACING := 24.0 # Metres between vertices: 72 x 24 = 1.7 km across.`
- `const REBUILD_DISTANCE := 96.0`
- `const ROWS_PER_FRAME := 4`
- `const NEAR_HIDE := 140.0 # Inside this the real chunks are always loaded: sink the far mesh away.`
- `const SINK := 0.8`
- `const TREE_NEAR := 150.0 # Real trees are drawn inside this radius.`
- `const IMPOSTOR_SIZE := 256`
- `const IMPOSTOR_TREES := ["CommonTree_1", "CommonTree_3", "Pine_2", "Pine_4", "TwistedTree_1", "CommonTree_5"]`
- `const BIOME_COLOURS := {`

## Functions

### `setup`

```gdscript
func setup(p_world) -> void
```

### `update`

```gdscript
func update(focus: Vector3) -> void
```

Call every frame with the player's position.

_8 private function(s) starting with `_` are not listed._
