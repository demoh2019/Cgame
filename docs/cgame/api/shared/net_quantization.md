# net_quantization.gd

> Network property quantization (Quake 3 / Valve Source / Unreal replication style): floats become fixed-point integers over a known range, so max error is hal...

`res://scripts/shared/net_quantization.gd`

## Overview

Network property quantization (Quake 3 / Valve Source / Unreal replication style):
floats become fixed-point integers over a known range, so max error is half a quantum.

## Functions

### `quantize_float`

```gdscript
static func quantize_float(v: float, min_v: float, max_v: float, bits: int) -> int
```

### `dequantize_float`

```gdscript
static func dequantize_float(q: int, min_v: float, max_v: float, bits: int) -> float
```

### `quantize_angle`

```gdscript
static func quantize_angle(radians: float, bits: int) -> int
```

Angles wrap into [0, TAU) and use `bits` bits with no duplicate endpoint.

### `dequantize_angle`

```gdscript
static func dequantize_angle(q: int, bits: int) -> float
```

### `pack_vector3`

```gdscript
static func pack_vector3(v: Vector3, bounds_min: Vector3, bounds_max: Vector3, bits_per_axis: int) -> PackedByteArray
```

### `unpack_vector3`

```gdscript
static func unpack_vector3(data: PackedByteArray, bounds_min: Vector3, bounds_max: Vector3, bits_per_axis: int) -> Vector3
```

_1 private function(s) starting with `_` are not listed._
