# Cgame native Image rectangular pixel updates

Cgame adds `Image.set_pixels_rect(rect: Rect2i, colors: PackedColorArray) -> void` to the engine's built-in `Image` API.

- The rectangle must be strictly within image bounds and have positive size.
- Colors use row-major order: `colors[y * rect.size.x + x]`.
- Exactly `rect.size.x * rect.size.y` colors are required; invalid input does not mutate the image.
- Compressed and empty images are rejected. Existing `Image.set_pixel` conversion semantics (L8, RGB8, RGBA8, float/HDR, etc.) are reused exactly.
- Only the CPU image pixels are modified. Existing `ImageTexture` GPU resources still require an explicit `ImageTexture.update(image)`. Mipmaps are not automatically regenerated.
- Native implementation validates once and obtains a writable data pointer once, so color-format writes for a whole block do not repeatedly cross the scripting boundary or detach a copy-on-write buffer.

## Integration in Albion After

- `game/scripts/client/image_batch.gd` calls the native method when available; otherwise it performs the original `Image.set_pixel` operations for compatibility with stock Godot.
- `game/scripts/client/world_map.gd` now assembles one `PackedColorArray` per 384-pixel chart row, maintaining its existing water gradient, hillshade, contours, ink, parchment, and texture uploads.
- `game/scripts/client/cloud_shadow_lut.gd` builds the same L8 noise-based cloud shadow texture, also one row at a time through the helper.
- No server-authoritative logic, multiplayer protocol, world seed, or save format changes.

This resembles the purpose of Unity `Texture2D.SetPixels` for rectangular CPU pixel writes. It does not implement Unreal Engine's GPU-side `UTexture2D::UpdateTextureRegions` behavior.

## Testing

- `tests/core/io/test_image.cpp` compares byte-identical packed and scalar writes across L8, RGB8, RGBA8 and RGBAF, including corners and invalid input rollback.
- `game/tests/test_image_batch.gd` covers the native/fallback paths and exact pixel equality; registered in `game/tests/run_all.gd`.
- The existing `test_cloud_shadow_lut.gd` checks generated cloud opacity, deterministic caching and GPU-side usage.

Suggested validation with built Cgame binary:

```sh
godot --headless --test --test-case="*Packed rectangular pixel update*"
godot --headless --path game --script res://tests/run_all.gd
```

Benchmark frame painting and texture creation before claiming a measurable speedup.

Sources: https://docs.unity.cn/6000.0/Documentation/ScriptReference/Texture2D.SetPixels.html and https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/Engine/UTexture2D/UpdateTextureRegions?application_version=5.5
