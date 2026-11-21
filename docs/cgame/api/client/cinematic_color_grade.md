# cinematic_color_grade.gd

> Scene-referred cinematic grade, inspired by filmic Unreal/HDRP color pipelines.

`res://scripts/client/cinematic_color_grade.gd`

## Overview

Scene-referred cinematic grade, inspired by filmic Unreal/HDRP color pipelines.
Reuse the engine-native ACES/AgX tonemapper: changing Environment uniforms
adds no fullscreen pass, LUT upload or material/mesh rebuild.

Deliberately subtle: normal midday albedo remains recognisable, evening has
warm atmospheric contrast, moonlight stays readable without crushing blacks,
and overcast storms reduce contrast and saturation like real diffuse light.

## Functions

### `look`

```gdscript
static func look(daylight: float, sun_height: float, storm: float) -> Dictionary
```

### `apply`

```gdscript
static func apply(environment: Environment, daylight: float, sun_height: float, storm: float) -> void
```

