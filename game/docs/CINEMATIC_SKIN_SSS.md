# Cinematic character skin subsurface scattering — native Godot + Albion After

## Motivation and reference engines

The existing game preserves imported skin and outfit PBR maps, wet-cloth
clearcoat and physically based reflections. However, every face previously
used ordinary opaque diffuse lighting, which makes the cheeks/ears appear
hard and plasticky in strong lateral sunlight, near torches or at sunset.

Contemporary engines use a distinct **subsurface scattering** lighting
response for flesh:

- Unreal Engine Subsurface Profile is a high-end skin shading model:
  https://dev.epicgames.com/documentation/en-us/unreal-engine/subsurface-profile-shading-model-in-unreal-engine
- Unity HDRP uses skin diffusion profiles:
  https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition@17.0/manual/skin-and-diffusive-surfaces-subsurface-scattering.html
- Godot BaseMaterial3D supports native skin SSS (Forward+ only):
  https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html

Albion After uses Godot's existing physically based SSS screen-space
composition, **not** Unreal's entire profile system or Unity diffusion
profile assets. It is an opt-in quality feature for actual imported skin.

## Engine changes

Added `BaseMaterial3D.configure_skin_subsurface(enabled, strength)` to
the custom C++ engine (`scene/resources/material.h/.cpp`).

- Validates finite strength in [0, 1] before touching any material state.
- Updates the shader's `FEATURE_SUBSURFACE_SCATTERING` and
  `FLAG_SUBSURFACE_MODE_SKIN` together, queueing **at most one** shader
  rebuild when either state changes.
- Sends the strength uniform only when its value actually changes.
- Repeated identical calls are no-ops. Disabling resets skin diffusion.
- Does not alter albedo/ORM/normal textures, alpha, roughness, metallic,
  shadows, clearcoat or other PBR properties.
- Existing individual Godot material setters remain available. The game
  falls back to those setters on stock Godot.

The built-in Forward+ render path already skips the SSS blur when there
are no eligible rendered skin materials. No new render path or shader pass
has been added to the engine.

## Game implementation

`game/scripts/client/graphics_skin_scattering.gd` creates a cached
material variant **only** for explicitly recognized opaque skin:

- Native imported character body meshes ending in `_Body` and artist
  tagged head/body meshes (metadata `skin`).
- No outfit `_Body` pieces, gear, helmets, robot fallback, eyes, brows,
  hair, transparent cutouts, unlit surfaces or metallic material.
- The original imported skin stays untouched. A cloned variant shares
  the imported albedo/normal/ORM textures and preserves tint.
- Existing CharacterModel skinned mesh override or per-surface override
  is recorded at construction. Low presets and renderer fallback restore
  that exact authored material instead of modifying it.
- Skin material variants are cached per source material/quality and cleared
  with the character template cache when the client exits.
- Existing characters update only when the quality/backend actually changes.
  Newly streamed characters inherit the current quality. No 60 Hz
  traversal of animated models or shader recompilation per frame.
- Character tint changes also update the active duplicate, so infected
  skin can retain combat/hit coloration.
- Wet-cloth shader variants and dynamic equipment are unaffected.

## Performance policy

| Quality | Backend | Skin SSS | Native screen filter | Strength |
| --- | --- | --- | --- | ---: |
| Performance | Any | Off | Disabled | 0 |
| Balanced | Any | Off | Disabled | 0 |
| High | Forward+ | On | Medium | 0.19 |
| Ultra | Forward+ | On | High | 0.29 |
| All | Compatibility/Mobile | Off | Disabled | 0 |

High uses blur scale 0.65 and depth scale 0.17; Ultra uses 0.86 / 0.22.
The global `RenderingServer.sub_surface_scattering_set_quality` and
`set_scale` methods are called only during a graphics preset/backend
transition, with their settings cached across repeated preset applies.

SSS **does cost a screen-space blur and extra material feature** when
rendering actual skin on High/Ultra. Performance/Balanced pay no cost for
that pass. It does not allocate new textures from the downloaded packs.

## Test and visual QA

Registered `game/tests/test_skin_subsurface.gd` to validate the
renderer/quality gates, head-vs-clothing categorization, original PBR
texture preservation, caching, on-mesh override/restoration, and live
graphics quality integration.

Added native C++ `tests/scene/test_skin_subsurface.cpp` to validate
the transaction, disabled path, invalid input rejection, source color
and shader flags.

After rebuilding the custom Godot binary, run:

```bash
godot --headless --editor --path game --quit
godot --headless --path game --script res://tests/run_all.gd
```

Visual comparison: inspect the same elf/orc/survivor close-up with the sun
grazing the face (late afternoon), beside a warm torch and under moonlight.
Check cheeks, ears and fingers for subtly softened light transitions;
hair and clothing must retain their original roughness. Check wet
equipment and player tint during gameplay.

Compare Performance/Balanced/High/Ultra and Compatibility on identical
cameras. Profile GPU p50/p95 frame time, additional SSS screen-pass
memory and shader compilation spikes on a populated hub. Reduce or
disable the premium feature on constrained GPUs if it exceeds budget.

**Runtime limitation:** The current editing environment cannot compile
the custom Godot C++ engine or measure actual GPU frames. Test source
is included, but no compile/runtime benchmarks are claimed here.
