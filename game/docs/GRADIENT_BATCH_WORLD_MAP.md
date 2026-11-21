# Gradient batch evaluation — native engine + Albion After

Cgame extends the built-in `Gradient` resource with:

```gdscript
var colors: PackedColorArray = gradient.sample_batch(offsets: PackedFloat32Array)
```

The result preserves the input order and matches repeated `Gradient.sample(offset)` calls across interpolation modes (linear, constant, cubic) and color spaces (sRGB, linear sRGB, Oklab). Calls are executed in one native loop to reduce interpreted/native boundary overhead. Empty input returns an empty packed array; non-finite offsets and batches over 65,536 values are rejected with an empty array and an engine error. The API does not change gradient authored stops, resource serialization, or default interpolation behavior.

**Albion After integration:** `game/scripts/client/world_map.gd` uses a two-stop gradient with the same existing WATER_SHALLOW and WATER_DEEP colors. At chart-paint time the map gathers water depth / coast distances for each row, samples the water-color gradient once for all water pixels, and applies the existing ripple, grain, coastline and parchment layers. This avoids repeated script calls to `Gradient.sample`, preserves current map art direction, and leaves terrain/world-generation and multiplayer state untouched.

`game/scripts/client/gradient_batch.gd` supplies `sample_many` fallback which calls `Gradient.sample` on stock Godot and uses `sample_batch` if available. Tests cover the original `Color.lerp` water colors and native/scalar parity in all supported interpolation modes.

## Validate

```sh
godot --headless --test --test-case="*Batch sampling matches scalar interpolation*"
godot --headless --path game --script res://tests/run_all.gd
```

Also compare the 384 × 384 world-map visual with previous builds on Cgame and stock Godot. Benchmark map paint time before making any speedup claim. No network or save format change.

Analogous engine color-curve authoring APIs: [Unity Gradient.Evaluate](https://docs.unity.cn/Documentation/ScriptReference/Gradient.Evaluate.html), [Unreal UCurveLinearColor](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UCurveLinearColor). Both references provide single-position evaluation; Cgame's new API is a packed batch addition.
