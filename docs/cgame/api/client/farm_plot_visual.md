# farm_plot_visual.gd

> Visuals for a homestead crop plot: a tilled soil bed with plants that grow with the server-reported progress and turn their ripe colour when ready to harvest.

`res://scripts/client/farm_plot_visual.gd`

## Overview

Visuals for a homestead crop plot: a tilled soil bed with plants that grow with
the server-reported progress and turn their ripe colour when ready to harvest.

## Constants

- `const PLANTS := 6`
- `const RIPE_COLORS := {`
- `const GROW_COLOR := Color(0.28, 0.6, 0.2)`

## Functions

### `make`

```gdscript
static func make(crop: String) -> Node3D
```

### `update`

```gdscript
static func update(root: Node, plot: Dictionary) -> void
```

Scales plants with growth (0..1) and switches to the ripe colour at 100%.

