# Cinematic ground tracks — terrain-aligned decals, quality budgets and native Godot optimization

**Integrated into:** `game/scripts/client/online_main.gd` on `develop`. The engine changes
live in `scene/3d/decal.cpp`.

## Visual result

Inspired by the PBR decal workflow in Unity HDRP and Unreal's contact
detail philosophy, survivors leave subtle **bootprints on muddy soil
during rain** and **soft blue-grey prints in snowy high mountains**.
Swamp ground stays damp even between storms. The effect belongs to
the real world renderer, not a mock screenshot or a combat mechanic.

- Each shoe mark is softly feathered, alternates left/right and follows
  the player's actual travel heading.
- A tiny **64 × 64 RGBA8** procedural albedo texture is cached once per
  surface kind; **Ultra adds a shared normal texture** so local lighting
  responds to the tread relief. Texture mipmaps prevent moiré and shimmer
  at small screen sizes.
- The decal is positioned using **WorldGen.height_at(x,z)** under
  the individual shoe, rather than assuming a flat scene or the
  avatar's vertical offset. Falling/cliff traversal is rejected.
- Footprints have a finite lifetime of **12 seconds**; the final
  3 seconds fade smoothly. A storm ending (or stepping onto dry soil)
  prevents **new** marks but does not suddenly erase already stamped
  terrain: those marks remain until their natural fade-out. Position
  sampling uses real travel distance, not a stationary emitter.
- Water, tunnels, dead/stationary characters, bike riding, teleports,
  invalid weather and dry terrain do not generate marks.
- One source of truth handles both online and solo mode. No server
  messages, persistent world mutations, network state changes or
  changes to authoritative physics are made.

## Strict renderer and quality limits

Godot's native `Decal` is supported on Forward+ and Mobile, but this
game intentionally enables its clustered PBR footprint renderer **only
on desktop Forward+ High/Ultra** to avoid spending GPU bandwidth on
the lower mobile budgets.

| Profile | Maximum native Decal nodes | Fade begins | Fade length |
| --- | ---: | ---: | ---: |
| Performance | 0 | Off | — |
| Balanced | 0 | Off | — |
| High | 16 | 27 m | 13 m |
| Ultra | 32 | 27 m | 13 m |

Decals are created lazily, one per new footprint, and reused as a
bounded ring pool when full. Lowering quality from Ultra to High
immediately hides all projectors above the new budget. Even on
Ultra the scene can hold at most 32 footprint nodes. Compatibility
has **zero** active projectors.

### Native engine improvement

The Godot fork's `scene/3d/decal.cpp` now short-circuits redundant
setters of:

- `modulate` (including unchanged alpha for long-lived decals);
- `distance_fade_enabled`;
- `distance_fade_begin`;
- `distance_fade_length`.

This avoids repeated RenderingServer calls from pooled, fading
material overlays without changing the effect or adding a shader
pass. The GDScript pool additionally compares alpha values before
calling the engine: during the first nine seconds a mark is fully
opaque relative to its alpha texture and therefore needs no
frame-to-frame modulation update.

The C++ native regression test is
`tests/scene/test_decal_cached_setters.cpp`; the scene regression
is `game/tests/test_footprint_decals.gd`. The native test covers API
semantics. Confirming the number of renderer submissions still
requires profiling; no FPS improvement is asserted yet.

## Validation

Run the native engine from this fork on the target platform and execute
both test suites:

```bash
godot --headless --path game --script res://tests/run_graphics.gd
godot --headless --path game --script res://tests/run_all.gd
```

The tests cover renderer support, dry/wet biomes, high-altitude snow,
stride filtering, teleports, water/tunnel gating, shared PBR textures,
terrain-height placement, pool limit, and runtime High/Ultra switches.

For GPU validation, compare exactly matched night/day and clear/storm
captures at the edge of a forest, a muddy swamp and a snowy mountain.
Verify a falling survivor cannot stamp the cliff below, that shoe
prints remain attached to slopes, and that reducing quality removes
the excess clustered projectors immediately. Measure actual draw
submissions, GPU p50/p95 latency, and the number of visible decals
before claiming frame-rate gains.

References:

- [Godot: Decals](https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html)
- [Unity HDRP: Feature matrix](https://github.com/Unity-Technologies/Graphics/blob/master/Packages/com.unity.render-pipelines.high-definition/Documentation~/HDRP-Features.md)
- [Unreal Engine: Contact shadows](https://dev.epicgames.com/documentation/en-us/unreal-engine/contact-shadows-in-unreal-engine)
