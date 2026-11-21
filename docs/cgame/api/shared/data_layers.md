# data_layers.gd

> Data Layers: named sets of world content switched on and off at runtime for the whole server (seasons and events), without touching the seed-generated world.

`res://scripts/shared/data_layers.gd`

## Overview

```text
Data Layers: named sets of world content switched on and off at runtime for the whole server
(seasons and events), without touching the seed-generated world. The server decides which are
active - by the calendar, or forced with `--layers winter,festival` (or `--layers none`) - and
sends the list to every client; clients add or remove the layer's content as it changes.
  winter   - snow settles on all low ground (ground shader), Dec-Feb.
  festival - lanterns and harvest decorations in settlements and camps, late Oct-early Nov
             and over the year-end holidays.
```

## Constants

- `const LAYERS := ["winter", "festival"]`

## Functions

### `scheduled`

```gdscript
static func scheduled(unix_time: float) -> Array
```

Layers the calendar turns on at this moment (UTC date).

### `parse_override`

```gdscript
static func parse_override(value: String) -> Variant
```

Parse a `--layers` value: comma list of known layers, "none" for an empty set, "" = calendar.

