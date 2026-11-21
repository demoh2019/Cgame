# world_poi.gd

> Points of interest of the world: villages, farms, camps, depots, military outposts, watchtowers, mines, ruined cities, bunkers, lighthouses and docks.

`res://scripts/shared/world_poi.gd`

## Overview

Points of interest of the world: villages, farms, camps, depots, military outposts, watchtowers, mines, ruined cities,
bunkers, lighthouses and docks. Everything comes from the seed, so the server and every client agree on all of it without
a byte on the network. The world is cut into 256 m regions and each holds at most one site; a site's contents (buildings,
walls, towers, props, loot crates, zombie packs, survivors and a workbench where people live) are built once and cached.

Sites where people live (village, outpost) have a station: a workbench with a trader, usable for crafting, the vendor and
contracts exactly like the hub's. The bank and the market stay in the hub's safe zone.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const REGION_SIZE := 256.0`
- `const MIN_HUB_DISTANCE := 150.0`
- `const SITE_CHANCE := 0.82`
- `const STATION_RANGE := 6.0`
- `const BUILDING_SCALE := 6.0`
- `const WALL_SCALE := 3.0`
- `const BUILDING_VARIANTS := 9 # Models of the client's HOUSES list; the client takes variant % installed models.`
- `const TOWN_CENTER_VARIANT := 7 # The big building in the middle of a village (not drawn at random for ordinary houses).`
- `const TOWER_VARIANTS := 3 # Watchtower, round tower, tall coastal tower.`
- `const WALL_WOOD := 2 # Palisade of villages, farms and camps.`
- `const WALL_STONE := 1 # Fort wall.`
- `const PROP_RADII := [0.45, 0.45, 0.6, 0.6, 0.35, 0.3, 0.5, 0.5, 0.6, 2.4, 0.4, 0.7, 0.9, 0.7, 0.8, 0.5, 0.9, 0.2, 1.0, 0.9, 0.8, 0.45, 1.5, 0.25, 0.25, 1.3, ...`
- `const RUIN_RADII := [0.8, 0.8, 1.8, 1.8, 1.1, 2.6, 1.6, 0.5, 1.9, 2.2,`
- `const CRATE_VARIANTS := 6`
- `const MONUMENT_RADII := [1.1, 1.3, 2.6, 0.9]`
- `const LANDMARKS := [`
- `const LANDMARK_CHANCE := 0.85`
- `const RUSTIC_PROPS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 20, 21, 22, 23, 24, 43, 46, 49, 45, 29, 28, 50, 51, 52, 53, 54, 55]`
- `const MARKET_PROPS := [9, 10, 8, 16, 11, 25, 22, 43, 46, 44, 49, 51, 52, 50]`
- `const MILITARY_PROPS := [6, 7, 13, 14, 15, 17, 8, 20, 22, 31, 32, 33, 30, 39, 40, 36, 26, 27, 47]`
- `const RUIN_PROPS := [13, 14, 15, 16, 19, 12, 0, 1, 26, 27, 28, 34, 35, 36, 37, 38, 41, 42, 45, 47, 48, 29, 44]`
- `const KINDS := {`
- `const PREFIXES := ["Ash", "Black", "Bright", "Cold", "Crow", "Dun", "Elm", "Fair", "Grey", "Hollow", "Iron", "Kings", "Lone", "Mill", "North", "Oak", "Pine",...`
- `const SUFFIXES := ["ford", "wick", "haven", "field", "brook", "stead", "fall", "ridge", "mere", "watch", "gate", "moor", "hollow", "port", "vale", "burn", "b...`
- `const FIRST_NAMES := ["Mara", "Tobias", "Ilya", "Nadia", "Boris", "Elena", "Marek", "Zosia", "Viktor", "Anya", "Piotr", "Katia", "Oleg", "Lena", "Jakub", "Ir...`
- `const CHARACTERS := ["Elf_Male", "Elf_Female", "Orc_Male", "Orc_Female"]`
- `const ROLES := {`

## Functions

### `sites_in_region`

```gdscript
func sites_in_region(rx: int, rz: int) -> Array
```

### `sites_near`

```gdscript
func sites_near(x: float, z: float, radius: float) -> Array
```

Every site whose area may touch a circle: for chunk generation, map markers and the HUD.

### `site_at`

```gdscript
func site_at(x: float, z: float) -> Dictionary
```

The site whose area covers a point, or {}.

### `station_near`

```gdscript
func station_near(x: float, z: float, reach: float = STATION_RANGE) -> bool
```

Whether a workbench station of any settlement is within `reach` of a point.

### `levellers`

```gdscript
func levellers(rx: int, rz: int) -> Array
```

Sites that level some ground inside a region: its own and those of the neighbours that reach over the border.
Sites that level ground inside a region, as light records for the terrain hot path: {x, z, y, inner, outer}: full level out
to `inner`, a smooth ramp to `outer`.

### `contents`

```gdscript
func contents(site: Dictionary) -> Dictionary
```

Buildings, walls, towers, props, crates, zombie packs, ore and survivors of a site, in world coordinates and without
ids (the chunk that holds an item gives it one). Built once.

_29 private function(s) starting with `_` are not listed._
