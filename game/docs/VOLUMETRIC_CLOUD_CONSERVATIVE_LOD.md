# Raymarched cloud empty-space skipping + sky cubemap quality caching

## Inspiration

Unreal Engine Volumetric Clouds implements *Conservative Density* to avoid
expensive 3D volume-material evaluations when a raymarch interval cannot
contain any visible cloud. Unity HDRP evaluates clouds at varying quality
for sky viewing and reflection probes. Godot sky shaders also have
separate cubemap and screen passes.

- Unreal: https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-cloud-component-properties-in-unreal-engine
- Unity HDRP: https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition@17.0/manual/understand-clouds.html
- Godot: https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html

The game already includes 24-step High / 40-step Ultra, Beer-Powder,
three-tap sunlight shadows, and a halved-step sky radiance cubemap path.
A previously uncached 3D cloud density function calculated four
eight-corner noise volumes **for every sample**, even if its density
was exactly zero.

## New shader optimization — mathematically conservative

Density noise has the *unchanged* form

`base = 0.55*N0 + 0.28*N1 + 0.17*N2`

where each `N` is in [0, 1]. The cloud does not exist when
`base <= 1 - coverage`. This update can reject exactly-zero samples
using progressively tighter upper bounds:

1. If height lies outside the bounded cloud slab, return zero.
2. Evaluate only `N0`. If `0.55*N0 + 0.45 <= 1 - coverage`,
   both omitted octaves together cannot create a cloud.
3. Evaluate `N1`. If `0.55*N0 + 0.28*N1 + 0.17 <= 1 - coverage`,
   the missing fine octave cannot create a cloud.
4. Compute `N2`. If base is still below threshold, skip erosion.
5. Otherwise evaluate the original fourth high-frequency edge-erosion
   noise, retaining identical density shaping and the three original
   self-shadow taps in illuminated clouds.

The bound never throws away a sample whose **original density was
nonzero**. It may skip 1–3 3D noise octaves in empty cloud regions,
including the costly secondary sunlight probes. It adds no textures,
buffers, passes, compute kernels or new sampling patterns.

The shader also computes a single `cloud_sunlit` flag per ray and skips
the three direct-light self-shadow density probes for *negligibly sunlit*
night/storm conditions. Ambient sky scattering remains. Any tiny color
difference from this night-only threshold is intentional and bounded.

Important: This is a cost-reduction optimization, **not** a new rendering
system, a Nanite-style solution, or a guaranteed GPU speedup.
Warp divergence and noise density determine real effectiveness.

## Engine: avoid reallocating the same sky radiance map

Native `Sky` now tracks whether each sky property has been uploaded at
least once and then skips identical sizes, process modes and materials.
The first upload is always sent to the render backend, even if its
C++ resource default equals the requested value.

Native method `Sky.configure_render_budget(radiance_size, process_mode)`
validates the full plan before changing either state; repeated Auto
quality settings cannot re-request identical cubemap sizes.

The game's `Atmosphere.apply_graphics_profile()` calls this native API
when available; stock Godot checks the old radiance size first. The
existing process mode remains **incremental** for smooth reflection
updates. Cloud shader time/weather changes still cause legitimate
sky-radiance refreshes, which this does not suppress.

| Tier | Cloud samples (screen / cubemap) | Sky radiance size |
| --- | --- | --- |
| Performance | off | 32 |
| Balanced | off | 64 |
| High | 24 / 12 | 128 |
| Ultra | 40 / 20 | 256 |

## Verification

- Native C++: run tests tagged `[SceneTree][Sky]`, including invalid
  render-budget pairs and repeated size/mode updates.
- Game: `godot --headless --path game --script res://tests/run_all.gd`.
  `test_sky_cloud_lighting_lut.gd` checks conservative algebra
  across bounded noise/coverage examples, sky shader stage restrictions,
  auto-quality wiring and shared ground shadow LUT.
- GPU: inspect cloud shape parity between baseline and optimized shaders
  across clear skies, low coverage, dusk, storms and moonlight. Record
  720p/1080p GPU frame times, cubemap update spikes and CPU render
  thread work on M1 Forward+; verify Compatibility/Performance still
  use the cheap path.

There is no compiled engine or GPU benchmark in the authoring environment.
Static and algebraic tests do not prove a measurable FPS gain.
