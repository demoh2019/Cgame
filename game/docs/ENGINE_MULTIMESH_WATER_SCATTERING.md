# Albion After — native MultiMesh correctness + physically inspired shallow-water light

November 20, 2026. Changes are committed directly to `develop` in both the
**Godot engine fork** at repository root and the **playable game** under `game/`.

## Native renderer fix — visible instances = -1

Source: `servers/rendering/renderer_rd/storage_rd/mesh_storage.cpp`

Godot's `MultiMesh.visible_instance_count` accepts the special value
**-1** for **all allocated instances**. Its RD backend previously used
the raw sentinel as the upper bound for marking newly visible dirty
regions:

```cpp
for (int i = start; i < p_visible; i++) {
    _multimesh_mark_dirty(multimesh, i, true);
}
```

When the visibility budget changed **N → -1**, the loop never ran.
Instances modified while hidden in the cached CPU MultiMesh buffer
could reappear without their latest GPU transforms/colors. This
affects streamable world foliage and dynamically batched VFX, especially
when a graphics preset is raised or a group is revealed.

The engine now resolves both visibility counts before the transition:

- Previous visible: `previous < 0 ? allocated : previous`.
- New visible: `requested < 0 ? allocated : requested`.
- Only newly visible instances are marked for resubmission to the GPU.
- Existing fast path still avoids submissions when the value is unchanged.
- **Indirect draw calls** use a concrete unsigned instance count rather
  than accidentally passing `-1` as `UINT32_MAX`.

This is a real rendering-backend change, not a GDScript approximation.
It does **not** allocate a new buffer or create additional draw calls.
The new C++ test `tests/scene/test_multimesh_visibility.cpp` exercises
public visibility transitions and cached instance data with a mock
render server; a GPU capture is still needed to verify RD upload
behavior under Vulkan.

The playable `game/scripts/client/ambient_motes.gd` takes advantage of
the native show-all sentinel on **Ultra**. The lower quality profiles
still draw 72 or 144 particles, while Ultra shows all 252 preallocated
instances. Raising quality from a lower preset tests the newly
corrected hidden-to-visible transition; returning to a lower
profile does not reallocate the MultiMesh.

## Spectral light scattering in shoreline water

Inspired by Unity's HDRP water scattering and Unreal Engine's
single-layer physically based water shading, the game's existing
`game/assets/shaders/water.gdshader` now includes a small, bounded
**single-scattering approximation**. It gives clear shallow water a
more natural translucent turquoise tone when the sun is above the
horizon, without replacing the existing Beer–Lambert absorption,
Fresnel highlights, wind waves, shoreline foam or High/Ultra
screen-space refraction.

We reuse the already calculated water transmission `T`:

```glsl
float single_scatter = (1.0 - transmission * transmission) * transmission;
```

One term approximates the probability of scattering through a thin
water layer, while the final transmission approximates escaping to
the viewer. Scattering is multiplied by the real solar color/energy,
view-to-sun angle, clarity, foam coverage, storm intensity and
shallow-water distance. Its contribution is zero for night, opaque
foam, deep water and the Performance setting.

**Performance cost:** no new texture reads, exponentials, 3D
volumes, per-pixel ray marches, lights or render passes. The branch
short-circuits entirely when the strength is zero. The sun direction
and color are uploaded as registered shader globals on the same
already-throttled sky radiance update, not every frame or for every
ocean fragment.

| Graphics | Scattering strength | Screen-space refraction |
| --- | ---: | --- |
| Performance | 0.00 | Off |
| Balanced | 0.13 | Off |
| High | 0.38 | On only in Forward+ |
| Ultra | 0.72 | On only in Forward+ |

Compatibility and Mobile can use the inexpensive depth-based
scattering while keeping high-end screen-space refraction disabled.
The existing time-of-day clock is the only source of solar light
direction/energy. Even when the moon illuminates the night sky, its
radiance cannot produce false daytime shallow-water scattering.

Integration:
- `game/project.godot`: `aa_sun_to_light`, `aa_sun_radiance`.
- `game/scripts/client/atmosphere.gd`: sun globals updated with
  cached sky uniforms.
- `game/assets/shaders/water.gdshader`: optional scattering term.
- `game/scripts/client/graphics_profiles.gd`: four quality budgets.
- `game/scripts/client/graphics_quality.gd`: active material update.
- `game/tests/test_water_scattering.gd`: optics, quality, sun
  synchronization and absence of additional shader texture samples.
- `game/tests/test_ambient_motes.gd`: 72 → 252 → 72 visibility
  transitions (Ultra now correctly reports `-1`).

## Validation

With an engine built **from this fork**, run the native test suite and
game scene tests:

```bash
scons platform=linuxbsd target=editor dev_build=yes tests=yes
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case='*[MultiMesh]*'
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path game --script res://tests/run_all.gd
```

Adjust executable name and build flags for your platform. A native
test with a mock rendering server does not prove the GPU-specific
dirty-region upload. Inspect an RD-enabled test scene that writes
hidden instance transforms, then switches `visible_instance_count`
from a low number to **-1**; verify the revealed transforms and
indirect-draw counts using the Godot GPU profiler.

For water visual review, compare the same shallow beach, clear
riverbank and stormy coastline at noon, dusk and midnight. Keep
the camera, quality, time, seed and backend constant between captures.
Profile GPU p50/p95 and the transparent-water draw. The game already
logs CPU p50/p95/p99 frame times for screenshot demos, but **no
measured FPS gain is asserted without actual GPU timing**.

Reference reading:
- Unreal Engine Single Layer Water:
  https://dev.epicgames.com/documentation/en-us/unreal-engine/single-layer-water-shading-model-in-unreal-engine
- Unity HDRP water overview:
  https://unity.com/blog/engine-platform/new-hdrp-water-system-in-2022-lts-and-2023-1
- Godot MultiMesh and visibility:
  https://docs.godotengine.org/en/stable/classes/class_multimesh.html
