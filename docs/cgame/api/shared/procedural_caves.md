# procedural_caves.gd

> Cellular-automata caves with guaranteed connectivity.

`res://scripts/shared/procedural_caves.gd`

## Overview

Cellular-automata caves with guaranteed connectivity.

Technique: classic cave-generation cellular automaton (random fill, repeated
8-neighbour majority smoothing) as described in public tutorials and in
Johnson, Yannakakis, Togelius, "Cellular Automata for Real-Time Generation of
Infinite Cave Levels" (PCGames 2010). Region labelling is a plain flood fill;
disconnected regions are joined with L-shaped tunnels between their closest
cells (the "connect rooms" step popular in roguelike dev write-ups).
Implementation written from the published algorithm descriptions (no code
copied). Source: https://www.roguebasin.com/index.php/Cellular_Automata_Method_for_Generating_Random_Cave-Like_Levels
(algorithm description) and the paper above. License: published algorithms only, no code copied.

## Functions

### `generate`

```gdscript
static func generate(width: int, height: int, seed: int, fill: float = 0.47, steps: int = 5) -> PackedByteArray
```

### `regions`

```gdscript
static func regions(grid: PackedByteArray, w: int, h: int) -> Array
```

Flood-fill the open cells (4-connected). Returns an Array of PackedInt32Array
(cell indices), one per region, ordered by discovery.

### `chambers`

```gdscript
static func chambers(grid: PackedByteArray, w: int, h: int, min_size: int) -> Array
```

Centroids (snapped to the nearest open cell of the region, in cell
coordinates) of every region with at least min_size cells. Good spots for
loot, bosses or spawners. Ordered by region size, largest first.

_4 private function(s) starting with `_` are not listed._
