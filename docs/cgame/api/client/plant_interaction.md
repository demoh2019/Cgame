# plant_interaction.gd

> Grass and bushes bend away from the player and plants shake when hit or harvested.

`res://scripts/client/plant_interaction.gd`

## Overview

Grass and bushes bend away from the player and plants shake when hit or harvested. Two global shader vec4s
(x, z, radius, strength) read by grass_field.gd / foliage.gd through plant_interaction.gdshaderinc.
Unity: vertex-shader "interactive grass" with a player-position uniform. Unreal: Niagara/material
"grass interaction" via a Material Parameter Collection. Purely cosmetic; never touches simulation.

## Constants

- `const BEND_RADIUS := [0.0, 1.1, 1.5, 1.9] # Low, Medium, High, Ultra: Low keeps grass untouched.`
- `const SHAKE_RADIUS := [0.0, 2.2, 2.8, 3.4]`
- `const SHAKE_SECONDS := 1.1`
- `const MAX_BEND := 0.5`
- `const MAX_CRUSHERS := 8`
- `const CRUSH_RANGE := 45.0 # Beyond the grass fade there is nothing to flatten.`
- `const FOOTPRINTS := {`

## Functions

### `bend_radius`

```gdscript
static func bend_radius(level: int) -> float
```

### `shake_radius`

```gdscript
static func shake_radius(level: int) -> float
```

### `bend_strength`

```gdscript
static func bend_strength(speed: float) -> float
```

Push strength in metres at the blade tip: standing presses a little, running presses fully.

### `shake_envelope`

```gdscript
static func shake_envelope(age: float, amp: float) -> float
```

Shake amplitude (metres of sway) of age `age` seconds after the hit: damped oscillation envelope.

### `shake_amplitude_for`

```gdscript
static func shake_amplitude_for(event_type: String) -> float
```

Harvesting shakes more than a glancing hit.

### `shake`

```gdscript
func shake(at: Vector3, amp: float) -> void
```

### `update`

```gdscript
func update(delta: float, player: Vector3, level: int) -> Vector2
```

### `pick_crushers`

```gdscript
static func pick_crushers(center: Vector2, sources: Array) -> Array
```

Nearest object footprints to `center` as Vector4(x, z, radius, strength), at most MAX_CRUSHERS.
`sources` is an Array of [kind, Dictionary-with-x-and-z].

### `set_crushers`

```gdscript
func set_crushers(crushers: Array) -> void
```

Uploads the footprints to the grass shader globals.

