# hydraulic_erosion.gd

> Droplet-based hydraulic erosion (Hans Beyer's particle model, as popularised by Sebastian Lague) plus a simple thermal/talus pass.

`res://scripts/shared/hydraulic_erosion.gd`

## Overview

Droplet-based hydraulic erosion (Hans Beyer's particle model, as popularised by
Sebastian Lague) plus a simple thermal/talus pass. Inspired by the erosion
nodes of World Machine and Gaea. Pure data in, new data out; deterministic per seed.
Heights are indexed y * width + x. Sediment is conserved: whatever a droplet
picks up is deposited again (at the latest where it dies).

## Constants

- `const DEFAULTS: Dictionary = {`

## Functions

### `erode`

```gdscript
static func erode(heights: PackedFloat32Array, width: int, height: int, droplets: int, seed: int, params: Dictionary = {}) -> PackedFloat32Array
```

Returns an eroded copy of `heights`; the input is not modified.

### `thermal`

```gdscript
static func thermal(heights: PackedFloat32Array, width: int, height: int, iterations: int, talus: float = 0.6) -> PackedFloat32Array
```

Thermal erosion: material slides to lower neighbours where the drop exceeds `talus`
(height units per cell). Mass conserving. Returns a new array.

### `max_slope`

```gdscript
static func max_slope(heights: PackedFloat32Array, width: int, height: int) -> float
```

Largest height difference between 4-neighbours, handy for thermal checks.

_3 private function(s) starting with `_` are not listed._
