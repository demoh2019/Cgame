# pcg_presets.gd

> Example procedural content graphs built on pcg_graph.gd.

`res://scripts/shared/pcg_presets.gd`

## Overview

Example procedural content graphs built on pcg_graph.gd.
Original content; node vocabulary follows the UE5 PCG concepts described in pcg_graph.gd.

forest_scatter()  inputs: volume, landscape, road (spline)      outputs: trees, rocks, floor
ruins_debris()    inputs: pois (points)                          outputs: debris, ground
cave_rocks()      inputs: entrances (points)                     outputs: rocks

## Constants

- `const PCGGraph = preload("res://scripts/shared/pcg_graph.gd")`

## Functions

### `forest_scatter`

```gdscript
static func forest_scatter(graph_seed: int = 1337) -> PCGGraph
```

Dense forest with a cleared corridor around the road; steep ground gets rocks instead of trees.

### `ruins_debris`

```gdscript
static func ruins_debris(graph_seed: int = 4242) -> PCGGraph
```

Rubble clusters stamped onto each point of interest.

### `cave_rocks`

```gdscript
static func cave_rocks(graph_seed: int = 9001) -> PCGGraph
```

Boulders ringing each cave mouth, with the opening itself kept clear.

_1 private function(s) starting with `_` are not listed._
