# world_map.gd

> The whole island on one screen (J), drawn like an old surveyor's chart: muted parchment colours, hillshade lit from the north-west, contour lines, an inked c...

`res://scripts/client/world_map.gd`

## Overview

The whole island on one screen (J), drawn like an old surveyor's chart: muted parchment colours, hillshade lit from the
north-west, contour lines, an inked coast with shallow water and ripple lines, paper grain and a vignette. Settlements and
sites are badges with a silhouette glyph; names are placed greedily so they never overlap, with a paper-coloured halo.
Dashed danger rings, cased roads, a compass rose, a scale bar and a pulsing player arrow. The wheel zooms toward the
cursor, dragging pans, Space centres on you. A click sets a private waypoint (Shift+click pings the party, right click
clears it), and the expedition atlas lists this player's goals: clicking one follows it, even as it moves. The picture is charted a few rows per frame the first time it opens.
Techniques: ArcGIS hillshade (zenith 45°, azimuth 315°), cartographic label hierarchy (Axis Maps, Ordnance Survey),
greedy candidate-position label placement.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const WorldPoi = preload("res://scripts/shared/world_poi.gd")`
- `const RegionalTrade = preload("res://scripts/shared/regional_trade.gd")`
- `const GrassField = preload("res://scripts/client/grass_field.gd")`
- `const GradientBatch = preload("res://scripts/client/gradient_batch.gd")`
- `const ImageBatch = preload("res://scripts/client/image_batch.gd")`
- `const MaskDistanceField = preload("res://scripts/client/mask_distance_field.gd")`
- `const HeightfieldGradients = preload("res://scripts/client/heightfield_gradients.gd")`
- `const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")`
- `const ExpeditionAtlas = preload("res://scripts/shared/expedition_atlas.gd")`
- `const PIXELS := 384`
- `const SPAN := WorldGen.WORLD_RADIUS * 2.0 + 200.0`
- `const ZOOMS := [1.0, 1.6, 2.6, 4.0]`
- `const SAMPLE_ROWS_PER_FRAME := 8`
- `const PAINT_ROWS_PER_FRAME := 48`
- `const PAPER := Color("#eadcc0")`
- `const PAPER_DARK := Color("#d9cba8")`
- `const INK := Color("#2b2418")`
- `const INK_SOFT := Color("#3b3428")`
- `const BIOME_COLORS := [Color("#d8c9a0"), Color("#6e7f4e"), Color("#9ca36b"), Color("#7d8459"), Color("#8e8576")]`
- `const STEPPE := Color("#c2b07a")`
- `const SNOW := Color("#e8e4d8")`
- `const WATER_DEEP := Color("#3f5e6e")`
- `const WATER_SHALLOW := Color("#6e909a")`
- `const RIPPLE := Color("#dce6e0")`
- `const ROAD_FILL := Color("#e3d3ae")`
- `const BIOME_IDS := {"beach": 0, "forest": 1, "plains": 2, "swamp": 3, "mountain": 4}`
- `const CONTOUR_STEP := 20.0`
- `const KIND_COLORS := {`
- `const RING_COLORS := [Color("#d9b44a"), Color("#d98a3a"), Color("#c0503a")]`
- `const RING_NAMES := ["SAFE LANDS", "BORDERLANDS", "WILDS"]`

## Signals

- `signal personal_waypoint_changed(point: Vector2)`

## Documented variables

- `var world_streamer: WorldStreamer` - Assigned by online_main after the native streamer exists. Optional on stock Godot/older Cgame binaries, so map markers remain fully usable.

## Functions

### `setup`

```gdscript
func setup(p_client) -> void
```

### `toggle`

```gdscript
func toggle() -> void
```

### `current_objectives`

```gdscript
func current_objectives() -> Array[Dictionary]
```

Available goals are derived solely from the authenticated local snapshot.

### `select_objective`

```gdscript
func select_objective(key: String) -> bool
```

Clicking a goal selects an ordinary private waypoint; there is no RPC.
Unlike a manual marker, a followed goal can move or expire.

### `objective_color`

```gdscript
static func objective_color(key: String) -> Color
```

### `set_waypoint`

```gdscript
func set_waypoint(point: Vector2) -> bool
```

Player-owned navigation only. No RPC and no server-side location leak.

### `clear_waypoint`

```gdscript
func clear_waypoint() -> void
```

### `waypoint_streaming_caption`

```gdscript
static func waypoint_streaming_caption(p_streamer: WorldStreamer, p_waypoint: Vector2, p_player: Vector2) -> String
```

The expedition atlas: this player's goals as clickable rows, and how far the waypoint is.
World Partition-style source completion is read-only: do not request
chunks from map draw or display distant pins as loaded.

_28 private function(s) starting with `_` are not listed._
