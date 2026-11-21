# world_roads.gd

> Dirt roads that join the hub and the places of the island, worked out from the seed like everything else.

`res://scripts/shared/world_roads.gd`

## Overview

Dirt roads that join the hub and the places of the island, worked out from the seed like everything else. Every place
that people built is linked to its two nearest neighbours (and the hub to its four), and each link winds a little so
it does not look ruled. Road segments are also indexed for deterministic travel grip.

The client asks per chunk: the road pieces crossing it (to paint the ground) and the signposts standing in it.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const HALF_WIDTH := 2.1`
- `const STEP := 14.0 # Spacing of the points along a road.`
- `const MAX_LINK := 720.0 # Longest road between two places.`
- `const NEIGHBOURS := 2`
- `const HUB_LINKS := 4`
- `const HUB_START := 19.0 # Roads leave the hub at the edge of its plaza.`
- `const SIGN_OFFSET := 26.0 # Signposts stand this far out along each road from where it leaves a place.`
- `const LINKED_KINDS := ["village", "farm", "camp", "depot", "outpost", "tower", "mine", "city", "bunker", "lighthouse", "dock"]`
- `const REGION_REACH := 13 # Sites of regions -13..12 on both axes: the whole island.`
- `const BRIDGE_MAX_SPAN := 70.0`
- `const BRIDGE_HALF_WIDTH := 2.4`

## Functions

### `pieces_in_cell`

```gdscript
func pieces_in_cell(cell: Vector2i) -> Array
```

The road pieces (segments) that pass close enough to a chunk to colour it.

### `signs_in_cell`

```gdscript
func signs_in_cell(cell: Vector2i) -> Array
```

Signposts in a chunk: {"x", "z", "yaw", "lines": [[name, metres], ...]}.

### `all_roads`

```gdscript
func all_roads() -> Array
```

### `compute_links`

```gdscript
static func compute_links(places: Array, max_link: float = MAX_LINK, regular_neighbors: int = NEIGHBOURS, hub_neighbors: int = HUB_LINKS, force_scalar: bool = false) -> Dictionary
```

Undirected nearest-neighbor graph. All locations have stable array indices.
On Cgame a single native query handles all pairs; on stock Godot we preserve
the original distance scan with a deterministic index tie-break.

### `rasterize_mask`

```gdscript
static func rasterize_mask(pieces: Array, origin: Vector2, size: int, half: float = HALF_WIDTH, soft: float = 1.2, force_scalar: bool = false) -> PackedByteArray
```

Paint a grayscale road coverage mask for one chunk. Engine-native rasterization
avoids GDScript calls per touched texel. The scalar path preserves stock Godot.
Endpoint coordinates are world x/z; pixel centers are at local (+0.5, +0.5).

### `coverage_on_segments`

```gdscript
static func coverage_on_segments(point: Vector2, segments: Array) -> float
```

Nearest point on each terrain-painted segment. All road checks use the
existing spatial cell index, never the full network on every frame.

### `coverage_at`

```gdscript
func coverage_at(x: float, z: float) -> float
```

### `bridge_deck`

```gdscript
func bridge_deck(x: float, z: float) -> float
```

Height of a bridge deck at this point, or -INF off every bridge.

### `deck_height`

```gdscript
static func deck_height(bridge: Dictionary, t: float) -> float
```

### `bridges_in_cell`

```gdscript
func bridges_in_cell(cell: Vector2i) -> Array
```

_6 private function(s) starting with `_` are not listed._
