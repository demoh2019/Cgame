# Albion After — GPU-instanced atmospheric pollen and fireflies

**Integration:** the canonical `game/` multiplayer client and the solo
client on `develop`. These are real render nodes in the playable scene,
not concept art or a separate postprocessing mockup.

## What changed visually

The open world now contains subtle **floating pollen in daylight** and
glowing, slowly drifting **fireflies in woodland and swamp at night**.
Their position and visibility follow real world biomes, the common
day/night clock, storms and regional wind. The soft translucent
billboards emphasize the sense of depth and life near the isometric
camera without needing new shadow maps or point lights.

- **Swamp at night:** strongest golden firefly activity.
- **Forest at night:** a sparser firefly glow.
- **Clear daylight:** occasional pale drifting pollen in meadows,
  woodland, sandy shores and mountain air.
- **Storms:** both effects fade to avoid implausible bright rain specks
  and to save transparent overdraw.
- **Underground:** disabled by the multiplayer renderer.
- **Performance:** effect disabled, zero visible instances.
- **Balanced / High / Ultra:** gradually denser, wider fields without
  changing any network, collision or world-generation rules.

This is a deliberately subtle material, not hundreds of real dynamic
lights. Firefly glow uses **unshaded emission and Godot's existing glow**
on high-end rendering profiles; lower tiers remain visible without a
screen-space blur, per-particle light or extra postprocess.

## Performance strategy

Godot's native `MultiMesh` is the appropriate way to batch numerous
instances with a shared material into a small number of draw calls.
The new `scripts/client/ambient_motes.gd` uses **one persistent
`MultiMeshInstance3D`**, a two-triangle `QuadMesh` and an opaque
fixed-capacity instance array of at most **252 motes**. The array is
allocated only once. Lower quality settings adjust only
`visible_instance_count`; there is no GPU buffer resize or particle
simulator restart when quality or weather changes.

The custom `ambient_motes.gdshader` animates billboards **at the
vertex stage** using each instance's seed and phase. No textures,
particle atlas, CPU per-frame transforms, noise texture fetches,
realtime point lights, screen-space ray tracing or shadow passes are
required. The shader also applies a feathered radial fade before the
outer draw range and a soft silhouette/halo in its fragment stage.

**Spatial stability:** the world is divided into **42 m** tiles.
A 3×3 field follows the viewer only when they cross a tile boundary.
Within each field, deterministic per-world-tile random seeds reproduce
the same particle positions as the player returns. Each mote is placed
using the game's existing `WorldGen.height_at(x, z)`, rather than
being rendered at fixed sea level. The field reuses the same one draw
call at every zoom level.

**CPU throttling:** visual weather/quality uniforms and grid position
are evaluated at most **4 times per second**. A new 3×3 grid and
up to 252 positions are generated only when crossing 42 m of world
space *and* the field is visible. There is no background actor process,
network traffic or persistent save state. Model heights are queried
only when changing tile, not on every GPU frame.

| Profile | Motes per tile | Max GPU instances | Fade distance |
| --- | ---: | ---: | ---: |
| Performance | 0 | 0 | Disabled |
| Balanced | 8 | 72 | 36 m |
| High | 16 | 144 | 48 m |
| Ultra | 28 | 252 | 64 m |

These values are **budgets**, not measured FPS. Setting both night
firefly and daylight pollen strengths to zero hides the entire mesh
and sets the visible count to zero. The shader uses the existing
quality presets rather than introducing another player-facing setting.

## Engine references

- Godot 4.7 MultiMesh:
  https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html
- Godot 4.7 spatial shaders (custom data, vertex transforms):
  https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html

The general approach matches how popular engines minimize CPU draw
submission for repeated small VFX, but **it is implemented directly
through Godot's supported MultiMesh/shader APIs** and does not claim
to reproduce Unreal Niagara or Unity VFX Graph.

## Verify

```bash
godot --headless --path game --script res://tests/run_all.gd
godot --headless --path game --script res://tests/smoke_client_scene.gd
```

`test_ambient_motes.gd` validates quality budgets, deterministic
world tiling, weather/biome switching, GPU instance reuse and actual
solo/online code paths. An engine-level headless test does not prove
visual quality. Capture equal camera/time/biome screenshots on the
target renderer for woodland midnight, swamp twilight, clear meadows,
coastline storms and a dungeon. Compare p50/p95 frame timing,
GPU time, transparent overdraw and VRAM before claiming FPS gains.

The system is optional visual presentation only: gameplay, inventory,
physics, crafting and dedicated-server calculations are unchanged.
